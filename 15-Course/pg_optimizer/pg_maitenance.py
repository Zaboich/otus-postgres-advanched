#!/usr/bin/env python3
"""
PostgreSQL Maitenance for Postgres Optimizer
"""
import subprocess
import time
import re
import csv
import os
import json
import signal
import sys
import datetime
import logging
import optuna
import pandas as pd
import yaml
from typing import Dict, Any, List
from pathlib import Path
from optuna.importance import FanovaImportanceEvaluator, get_param_importances
import matplotlib.pyplot as plt


# ==============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ И ЛОГИРОВАНИЕ
# ==============================================================================
def setup_logging(log_file: str) -> None:
    """Настраивает единый вывод логов: в файл и в консоль с меткой времени."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)-8s | %(message)s",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(sys.stdout)
        ],
        force=True  # Гарантирует применение даже при повторных импортах
    )


def load_and_setup_config(config_path: str = "config.yaml") -> dict:
    """Загружает YAML-конфиг, создаёт уникальные артефакты, логирует старт."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Файл конфигурации не найден: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    run_id = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    cfg["run_id"] = run_id

    os.makedirs("logs", exist_ok=True)
    os.makedirs("results", exist_ok=True)

    cfg["log_file"] = f"logs/pg_tuner_{run_id}.log"
    cfg["results_file"] = f"results/pg_tuner_results_{run_id}.csv"

    # Инициализация логирования ДО любых сообщений
    setup_logging(cfg["log_file"])
    logging.info("🚀 Запуск оптимизации (ID: %s)", run_id)
    logging.info("📄 Используемая конфигурация:\n%s", json.dumps(cfg, indent=2, default=str))

    # Преобразование в плоский вид, совместимый с классом
    return {
        "docker_image": cfg["docker"]["image"],
        "docker_network": cfg["docker"]["network"],
        "container_memory": cfg["docker"]["memory"],
        "container_cpu": cfg["docker"]["cpu"],
        "db_container_name": cfg["docker"]["db_container"],
        "client_container_name": cfg["docker"]["client_container"],
        "volume_name": cfg["docker"]["volume"],
        "db_name": cfg["database"]["name"],
        "db_user": cfg["database"]["user"],
        "db_password": cfg["database"]["password"],
        "pgbench_scale": cfg["database"]["pgbench_scale"],
        "warmup": cfg["pgbench"]["warmup"],
        "test": cfg["pgbench"]["test"],
        "checked_params": cfg["pgbench"]["checked_params"],
        "tunable_params": cfg["optimization"]["tunable_params"],
        "optimization_target": cfg["optimization"]["target"],
        "n_trials": cfg["optimization"]["n_trials"],
        "results_file": cfg["results_file"],
        "log_file": cfg["log_file"],
        "run_id": run_id
    }


