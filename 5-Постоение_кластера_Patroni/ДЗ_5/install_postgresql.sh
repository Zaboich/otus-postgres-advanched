#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="ru_RU.UTF-8,"
export LANGUAGE="ru_RU.UTF-8"
export LANG="ru_RU.UTF-8"
export LC_TIME="ru_RU.UTF-8",
export LC_MONETARY="ru_RU.UTF-8",
export LC_ADDRESS="ru_RU.UTF-8",
export LC_TELEPHONE="ru_RU.UTF-8",
export LC_NAME="ru_RU.UTF-8",
export LC_MEASUREMENT="ru_RU.UTF-8",
export LC_IDENTIFICATION="ru_RU.UTF-8",
export LC_NUMERIC="ru_RU.UTF-8",
export LC_PAPER="ru_RU.UTF-8",

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt -y install postgresql mc

# Установка пароля пользователя postgres
export PGPASSWORD=postgres
sudo -u postgres psql -c "alter user postgres password '${PGPASSWORD}';"
echo "localhost:5432:*:postgres:${PGPASSWORD}" > .pgpass
chmod 0600 ~/.pgpass

sudo -u postgres psql -c "CREATE USER replicator replication login encrypted password 'password';"
echo "host    replication     all             192.168.0.0/24          scram-sha-256" | sudo tee -a /etc/postgresql/18/main/pg_hba.conf
sudo sed -i "/^#listen_addresses/s/.*/listen_addresses = '*'/" /etc/postgresql/18/main/postgresql.conf