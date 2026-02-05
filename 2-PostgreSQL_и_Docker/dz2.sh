yc vpc network create --name net-otus1
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1

yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub

ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}')
ssh -o StrictHostKeyChecking=no yc-user@$ADDR_VM1

sess1
sudo apt update && sudo apt install -y docker.io docker-compose-v2

sudo usermod -aG docker yc-user

mkdir /var/lib/postgres


nano docker-compose.yml
```
services:
    postgres:
        image: postgres:18-alpine
        volumes:
            - /var/lib/postgres:/var/lib/postgresql:rw
        ports:
            - 0.0.0.0:5432:5432
```

docker compose -f docker-compose.yml pull

docker compose -f docker-compose.yml up -d



yc compute instance delete vm-otus1
yc vpc subnet delete subnet-otus1
yc vpc network delete net-otus1