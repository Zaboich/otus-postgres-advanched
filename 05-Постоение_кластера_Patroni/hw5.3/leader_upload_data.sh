#!/bin/bash
set -e

# Предварительное наполенение данными

curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz
sudo -u postgres psql -c "CREATE DATABASE demo;"
gunzip -c demo-20250901-6m.sql.gz | psql -h localhost -U postgres
