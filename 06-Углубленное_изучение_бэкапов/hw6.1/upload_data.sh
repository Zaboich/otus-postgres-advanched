#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"
# Загрузка данных в кластер

curl https://edu.postgrespro.ru/demo-20250901-3m.sql.gz -o demo-20250901-3m.sql.gz

gunzip -c demo-20250901-3m.sql.gz | sudo -u postgres psql
