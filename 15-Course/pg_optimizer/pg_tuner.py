#!/usr/bin/env python3
# автоматизация процесса выбора оптимальных конфигурационных настроек
"""
PostgreSQL Config Optimizer v1.6.3
Развёртывание: Local Docker (разделённые клиент/сервер)
Оптимизатор: Optuna (TPE / Bayesian Optimization)
Тестирование: pgbench + сбор внутренних метрик PG
Логирование: Единый вывод в stdout + уникальный файл лога
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
class PostgresConfigOptimizer:
    def __init__(self, cfg: Dict[str, Any]):
        self.cfg = cfg
        self._cleanup_on_exit = False

    def _run(self, cmd: str, check: bool = True, timeout: int = 1800) -> subprocess.CompletedProcess:
        """Обёртка над subprocess.run с логированием"""
        logging.info("[CMD] %s", cmd)
        return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True, timeout=timeout)

    def _cleanup(self):
        """Остановка и удаление обоих контейнеров"""
        logging.info("[CLEANUP] Stopping containers & network...")
        for cname in [self.cfg['client_container_name'], self.cfg['db_container_name']]:
            self._run(f"docker stop {cname} || true", check=False)
            self._run(f"docker rm {cname} || true", check=False)

    def _create_network(self):
        """Создание изолированной Docker-сети"""
        self._run(f"docker network create {self.cfg['docker_network']} || true")

    def _remove_network(self):
        """Удаление сети после завершения"""
        self._run(f"docker network rm {self.cfg['docker_network']} || true")

    def _start_db_container(self, params: Dict[str, str]):
        """Запуск PostgreSQL в выделенном контейнере"""
        self._cleanup()
        flags = " ".join([f"-c {k}={v}" for k, v in params.items()])
        cmd = (
            f"docker run -d --name {self.cfg['db_container_name']} --network {self.cfg['docker_network']} "
            f"--memory {self.cfg['container_memory']} --cpus {self.cfg['container_cpu']} "
            f"-u {self.cfg['db_user']} "
            f"-e POSTGRES_PASSWORD={self.cfg['db_password']} -e POSTGRES_USER={self.cfg['db_user']} "
            f"-p 5432:5432 -v {self.cfg['volume_name']}:/var/lib/postgresql/data "
            f"{self.cfg['docker_image']} {flags}"
        )
        self._run(cmd)

    def _start_client_container(self):
        """Запуск легковесного клиентского контейнера (pgbench)"""
        cmd = (
            f"docker run -d --name {self.cfg['client_container_name']} --network {self.cfg['docker_network']} "
            f"--memory 2G --cpus 2 "
            f"{self.cfg['docker_image']} tail -f /dev/null"
        )
        self._run(cmd)
        time.sleep(2)

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

    def _run_pgbench(self, phase: str) -> Dict[str, float]:
        """Запуск pgbench с логированием прогресса TPS"""
        cfg_phase = self.cfg[phase]
        progress_sec = cfg_phase.get("progress_sec", 0)

        cmd_parts = [
            f"docker exec -e PGPASSWORD={self.cfg['db_password']} {self.cfg['client_container_name']}",
            f"pgbench -U {self.cfg['db_user']} -h {self.cfg['db_container_name']}",
            f"-c {cfg_phase['clients']} -j {cfg_phase['threads']}",
            f"-T {cfg_phase['time_sec']}"
        ]
        # Добавляем флаг прогресса, если задан > 0
        if progress_sec and progress_sec > 0:
            cmd_parts.append(f"-P {progress_sec}")

        if cfg_phase['command'] != "default":
            cmd_parts.append(cfg_phase['command'])
        cmd_parts.append(self.cfg['db_name'])

        logging.info("[TEST] Running pgbench (%s) from client container...", phase)
        res = self._run(" ".join(cmd_parts), timeout=cfg_phase['time_sec'] + 60)

        # Логирование промежуточных метрик из stderr
        if res.stderr:
            for line in res.stderr.splitlines():
                line = line.strip()
                if line.startswith("progress:"):
                    logging.info("[PG_PROGRESS] %s", line)
                    # Опционально: можно извлечь только TPS для машинного парсинга
                    # tps_match = re.search(r'(\d+\.\d+)\s*tps', line)
                    # if tps_match: logging.info("[PG_PROGRESS_TPS] %.2f", float(tps_match.group(1)))

        if phase == "test":
            return self._parse_pgbench_output(res.stdout, self.cfg['checked_params'])
        return {}

    def _collect_pg_metrics(self) -> Dict[str, float]:
        """Сбор внутренних метрик PostgreSQL после теста (совместимо с PG 15–18)"""
        query = f"""
