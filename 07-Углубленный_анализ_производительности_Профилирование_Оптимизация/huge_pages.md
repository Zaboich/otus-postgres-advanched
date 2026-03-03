# Virtual Machines (Compute Cloud) https://cloud.yandex.ru/docs/free-trial/


Создание виртуальной машины:
https://cloud.yandex.ru/docs/compute/quickstart/quick-create-linux

Подключение к VM:
https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh

'yc' в составе Яндекс.Облако CLI для управления облачными ресурсами в Яндекс.Облако
https://cloud.yandex.com/en/docs/cli/quickstart


# Создаем сетевую инфраструктуру и саму VM:
yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create --name otus-vm --hostname otus-vm --cores 4 --memory 32 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/yc_key.pub 

yc compute instances list

# Подключимся к VM:
vm_ip_address=$(yc compute instance show --name otus-vm | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/yc_key yc-user@$vm_ip_address 

# Установим PostgreSQL:
sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt update && sudo apt -y install postgresql && sudo apt install unzip && sudo apt -y install mc



pg_lsclusters

------

sudo -u postgres psql

create database otus;

\c otus

\timing

CREATE TABLE student(
  id serial,
  fio char(100)
);

INSERT INTO student(fio) SELECT 'noname' FROM generate_series(1,10000000);  
--- 59244.557 ms (00:59.245)
--- 41272.019 ms (00:41.272)
--- 43433.258 ms (00:43.433)

SELECT pg_size_pretty(pg_database_size('otus'));
-------------

# huge pages
grep HUGETLB /boot/config-$(uname -r)
grep Huge /proc/meminfo
sudo head -1 /var/lib/postgresql/18/main/postmaster.pid 	--- 9260
grep ^VmPeak /proc/9260/status 		                        --- 231604
grep -i hugepagesize /proc/meminfo		                    --- 2024
echo $((231604 / 2048 + 5)) 			                        --- 118 
sudo sysctl -w vm.nr_hugepages=118

--- sudo systemctl daemon-reload
--- sudo systemctl -p --system

select name, setting from pg_settings where name like 'huge%';

alter system set huge_pages = 'on';

sudo pg_ctlcluster 18 main restart

---
truncate TABLE student;

INSERT INTO student(fio) SELECT 'noname' FROM generate_series(1,10000000); 

-----------
# transparent_hugepage
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag

## Создать новый файл
sudo nano /etc/systemd/system/disable-thp.service

[Unit]
Description=Disable Transparent Huge Pages

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
  
## Перезагрузить
sudo systemctl daemon-reload
sudo systemctl enable disable-thp.service
sudo systemctl start disable-thp.service

# swappiness 
cat /proc/sys/vm/swappiness
sudo sysctl vm.swappiness=5
echo 'vm.swappiness=5' >> sudo /etc/sysctl.conf


# удаление ВМ и сети
yc compute instance delete otus-vm && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net




