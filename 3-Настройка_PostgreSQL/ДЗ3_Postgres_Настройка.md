Разворачиваю VM ЯО
```
yc vpc network create --name net-otus1
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
```

Создаю дополнительный диск для ВМ:
```
yc compute disk-type list

yc compute disk create \
    --name disk-otus3 \
    --type network-hdd \
    --size 5 \
    --description "second disk for vm-otus1"

yc compute disk list
yc compute instance list
```
Подключаю диск к VM
Подключим новый диск к нашей ВМ:
```
yc compute instance attach-disk vm-otus1 \
    --disk-name disk-otus3 \
    --mode rw \
    --auto-delete
```

Вход ssh на VM vm-otus1
```
ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
ssh yc-user@$ADDR_VM1
```

Установить  PostgreSQL
```
sudo apt update && sudo apt upgrade -y 
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
sudo apt update && \
sudo apt install -y postgresql
```

Устанавливаем пароль пользователю postgres
```
sudo -u postgres psql -c "alter user postgres password 'postgres';"
export PGPASSWORD=postgres
echo "*:5432:*:postgres:postgres" > .pgpass
chmod 0600 ~/.pgpass
```

Скачать файл "Демонстрационная база данных" PostgresPro 
```
curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz 
```
Загрузить дамп в БД
```
gunzip -c demo-20250901-6m.sql.gz | psql -U postgres -w
```
Проверить содерижимое БД
```
psql -U postgres -w -c "\l"

psql -U postgres -w -d demo -c "\dt"

psql -U postgres -w -d demo -c "SELECT count(1) FROM boarding_passes;"
```

Отформатирую и монтирую дополнительный диск в /mnt/pg_data
```
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /mnt/pg_data
sudo mount /dev/vdb /mnt/pg_data
echo '/dev/vdb /mnt/pg_data ext4 defaults 0 2' | sudo tee -a /etc/fstab

sudo chown -R postgres:postgres /mnt/pg_data
sudo chmod 700 /mnt/pg_data
```

**Перенос БД на новый диск с помощью pg_basebackup**
разрешение на подключение в pg_hba.conf по протоколу репликации
```
echo '127.0.0.1   replication     postgres        127.0.0.1/32    md5' | sudo tee -a /var/lib/postgres/18/main/pg_hba.conf
sudo pg_ctlcluster 14 main restart
```
Создание резервной копии 
```
sudo rm -rf /mnt/pg_data/*
sudo -u postgres pg_basebackup -h 127.0.0.1 -U postgres -w -D /mnt/pg_data -Fp -Xs -P -R -v
```

Остановка и удаление VM в ЯО
```
yc compute instance delete vm-otus1 &&\
yc vpc subnet delete subnet-otus1 &&\
yc vpc network delete net-otus1
```