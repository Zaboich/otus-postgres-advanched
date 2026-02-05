Разворачиваю VM ЯО
```
yc vpc network create --name net-otus1 &&\
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
```

Создаю дополнительный диск для ВМ:
```
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

Вход ssh на VM vm-otus1
```
ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
ssh  -o StrictHostKeyChecking=no yc-user@$ADDR_VM1
```

Установить  PostgreSQL
```
sudo apt update && sudo apt upgrade -y 
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - 

sudo apt update && \
sudo apt install -y postgresql
```

Устанавливаем пароль пользователю postgres
```
sudo -u postgres psql -c "alter user postgres password 'postgres';"

export PGPASSWORD=postgres
echo "localhost:5432:*:postgres:postgres" > .pgpass
`chmod 0600 ~/.pgpass`
```

Скачать файл "Демонстрационная база данных" PostgresPro 
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

Форматирую и монтирую дополнительный диск в /mnt/pg_data
```
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /mnt/pg_data
sudo mount /dev/vdb /mnt/pg_data
echo '/dev/vdb /mnt/pg_data ext4 defaults 0 2' | sudo tee -a /etc/fstab

sudo chown -R postgres:postgres /mnt/pg_data
sudo chmod 700 /mnt/pg_data
```
```
sudo pvcreate /dev/vdb
sudo vgcreate vg-pg_data /dev/vdb
sudo lvcreate --size 5G --name lv-pg_data vg-pg_data

sudo mkfs.ext4 /dev/vg-pg_data/lv-pg_data
sudo mkdir /mnt/pg_data
sudo mount /dev/vg-pg_data/lv-pg_data /mnt/pg_data
echo '/dev/vg-pg_data/lv-pg_data /mnt/pg_data ext4 defaults 0 2' | sudo tee -a /etc/fstab
```

```
sudo chown -R postgres:postgres /mnt/pg_data
sudo chmod 700 /mnt/pg_data
```

**Перенос БД на новый диск с помощью pg_basebackup**
разрешение на подключение в pg_hba.conf по протоколу репликации
```
# echo 'local   replication     postgres        127.0.0.1/32    scram-sha-256' | sudo tee -a /etc/postgresql/18/main/pg_hba.conf
# sudo pg_ctlcluster 14 main restart
```

Копирование файлов БД на созданный диск с помощью pg_basebackup
```
sudo rm -rf /mnt/pg_data/*
sudo -u postgres export PGPASSWORD=postgres && pg_basebackup -h 127.0.0.1 -U postgres -w -D /mnt/pg_data -Fp -Xs -P -R -v

sudo -u postgres rm /mnt/pg_data/standby.signal
```

Остановка Postgres и проверка состояния
```
sudo systemctl stop postgresql@18-main

sudo systemctl status postgresql@18-main
```
Создаю копию postgres.conf
В конфигурационном файле postgres.conf меняю рабочую директорию
```
sudo cp /etc/postgresql/18/main/postgresql.conf /etc/postgresql/18/main/postgresql.conf.backup-$(date +%F)
sudo sed -i "s|data_directory = '.*'|data_directory = '/mnt/pg_data'|" /etc/postgresql/18/main/postgresql.conf
```


Остановка и удаление VM в ЯО
```
yc compute instance delete vm-otus1 &&\
yc vpc subnet delete subnet-otus1 &&\
yc vpc network delete net-otus1
```