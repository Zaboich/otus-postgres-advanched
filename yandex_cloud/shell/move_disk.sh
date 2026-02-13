# перенос директории на отдельный диск
yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 2 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub &&\
yc compute disk create \
    --name disk-otus3 \
    --type network-hdd \
    --size 5 \
    --description "second disk for vm-otus1"  &&\
yc compute instance attach-disk vm-otus1 \
    --disk-name disk-otus3 \
    --mode rw \
    --auto-delete &&\
ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
ssh  -o StrictHostKeyChecking=no yc-user@$ADDR_VM1

sudo pvcreate /dev/vdb &&\
sudo vgcreate vg-pg_data /dev/vdb &&\
sudo lvcreate -l +100%FREE --name lv-pg_data vg-pg_data &&\
sudo mkfs.ext4 -T news /dev/vg-pg_data/lv-pg_data &&\
sudo mkdir -p /mnt/pg_data &&\
sudo mount /dev/vg-pg_data/lv-pg_data /mnt/pg_data &&\
sudo rsync -aHX /var/log/ /mnt/pg_data/ &&\
sudo ls -l /mnt/pg_data/ &&\
sudo umount /mnt/pg_data &&\
sudo mv /var/log /var/log.bak
sudo mkdir  /var/log &&\
sudo mount /dev/vg-pg_data/lv-pg_data /var/log
sudo ls -l /var/log/
sudo systemctl restart rsyslog
sudo systemctl restart systemd-journald