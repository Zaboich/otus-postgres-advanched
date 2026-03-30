#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
echo "Имя каталога для хранения резервных копий "
MNT_NAME="backup"
MNT_PATH=/mnt/${MNT_NAME}
# общая часть имён хостов
HOSTNAME=$(hostname)

echo "Дополнительный диск монтируется в /mnt/backup как том LVM" 

sudo pvcreate /dev/vdb
sudo vgcreate vg-${MNT_NAME} /dev/vdb
sudo lvcreate -l +100%FREE --name lv-${MNT_NAME} vg-${MNT_NAME}
sudo mkfs.ext4 /dev/vg-${MNT_NAME}/lv-${MNT_NAME}

sudo mkdir $MNT_PATH
sudo mount /dev/vg-${MNT_NAME}/lv-${MNT_NAME} $MNT_PATH
echo "/dev/vg-${MNT_NAME}/lv-${MNT_NAME} $MNT_PATH ext4 defaults 0 2" | sudo tee -a /etc/fstab

sudo chown -R postgres:postgres $MNT_PATH
sudo chmod 700 $MNT_PATH

