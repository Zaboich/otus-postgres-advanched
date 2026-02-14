#!/bin/bash
set -e

sudo apt install -y -q etcd-server etcd-client

# Параметры конфигурации можно задавать через env или файл /etc/default/etcd

# общая часть имён хостов
HOSTNAME=$(hostname)
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')

IP_ADDR1=$(getent hosts vm-otus1 | awk '{ print $1 }')
IP_ADDR2=$(getent hosts vm-otus2 | awk '{ print $1 }')
IP_ADDR3=$(getent hosts vm-otus3 | awk '{ print $1 }')

echo "ETCD_NAME='${HOSTNAME}'
ETCD_LISTEN_PEER_URLS='http://127.0.0.1:2380,http://${IP_ADDR}:2380'
ETCD_LISTEN_CLIENT_URLS='http://127.0.0.1:2379,http://${IP_ADDR}:2379'
ETCD_INITIAL_CLUSTER='${HOSTNAME}=http://${IP_ADDR}:2380'
ETCD_INITIAL_CLUSTER_STATE='new'
ETCD_INITIAL_CLUSTER_TOKEN='etcd_otus_Claster'
ETCD_DATA_DIR='/var/lib/etcd'
ETCD_ELECTION_TIMEOUT='10000'
ETCD_HEARTBEAT_INTERVAL='2000'
ETCD_ADVERTISE_CLIENT_URLS='http://${HOSTNAME}:2379'
ETCD_INITIAL_ADVERTISE_PEER_URLS='http://${HOSTNAME}:2380'
ETCD_INITIAL_ELECTION_TICK_ADVANCE='false'
ETCD_ENABLE_V2='true'
" | sudo tee /etc/default/etcd

sudo systemctl restart etcd

sudo etcdctl endpoint status --cluster -w table

for NUM in $(seq 1 1 3); do
  VM_NAME = "vm-otus${NUM}"
  if[ "${VM_NAME}" != "vm-otus${NUM}"]; then
    sudo etcdctl member add vm-otus1 --peer-urls=http://vm-otus1:2380;
  fi
done

etcdctl member add vm-otus1 --peer-urls=http://vm-otus1:2380
etcdctl member add vm-otus2 --peer-urls=http://vm-otus2:2380
etcdctl member add vm-otus3 --peer-urls=http://vm-otus3:2380