# установка CLI for Windows
https://yandex.cloud/ru/docs/cli/operations/install-cli


# создание профиля
https://yandex.cloud/ru/docs/cli/operations/profile/profile-create

yc config profile create vic

yc init

## token:
y0_AgAAAAAQIbZeAATuwQAAAAEGHicVAAAhx0EQdilMhpLFUyJBQBylwTCxAA

yc config list

# 1 Создаем сетевую инфраструктуру:

yc vpc network create --name otus-net --description "otus-net"

yc vpc network list

yc vpc subnet create --name otus-subnet --range 10.0.0.0/24 --network-name otus-net --description "otus-subnet"

yc vpc subnet list

yc dns zone create --name otus-dns --zone staging. --private-visibility enpev3s0gmmlgpfhettj  -- id из network list

yc dns zone list

# 2 Развернем 3 ВМ для etcd:
for i in {1..3}; do yc compute instance create --name etcd$i --hostname etcd$i --cores 2 --memory 2 --create-boot-disk size=10G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/yc_key.pub & done;

yc compute instances list



## 3 перейти в ВМ и установить etcd
ssh -i ~/yc_key yc-user@178.154.231.155
ssh -i ~/yc_key yc-user@158.160.126.70
ssh -i ~/yc_key yc-user@62.84.125.225

sudo apt update && sudo apt upgrade -y && sudo apt install -y etcd-server && sudo apt install -y etcd-client

# 4 проверим, что etcd установлен
systemctl is-enabled etcd
systemctl status etcd
hostname; ps -aef | grep etcd | grep -v grep


etcd --version

ETCDCTL_API=2

echo $ETCDCTL_API

## останавливаем etcd
sudo systemctl stop etcd
sudo systemctl disable etcd

## Удаляем конфигурацию по умолчанию
sudo rm -rf /var/lib/etcd/default


sudo nano /etc/default/etcd

ETCD_NAME="etcd1"
ETCD_LISTEN_CLIENT_URLS="http://10.0.0.19:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.0.19:2379"
ETCD_LISTEN_PEER_URLS="http://10.0.0.19:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.19:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-postgres-cluster"
ETCD_INITIAL_CLUSTER="etcd1=http://10.0.0.19:2380,etcd2=http://10.0.0.24:2380,etcd3=http://10.0.0.10:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
ETCD_INITIAL_ELECTION_TICK_ADVANCE="false"
ETCD_ENABLE_V2="true"

----
ETCD_NAME="etcd2"
ETCD_LISTEN_CLIENT_URLS="http://10.0.0.24:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.0.24:2379"
ETCD_LISTEN_PEER_URLS="http://10.0.0.24:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.24:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-postgres-cluster"
ETCD_INITIAL_CLUSTER="etcd1=http://10.0.0.19:2380,etcd2=http://10.0.0.24:2380,etcd3=http://10.0.0.10:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
ETCD_INITIAL_ELECTION_TICK_ADVANCE="false"
ETCD_ENABLE_V2="true"

----
ETCD_NAME="etcd3"
ETCD_LISTEN_CLIENT_URLS="http://10.0.0.10:2379,http://127.0.0.1:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.0.10:2379"
ETCD_LISTEN_PEER_URLS="http://10.0.0.10:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.10:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-postgres-cluster"
ETCD_INITIAL_CLUSTER="etcd1=http://10.0.0.19:2380,etcd2=http://10.0.0.24:2380,etcd3=http://10.0.0.10:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_ELECTION_TIMEOUT="10000"
ETCD_HEARTBEAT_INTERVAL="2000"
ETCD_INITIAL_ELECTION_TICK_ADVANCE="false"
ETCD_ENABLE_V2="true"

## настраиваем автозапуск службы etcd и ее запускаем
sudo systemctl daemon-reload

sudo systemctl enable etcd

sudo systemctl start etcd

systemctl status etcd

hostname; ps -aef | grep etcd | grep -v grep

etcdctl member list
etcdctl endpoint status --cluster -w table


