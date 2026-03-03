# Спасение данных на внешнем диске
## Разворачиваю VM ЯО
```shell
yc vpc network create --name net-otus1 &&\
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
```

Создаю дополнительный диск для ВМ:
```shell
yc compute disk create \
    --name disk-otus3 \
    --type network-hdd \
    --size 5 \
    --description "second disk for vm-otus1"
```
Подключаю диск к VM
Подключим новый диск к нашей ВМ:
```
yc compute instance attach-disk vm-otus1 \
    --disk-name disk-otus3 \
    --mode rw \
    --auto-delete
```
Проверка подключения диска
```
yc compute disk list
+----------------------+------------+-------------+---------------+--------+----------------------+-----------------+--------------------------+
|          ID          |    NAME    |    SIZE     |     ZONE      | STATUS |     INSTANCE IDS     | PLACEMENT GROUP |       DESCRIPTION        |
+----------------------+------------+-------------+---------------+--------+----------------------+-----------------+--------------------------+
| fv49ok9lhh9vu6rppk6d |            | 16106127360 | ru-central1-d | READY  | fv4sdgenp51d0svnjvke |                 |                          |
| fv4tv0c29ktqbosjs0k8 | disk-otus3 |  5368709120 | ru-central1-d | READY  | fv4sdgenp51d0svnjvke |                 | second disk for vm-otus1 |
+----------------------+------------+-------------+---------------+--------+----------------------+-----------------+--------------------------+

```

## Подготовка VM vm-otus1  
Вход ssh на VM vm-otus1
```
ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
ssh  -o StrictHostKeyChecking=no yc-user@$ADDR_VM1
```

Устанавливаю PostgreSQL
```shell
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - 

sudo apt update && \
sudo apt install -y postgresql
```

Устанавливаем пароль пользователю `postgres`
```
export PGPASSWORD=postgres

sudo -u postgres psql -c "alter user postgres password '${PGPASSWORD}';"

echo "localhost:5432:*:postgres:${PGPASSWORD}" > .pgpass
chmod 0600 ~/.pgpass
```

Скачиваю файл "Демонстрационная база данных" PostgresPro 
```
curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz 
```
Загрузить дамп в БД
```
sudo -u postgres psql -c "CREATE DATABASE demo;"
gunzip -c demo-20250901-6m.sql.gz | psql -h localhost -U postgres
```
Проверить содерижимое БД
```
psql -h localhost -U postgres -w -c "\l"
psql -h localhost -U postgres -w -d demo -c "\dt"
psql -h localhost -U postgres -w -d demo -c "SELECT count(1) FROM boarding_passes;"
```
БД demo создана и заполнена данными

## Перенос данных на дополнительный диск 

Дополнительный диск в /mnt/pg_data подключаю в виде тома LVM 
```
sudo pvcreate /dev/vdb
sudo vgcreate vg-pg_data /dev/vdb
sudo lvcreate -l +100%FREE --name lv-pg_data vg-pg_data

sudo mkfs.ext4 /dev/vg-pg_data/lv-pg_data
sudo mkdir /mnt/pg_data
sudo mount /dev/vg-pg_data/lv-pg_data /mnt/pg_data
echo '/dev/vg-pg_data/lv-pg_data /mnt/pg_data ext4 defaults 0 2' | sudo tee -a /etc/fstab
```

```
sudo chown -R postgres:postgres /mnt/pg_data
sudo chmod 700 /mnt/pg_data
```

### Перенос БД на новый диск с помощью `pg_basebackup`
Разрешение на подключение в `pg_hba.conf` по протоколу репликации Postgres 18 на Ubuntu пользователю `postgres` выдавать не требуется. Они обеспечены правилом
```
# Database administrative login by Unix domain socket
local   all             postgres                                peer
```
Если pg_hba.conf изменён и пользователь postgres не имеет прав replication, надо добавить строку
```
# echo 'local   replication     postgres        127.0.0.1/32    scram-sha-256' | sudo tee -a /etc/postgresql/18/main/pg_hba.conf
# sudo pg_ctlcluster 14 main restart
```

Копирование файлов БД на созданный диск с помощью pg_basebackup
```
sudo find /mnt/pg_data/ -mindepth 1 -delete
sudo -u postgres bash -c 'export PGPASSWORD=postgres && pg_basebackup -h 127.0.0.1 -U postgres -w -D /mnt/pg_data -Fp -Xs -P -R -v'

sudo -u postgres rm /mnt/pg_data/standby.signal
```

