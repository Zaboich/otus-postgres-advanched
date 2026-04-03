#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
echo "Имя каталога для хранения резервных копий "
MNT_NAME="backup"
MNT_PATH=/mnt/${MNT_NAME}
# общая часть имён хостов
HOSTNAME=$(hostname)

sudo mkdir -p $MNT_PATH && echo "${HOSTNAME} создана директория ${MNT_PATH}"


if [ -b /dev/vdb ]; then
    echo "Дополнительный диск /dev/vdb монтируется в ${MNT_PATH} как том LVM"
    sudo pvcreate /dev/vdb
    sudo vgcreate vg-${MNT_NAME} /dev/vdb
    sudo lvcreate -l +100%FREE --name lv-${MNT_NAME} vg-${MNT_NAME}
    sudo mkfs.ext4 /dev/vg-${MNT_NAME}/lv-${MNT_NAME}

    sudo mount /dev/vg-${MNT_NAME}/lv-${MNT_NAME} $MNT_PATH
    echo "/dev/vg-${MNT_NAME}/lv-${MNT_NAME} $MNT_PATH ext4 defaults 0 2" | sudo tee -a /etc/fstab
    echo "Диск смонтирован в ${MNT_PATH}"
else
    echo "/dev/vdb does not exist"
fi


sudo chown -R postgres:postgres $MNT_PATH
sudo chmod 700 $MNT_PATH

