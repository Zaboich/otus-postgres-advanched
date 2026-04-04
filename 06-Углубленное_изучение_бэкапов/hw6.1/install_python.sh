#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')


IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')
IP_ADDR4=$(getent hosts vm-otus4 | awk '{ print $1 }')
IP_ADDR5=$(getent hosts vm-otus5 | awk '{ print $1 }')
IP_ADDR6=$(getent hosts vm-otus6 | awk '{ print $1 }')

echo "Установка python"
sudo apt install -y -qq python3-venv python-is-python3 > /dev/null 2>&1

echo "Подготовка каталогов"
sudo mkdir -p -m 755 /opt/app
sudo chown -R yc-user:yc-user /opt/app

echo "Создание venv"
python -m venv /opt/app
source /opt/app/bin/activate

pip install --upgrade pip > /dev/null
pip install psycopg2-binary

echo ""



