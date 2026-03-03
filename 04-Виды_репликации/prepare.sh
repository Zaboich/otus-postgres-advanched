#!/bin/bash
set -e

# указать расположение публичной части ключа ssh
SSH_KEY=~/.ssh/id_rsa.pub


if ! yc vpc network show --name net-otus1 2>/dev/null; then
  yc vpc network create --name net-otus1;
  echo "Создана network net-otus1"
else
  echo "Работает network net-otus1"
fi


if ! yc vpc subnet show --name subnet-otus1 2>/dev/null; then
  yc vpc subnet create --name subnet-otus1 --range 192.168.0.0/24 --network-name net-otus1;
  echo "Создана subnet subnet-otus1"
else
  echo "Работает subnet subnet-otus1"
fi


if ! yc compute instance show --name  vm-otus1 2>/dev/null; then
  yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key $SSH_KEY
  echo "Создана vm-otus1"
else
  echo "Работает vm-otus1"
fi

if ! yc compute instance show --name  vm-otus2 2>/dev/null; then
  yc compute instance create --name vm-otus2 --hostname vm-otus2 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key $SSH_KEY
  echo "Создана vm-otus2"
else
  echo "Работает vm-otus2"
fi

if ! yc compute instance show --name  vm-otus3 2>/dev/null; then
  yc compute instance create --name vm-otus3 --hostname vm-otus3 --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts --network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key $SSH_KEY
  echo "Создана vm-otus3"
else
  echo "Работает vm-otus3"
fi

echo "Установка Posgresql vm-otus1"
IP_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
export IP_VM1
ssh -o StrictHostKeyChecking=no -t -i $SSH_KEY yc-user@$IP_VM1 'bash -s ' < ./install_postgresql.sh
echo "Подготовлена vm-otus1"

IP_VM2=$(yc compute instance show --name vm-otus2 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
ssh -o StrictHostKeyChecking=no -t -i $SSH_KEY yc-user@$IP_VM2  'bash -s ' < ./install_postgresql.sh
echo "Подготовлена vm-otus2"

IP_VM3=$(yc compute instance show --name vm-otus3 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
ssh -o StrictHostKeyChecking=no -t -i $SSH_KEY yc-user@$IP_VM3 'bash -s ' < ./install_postgresql.sh
echo "Подготовлена vm-otus3"