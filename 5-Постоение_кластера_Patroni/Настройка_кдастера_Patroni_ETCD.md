Source https://habr.com/ru/companies/jetinfosystems/articles/847872/ 

В этом материале будем настраивать кластер PostgreSQL с Patroni и etcd. Видели множество статей на эту тему, но наше отличие в том, что мы устанавливаем кластер в виртуальной среде, используя новые компоненты.

Немного теории. Patroni — это инструмент для управления высокодоступными кластерами PostgreSQL. Он упрощает настройку и управление репликацией благодаря автоматическому переключению на резервные узлы и восстановлению после сбоев.

В нашем материале мы рассмотрим настройку такого кластера с использованием etcd для координации, а еще будем использовать только пакеты для ручной установки. Потому что частенько в локальных репозиториях преобладают старые пакеты, в которых есть уязвимости. В таких случаях лучше устанавливать пакеты вручную.

Зачем мы это делаем?

Во-первых, интересно. Во-вторых, это нам позволит установить последние версии пакетов без открытого доступа в интернет с серверов. Во многих компаниях изолированная сетевая среда — поэтому вот вам памятка по такой задаче.:)

Итак, приступим.

Систему можно использовать любую, автору захотелось Centos 8 (личное предпочтение автора, не более — прим. ред.). Совет: лучше заранее описать, какие будут имя сервера и IP-адреса. Сетевая структура у нас такая:

etcd1 192.168.60.141
etcd2 192.168.60.142
etcd3 192.168.60.143
node1 192.168.60.131
node2 192.168.60.132
Объяснить с

У вас могут быть и другие адреса, поэтому не забудьте их поменять в конфигах.
Установка и настройка etcd

Шаг 1: скачиваем etcd

Для этого качаем пакет с оф. гита etcd вот отсюда:  https://github.com/etcd-io/etcd/releases/download/v3.5.15/etcd-v3.5.15-linux-amd64.tar.gz

Затем распаковываем архив и перемещаем файлы:

tar -xzvf etcd-v3.5.15-linux-amd64.tar.gz
sudo mv etcd-v3.5.15-linux-amd64/etcd* /usr/bin/
Объяснить с

Шаг 2: создаем пользователей и директории

1. Выполняем следующие команды:

sudo groupadd --system etcd
sudo useradd -s /sbin/nologin --system -g etcd etcd
Объяснить с

2. Теперь создаем необходимые директории и устанавливаем права доступа с помощью:

