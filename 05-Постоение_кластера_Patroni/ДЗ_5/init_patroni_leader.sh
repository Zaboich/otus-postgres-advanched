#!/bin/bash
set -e

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
