#!/usr/bin/env python3
# автоматизация процесса выбора оптимальных конфигурационных настроек
"""
PostgreSQL Config Optimizer v1
Развёртывание: Local Docker
Оптимизатор: Optuna (TPE / Bayesian Optimization)
Тестирование: pgbench (Read/Write/Insert mix)
"""

import subprocess
import time
import re
import csv
import os
import signal
import optuna
import pandas as pd
from typing import Dict, Any, List
from pathlib import Path

# ==============================================================================
# 🔧 КОНФИГУРАЦИЯ СИСТЕМЫ
# ==============================================================================
CONFIG = {
    # Docker / БД
    "docker_image": "postgres:18-alpine",
    "container_name": "tuning",
    "db_name": "benchdb",
    "db_user": "postgres",
    "db_password": "password_test",
    "volume_name": "pg_bench",
    "pgbench_scale": 50,  # 100 -> ~1.6 ГБ при стандартной схеме pgbench

    # Параметры pgbench
    "warmup": {
        "clients": 16,
        "threads": 4,
        "time_sec": 10,
        "command": "default"  # или путь к .sql файлу: "-f /path/to/custom.sql"
    },
    "test": {
        "clients": 32,
        "threads": 8,
        "time_sec": 30,
        "command": "default"
    },

    # Пространство параметров для оптимизации
    "tunable_params": {
        "shared_buffers": {"type": "categorical", "values": ["2GB", "4GB", "8GB"]},
        "work_mem": {"type": "int", "low": 4, "high": 64, "step": 4},  # MB
        "maintenance_work_mem": {"type": "int", "low": 64, "high": 1024, "step": 128},  # MB
        "max_parallel_workers_per_gather": {"type": "categorical", "values": [3,5,7,9,11]},
        "checkpoint_completion_target": {"type": "float", "low": 0.7, "high": 0.95},
        "random_page_cost": {"type": "float", "low": 1.0, "high": 1.3},
        "effective_cache_size": {"type": "int", "low": 4, "high": 24, "step": 4}  # GB
    },

    # Оптимизация
    "checked_params":["tps", "latency average", "number of transactions actually processed", "number of failed transactions"],
    "optimization_target": "tps",  # "tps" (максимизировать) или "latency_avg" (минимизировать)
    "n_trials": 5,
    "results_file": "pg_tuning_results.csv"
}

