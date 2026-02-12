#!/bin/bash
set -e

sudo apt -y install etcd-server && sudo apt -y install etcd-client

# Параметры конфигурации можно задавать через env или файл /etc/default/etcd

# общая часть имён хостов
HOSTNAME=$(hostname)
IP_ADDR=$(hostname -I | sed -e 's/[[:space:]]*$//')
echo "ETCD_NAME='${HOSTNAME}'
ETCD_LISTEN_PEER_URLS='http://127.0.0.1:2380,http://${IP_ADDR}:2380'
ETCD_LISTEN_CLIENT_URLS='http://127.0.0.1:2379,http://${IP_ADDR}:2379'
ETCD_INITIAL_CLUSTER='${HOSTNAME}=http://${HOSTNAME}:2380'
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

etcdctl member add vm-otus1 --peer-urls=http://192.168.0.16:2380
etcdctl member add vm-otus2 --peer-urls=http://192.168.0.15:2380
etcdctl member add vm-otus3 --peer-urls=http://192.168.0.31:2380