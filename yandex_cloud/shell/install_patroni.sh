#!/bin/bash
set -e

sudo apt install -y -q python3-venv python-is-python3

sudo mkdir -p /opt/patroni
sudo chown postgres:postgres /opt/patroni
sudo -u postgres python -m venv /opt/patroni/.venv
sudo -u postgres /opt/patroni/.venv/bin/pip install 'patroni[etcd3]'
sudo -u postgres /opt/patroni/.venv/bin/pip install 'psycopg2-binary'

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')

IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')
