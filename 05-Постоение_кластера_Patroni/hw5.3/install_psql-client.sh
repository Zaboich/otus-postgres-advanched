#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="C.UTF-8"

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update  > /dev/null 2>&1
sudo apt install -y --quiet postgresql-client > /dev/null 2>&1
echo "Установлен client psql 18"

export PGPASSWORD=postgres
echo "*:*:*:postgres:${PGPASSWORD}" > .pgpass
chmod 0600 ~/.pgpass
echo "Создан .pgpass"
