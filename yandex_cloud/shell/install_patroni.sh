#!/bin/bash
set -e

echo "Установка python"
sudo apt install -y -q python3-venv python-is-python3

echo "mkdir -p /opt/patroni"
sudo mkdir -p /opt/patroni
#echo "chown  /opt/patroni"
sudo chown yc-user:yc-user /opt/patroni


echo "Создание venv"
python -m venv /opt/patroni
source /opt/patroni/bin/activate

echo "Установка пакетов patroni"
/opt/patroni/bin/pip install 'patroni[etcd3]'
/opt/patroni/bin/pip install 'psycopg2-binary'

sudo chown -R postgres:postgres /opt/patroni

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')

IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')
