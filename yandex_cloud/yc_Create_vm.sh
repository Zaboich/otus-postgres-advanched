yc vpc network create --name net-otus1 --description "Net otus postgres adv 1" 

yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1 --description "SubNet otus postgres adv 1" 

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub 

ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') 
ssh -o StrictHostKeyChecking=no yc-user@$ADDR_VM1

sudo apt update && sudo apt upgrade -y && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt update && sudo apt install -y postgresql 

# слушать внешние подключения
sudo sed -i "/listen_addresses/c\listen_addresses = '*'" /etc/postgresql/18/main/postgresql.conf 
# принимать подключения со всех адресов с паролем
sudo sed -i 's#host.*all.*all.*127.0.0.1/.*$#host    all             all             0.0.0.0/0               scram-sha-256#' /etc/postgresql/18/main/pg_hba.conf

yc compute instance delete vm-otus1
yc vpc subnet delete subnet-otus1
yc vpc network delete net-otus1


yc vpc subnet list


sudo -u postgres psql
---------------------------
create database otus;
\c otus


текущее состояние
\echo :AUTOCOMMIT


SET SESSION AUTOCOMMIT = 0; 
или
\set AUTOCOMMIT 0


show transaction isolation level;

\dt
Did not find any tables.

CREATE TABLE test2 (i serial, amount int);
INSERT INTO test2(amount) VALUES (100),(500);
SELECT * FROM test2;