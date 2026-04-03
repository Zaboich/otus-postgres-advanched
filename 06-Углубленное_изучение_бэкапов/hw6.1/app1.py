import sys
import time
import psycopg2
from datetime import datetime
from psycopg2 import sql, OperationalError

# ================= КОНФИГУРАЦИЯ =================
# Параметры подключения к БД
DB_CONFIG = {
    'host': 'localhost',
    'port': '5432',
    'dbname': 'demo',  # Замените на имя вашей БД
    'user': 'postgres',         # Замените на пользователя
    'password': 'postgres'      # Замените на пароль
}

# Время работы скрипта в секундах (по умолчанию 10, если не передано в аргументах)
DEFAULT_DURATION = 100
# ================================================

def get_duration():
    """Получает длительность работы из аргументов командной строки или использует дефолт."""
    if len(sys.argv) > 1:
        try:
            return int(sys.argv[1])
        except ValueError:
            print("Ошибка: Аргумент должен быть целым числом (секунды).")
            sys.exit(1)
    return DEFAULT_DURATION

def main():
    duration = get_duration()
    print(f"Запуск скрипта. Длительность: {duration} сек.")

    conn = None
    cursor = None

    try:
        # Подключение к БД
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        print("Подключение к БД успешно.")

        start_time = time.time()
        end_time = start_time + duration

        # Переменная для планирования точного времени следующей вставки
        next_tick = start_time

        while time.time() < end_time:
            # Получаем текущее время
            now = datetime.now()

            # Вставка данных (id добавится автоматически благодаря SERIAL)
            insert_query = "INSERT INTO logs (date_time) VALUES (%s)"
            cursor.execute(insert_query, (now,))
            conn.commit()

            print(f"[{datetime.now().strftime('%H:%M:%S')}] Запись добавлена. Осталось: {int(end_time - time.time())} сек.")

            # Планирование следующего шага (ровно через 1 секунду от начала предыдущего цикла)
            next_tick += 1.0
            sleep_time = next_tick - time.time()

            # Если база данных работает медленно и мы уже отстали от графика, не спим отрицательное время
            if sleep_time > 0:
                time.sleep(sleep_time)

    except OperationalError as e:
        print(f"Ошибка подключения к БД: {e}")
    except KeyboardInterrupt:
        print("\nРабота скрипта прервана пользователем.")
    except Exception as e:
        print(f"Произошла ошибка: {e}")
    finally:
        # Закрытие соединений
        if cursor:
            cursor.close()
        if conn:
            conn.close()
        print("Соединение с БД закрыто. Скрипт завершен.")

if __name__ == "__main__":
    main()