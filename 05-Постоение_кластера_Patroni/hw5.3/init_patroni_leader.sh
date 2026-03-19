#!/bin/bash
set -e

# Leader создаётся без базы. Инициализацию БД должна выполнить Patroni

echo "Остановка сервиса postgres"
sudo systemctl stop postgresql@18-main
sudo systemctl stop postgresql.service
sudo systemctl disable postgresql

echo "Проверка конфигурации Patroni"
sudo -u postgres /opt/patroni/bin/patroni --validate-config /etc/patroni/patroni.yml

# на Replica Node удаляются файлы данных Postgres
echo "Очистка data dir postgres"
sudo rm -rf /var/lib/postgresql/18/main
sudo mkdir -p -m 700 /var/lib/postgresql/18/main
sudo chown -R postgres:postgres /var/lib/postgresql/18/main

## Запуск Patroni и Postgres на Leader Node
## предварительно установлен и настроен Postgres и Patroni
echo "Запуск сервиса Patroni"
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni

echo "Ожидание 10 сек"
sleep 10

echo "Статус сервиса Patroni"
sudo systemctl status patroni

echo "Список Patroni nodes"
/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list
