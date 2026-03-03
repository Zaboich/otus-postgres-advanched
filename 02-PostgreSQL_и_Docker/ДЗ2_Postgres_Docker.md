1. развернуть VM ЯО
```
yc vpc network create --name net-otus1
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
```

Вход ssh
```
ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
ssh yc-user@$ADDR_VM1
```
2. установить Docker в VM
```
sudo apt update && sudo apt install -y docker.io docker-compose-v2
```
Добавить пользователя в группу `docker` для выполения команд `docker` и `docker compose`
```
sudo usermod -aG docker yc-user
```

на хосте (VM) создаём каталог для хранения данных Postgres
```
sudo mkdir /var/lib/postgres
```

Создаётся проект docker compose c двумя контейнерами (находящимся в одной docker-сети) 
1. контейнер `server` (image postgres:18-alpine) в котором работает сервер бд postgres, локальный каталог хоста `/var/lib/postgres` монтируется в контейнере в `/var/lib/postgresql`
порт контейнера `5432` маппится на `5432` и слушаются запросы со всех внешних адресов 
2. контейнер `client`, в котором не запускается серверная часть postgres, но будет использоваться psql, порты не слушаются

docker-compose.yml
```
services:
    server:
        image: postgres:18-alpine
        environment:
            - POSTGRES_DB=otus1
            - POSTGRES_PASSWORD=otus2password
            - POSTGRES_USER=otus
        volumes:
            - /var/lib/postgres:/var/lib/postgresql:rw
        ports:
            - 0.0.0.0:5432:5432
    client:
        image: postgres:18-alpine
        depends_on:
            - server
        command: bash
        tty: true
        environment:
            - PGPASSWORD=otus2password
```

Запуск контейнера 
```
~$ docker compose -f docker-compose.yml pull
~$ docker compose -f docker-compose.yml up -d
```

Список работающих контейнеров
```
~$ docker compose ps
NAME               IMAGE                COMMAND                  SERVICE   CREATED         STATUS         PORTS
yc-user-client-1   postgres:18-alpine   "docker-entrypoint.s…"   client    3 minutes ago   Up 3 minutes   5432/tcp
yc-user-server-1   postgres:18-alpine   "docker-entrypoint.s…"   server    3 minutes ago   Up 3 minutes   0.0.0.0:5432->5432/tcp
```

Через контейнер `client` создаём таблицу `shipments` и заполняем её данными
```
docker compose -f docker-compose.yml exec client psql -h server -U otus -d otus1 -c "create table shipments(id serial, product_name text, quantity int, destination text);
insert into shipments (product_name, quantity, destination) values ('bananas', 1000, 'Europe'),('bananas', 1500, 'Asia'),('bananas', 2000, 'Africa'),('coffee', 500, 'USA'),('coffee', 700, 'Canada'),
('coffee', 300, 'Japan'),('sugar', 1000, 'Europe'),('sugar', 800, 'Asia'),('sugar', 600, 'Africa'),('sugar', 400, 'USA');"
CREATE TABLE
INSERT 0 10
```

Проверка добавленных данных через контейнер client
```
docker compose -f docker-compose.yml exec client psql -h server -U otus -d otus1 -c 'SELECT * FROM  shipments;'
id | product_name | quantity | destination
----+--------------+----------+-------------
1 | bananas      |     1000 | Europe
2 | bananas      |     1500 | Asia
3 | bananas      |     2000 | Africa
4 | coffee       |      500 | USA
5 | coffee       |      700 | Canada
6 | coffee       |      300 | Japan
7 | sugar        |     1000 | Europe
8 | sugar        |      800 | Asia
9 | sugar        |      600 | Africa
10 | sugar        |      400 | USA
(10 rows)
```

Подключение к БД с ноутбука
```
~$ export ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
docker run -it --rm postgres:18-alpine psql -h $ADDR_VM1 -U otus -d otus1 
Password for user otus: 
psql (18.1)
Type "help" for help.

otus1=# SELECT * FROM shipments LIMIT 1;
 id | product_name | quantity | destination 
----+--------------+----------+-------------
  1 | bananas      |     1000 | Europe
(1 row)

otus1=# 
```

Остановка и удаление контейнеров 
```
~$ docker compose -f docker-compose.yml down
[+] Running 3/3
 ✔ Container yc-user-client-1  Removed                                                                                                                                10.1s 
 ✔ Container yc-user-server-1  Removed                                                                                                                                 0.2s 
 ✔ Network yc-user_default     Removed
```

Директория с данными сохранилась на хосте VM
```
sudo ls -l /var/lib/postgres/18/docker/
total 124
-rw------- 1 70 70     3 Jan 27 20:54 PG_VERSION
drwx------ 6 70 70  4096 Jan 27 20:54 base
drwx------ 2 70 70  4096 Jan 27 20:58 global
drwx------ 2 70 70  4096 Jan 27 20:54 pg_commit_ts
drwx------ 2 70 70  4096 Jan 27 20:54 pg_dynshmem
-rw------- 1 70 70  5753 Jan 27 20:54 pg_hba.conf
-rw------- 1 70 70  2681 Jan 27 20:54 pg_ident.conf
drwx------ 4 70 70  4096 Jan 27 21:21 pg_logical
drwx------ 4 70 70  4096 Jan 27 20:54 pg_multixact
drwx------ 2 70 70  4096 Jan 27 20:54 pg_notify
drwx------ 2 70 70  4096 Jan 27 20:54 pg_replslot
drwx------ 2 70 70  4096 Jan 27 20:54 pg_serial
drwx------ 2 70 70  4096 Jan 27 20:54 pg_snapshots
drwx------ 2 70 70  4096 Jan 27 21:21 pg_stat
drwx------ 2 70 70  4096 Jan 27 20:54 pg_stat_tmp
drwx------ 2 70 70  4096 Jan 27 20:54 pg_subtrans
drwx------ 2 70 70  4096 Jan 27 20:54 pg_tblspc
drwx------ 2 70 70  4096 Jan 27 20:54 pg_twophase
drwx------ 4 70 70  4096 Jan 27 20:59 pg_wal
drwx------ 2 70 70  4096 Jan 27 20:54 pg_xact
-rw------- 1 70 70    88 Jan 27 20:54 postgresql.auto.conf
-rw------- 1 70 70 32307 Jan 27 20:54 postgresql.conf
-rw------- 1 70 70    24 Jan 27 20:54 postmaster.opts
```

Повторно запускаем контейнеры
```
~$ docker compose up -d
[+] Running 3/3
 ✔ Network yc-user_default     Created                                                                                                                                 0.1s 
 ✔ Container yc-user-server-1  Started                                                                                                                                 0.3s 
 ✔ Container yc-user-client-1  Started
```

Проверка данных в таблице после запуска
```
~$ docker compose -f docker-compose.yml exec client psql -h server -U otus -d otus1 -c 'SELECT * FROM  shipments LIMIT 1;'
id | product_name | quantity | destination
----+--------------+----------+-------------
1 | bananas      |     1000 | Europe
(1 row)
```

Остановка и удаление VM в ЯО
```
yc compute instance delete vm-otus1 &&\
yc vpc subnet delete subnet-otus1 &&\
yc vpc network delete net-otus1
```