#!/bin/bash
set -e
if ! yc vpc network show --name net-otus1; then
  yc vpc network create --name net-otus1;
fi
echo "Создана network"

if ! yc vpc subnet show --name subnet-otus1; then
  yc vpc subnet create --name subnet-otus1 --range 192.168.0.0/24 --network-name net-otus1;
fi
echo "Создана subnet"

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
vm_ip_address1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
echo "Создана vm-otus1"

yc compute instance create --name vm-otus2 --hostname vm-otus2 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
vm_ip_address2=$(yc compute instance show --name vm-otus2 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
echo "Создана vm-otus2"

yc compute instance create --name vm-otus3 --hostname vm-otus3 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub
vm_ip_address3=$(yc compute instance show --name vm-otus3 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
echo "Создана vm-otus3"

sleep 15

echo "Установка Posgresql vm-otus1"
ssh -o StrictHostKeyChecking=no yc-user@$vm_ip_address1 'bash -s ' < /home/andrey/www/postgres/postgres-otus/yandex_cloud/install_postgresql.sh
echo "Подготовлена vm-otus1"

ssh -o StrictHostKeyChecking=no yc-user@$vm_ip_address2  'bash -s ' < /home/andrey/www/postgres/postgres-otus/yandex_cloud/install_postgresql.sh
echo "Подготовлена vm-otus2"

ssh -o StrictHostKeyChecking=no yc-user@$vm_ip_address3 'bash -s ' < /home/andrey/www/postgres/postgres-otus/yandex_cloud/install_postgresql.sh
echo "Подготовлена vm-otus3"