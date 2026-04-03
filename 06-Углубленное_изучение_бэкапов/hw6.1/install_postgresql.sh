#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update  > /dev/null 2>&1
sudo apt install -y --quiet postgresql > /dev/null 2>&1
echo "Установлен Postgres 18"

# Установка пароля пользователя postgres
export PGPASSWORD=postgres
sudo -u postgres psql -c "alter user postgres password '${PGPASSWORD}';"

# Содание пользователя replicator c правами репликации и паролем password
sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION LOGIN ENCRYPTED PASSWORD 'replicator';"

echo "localhost:5432:*:postgres:${PGPASSWORD}" > .pgpass
echo "localhost:5432:*:replicator:replicator" >> .pgpass
chmod 0600 ~/.pgpass
echo "Создан .pgpass"

echo "Настройка конфигурационных файлов"
echo "Прослушивание всех интерфейсов d /etc/postgresql/18/main/postgresql.conf"
sudo sed -i "/^#listen_addresses/s/.*/listen_addresses = '*'/" /etc/postgresql/18/main/postgresql.conf

# Разрешение на подключение replication для пользователя replicator из подсети 192.168.0.0/24
echo "host    replication     replicator             0.0.0.0/0          scram-sha-256" | sudo tee -a /etc/postgresql/18/main/pg_hba.conf
echo "host    all     postgres             127.0.0.0/24          scram-sha-256" | sudo tee -a /etc/postgresql/18/main/pg_hba.conf
echo "host    all     postgres             192.168.0.0/24          scram-sha-256" | sudo tee -a /etc/postgresql/18/main/pg_hba.conf