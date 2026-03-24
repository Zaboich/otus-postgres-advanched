#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')


#IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
#IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
#IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')
IP_ADDR4=$(getent hosts vm-otus4 | awk '{ print $1 }')
IP_ADDR5=$(getent hosts vm-otus5 | awk '{ print $1 }')
IP_ADDR6=$(getent hosts vm-otus6 | awk '{ print $1 }')

echo "Установка Haproxy"
sudo apt install -y -qq haproxy > /dev/null 2>&1

echo "Подготовка конфигурации"
sudo systemctl stop haproxy
sudo mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.orig
sudo mv /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
echo "Обработка шаблона /etc/haproxy/haproxy.cfg";

# Установка полей в файле шаблона
sudo sed -i "s/{IP_ADDR4}/${IP_ADDR4}/g" /etc/haproxy/haproxy.cfg
sudo sed -i "s/{IP_ADDR5}/${IP_ADDR5}/g" /etc/haproxy/haproxy.cfg
sudo sed -i "s/{IP_ADDR6}/${IP_ADDR6}/g" /etc/haproxy/haproxy.cfg

echo "Проверка конфигурации"
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

sudo systemctl start haproxy
echo "Haproxy запущен на ${IP_ADDR}:5432 и ${IP_ADDR}:5433"

