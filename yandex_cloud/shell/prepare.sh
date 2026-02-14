#!/bin/bash
set -e
SSH_KEY=~/.ssh/id_rsa.pub
NAMESPACE='otus'

QUANTITY=$1
if [ -z "$QUANTITY" ]; then
  read -p "Количество vm: " QUANTITY
fi
QUANTITY=${QUANTITY:-1}

read -p "Установить Postgres? Y/N [N]: " IS_INSTALL

NET="net-${NAMESPACE}"
SUBNET="subnet-${NAMESPACE}"
DNS_ZONE="dns-${NAMESPACE}"
if ! yc vpc network show --name ${NET} 2>/dev/null; then
  yc vpc network create --name ${NET};
  echo "Создан network ${NET}"
else
  echo "Работает network ${NET}"
fi

if ! yc vpc subnet show --name ${SUBNET} 2>/dev/null; then
  yc vpc subnet create --name ${SUBNET} --range 192.168.0.0/24 --network-name ${NET};
  echo "Создана subnet ${SUBNET}"
else
  echo "Работает subnet ${SUBNET}"
fi

if ! yc dns zone show --name ${DNS_ZONE} 2>/dev/null; then
  NET_ID = $(yc vpc network show --name ${NET} --format=json | jq -r ".id")
  yc dns zone create --name dns-otus --zone staging. --private-visibility ${NET_ID}
  echo "Создана dns ${DNS_ZONE}}"
else
  echo "Работает dns ${DNS_ZONE}"
fi

echo "Создаются $QUANTITY VM"
for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "Создаётся VM ${VM_NAME}"
  if ! yc compute instance show --name ${VM_NAME} 2>/dev/null; then
    yc compute instance create --name ${VM_NAME} --hostname ${VM_NAME} --cores 2 --memory 4 \
    --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
    --network-interface subnet-name=${SUBNET},nat-ip-version=ipv4 --ssh-key $SSH_KEY
    echo "Создана ${VM_NAME}"
  else
    echo "Работает ${VM_NAME}"
  fi
  IP_VM=$(yc compute instance show --name ${VM_NAME} | grep -E ' +address' | tail -n 1 | awk '{print $2}')
  ADDR_VM[$NUM]=${IP_VM}
done

export ADDR_VM

if [[ "$IS_INSTALL" == "Y" || "$IS_INSTALL" == "y" ]]; then
  for NUM in $(seq 1 1 $QUANTITY); do
    echo "Установка Posgresql ${VM_NAME} ";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh;
    echo "Подготовлена ${VM_NAME}";
  done;
fi

for NUM in $(seq 1 1 $QUANTITY); do
  echo "VM vm-${NAMESPACE}${NUM} : ${ADDR_VM[$NUM]}"
done

echo "ADDR_VM[1]=\$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print \$2}') && ssh  -o StrictHostKeyChecking=no yc-user@\${ADDR_VM[1]}"