# ==============================================================================
# 🤖 КЛАСС ОПТИМИЗАТОРА
# ==============================================================================
class PostgresConfigOptimizer:
    def __init__(self, cfg: Dict[str, Any]):
        self.cfg = cfg
        self._cleanup_on_exit = False

    def _run(self, cmd: str, check: bool = True, timeout: int = 300) -> subprocess.CompletedProcess:
        """Обёртка над subprocess.run с логированием"""
        print(f"[CMD] {cmd}")
        return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True, timeout=timeout)

    def _cleanup(self):
        """Остановка и удаление контейнера"""
        print("[CLEANUP] Stopping container...")
        self._run(f"docker stop {self.cfg['container_name']} || true", check=False)
        self._run(f"docker rm {self.cfg['container_name']} || true", check=False)

    def _start_container(self, params: Dict[str, str]):
        """Запуск Docker-контейнера с переданными параметрами конфигурации"""
        self._cleanup()
        flags = " ".join([f"-c {k}={v}" for k, v in params.items()])
        cmd = (
            f"docker run -d --name {self.cfg['container_name']} "
            f"-u {self.cfg['db_user']} "
            f"-e POSTGRES_PASSWORD={self.cfg['db_password']} "
            f"-e POSTGRES_USER={self.cfg['db_user']} "
            f"-p 5432:5432 -v {self.cfg['volume_name']}:/var/lib/postgresql/data "
            f"{self.cfg['docker_image']} {flags}"
        )
        self._run(cmd)

    def _wait_ready(self, timeout: int = 60):
        """Ожидание готовности PostgreSQL"""
        print("[DB] Waiting for PostgreSQL to be ready...")
        cmd = f"docker exec {self.cfg['container_name']} pg_isready -U {self.cfg['db_user']} -h 127.0.0.1"
        start = time.time()
        while time.time() - start < timeout:
            res = self._run(cmd, check=False, timeout=5)
            if res.returncode == 0:
                print("[DB] PostgreSQL is ready.")
                time.sleep(3)
                return
            time.sleep(1)
        raise RuntimeError("PostgreSQL did not become ready in time.")

    def _init_db(self):
        """Создание БД и инициализация pgbench (выполняется 1 раз)"""
        print(f"[DB] Initializing pgbench with scale={self.cfg['pgbench_scale']}...")
        cmd = (
            f"docker exec {self.cfg['container_name']} bash -c "
            f"'dropdb {self.cfg['db_name']}; createdb {self.cfg['db_name']}; pgbench -iqs {self.cfg['pgbench_scale']} {self.cfg['db_name']}'"
        )
        self._run(cmd, timeout=600)
        # Анализ после создания
        self._run(f"docker exec {self.cfg['container_name']} psql -U {self.cfg['db_user']} -d {self.cfg['db_name']} -c 'ANALYZE;'", timeout=120)

    def _run_pgbench(self, phase: str) -> Dict[str, float]:
        """Запуск pgbench (warmup или test) и возврат метрик"""
        cfg_phase = self.cfg[phase]
        cmd_parts = [
            f"docker exec {self.cfg['container_name']}",
            f"pgbench -U {self.cfg['db_user']} -h 127.0.0.1",
            f"-c {cfg_phase['clients']} -j {cfg_phase['threads']}",
            f"-T {cfg_phase['time_sec']}"
        ]
        if cfg_phase['command'] != "default":
            cmd_parts.append(cfg_phase['command'])
        cmd_parts.append(self.cfg['db_name'])

        print(f"[TEST] Running pgbench ({phase})...")
        res = self._run(" ".join(cmd_parts), timeout=cfg_phase['time_sec'] + 60)

        if phase == "test":
            return self._parse_pgbench_output(res.stdout, self.cfg['checked_params'])
        return {}

    @staticmethod
    def _parse_pgbench_output(output: str, checked_params:list[str]=None) -> Dict[str, float]:
        """Парсинг stdout pgbench"""
        if checked_params is None:
            checked_params = ["tps"]
        results = {}
        for metric in checked_params:
            match = re.search(rf'{metric}\s*[=:]\s*([\d.]+)\s*', output)
            results[metric] = float(match.group(1)) if match else None
        return results
        # tps_match = re.search(r'tps\s*=\s*([\d.]+)\s*\(excluding', output)
        # lat_match = re.search(r'latency average\s*:\s*([\d.]+)', output)
        # tps_95_match = re.search(r'latency 95th percentile\s*:\s*([\d.]+)', output)
        #
        # return {
        #     "tps_excl": float(tps_match.group(1)) if tps_match else 0.0,
        #     "latency_avg_ms": float(lat_match.group(1)) if lat_match else 0.0,
        #     "latency_95th_ms": float(tps_95_match.group(1)) if tps_95_match else 0.0
        # }

    def objective(self, trial: optuna.Trial) -> float:
        """Целевая функция для Optuna"""
        # 1. Сэмплирование параметров
        params = {}
        for name, spec in self.cfg["tunable_params"].items():
            if spec["type"] == "categorical":
                params[name] = trial.suggest_categorical(name, spec["values"])
            elif spec["type"] == "int":
                params[name] = str(trial.suggest_int(name, spec["low"], spec["high"], step=spec.get("step", 1))) + "MB"
            elif spec["type"] == "float":
                params[name] = str(trial.suggest_float(name, spec["low"], spec["high"]))

        # 2. Развёртывание с новой конфигурацией
        print(f"\n{'='*40}\n[Trial {trial.number}] Config: {params}")
        self._start_container(params)
        self._wait_ready()

        # 3. Прогрев
        self._run_pgbench("warmup")

        # 4. Тест
        metrics = self._run_pgbench("test")

        # 5. Сохранение результатов
        row = {"trial": trial.number, **params, **metrics}
        file_exists = os.path.exists(self.cfg["results_file"])
        with open(self.cfg["results_file"], "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=row.keys())
            if not file_exists:
                writer.writeheader()
            writer.writerow(row)

        print(f"[Trial {trial.number}] TPS: {metrics['tps']:.2f} | Latency Avg: {metrics['latency average']:.2f} ms")
        return metrics[self.cfg["optimization_target"]]

    def run(self):
        """Запуск оптимизации"""
        # Подготовка
        self._cleanup_on_exit = True
        signal.signal(signal.SIGINT, lambda s, f: self._exit_handler())
        signal.signal(signal.SIGTERM, lambda s, f: self._exit_handler())

        # Создание volume (если нет)
        self._run(f"docker volume create {self.cfg['volume_name']} || true")

        # Запуск контейнера для инициализации БД
        print("[INIT] Starting container for DB initialization...")
        self._start_container({})
        self._wait_ready()
        self._init_db()
        self._cleanup()

        # Оптимизация
        direction = "maximize" if "tps" in self.cfg["optimization_target"] else "minimize"
        study = optuna.create_study(direction=direction, sampler=optuna.samplers.TPESampler(seed=42))
        study.optimize(self.objective, n_trials=self.cfg["n_trials"], show_progress_bar=True)

        # Итоги
        print("\n" + "="*50)
        print("✅ ОПТИМИЗАЦИЯ ЗАВЕРШЕНА")
        print(f"📊 Лучшая конфигурация (Trial {study.best_trial.number}):")
        for k, v in study.best_params.items():
            print(f"   {k} = {v}")
        print(f"🏆 {self.cfg['optimization_target']}: {study.best_value:.2f}")
        print(f"📁 Результаты сохранены в: {self.cfg['results_file']}")

        # Вывод таблицы
        df = pd.read_csv(self.cfg["results_file"])
        print("\n📋 Таблица результатов (первые 5 строк):")
        print(df.head().to_markdown(index=False))

        self._cleanup()
        self._cleanup_on_exit = False

    def _exit_handler(self):
        print("\n[INTERRUPT] Завершение работы...")
        if self._cleanup_on_exit:
            self._cleanup()
        exit(1)

# ==============================================================================
if __name__ == "__main__":
    # Примечание: Для work_mem в Docker -c указывается без суффикса MB/GB в некоторых версиях,
    # но PG16 поддерживает суффиксы. В коде выше добавлен "MB" для int-параметров.
    # shared_buffers и effective_cache_size требуют суффиксов GB/MB.

    # Корректировка формата значений перед передачей в Docker (PG требует суффиксы для размеров)
    # В objective() это уже учтено, но для categorical значений нужно убедиться в суффиксах.

    tuner = PostgresConfigOptimizer(CONFIG)
    tuner.run()