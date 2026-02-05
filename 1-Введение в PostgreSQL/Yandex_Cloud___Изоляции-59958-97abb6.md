# Virtual Machines (Compute Cloud) https://cloud.yandex.ru/docs/free-trial/

Создание виртуальной машины:
https://cloud.yandex.ru/docs/compute/quickstart/quick-create-linux

name vm: otus-vm

Создать сеть:
Каталог: default
Имя: otus-net

Доступ
username: otus

настройка OpenSSH в Windows
Параметры -> Система -> Дополнительные компоненты -> клиент Open SSH (добавить)
Службы (Service) -> OpenSSH SSH Server (запустить)

Сгенерировать ssh-key:
```bash
ssh-keygen -t rsa -b 2048
name ssh-key: yc_key
chmod 600 ~/.ssh/yc_key.pub
ls -lh ~/.ssh/
cat ~/.ssh/yc_key.pub # в Windows C:\Users\<имя_пользователя>\.ssh\yc_key.pub
```
Подключение к VM:
https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh

```bash
ssh -i ~/yc_key otus@158.160.154.149 # в Windows ssh -i <путь_к_ключу/имя_файла_ключа> <имя_пользователя>@<публичный_IP-адрес_виртуальной_машины>

Установка Postgres:
sudo apt update && sudo apt upgrade -y && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt-get -y install postgresql && sudo apt install unzip && sudo apt -y install mc

pg_lsclusters

sudo -u postgres psql

-----
Установить пароль для Postgres:
\password   #12345
\q

Добавить сетевые правила для подключения к Postgres:
sudo nano /etc/postgresql/18/main/postgresql.conf
#listen_addresses = 'localhost'
listen_addresses = '*'

sudo nano /etc/postgresql/18/main/pg_hba.conf
#host    all             all             127.0.0.1/32            scram-sha-256 password
host    all             all             0.0.0.0/0               scram-sha-256 

sudo pg_ctlcluster 18 main restart

Подключение к Postgres:
psql -h 158.160.154.149 -U postgres
--------

\l

## уровни изоляции транзакций

###  создадим табличку для тестов
create database otus;
\c otus

CREATE TABLE test2 (i serial, amount int);
INSERT INTO test2(amount) VALUES (100),(500);
SELECT * FROM test2;

show transaction isolation level;

##    TRANSACTION ISOLATION LEVEL READ COMMITTED;
###     1 console
begin;
SELECT * FROM test2;

###   2 console
begin;
UPDATE test2 set amount = 555 WHERE i = 1;
SELECT * FROM test2;
commit;

## TRANSACTION ISOLATION LEVEL REPEATABLE READ;
### 1 console
begin;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SHOW TRANSACTION ISOLATION LEVEL;
SELECT * FROM test2;

### 2 console
begin;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
INSERT INTO test2(amount) VALUES (777);
SELECT * FROM test2;
COMMIT;

### 1 console
SELECT * FROM test2;
COMMIT;
SELECT * FROM test2;

## TRANSACTION ISOLATION LEVEL SERIALIZABLE;
### 1 console
DROP TABLE IF EXISTS testS;
CREATE TABLE testS (i int, amount int);
INSERT INTO testS VALUES (1,10), (1,20), (2,100), (2,200); 


BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SELECT sum(amount) FROM testS WHERE i = 1;
INSERT INTO testS VALUES (2,30);
SELECT * FROM testS;

### 2 consol
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SELECT sum(amount) FROM testS WHERE i = 2;
INSERT INTO testS VALUES (1,300);
SELECT * FROM testS; 

### 1 console 
COMMIT;

### 2 console 
COMMIT;

DROP TABLE IF EXISTS testS;
```