Резервная копия текущего кластера перед переносом данных на новый диск
```
sudo -u postgres pg_dumpall | gzip > ./backup/pg_full_$(date +%F).sql.gz
```

Остановка Postgres и проверка состояния
```
sudo systemctl stop postgresql@18-main
sudo systemctl status postgresql@18-main
```
Создаю копию postgresql.conf
В конфигурационном файле postgresql.conf меняю рабочую директорию
```
sudo cp /etc/postgresql/18/main/postgresql.conf /etc/postgresql/18/main/postgresql.conf.backup-$(date +%F)
sudo sed -i "s|data_directory = '.*'|data_directory = '/mnt/pg_data'|" /etc/postgresql/18/main/postgresql.conf
```

Удаляю исходную директорию с данными Postgresql (В реальных условиях директория будет удалена после успешного запуска Postgres с новым расположением файлов) 
```
sudo rm -rf /var/lib/postgresql/18/main

sudo ls -la /var/lib/postgresql/18/
total 8
drwxr-xr-x 2 postgres postgres 4096 Feb  2 10:04 .
drwxr-xr-x 3 postgres postgres 4096 Feb  2 09:25 ..

```
## Запуск и проверка Postgres после переноса данных на дополнительный диск
Запускаю Postgres и проверяю данные
```
sudo systemctl start postgresql@18-main
sudo systemctl status postgresql@18-main

psql -h localhost -U postgres -w -c "\l"
                                                     List of databases
   Name    |  Owner   | Encoding | Locale Provider |   Collate   |    Ctype    | Locale | ICU Rules |   Access privileges   
-----------+----------+----------+-----------------+-------------+-------------+--------+-----------+-----------------------
 demo      | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | 
 postgres  | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | 
 template0 | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | =c/postgres          +
           |          |          |                 |             |             |        |           | postgres=CTc/postgres
 template1 | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | =c/postgres          +
           |          |          |                 |             |             |        |           | postgres=CTc/postgres
(4 rows)

psql -h localhost -U postgres -w -d demo -c "\dt"
                List of tables
  Schema  |      Name       | Type  |  Owner   
----------+-----------------+-------+----------
 bookings | airplanes_data  | table | postgres
 bookings | airports_data   | table | postgres
 bookings | boarding_passes | table | postgres
 bookings | bookings        | table | postgres
 bookings | flights         | table | postgres
 bookings | routes          | table | postgres
 bookings | seats           | table | postgres
 bookings | segments        | table | postgres
 bookings | tickets         | table | postgres
(9 rows)


psql -h localhost -U postgres -w -d demo -c "SELECT count(1) FROM boarding_passes;"
  count  
---------
 5982418
(1 row)

```

При правильном порядке действия простой БД будет равен времени остановки и запуска сервиса
```
sudo systemctl stop postgresql@18-main
sudo systemctl start postgresql@18-main
```
что составит менее 30 сек.


## Перенос диска с данными на другую VM

Диск с данными можно открепить от VM vm-otus1, прикрепить к другой VM запустить БД на новой VM.

### Подготовка VM vm-otus2

Создаю VM vm-otus2
```
yc compute instance create --name vm-otus2 --hostname vm-otus2 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
```

Останавливаю Postgres на `vm-otus1` и отмонтирую диск из `/mnt/pg_data` 
```
sudo systemctl stop postgresql@18-main
sudo umount /mnt/pg_data
## (Удалить из запись из fstab)

ll /mnt/pg_data/
total 8
drwxr-xr-x 2 root root 4096 Feb  2 09:38 ./
drwxr-xr-x 3 root root 4096 Feb  2 09:38 ../
```

Окрекпляю диск disk-otus3 от vm-otus1
```
yc compute instance detach-disk vm-otus1 --disk-name disk-otus3
```

Создаю VM vm-otus2 и прикрепляю к нему диск 
```
yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub

yc compute instance attach-disk vm-otus2 \
    --disk-name disk-otus3 \
    --mode rw \
    --auto-delete
```