# еще вариант установки etcd
https://sysad.su/%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-%D0%B8-%D0%BD%D0%B0%D1%81%D1%82%D1%80%D0%BE%D0%B9%D0%BA%D0%B0-%D0%BA%D0%BB%D0%B0%D1%81%D1%82%D0%B5%D1%80%D0%B0-etcd-ubuntu-18/


# 5 Развернем 3 ВМ для PostgreSQL:
for i in {1..3}; do yc compute instance create --name pgsql$i --hostname pgsql$i --cores 2 --memory 4 --create-boot-disk size=20G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/yc_key.pub & done;

yc compute instances list




  - host replication replicator 158.160.150.58 scram-sha-256
  - host replication replicator 158.160.162.171 scram-sha-256  
  - host replication replicator 158.160.153.148 scram-sha-256

# 6 установка PostgreSQL на 3 ВМ:
ssh -i ~/yc_key yc-user@158.160.46.55
ssh -i ~/yc_key yc-user@193.32.219.124
ssh -i ~/yc_key yc-user@158.160.61.206


sudo apt update && sudo apt upgrade -y -q && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee -a /etc/apt/sources.list.d/pgdg.list && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql

pg_lsclusters

ping etcd1

## Задаем пароль для роли postgres на 1 ВМ:
sudo -u postgres psql

\password

## создаем пользователя replicator на 1 ВМ:
create user replicator replication login encrypted password 'password';

## Редактируем файл pg_hba.conf
sudo nano /etc/postgresql/18/main/pg_hba.conf
## меняем строки 
host all all 127.0.0.1/32 scram-sha-256
host replication all 127.0.0.1/32 scram-sha-256
## на 
host all all 0.0.0.0/0 scram-sha-256
host replication all 0.0.0.0/0 scram-sha-256

## Редактируем файл postgresql.conf
sudo nano /etc/postgresql/18/main/postgresql.conf
## В строке 
#listen_address = 'localhost'
## снимаем коментарий и ставим звездочку:
listen_address = '*'

## После этого первую ноду нужно перезапустить:
sudo systemctl restart postgresql

## На второй и третьей ноде удалить содержимое каталога pgdata, поскольку оно будет отреплицировано с первой ноды при развертывании кластера:
sudo systemctl stop postgresql

sudo su postgres