# ==============================================================================
# Поиск оптимальной конфигурации
# ==============================================================================
class PostgresMaintenance:
    def __init__(self, cfg: Dict[str, Any]):
        self.cfg = cfg
        self._cleanup_on_exit = False

    def _run(self, cmd: str, check: bool = True, timeout: int = 1800) -> subprocess.CompletedProcess:
        """Обёртка над subprocess.run с логированием"""
        logging.info("[CMD] %s", cmd)
        return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True, timeout=timeout)

    def _start_db_container(self, params: Dict[str, str]):
        """Запуск PostgreSQL в выделенном контейнере"""
        flags = " ".join([f"-c {k}={v}" for k, v in params.items()])
        cmd = (
            f"docker run -d --name {self.cfg['db_container_name']} "
            f"--memory {self.cfg['container_memory']} --cpus {self.cfg['container_cpu']} "
            f"-u {self.cfg['db_user']} "
            f"-e POSTGRES_PASSWORD={self.cfg['db_password']} -e POSTGRES_USER={self.cfg['db_user']} "
            f"-p 5432:5432 -v {self.cfg['volume_name']}:/var/lib/postgresql/data "
            f"{self.cfg['docker_image']} {flags}"
        )
        self._run(cmd)

    def _cleanup(self):
        """Остановка и удаление обоих контейнеров"""
        logging.info("[CLEANUP] Stopping containers & network...")
        for cname in [self.cfg['client_container_name'], self.cfg['db_container_name']]:
            self._run(f"docker stop {cname} || true", check=False)
            self._run(f"docker rm {cname} || true", check=False)

    def _create_db_archive(self):
        """Архивирует data-директорию после инициализации"""
        logging.info("[CACHE] Creating cache of initialized DB...")
        os.makedirs("cache", exist_ok=True)
        cache_name = f"pg_bench_s{self.cfg['pgbench_scale']}.tar.gz"
        cache_path = f"cache/{cache_name}"

        # Останавливаем БД для консистентного снапшота
        self._run(f"docker stop {self.cfg['db_container_name']}")

        # Архивируем через временный контейнер (без root на хосте)
        cmd = (
            f"docker run --rm -v {self.cfg['volume_name']}:/pg_data "
            f"-v {os.path.abspath('cache')}:/cache "
            f"alpine tar czf /cache/{cache_name} -C /pg_data ."
        )
        self._run(cmd, timeout=6000)

        # Запускаем обратно
        self._run(f"docker start {self.cfg['db_container_name']}")
        logging.info("[CACHE] Cache saved: %s", cache_path)

    def _restore_db_archve(self):
        """Восстанавливает data-директорию из кэша перед trial"""
        cache_name = f"pg_bench_s{self.cfg['pgbench_scale']}.tar.gz"
        cache_path = f"cache/{cache_name}"
        if not os.path.exists(cache_path):
            raise FileNotFoundError(f"Cache not found: {cache_path}. Run with cache_enabled=false first.")

        logging.info("[CACHE] Restoring DB from cache...")
        # Очищаем volume и распаковываем + фиксируем права (UID 999 = postgres в оф. образе)
        # Todo: alpine image postgres uid= 70, other distr postgres uid= 999
        cmd = (
            f"docker run --rm -v {self.cfg['volume_name']}:/pg_data "
            f"-v {os.path.abspath('cache')}:/cache "
            f"alpine sh -c 'rm -rf /pg_data/* && tar xzf /cache/{cache_name} -C /pg_data && chown -R 70:70 /pg_data'"
        )
        self._run(cmd, timeout=3000)

    def _create_db_copy(self):
        """Создаёт копию каталога БД без упаковки в архив"""
        logging.info("[CACHE] Creating cache of initialized DB...")
        os.makedirs("pg_copy", exist_ok=True)
        cache_name = f"pg_bench_s{self.cfg['pgbench_scale']}"
        cache_path = f"pg_copy/{cache_name}"

        # Архивируем через временный контейнер (без root на хосте)
        cmd = (
            f"docker run --rm -v {self.cfg['volume_name']}:/pg_data "
            f"-v {os.path.abspath('pg_copy')}:/pg_copy "
            f"alpine cp -r /pg_data /pg_copy/{cache_name}  "
        )
        self._run(cmd, timeout=6000)

    def _restore_db_from_copy(self):
        """Восстанавливает data-директорию из копии директории DB"""
        cache_name = f"pg_bench_s{self.cfg['pgbench_scale']}"
        cache_path = f"pg_copy/{cache_name}"
        if not os.path.exists(cache_path):
            raise FileNotFoundError(f"Cache not found: {cache_path}. Run with cache_enabled=false first.")

        logging.info("[CACHE] Restoring DB from cache...")
        # Очищаем volume и распаковываем + фиксируем права (UID 999 = postgres в оф. образе)
        cmd = (
            f"docker run --rm -v {self.cfg['volume_name']}:/pg_data "
            f"-v {os.path.abspath('pg_copy')}:/pg_copy "
            f"alpine sh -c 'rm -rf /pg_data/* && cp -r /pg_copy/{cache_name}/. /pg_data/ && chown -R 70:70 /pg_data'"
        )
        self._run(cmd, timeout=3000)


    def _init_db(self):
        """Создание БД и инициализация pgbench (выполняется 1 раз)"""
        logging.info("[DB] Initializing pgbench with scale=%s...", self.cfg['pgbench_scale'])
        cmd = (
            f"docker exec {self.cfg['db_container_name']} bash -c "
            f"'dropdb {self.cfg['db_name']}; createdb {self.cfg['db_name']}; pgbench -iqs {self.cfg['pgbench_scale']} {self.cfg['db_name']}'"
        )
        self._run(cmd, timeout=12000)
        self._run(
            f"docker exec {self.cfg['db_container_name']} psql -U {self.cfg['db_user']} -d {self.cfg['db_name']} -c 'ANALYZE;'",
            timeout=120)

    def _pg_vacuum(self):
        logging.info("[DB] Waiting for PostgreSQL to be VACUUM ANALYZE")
        self._run(
            f"docker exec {self.cfg['db_container_name']} psql -U {self.cfg['db_user']} -d {self.cfg['db_name']} -c 'VACUUM ANALYZE;'",
            timeout=3600)

    def _pg_checkpoint(self):
        logging.info("[DB] PostgreSQL CHECKPOINT")
        self._run(
            f"docker exec {self.cfg['db_container_name']} psql -U {self.cfg['db_user']} -d {self.cfg['db_name']} -c 'CHECKPOINT;'",
            timeout=120)

    def _wait_ready(self, timeout: int = 60):
        """Ожидание готовности PostgreSQL"""
        logging.info("[DB] Waiting for PostgreSQL to be ready...")
        cmd = f"docker exec {self.cfg['db_container_name']} pg_isready -U {self.cfg['db_user']} -h 127.0.0.1"
        start = time.time()
        while time.time() - start < timeout:
            res = self._run(cmd, check=False, timeout=5)
            if res.returncode == 0:
                logging.info("[DB] PostgreSQL is ready.")
                time.sleep(3)
                return
            time.sleep(1)
        raise RuntimeError("PostgreSQL did not become ready in time.")


# ==============================================================================
if __name__ == "__main__":
    CONFIG = load_and_setup_config("config.yaml")
    tuner = PostgresMaintenance(CONFIG)
    tuner._start_db_container({})
    tuner._wait_ready()
    logging.info("Запущен контейнер. Запуск VACUUM ANALYZE")
    tuner._pg_vacuum()
    tuner._pg_checkpoint()
    tuner._cleanup()
    tuner._create_db_copy()