SELECT json_build_object(
    'checkpoints_req', c.num_requested,
    'checkpoints_timed', c.num_timed,
    'deadlocks', d.deadlocks,
    'temp_bytes', d.temp_bytes,
    'blk_read_time', d.blk_read_time,
    'blk_write_time', d.blk_write_time
    ) FROM pg_stat_checkpointer c, pg_stat_database d 
    WHERE d.datname =  '{self.cfg['db_name']}';
        """
        cmd = (
            f"docker exec {self.cfg['db_container_name']} "
            f"psql -q -U {self.cfg['db_user']} -d {self.cfg['db_name']} "
            f"-t -A -c \"{query}\""
        )
        try:
            res = self._run(cmd, timeout=30)
            data = json.loads(res.stdout.strip())
            return {k: float(v) if v is not None else 0.0 for k, v in data.items()}
        except Exception as e:
            logging.warning("[WARN] Сбор PG-метрик пропущен: %s", e)
            return {}

    @staticmethod
    def _parse_pgbench_output(output: str, checked_params: list[str] = None) -> Dict[str, float]:
        if checked_params is None:
            checked_params = ["tps"]
        results = {}
        for metric in checked_params:
            match = re.search(rf'{metric}\s*[=:]\s*([\d.]+)\s*', output)
            results[metric] = float(match.group(1)) if match else None
        return results

    def objective(self, trial: optuna.Trial) -> float:
        params = {}
        for name, spec in self.cfg["tunable_params"].items():
            if spec["type"] == "categorical":
                params[name] = trial.suggest_categorical(name, spec["values"])
            elif spec["type"] == "int":
                params[name] = str(
                    trial.suggest_int(name=name, low=spec["low"], high=spec["high"], step=spec.get("step", 1))) + "MB"
            elif spec["type"] == "float":
                params[name] = str(trial.suggest_float(name=name, low=spec["low"], high=spec["high"]))

        logging.info("%s\n[Trial %d] Config: %s", "=" * 40, trial.number, params)
        self._start_db_container(params)
        self._start_client_container()
        self._wait_ready()

        self._run_pgbench("warmup")
        metrics = self._run_pgbench("test")
        pg_metrics = self._collect_pg_metrics()

        row = {"trial": trial.number, **params, **metrics, **pg_metrics}
        file_exists = os.path.exists(self.cfg["results_file"])
        with open(self.cfg["results_file"], "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=sorted(row.keys()))
            if not file_exists:
                writer.writeheader()
            writer.writerow(row)

        target_val = metrics[self.cfg["optimization_target"]]
        if target_val is None:
            logging.warning("[Trial %d] Пропущен (метрика '%s' не найдена)", trial.number,
                            self.cfg["optimization_target"])
            raise optuna.TrialPruned()

        logging.info("[Trial %d] %s: %.2f | PG Checkpoints Req: %.0f",
                     trial.number, self.cfg["optimization_target"], target_val, pg_metrics.get("checkpoints_req", 0))
        return target_val

    def get_direction_optimize(self):
        return "maximize" if self.cfg["optimization_target"] in ["tps",
                                                                 "number of transactions actually processed"] else "minimize"

    def is_sort_asc(self):
        return self.get_direction_optimize() != 'maximize'

    def run_test(self):
        self._cleanup_on_exit = True
        signal.signal(signal.SIGINT, lambda s, f: self._exit_handler())
        signal.signal(signal.SIGTERM, lambda s, f: self._exit_handler())

        logging.info("Параметры поиска оптимальной конфигурации: %s", self.cfg)
        self._run(f"docker volume create {self.cfg['volume_name']} || true")
        self._create_network()

        logging.info("[INIT] Starting DB for initialization...")
        self._start_db_container({})
        self._start_client_container()
        self._wait_ready()
        self._init_db()
        self._cleanup()

        target_col = self.cfg["optimization_target"]
        direction = self.get_direction_optimize()
        tunable_names = list(self.cfg["tunable_params"].keys())

        study = optuna.create_study(direction=direction, sampler=optuna.samplers.TPESampler(seed=42))
        study.optimize(self.objective, n_trials=self.cfg["n_trials"], show_progress_bar=True)

        # Итоги
        logging.info("%s\n✅ ОПТИМИЗАЦИЯ ЗАВЕРШЕНА\n%s", "=" * 50, "=" * 50)
        logging.info("Лучшая конфигурация (Trial %d):", study.best_trial.number)
        for k, v in study.best_params.items():
            logging.info("   %s = %s", k, v)
        logging.info("%s: %.2f", self.cfg["optimization_target"], study.best_value)
        logging.info("Результаты сохранены в: %s", self.cfg["results_file"])

        df = pd.read_csv(self.cfg["results_file"])
        df_sorted = df.sort_values(by=target_col, ascending=self.is_sort_asc()).head(5)
        sort_label = f"TOP-5 by {direction}"
        logging.info("%s '%s':", sort_label, target_col)

        numeric_cols = df_sorted.select_dtypes(include='number').columns
        display_df = df_sorted.copy()
        for col in numeric_cols:
            if col != "trial":
                display_df[col] = display_df[col].apply(lambda x: f"{x:.2f}" if pd.notna(x) else "N/A")
        logging.info("%s", display_df.to_markdown(index=False))

        logging.info("Статистика по '%s':", target_col)
        logging.info("Min: %.2f | Max: %.2f | Mean: %.2f | Std: %.2f",
                     df[target_col].min(), df[target_col].max(), df[target_col].mean(), df[target_col].std())

        logging.info("Важность гиперпараметров (оценка влияния на '%s'):", target_col)
        try:
            importances = get_param_importances(
                study, evaluator=FanovaImportanceEvaluator(seed=42),
                params=tunable_names,
                target=lambda t: t.value if direction == "maximize" else -t.value
            )
            importances_sorted = dict(sorted(importances.items(), key=lambda x: x[1], reverse=True))
            bar_header = f"{'Параметр':<40} {'Важность':>10} {'Визуализация'}"
            logging.info("%s\n%s", bar_header, "-" * 70)
            for param, imp in importances_sorted.items():
                bar_len = int(imp * 50)
                logging.info("%s %6.2f%%  %s", param, imp * 100, "█" * bar_len)
            top_param = next(iter(importances_sorted))
            logging.info("💡 Параметр '%s' наиболее сильно влияет на %s.", top_param, target_col)
        except Exception as e:
            logging.warning("Не удалось рассчитать важности: %s", e)

        try:
            optuna.visualization.matplotlib.plot_param_importances(study, evaluator=FanovaImportanceEvaluator(),
                                                                   params=tunable_names)
            plt.savefig("importances.png", dpi=300, bbox_inches="tight")
            logging.info("📊 График сохранён: importances.png")
        except ImportError:
            pass

        self._cleanup()
        self._remove_network()
        self._cleanup_on_exit = False

    def _exit_handler(self):
        logging.warning("[INTERRUPT] Завершение работы...")
        if self._cleanup_on_exit:
            self._cleanup()
            self._remove_network()
        sys.exit(1)


# ==============================================================================
if __name__ == "__main__":
    CONFIG = load_and_setup_config("config.yaml")
    logging.info("✅ Конфиг загружен из config.yaml")
    logging.info("Лог:      %s", CONFIG['log_file'])
    logging.info("Результаты: %s", CONFIG['results_file'])
    logging.info("%s", "=" * 50)

    tuner = PostgresConfigOptimizer(CONFIG)
    tuner.run_test()