sudo mkdir -p /var/lib/etcd /etc/default/etcd/.tls
sudo chown -R etcd:etcd /var/lib/etcd /etc/default/etcd
```
Объяснить с

Шаг 3: генерируем сертификаты

Если у вас нет возможности использовать собственные сертификаты, то берем самописные. Небольшой скрипт ниже в этом нам поможет:
Скрытый текст

Запускаем скрипт:

chmod +x generate_etcd_certs.sh
sudo ./generate_etcd_certs.sh
Объяснить с

Сделали. Чтобы узлы etcd взаимодействовали между собой, копируем ca.crt и node[01 или 03] на остальные узлы.

Теперь меняем права на всех узлах etcd:

chown -R etcd:etcd /etc/default/etcd/.tls
chmod -R 744 /etc/default/etcd/.tls
chmod 600 /etc/default/etcd/.tls/*.key
Объяснить с

Шаг 4: определяем, как должен работать etcd (параметры)

На каждой ноде создаем конфиг, который минимально отличается от ноды к ноде (подсветили комментариями):

# /etc/etcd/etcd.conf.yml
name: etcd01 # Изменить на других нодах
data-dir: /var/lib/etcd/default
listen-peer-urls: https://0.0.0.0:2380
listen-client-urls: https://0.0.0.0:2379
advertise-client-urls: https://etcd01:2379 # Изменить на других нодах
initial-advertise-peer-urls: https://etcd01:2380 # Изменить на других нодах
initial-cluster-token: etcd_scope
initial-cluster: etcd01=https://etcd01:2380,etcd02=https://etcd02:2380,etcd03=https://etcd03:2380
initial-cluster-state: new
election-timeout: 5000
heartbeat-interval: 500
 
client-transport-security:
  cert-file: /etc/default/etcd/.tls/etcd01.crt # Изменить на других нодах
  key-file: /etc/default/etcd/.tls/etcd01.key
  client-cert-auth: true
  trusted-ca-file: /etc/default/etcd/.tls/ca.crt
 
peer-transport-security:
  cert-file: /etc/default/etcd/.tls/etcd01.crt # Изменить на других нодах
  key-file: /etc/default/etcd/.tls/etcd01.key
  client-cert-auth: true
  trusted-ca-file: /etc/default/etcd/.tls/ca.crt
Объяснить с

Шаг 5: для запуска etcd cоздаем Systemd-Unit-файл

Как правило, сервис создается по следующему пути (мы использовали его): /etc/systemd/system/etcd.service

[Unit]
Description=etcd key-value store
Documentation=https://etcd.io/docs/
Wants=network-online.target
After=network-online.target
 
[Service]
User=etcd
Type=notify
ExecStart=/usr/bin/etcd --config-file=/etc/etcd/etcd.conf.yml
Restart=always
RestartSec=5
LimitNOFILE=40000
 
[Install]
WantedBy=multi-user.target
Объяснить с

Шаг 6: применяем следующие команды

sudo systemctl daemon-reload
sudo systemctl enable etcd
Объяснить с

Заметка на полях: Помним, что любое изменение конфига Systemd для новых настроек требует выполнения команд выше. А также не забываем, что поезд etcd ждать не будет :) (у нас есть только 30 секунд, чтобы запустить другие ноды кластера).

На этом этапе поочередно запускаем сервис с 1-й по 3-ю ноду с помощью команды: sudo systemctl start etcd

Шаг 7: настраиваем alias для etcdctl

Для этого добавляем alias в наш `~/.bashrc` или `~/.zshrc`:

echo 'alias ectl="etcdctl --cacert=/etc/default/etcd/.tls/ca.crt --cert=/etc/default/etcd/.tls/$(hostname).crt --key=/etc/default/etcd/.tls/$(hostname).key --endpoints=https://etcd01:2379,https://etcd02:2379,https://etcd03:2379"' >> ~/.bashrc
source ~/.bashrc

Благодаря этому мы получаем статус кластера etcd, не прописывая каждый раз сертификаты.

Примечание. Учтите, что имя crt и key нод должно быть аналогично hostname. Иначе команда выше не сработает и придется все настраивать вручную.

Получаем удобную таблицу:

После того как кластер запустился, на всех узлах редактируем конфиг `/etc/default/etcd` и устанавливаем параметр:

ETCD_INITIAL_CLUSTER_STATE="existing"
```
Объяснить с

Перезапускаем службу:

systemctl restart etcd
Объяснить с

Фух! С etcd закончили, :) приступаем к Postgres и Patroni.
Установка PostgreSQL

Шаг 1: скачиваем и устанавливаем пакеты из оф. репозитория

Делаем это отсюда: https://download.postgresql.org/pub/repos/

NB: В системе по умолчанию создается daemon PostgreSQL. Его требуется отключить. Применяем команду:

systemctl --now disable postgresql-16
Объяснить с

Затем меняем настройки пользователя Postgres при необходимости:

mkdir /home/postgres
chown postgres:postgres /home/postgres
usermod --home /home/postgres postgres
Объяснить с

Шаг 2: готовим каталог PGDATA

Для этого делаем:

mkdir -p /data/16
chmod -R 700 /data
mkdir /data/log
chown -R postgres:postgres /data
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql
Объяснить с

Важное примечание на полях: на astra linux встречали удаление директории  /var/run/postgresql для сокетов, если ставить Postgres из оф. репозитория. Это можно поправить, если изменить сервис Postgres и добавить RuntimeDirectory=postgresql

Теперь нам понадобится каталог для сертификатов:
mkdir -p /opt/patroni/.tls

Помните, как мы сгенерировали сертификаты для etcd? Там же есть сертификаты для Patroni. Забираем их оттуда на узлы Patroniи назначаем права:

