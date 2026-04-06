#!/usr/bin/env python3
"""
Load test script for PostgresPro Demo Database "Airlines"
Inserts realistic booking records into bookings table every second.
"""

import sys
import time
import random
import string
import psycopg2
from datetime import datetime, timedelta
from psycopg2 import OperationalError, sql
from contextlib import contextmanager

# ================= КОНФИГУРАЦИЯ =================
DB_CONFIG = {
    'host': 'localhost',
    'port': '5432',
    'dbname': 'demo',  # Имя демо-БД от postgrespro
    'user': 'postgres',
    'password': 'postgres',
    'options': '-c search_path=bookings'  # Важно: схема bookings
}

# Параметры теста
DEFAULT_DURATION = 300  # секунды по умолчанию
MIN_AMOUNT = 1000.00   # минимальная сумма бронирования
MAX_AMOUNT = 150000.00 # максимальная сумма

# Генерация реалистичных данных
AIRPORT_CODES = ['LED', 'DME', 'SVX', 'OVB', 'KGD', 'IKT', 'KZN', 'ROV', 'UFA', 'VVO']
# ================================================

def generate_book_ref():
    """Генерирует уникальный 6-символьный код бронирования (буквы+цифры)."""
    chars = string.ascii_uppercase + string.digits
    return ''.join(random.choices(chars, k=6))

def generate_book_date():
    """Генерирует дату бронирования в разумном диапазоне."""
    # Бронирование от 60 дней до вылета до текущего момента
    start = datetime.now() - timedelta(days=60)
    end = datetime.now()
    random_seconds = random.randint(0, int((end - start).total_seconds()))
    return start + timedelta(seconds=random_seconds)

def generate_total_amount():
    """Генерирует реалистичную сумму бронирования."""
    return round(random.uniform(MIN_AMOUNT, MAX_AMOUNT), 2)

@contextmanager
def get_db_connection(config):
    """Контекстный менеджер для подключения к БД."""
    conn = None
    try:
        conn = psycopg2.connect(**config)
        print(f"✓ Подключено к БД: {config['dbname']}@{config['host']}")
        yield conn
    except OperationalError as e:
        print(f"✗ Ошибка подключения: {e}")
        raise
    finally:
        if conn:
            conn.close()
            print("✓ Соединение закрыто")

def get_duration():
    """Получает длительность теста из аргументов или использует дефолт."""
    if len(sys.argv) > 1:
        try:
            duration = int(sys.argv[1])
            if duration <= 0:
                raise ValueError
            return duration
        except ValueError:
            print("⚠ Неверный аргумент. Используйте целое положительное число секунд.")
            sys.exit(1)
    return DEFAULT_DURATION

def main():
    duration = get_duration()
    print(f"🚀 Запуск нагрузочного теста на {duration} сек.")
    print(f"📊 Цель: таблица bookings.bookings")
    print("-" * 50)

    stats = {'inserted': 0, 'errors': 0}
    start_time = time.time()
    next_tick = start_time

    try:
        with get_db_connection(DB_CONFIG) as conn:
            cursor = conn.cursor()

            # Проверяем доступность таблицы
            cursor.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables
                    WHERE table_schema = 'bookings' AND table_name = 'bookings'
                );
            """)
            if not cursor.fetchone()[0]:
                raise RuntimeError("Таблица bookings.bookings не найдена!")

            while time.time() < start_time + duration:
                try:
                    # Генерируем данные для вставки
                    book_ref = generate_book_ref()
                    book_date = generate_book_date()
                    total_amount = generate_total_amount()

                    # Выполняем вставку
                    insert_sql = """
                        INSERT INTO bookings (book_ref, book_date, total_amount)
                        VALUES (%s, %s, %s)
                    """
                    cursor.execute(insert_sql, (book_ref, book_date, total_amount))
                    conn.commit()

                    stats['inserted'] += 1
                    elapsed = time.time() - start_time
                    print(f"[{elapsed:5.1f}с] + Бронь #{stats['inserted']}: "
                          f"{book_ref} | {total_amount:,.2f} RUB")

                except psycopg2.errors.UniqueViolation:
                    # Код уже существует — генерируем новый и пробуем ещё раз
                    conn.rollback()
                    continue
                except Exception as e:
                    conn.rollback()
                    stats['errors'] += 1
                    print(f"⚠ Ошибка вставки: {e}")

                # Точное планирование следующего шага (ровно 1 секунда)
                next_tick += 0.1
                sleep_time = next_tick - time.time()
                if sleep_time > 0:
                    time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\n⚠ Прервано пользователем")
    except Exception as e:
        print(f"\n✗ Критическая ошибка: {e}")
    finally:
        # Итоговая статистика
        total_time = time.time() - start_time
        print("\n" + "=" * 50)
        print("📈 РЕЗУЛЬТАТЫ ТЕСТА")
        print(f"   Длительность: {total_time:.1f} сек")
        print(f"   Успешных вставок: {stats['inserted']}")
        print(f"   Ошибок: {stats['errors']}")
        if total_time > 0:
            print(f"   Средняя скорость: {stats['inserted']/total_time:.2f} записей/сек")
        print("=" * 50)

if __name__ == "__main__":
    main()