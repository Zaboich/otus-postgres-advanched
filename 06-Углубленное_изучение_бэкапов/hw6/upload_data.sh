#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"
# Загрузка данных в кластер

#IP_HAPROXY=$(getent hosts vm-otus7 | awk '{ print $1 }')

echo "HAPROXY = ${IP_HAPROXY}"

curl https://edu.postgrespro.ru/demo-20250901-3m.sql.gz -o demo-20250901-3m.sql.gz
echo "Загрузка дампа demo через ${IP_HAPROXY} HAPROXY"
gunzip -c demo-20250901-3m.sql.gz | psql -h ${IP_HAPROXY} -U postgres -w
