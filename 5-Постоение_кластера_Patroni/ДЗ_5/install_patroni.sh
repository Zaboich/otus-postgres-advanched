#!/bin/bash
set -e

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

sudo apt install -y -qq python3-venv python-is-python3

sudo mkdir -p -m 755 yc-user /opt/patroni
sudo mkdir -p /etc/patroni
sudo mkdir -p /var/log/patroni

python -m venv /opt/patroni/.venv
source /opt/patroni/.venv/bin/activate

pip install --upgrade pip

pip install 'patroni[etcd3]'
pip install 'psycopg2-binary'
deactivate

chown -R postgres:postgres /opt/patroni

if [ !-f /tmp/patroni.yml ]; then
  echo "Файл /tmp/patroni.yml не найден. Выход";
  exit 1;
fi

sudo mv /tmp/patroni.yml /etc/patroni.yml
echo "Обработка шаблона /etc/patroni.yml";

# Установка полей в файле шаблона
sudo sed -i 's/\{HOSTNAME\}/$HOSTNAME/g' /etc/patroni.yml
sudo sed -i 's/\{IP_ADDR\}/$IP_ADDR/g' /etc/patroni.yml
sudo sed -i 's/\{HOSTNAME_ETCD1\}/vm-otus1/g' /etc/patroni.yml
sudo sed -i 's/\{HOSTNAME_ETCD2\}/vm-otus2/g' /etc/patroni.yml
sudo sed -i 's/\{HOSTNAME_ETCD3\}/vm-otus3/g' /etc/patroni.yml