rm -rf /var/lib/postgresql/18/main/*


# 7 установка Патрони
sudo apt -y install python3 python3-pip python3-dev python3-psycopg2 libpq-dev
sudo pip3 install launchpadlib --break-system-packages
sudo pip3 install --upgrade setuptools --break-system-packages
sudo pip3 install psycopg2 --break-system-packages
sudo pip3 install python-etcd --break-system-packages
sudo apt -y install patroni
sudo systemctl stop patroni
sudo systemctl disable patroni


## На трёх машинах инициализировать службу
sudo nano /etc/systemd/system/patroni.service

[Unit]
Description=High availability PostgreSQL Cluster
After=syslog.targetnetwork.target
[Service]
Type=simple:
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no
[Install]
WantedBy=multi-user.target

## Создаем файл конфигурации Patroni:
sudo nano /etc/patroni.yml

## ---- node 1
scope: patroni
name: node1
restapi:
  listen: 10.0.0.28:8008
  connect_address: 10.0.0.28:8008
etcd:
  hosts: etcd1:2379,etcd2:2379,etcd3:2379
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
#  initdb:
#    - encoding: UTF8
#    - data-checksums
  pg_hba:
    - host replication replicator 0.0.0.0/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256
  users:
    admin:
      password: admin_otus
      options:
        - createrole
        - createdb
postgresql:
  listen: 10.0.0.28,127.0.0.1:5432
  connect_address: 10.0.0.28:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /etc/postgresql/18/main
  authentication:
    replication:
      username: replicator
      password: password
    superuser:
      username: postgres
      password: password
    rewind:
      username: rewind_user
      password: rewind_password_321
  parameters:
    unix_socket_directories: /var/run/postgresql

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

## ---- node 2
scope: patroni
name: node2
restapi:
  listen: 10.0.0.33:8008
  connect_address: 10.0.0.33:8008
etcd:
  hosts: etcd1:2379,etcd2:2379,etcd3:2379
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
#  initdb: 
#    - encoding: UTF8
#    - data-checksums
  pg_hba:
    - host replication replicator 0.0.0.0/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256
  users:
    admin:
      password: admin_otus
      options:
        - createrole
        - createdb
postgresql:
  listen: 10.0.0.33,127.0.0.1:5432
  connect_address: 10.0.0.33:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /etc/postgresql/18/main
  authentication:
    replication:
      username: replicator
      password: password
    superuser:
      username: postgres
      password: password
    rewind:
      username: rewind_user
      password: rewind_password_321
  parameters:
    unix_socket_directories: /var/run/postgresql

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false


---- node 3
scope: patroni
name: node3
restapi:
  listen: 10.0.0.13:8008
  connect_address: 10.0.0.13:8008
etcd:
  hosts: etcd1:2379,etcd2:2379,etcd3:2379
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 200
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:  
    - host replication replicator 0.0.0.0/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256
  users:
    admin:
      password: admin_otus
      options:
        - createrole
        - createdb
postgresql:
  listen: 10.0.0.13,127.0.0.1:5432
  connect_address: 10.0.0.13:5432
  data_dir: /var/lib/postgresql/18/main
  bin_dir: /usr/lib/postgresql/18/bin
  config_dir: /etc/postgresql/18/main
  authentication:
    replication:
      username: replicator
      password: password
    superuser:
      username: postgres
      password: password
    rewind:
      username: rewind_user
      password: rewind_password_321
  parameters:
    unix_socket_directories: /var/run/postgresql

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

/*
## name — имя узла, на котором настраивается данный конфиг.
## scope — имя кластера. Его мы будем использовать при обращении к ресурсу, а также под этим именем будет зарегистрирован сервис в consul.
## restapi-connect_address — адрес на настраиваемом сервере, на который будут приходить подключения к patroni.
## restapi-auth — логин и пароль для аутентификации на интерфейсе API.
## pg_hba — блок конфигурации pg_hba для разрешения подключения к СУБД и ее базам. Необходимо обратить внимание на подсеть для
## строки host replication replicator. Она должна соответствовать той, которая используется в вашей инфраструктуре.
## postgresql-pgpass — путь до файла, который создаст патрони. В нем будет храниться пароль для подключения к postgresql.
## postgresql-connect_address — адрес и порт, которые будут использоваться для подключения к СУБД.
## postgresql - data_dir — путь до файлов с данными базы.
## postgresql - bin_dir — путь до бинарников postgresql.
## pg_rewind, replication, superuser — логины и пароли, которые будут созданы для базы.
*/

## Отладка конфига
sudo patroni --validate-config /etc/patroni.yml

## Запускаем Кластер Патрони:
sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni
sudo systemctl status patroni
sudo patronictl -c /etc/patroni.yml list

## если ошибка system ID mismatch, node belongs to a different cluster
## на всех нодах 
## 1. остановить etcd: sudo systemctl stop etcd
## 2. удалить каталог var/lib/etcd/member/: sudo rm -R /var/lib/etcd/member/
## 3. запустить etcd: sudo systemctl start etcd



curl -s http://158.160.158.58:2380/members |jq -r

patronictl -c /etc/patroni.yml edit-config

-- Выключение одной ноды:
sudo systemctl stop patroni 

-- Рестарт всего кластера:
patronictl -c /etc/patroni.yml restart patroni

-- Рестарт reload кластера:
patronictl -c /etc/patroni.yml reload patroni

-- Плановое переключение:
patronictl -c /etc/patroni.yml switchover patroni

-- Реинициализации ноды:
patronictl -c /etc/patroni.yml reinit patroni pgsql2



#  Удалим кластер:
for i in {1..3}; do yc compute instance delete etcd$i && yc compute instance delete pgsql$i; done && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net && yc dns zone delete otus-dns 