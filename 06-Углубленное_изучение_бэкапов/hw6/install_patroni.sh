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
sudo mkdir -p -m 755 /opt/patroni
sudo chown -R yc-user:yc-user /opt/patroni
sudo mkdir -p /etc/patroni
sudo mkdir -p /var/log/patroni

echo "Создание venv"
python -m venv /opt/patroni
source /opt/patroni/bin/activate

pip install --upgrade pip > /dev/null

pip install 'patroni[etcd3]' > /dev/null
pip install 'psycopg2-binary' > /dev/null

sudo chown -R postgres:postgres /opt/patroni

if [ ! -f /tmp/patroni.yml ]; then
  echo "Файл /tmp/patroni.yml не найден. Выход";
  exit 1;
fi

sudo mv /tmp/patroni.yml /etc/patroni/patroni.yml
echo "Обработка шаблона конфигурации /etc/patroni/patroni.yml";

# Установка полей в файле шаблона
sudo sed -i "s/{HOSTNAME}/${HOSTNAME}/g" /etc/patroni/patroni.yml
sudo sed -i "s/{IP_ADDR}/${IP_ADDR}/g" /etc/patroni/patroni.yml
sudo sed -i 's/{HOSTNAME_ETCD1}/vm-otus1/g' /etc/patroni/patroni.yml
sudo sed -i 's/{HOSTNAME_ETCD2}/vm-otus2/g' /etc/patroni/patroni.yml
sudo sed -i 's/{HOSTNAME_ETCD3}/vm-otus3/g' /etc/patroni/patroni.yml

echo "Patroni установлен и сконфигурирован. Сервис patroni не запущен"



