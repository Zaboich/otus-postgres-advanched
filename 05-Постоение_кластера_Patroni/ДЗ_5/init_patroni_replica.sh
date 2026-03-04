#!/bin/bash
set -e

## Запуск Patroni и Postgres на Leader Node
## предварительно установлен и настроен Postgres и Patroni

# на Replica Node удаляются файлы данных Postgres
sudo rm -rf /var/lib/postgresql/18/main
sudo mkdir -p -m 700 /var/lib/postgresql/18/main
sudo chown -R postgres:postgres /var/lib/postgresql/18/main

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