Вход ssh на VM vm-otus2
```
ADDR_VM2=$(yc compute instance show --name vm-otus2 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
ssh  -o StrictHostKeyChecking=no yc-user@$ADDR_VM2
```

Установить  PostgreSQL vm-otus2
```
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - 

sudo apt update && \
sudo apt install -y postgresql
```

Прикреплённый диск определился системой LVM
```
sudo lvs
  LV         VG         Attr       LSize  Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  lv-pg_data vg-pg_data -wi-a----- <5.00g                                                    
```

Дополнительный диск disk-otus3 в /mnt/pg_data подключаю в виде тома LVM vm-otus2
```
sudo mkdir /mnt/pg_data
sudo mount /dev/vg-pg_data/lv-pg_data /mnt/pg_data
echo '/dev/vg-pg_data/lv-pg_data /mnt/pg_data ext4 defaults 0 2' | sudo tee -a /etc/fstab


sudo ls -la /mnt/pg_data/
total 280
drwx------ 19 postgres postgres   4096 Feb  2 11:17 .
drwxr-xr-x  3 root     root       4096 Feb  2 11:59 ..
-rw-------  1 postgres postgres      3 Feb  2 09:58 PG_VERSION
-rw-------  1 postgres postgres    225 Feb  2 09:58 backup_label.old
-rw-------  1 postgres postgres 189444 Feb  2 09:59 backup_manifest
drwx------  6 postgres postgres   4096 Feb  2 09:59 base
......
```

Сложный момент - пользователь postgres vm-otus1 и vm-otus2 могут не совпадать по id, потребуется ручная коррекция прав доступа в /mnt/pg_data  

vm-otus2 Останавливаю Postgres
```
sudo systemctl stop postgresql@18-main.service
```

vm-otus2 В конфигурационном файле postgresql.conf меняю рабочую директорию
```
sudo cp /etc/postgresql/18/main/postgresql.conf /etc/postgresql/18/main/postgresql.conf.backup-$(date +%F)
sudo sed -i "s|data_directory = '.*'|data_directory = '/mnt/pg_data'|" /etc/postgresql/18/main/postgresql.conf
```

Удаляю исходную директорию с данными Postgresql (В реальных условиях директория будет удалена после успешного запуска с новым расположением файлов)
```
sudo rm -rf /var/lib/postgresql/18/main
```

vm-otus2 Запускаю Postgres
```
sudo systemctl start postgresql@18-main.service
```
Подготовка env PGPASSWORD 
```
export PGPASSWORD=postgres
echo "localhost:5432:*:postgres:${PGPASSWORD}" > .pgpass
`chmod 0600 ~/.pgpass`
```

Проверка состояния БД
```
psql -h localhost -U postgres -w -c "\l"
                                                     List of databases
   Name    |  Owner   | Encoding | Locale Provider |   Collate   |    Ctype    | Locale | ICU Rules |   Access privileges   
-----------+----------+----------+-----------------+-------------+-------------+--------+-----------+-----------------------
 demo      | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 |        |           | 
 postgres  | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | 
 template0 | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | =c/postgres          +
           |          |          |                 |             |             |        |           | postgres=CTc/postgres
 template1 | postgres | UTF8     | libc            | C.UTF-8     | C.UTF-8     |        |           | =c/postgres          +
           |          |          |                 |             |             |        |           | postgres=CTc/postgres
(4 rows)

psql -h localhost -U postgres -w -d demo -c "\dt"
                List of tables
  Schema  |      Name       | Type  |  Owner   
----------+-----------------+-------+----------
 bookings | airplanes_data  | table | postgres
 bookings | airports_data   | table | postgres
 bookings | boarding_passes | table | postgres
 bookings | bookings        | table | postgres
 bookings | flights         | table | postgres
 bookings | routes          | table | postgres
 bookings | seats           | table | postgres
 bookings | segments        | table | postgres
 bookings | tickets         | table | postgres
(9 rows)

psql -h localhost -U postgres -w -d demo -c "SELECT count(1) FROM boarding_passes;"
  count  
---------
 5982418
(1 row)

```


Остановка и удаление VM в ЯО
```
yc compute instance delete vm-otus2 &&\
yc compute instance delete vm-otus1 &&\
yc vpc subnet delete subnet-otus1 &&\
yc vpc network delete net-otus1

yc compute instance list
yc vpc subnet list
yc vpc network list
```