chmod -R 744 /opt/patroni/.tls
chmod 600 /opt/patroni/.tls/*.key
Объяснить с

Установка Patroni: подготовительные работы

Шаг 1: устанавливаем свежую версию Python

Если вдруг ее не оказалось:

yum install openssl-devel libffi-devel bzip2-devel
tar -xzvf Python-3.12.4.tgz
cd Python-3.12.4/
./configure --enable-optimizations --with-ssl
make altinstall
sudo ln -sf /usr/local/bin/python3.12 /usr/bin/python3
sudo ln -sf /usr/local/bin/pip3.12 /usr/bin/pip3
Объяснить с

Зачем? Так мы можем установить Patroni, не повредив систему, а также получить очень удобный каталог с бинарями.

Шаг 2: создаем виртуальную среду

Для этого используем команды:

python3 –m venv /opt/patroni
source /opt/patroni/bin/activate
mkdir –p /opt/patroni/packages
cd /opt/patroni/packages
Объяснить с

Сама установка

Копируем whl и архивы в /opt/patroni/packages. Затем скачиваем следующие пакеты (примерный список):

click-8.1.7-py3-none-any.whl
dnspython-2.6.1-py3-none-any.whl
patroni-3.3.2-py3-none-any.whl
prettytable-3.10.2-py3-none-any.whl
psutil-6.0.0-cp36-abi3-manylinux_2_12_x86_64.manylinux2010_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl
python_dateutil-2.9.0.post0-py2.py3-none-any.whl
python-etcd-0.4.5.tar.gz
PyYAML-6.0.1-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
setuptools-72.1.0-py3-none-any.whl
six-1.16.0-py2.py3-none-any.whl
urllib3-2.2.2-py3-none-any.whl
wcwidth-0.2.13-py2.py3-none-any.whl
ydiff-1.3.tar.gz
psycopg2_binary-2.9.9-cp312-cp312-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
Объяснить с

Применяем команды:

pip3 install --no-index --find-links=/opt/patroni/packages patroni[etcd3]
pip3 install --no-index --find-links=/opt/patroni/packages psycopg2-binary
chown -R postgres:postgres /opt/patroni
Объяснить с

Patroni есть! Теперь добавляем в профайл PostgreSQL параметры:

export PG_CONFIG=/usr/pgsql-16/bin/pg_config
export PATRONI_CONFIG_FILE=/etc/patroni/config.yml
Объяснить с

А теперь активируем виртуальную среду: source /opt/patroni/bin/activate

Настройка Patroni

Cоздаем конфигурационный файл /etc/patroni/config.yml на нодах кластера Patroni:
Скрытый текст

patroni
scope: patroni_cluster
namespace: /patroni
name: patroni_node01 # Изменить на 2 ноде
log:
level: INFO
dir: /data/log/patroni
file_size: 50000000
file_num: 10
restapi:
listen: 0.0.0.0:8008
connect_address: node01:8008 # Изменить на 2 ноде
verify_client: optional
cafile: /opt/patroni/.tls/ca.crt
certfile: /opt/patroni/.tls/node01.crt # Не забыть изменить сертификаты на 2 ноде
keyfile: /opt/patroni/.tls/node01.key
ctl:
cacert: /opt/patroni/.tls/ca.crt # Не забыть изменить сертификаты на 2 ноде
certfile: /opt/patroni/.tls/node01.crt
keyfile: /opt/patroni/.tls/node01.key
etcd3:
hosts: ["etcd01:2379", "etcd02:2379", "etcd03:2379"]
protocol: https
cacert: /opt/patroni/.tls/ca.crt
cert: /opt/patroni/.tls/node01.crt # Не забыть изменить сертификаты на 2 ноде
key: /opt/patroni/.tls/node01.key
watchdog:
mode: off # Если настроен, можно включить
bootstrap:
dcs:
failsafe_mode: true
ttl: 30
loop_wait: 10
retry_timeout: 10
maximum_lag_on_failover: 1048576
synchronous_mode: true
synchronous_mode_strict: true
synchronous_mode_count: 1
master_start_timeout: 30
slots:
prod_replica1:
type: physical
postgresql:
use_pg_rewind: true
use_slots: true
parameters:
shared_buffers: '512MB'
wal_level: 'replica'
wal_keep_size: '512MB'
max_connections: 100
effective_cache_size: '1GB'
maintenance_work_mem: '256MB'
max_wal_senders: 5
max_replication_slots: 5
checkpoint_completion_target: 0.7
log_connections: 'on'
log_disconnections: 'on'
log_statement: 'ddl'
log_line_prefix: '%m [%p] %q%u@%d '
logging_collector: 'on'
log_destination: 'stderr'
log_directory: '/data/log'
log_filename: 'postgresql-%Y-%m-%d.log'
log_rotation_size: '100MB'
log_rotation_age: '1d'
log_min_duration_statement: -1
log_min_error_statement: 'error'
log_min_messages: 'warning'
log_error_verbosity: 'verbose'
log_hostname: 'off'
log_duration: 'off'
log_timezone: 'Europe/Moscow'
timezone: 'Europe/Moscow'
lc_messages: 'C.UTF-8'
password_encryption: 'scram-sha-256'
debug_print_parse: 'off'
debug_print_rewritten: 'off'
debug_print_plan: 'off'
superuser_reserved_connections: 3
synchronous_commit: 'on'
synchronous_standby_names: '*'
hot_standby: 'on'
compute_query_id: 'on'
pg_hba:
- local all all peer
- host all all 127.0.0.1/32 scram-sha-256
- host all all 0.0.0.0/0 md5
- host replication replicator 127.0.0.1/32 scram-sha-256
- host replication replicator 192.168.60.0/24 scram-sha-256
pg_hba:
- local all all peer
- host all all 127.0.0.1/32 scram-sha-256
- host all all 0.0.0.0/0 md5
- host replication replicator 127.0.0.1/32 scram-sha-256
- host replication replicator 192.168.60.0/24 scram-sha-256
initdb: ["encoding=UTF8", "data-checksums", "username=postgres", "auth=scram-sha-256"]
users:
admin:
password: 'new_secure_password1'
options: ["createdb"]
postgresql:
listen: 0.0.0.0
connect_address: 192.168.60.131:5432 # не забываем заменить адрес на 2 ноде.
use_unix_socket: true
data_dir: /data/16
config_dir: /data/16
bin_dir: /usr/pgsql-16/bin
pgpass: /home/postgres/.pgpass_patroni
authentication:
replication:
username: replicator
password: 'new_repl_password'
superuser:
username: postgres
password: 'new_superuser_password'
rewind:
username: postgres
password: 'new_superuser_password'
parameters:
unix_socket_directories: "/var/run/postgresql"
create_replica_methods: ["basebackup"]
basebackup:
max-rate: 100M
checkpoint: fast
tags:
nofailover: false
noloadbalance: false
clonefrom: false
nosync: false

Объяснить с

Чтобы не пропустить ошибки, проверяем валидность конфига:

patroni --validate-config /etc/patroni/config.yml
Объяснить с

Patroni требуется журналирование. Для этого создаем подкаталог для логов:

mkdir /data/log/patroni
chown -R postgres:postgres /data/log/patroni
Объяснить с

Теперь — Systemd-Unit-файл для Patroni:

```
service patroni
[Unit]
Description=Patroni high-availability PostgreSQL
After=network.target

[Service]
User=postgres
Type=simple
ExecStart=/opt/patroni/bin/patroni /etc/patroni/config.yml
Restart=always
RestartSec=5
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
```
Объяснить с

Перезапустите Systemd и запустите Patroni:

sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni
Объяснить с

Проверяем список узлов в кластере: patronictl list

Проверяем переключение (switchover)*:
patronictl  switchover
и убеждаемся, что Мастер переехал: у БД есть мастер-нода и slave-нода. Для просмотра подробной работы Patroni и PostgreSQL в арсенале есть логи:

Лог Patroni: /data/log/patroni/patroni.log

Логи экземпляра СУБД: /data/log/postgresql-*.log

Теперь у вас настроен высокодоступный кластер PostgreSQL с использованием Patroni и etcd. В следующей части мы расскажем, как интегрировать балансировщик и пулер pgbouncer в кластер, созданный в этой статье. До встречи!