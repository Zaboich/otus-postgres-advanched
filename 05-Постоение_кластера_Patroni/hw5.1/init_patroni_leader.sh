#!/bin/bash
set -e

# Предварительное наполенение данными

curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz
sudo -u postgres psql -c "CREATE DATABASE demo;"
gunzip -c demo-20250901-6m.sql.gz | psql -h localhost -U postgres

echo "Остановка сервиса postgres"
sudo systemctl stop postgresql@18-main
sudo systemctl stop postgresql.service
sudo systemctl disable postgresql

echo "Проверка конфигурации Patroni"
sudo -u postgres /opt/patroni/bin/patroni --validate-config /etc/patroni/patroni.yml

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
