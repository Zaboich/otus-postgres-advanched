#!/bin/bash
set -e

# Загрузка данных в кластер

IP_HAPROXY=$(getent hosts vm-otus7 | awk '{ print $1 }')

curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz
#psql -h $IP_ADDR6 -U postgres -w -c "CREATE DATABASE demo;"
echo "Загрузка дампа demo через ${IP_HAPROXY} HAPROXY"
gunzip -c demo-20250901-6m.sql.gz | psql -h ${IP_HAPROXY} -U postgres -w
