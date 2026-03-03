# Virtual Machines (Compute Cloud) https://cloud.yandex.ru/docs/free-trial/

Создание виртуальной машины:
https://cloud.yandex.ru/docs/compute/quickstart/quick-create-linux



# Создаем сетевую инфраструктуру и саму VM:
yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create --name otus-vm2 --hostname otus-vm2 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/yc_key.pub 

# Подключимся к VM:
vm_ip_address=$(yc compute instance show --name otus-vm2 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/yc_key yc-user@$vm_ip_address 

# Установим PostgreSQL:
sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql && sudo apt -y install mc

pg_lsclusters


https://habr.com/ru/articles/494338/
https://habr.com/ru/articles/486188/
https://habr.com/ru/articles/506610/
https://github.com/wal-g/wal-g


# Скачать бинарник WAL-G
https://github.com/wal-g/wal-g/releases

wget https://github.com/wal-g/wal-g/releases/download/v3.0.7/wal-g-pg-ubuntu-24.04-amd64.tar.gz && tar -zxvf wal-g-pg-ubuntu-24.04-amd64.tar.gz && sudo mv wal-g-pg-ubuntu-24.04-amd64.tar.gz /usr/local/bin/wal-g

curl -L "https://github.com/wal-g/wal-g/releases/download/v3.0.7/wal-g-pg-ubuntu-24.04-amd64" -o "wal-g"

# Перенести файл
sudo mv wal-g /usr/local/bin/

sudo ls -l /usr/local/bin/wal-g

sudo chmod ugo+x /usr/local/bin/wal-g
sudo wal-g --version

# Создаем каталог для хранения резервных копий и сделаем владельцем пользователя postgres
sudo mkdir /home/backups && sudo chown -R postgres:postgres /home/backups/

# Создать настроечный файл для wal-g под текущим пользователем = в /var/lib/postgresql/.walg.json
sudo su postgres
nano ~/.walg.json

# Заполняем настройками
{
    "WALG_FILE_PREFIX": "/home/backups",
    "WALG_COMPRESSION_METHOD": "brotli",
    "WALG_DELTA_MAX_STEPS": "5",
    "WALG_UPLOAD_DISK_CONCURRENCY": "4",
    "PGDATA": "/var/lib/postgresql/18/main",
    "PGHOST": "localhost"
}

// - указывается папка назначения
// - метод компрессии ( brotli, lz4, zstd, zlib )
// - количество "дельт"  (инкрементальных архивов) между полными ( full ) архивами
// - количество потоков записи к диску при выгрузке
// - папка с данными<br>
// - сервер PostgreSQL



# создать каталог для логов
mkdir /var/lib/postgresql/log

# Настраиваем параметры конфигурации
echo "wal_level=replica" >> /var/lib/postgresql/18/main/postgresql.auto.conf
echo "archive_mode=on" >> /var/lib/postgresql/18/main/postgresql.auto.conf
echo "archive_timeout=60" >> /var/lib/postgresql/18/main/postgresql.auto.conf 

echo "archive_command='wal-g wal-push \"%p\" >> /var/log/postgresql/archive_command.log 2>&1' " >> /var/lib/postgresql/18/main/postgresql.auto.conf 

echo "restore_command='wal-g wal-fetch \"%f\" \"%p\" >> /var/log/postgresql/restore_command.log 2>&1' " >> /var/lib/postgresql/18/main/postgresql.auto.conf


cat ~/18/main/postgresql.auto.conf


nano /etc/postgresql/18/main/pg_hba.conf
host all all 127.0.0.1/32 trust

# Перезагружаем сервис БД  
exit
sudo systemctl restart postgresql

psql -c 'show archive_mode'

# Создадим новую базу данных
psql -c "CREATE DATABASE otus;"

## Таблицу в этой базе данных и заполним ее тестовыми данными
psql otus -c "CREATE TABLE test(i int);"
psql otus -c "INSERT INTO test VALUES (10), (20), (30);"
psql otus -c "SELECT * FROM test;"

# Делаем первый бэкап
/usr/local/bin/wal-g backup-push /var/lib/postgresql/18/main

wal-g --config=/var/lib/postgresql/.walg.json backup-push /var/lib/postgresql/18/main

# Смотрим что получилось
/usr/local/bin/wal-g backup-list

ls -l /home/backups

# В таблицу test внесем дополнительные данные
psql otus -c "insert into test values (110), (120), (130);"
psql otus -c "select * from test;"

# Делаем еще бэкап
wal-g backup-push /var/lib/postgresql/18/main

# Смотрим что получилось
wal-g backup-list

wal-g backup-list --detail --json | jq .

wal-g wal-show

wal-g wal-show --detailed-json | jq .

sudo apt install tree
cd /home/backups
tree

# Восстановление базы

## Создадим новый кластер БД  
pg_createcluster -d /var/lib/postgresql/18/main2 18 main2

exit
sudo systemctl stop postgresql

## Удаляем данные 
rm -rf /var/lib/postgresql/18/main2/*

wal-g backup-fetch /var/lib/postgresql/18/main2 LATEST

touch /var/lib/postgresql/18/main2/recovery.signal

## Стартуем сервис БД и проверяем содержимое таблички
pg_ctlcluster 18 main2 start
или 
exit
sudo systemctl start postgresql@18-main2



sudo -u postgres psql otus -p 5433 -c "SELECT * FROM test;"




# удаление ВМ и сети
yc compute instance delete otus-vm2 && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net


