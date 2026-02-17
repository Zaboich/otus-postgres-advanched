#!/bin/bash
set -e

sudo apt install -y -qq python3-venv python-is-python3 >> /dev/null

sudo mkdir -p /opt/patroni
sudo mkdir -p /etc/patroni
sudo mkdir -p /var/log/patroni

python -m venv /opt/patroni/.venv
source /opt/patroni/.venv/bin/activate

pip install --upgrade pip

pip install 'patroni[etcd3]'
pip install 'psycopg2-binary'
deactivate

chown -R postgres:postgres /opt/patroni

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')

IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')
