# Virtual Machines (Compute Cloud) https://cloud.yandex.ru/docs/free-trial/

Создание виртуальной машины:
https://cloud.yandex.ru/docs/compute/quickstart/quick-create-linux



# Создаем сетевую инфраструктуру и саму VM:
yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create --name otus-vm --hostname otus-vm --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/yc_key.pub 

# Подключимся к VM:
vm_ip_address=$(yc compute instance show --name otus-vm | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/yc_key yc-user@$vm_ip_address 

# Установим PostgreSQL:
sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql && sudo apt install unzip && sudo apt -y install mc

pg_lsclusters

/*
sudo sh -c 'echo "deb [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb/ $(lsb_release -cs) main-$(lsb_release -cs)" > /etc/apt/sources.list.d/pg_probackup.list' && sudo wget -O - https://repo.postgrespro.ru/pg_probackup/keys/GPG-KEY-PG_PROBACKUP | sudo apt-key add - && sudo apt-get update
*/

https://postgrespro.github.io/pg_probackup
https://github.com/postgrespro/pg_probackup
https://postgrespro.ru/docs/postgrespro/18/app-pgprobackup
https://habr.com/ru/companies/barsgroup/articles/515592/

# Add the pg_probackup repository GPG key
sudo apt install gpg wget && sudo wget -qO - https://repo.postgrespro.ru/pg_probackup/keys/GPG-KEY-PG-PROBACKUP 

# Setup the binary package repository
sudo sh -c 'echo "deb [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb/ $(lsb_release -cs) main-$(lsb_release -cs)" > /etc/apt/sources.list.d/pg_probackup.list'

# Optionally setup the source package repository for rebuilding the binaries
sudo sh -c 'echo "deb-src [arch=amd64] https://repo.postgrespro.ru/pg_probackup/deb $VERSION_CODENAME main-$VERSION_CODENAME" | \
sudo tee -a /etc/apt/sources.list.d/pg_probackup.list'

sudo apt update
apt search pg_probackup

# Install or upgrade a pg_probackup version of your choice
sudo apt install pg-probackup-18

# Optionally install the debug package
sudo apt install pg-probackup-18-dbg

# Создаем каталог для хранения резервных копий + (Со ВСЕМИ правами - НЕ ДЛЯ ПРОДа)
sudo mkdir /home/backups && sudo chmod 777 /home/backups

# Переключимся на пользователя который описан в PG
sudo su postgres

# Инициализируем созданный каталог как каталог для бакапов:
pg_probackup-18 init -B /home/backups

## Посмотрим содержимое(или в любом навигаторе):
ls -al /home/backups

# Инициализируем инстанс кластера по его пути и назовем его 'main' и определим что он будет хранить бакапы по выбранному пути
pg_probackup-18 add-instance --instance 'main' -D /var/lib/postgresql/18/main -B /home/backups

# Создадим новую базу данных
psql -c "CREATE DATABASE otus;"

## Таблицу в этой базе данных и заполним ее тестовыми данными
psql otus -c "CREATE TABLE test(i int);"
psql otus -c "INSERT INTO test VALUES (10), (20), (30);"
psql otus -c "SELECT * FROM test;"


# Смотрим текущие настройки конкретного инстанса и каталога
pg_probackup-18 show-config --instance main -B /home/backups

# Делаем бэкап - первый раз всегда FULL
## -b           тип создания резервной копии. Для первого запуска нужно создать полную копию кластера PostgreSQL, поэтому команда FULL
## -–stream     указывает на то, что нужно вместе с созданием резервной копии, параллельно передавать wal по слоту репликации. Запуск потоковой передачи wal.
## --temp-slot  указывает на то, что потоковая передача wal-ов будет использовать временный слот репликации
pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot -B /home/backups

# Посмотрим на перечень бэкапов
pg_probackup-18 show -B /home/backups


# В таблицу test внесем дополнительные данные
psql otus -c "insert into test values (4);"

# Создадим инкрементальную копию 
pg_probackup-18 backup --instance 'main' -b DELTA --stream --temp-slot -B /home/backups

pg_probackup-18 show -B /home/backups

# Восстановление базы

## Удалим таблицу
psql otus -c "DROP TABLE test;"

## Останавливаем сервис БД  
exit
sudo systemctl stop postgresql

## Удаляем данные 
rm -rf /var/lib/postgresql/18/main/*

## Восстанавливаемся из FULL бэкапа с указанием ID 
sudo su postgres
pg_probackup-18 show -B /home/backups

pg_probackup-18 restore --instance 'main' -i 'T9JBCT' -D /var/lib/postgresql/18/main -B /home/backups

## Стартуем сервис БД и проверяем содержимое таблички
exit
sudo systemctl start postgresql

sudo -u postgres psql otus -c "SELECT * FROM test;"

## !!! Обратите внимание - без 4-и !!!

# Восстановление из инкрементального бэкапа и с его ИД
## Останавливаем сервис БД
exit
sudo systemctl stop postgresql

## Чистим кластер
rm -rf /var/lib/postgresql/18/main/*

## Восстанавливаемся из DELTA бэкапа
sudo su postgres
pg_probackup-18 restore --instance 'main' -i 'T9JBG3' -D /var/lib/postgresql/18/main -B /home/backups

## Стартуем сервис БД и проверяем содержимое таблички
exit
sudo systemctl start postgresql

sudo -u postgres psql otus -c "SELECT * FROM test;"

# Настроить хранение не больше 2 полных копий
## Несколько раз сделать полный бекап
pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot -B /home/backups
pg_probackup-18 show -B /home/backups


pg_probackup-18 show-config --instance main -B /home/backups

pg_probackup-18 set-config --instance 'main' --retention-redundancy=2 -B /home/backups
pg_probackup-18 delete --instance 'main' --delete-expired --retention-redundancy=2 -B /home/backups

# Настроить архивирование WAL - файлов (Point-In-Time-Recovery)


## смотрим состояние архивирования
psql -c 'show archive_mode'

psql

alter system set archive_mode = on;
alter system set archive_command = 'pg_probackup-18 archive-push -B /home/backups/ --instance=main --wal-file-path=%p --wal-file-name=%f --compress';

exit
sudo systemctl restart postgresql

sudo su postgres 
psql -c 'show archive_mode'

## делаем новый полный бэкап(т.к. изменили режим бэкапирования!!!)
## задать пароль для пользователя postgres
\password

pg_probackup-18 backup --instance 'main' -b FULL --stream --temp-slot -h localhost -d otus -p 5432 -B /home/backups

## посмотрим на перечень бэкапов
pg_probackup-18 show -B /home/backups

## Добавим запись
psql otus -c "insert into test values (10);"

psql otus -c "select now();"     --- 2026-01-27 15:25:10.676836+00

psql otus -c "select * from test;"

psql otus -c "delete from test where i = 10;"

## Останавливаем сервис БД
exit
sudo systemctl stop postgresql

## Чистим кластер
rm -rf /var/lib/postgresql/18/main/*

# Восстанавливаемся на конкретную точку времени
sudo su postgres
pg_probackup-18 restore --instance 'main' -D /var/lib/postgresql/18/main -B /home/backups --recovery-target-time="2026-01-27 15:25:10.676836+00"



# удаление ВМ и сети
yc compute instance delete otus-vm && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net


