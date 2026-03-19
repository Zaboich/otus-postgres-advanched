#!/bin/bash
set -e
START_DATE=$(date)
SSH_KEY=~/.ssh/id_rsa.pub
NAMESPACE='otus'

# 3 VM для кластера Patroni+Postgres 3 VM для кластера etcd
QUANTITY=6

QUANT_ETCD=$(($QUANTITY/2))
FIRST_POSTGRES=$((QUANT_ETCD+1))

read -p "Установить ETCD и Postgres? Y/N [N]: " IS_INSTALL

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
  NET_ID=$(yc vpc network show --name ${NET} --format=json | jq -r ".id")
  yc dns zone create --name dns-otus --zone staging. --private-visibility ${NET_ID}
  echo "Создана dns ${DNS_ZONE}"
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
  echo "------------------------------------------------"
done
# Массив ip созданных VM
export ADDR_VM

# Устанавливаем программы
# Установка ETCD на машины 1-3
if [[ "$IS_INSTALL" == "Y" || "$IS_INSTALL" == "y" ]]; then

  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Установка ETCD ";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_etcd.sh;
    echo "${VM_NAME} Установлен и подготовлен ETCD. Сервис etcd остановлен";
    echo "------------------------------------------------"
  done;

  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Запуск ETCD ";
    # Вызывается команда старта сервиса без ожидания результата, чтобы стартовать etcd на всех серверах кластера
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'nohup sudo systemctl start etcd  > /dev/null 2>&1 &';
    echo "${VM_NAME} Запущен ETCD";
  done;
  echo "Ожидаение 15 c для согласования кластера ETCD"
  sleep 15;
  echo "------------------------------------------------"

  # Проверка состояния кластера
  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Состояние ETCD";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'etcdctl endpoint status --cluster -w table';
  done;

  # На VM 4-6  Устанавливается Postgresql 18 и Patroni. Оба сервиса настраиваются и останавиливаются
  for NUM in $(seq $(($QUANT_ETCD + 1)) 1 $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Установка Posgresql";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh;
    echo "${VM_NAME} Установлен и подготовлен Postgres.";

    echo "${VM_NAME} загрузка шаблона файла конфигурации Patroni";
    scp ./patroni.yml yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.yml

    echo "${VM_NAME} загрузка файла сервиса Patroni";
    scp ./patroni.service yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.service && ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'sudo mv /tmp/patroni.service /etc/systemd/system/patroni.service';
    echo "${VM_NAME} Загружен файл службы patroni.service";

    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_patroni.sh;
    echo "${VM_NAME} Установлен и подготовлен Patroni . Сервис patroni остановлен";
    echo "------------------------------------------------";
  done;

  # Стартуем Leader Node для кластера Patroni
  echo "${VM_NAME} Запуск Patroni как Leader node";
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$FIRST_POSTGRES]} 'bash -s ' < ./init_patroni_leader.sh;
  sleep 10
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
  echo "${VM_NAME} Patroni Leader node запущен";
  echo "------------------------------------------------";


  for NUM in $(seq $(($FIRST_POSTGRES+1)) 1  $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Запуск Patroni как Replica node";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./init_patroni_replica.sh;
    echo "${VM_NAME} Запущен Patroni";
  done;


fi

# Проверка состояния кластера
for NUM in $(seq $FIRST_POSTGRES 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
#    echo "${VM_NAME} Состояние сервиса Patroni";
#    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'systemctl status patroni';
  echo "${VM_NAME} Список нод в кластере Patroni";
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;

# Создаём БД Demo и заполняем данными
echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Запуск Patroni как Leader node";
(ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$FIRST_POSTGRES]} 'bash -s ' < ./init_patroni_leader.sh && echo "БД на Leader заполнена") &
sleep 10

# Проверка состояния кластера
for NUM in $(seq $FIRST_POSTGRES 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
#    echo "${VM_NAME} Состояние сервиса Patroni";
#    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'systemctl status patroni';
  echo "${VM_NAME} Список нод в кластере Patroni";
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;


for NUM in $(seq 1 1 $QUANTITY); do
  echo "VM vm-${NAMESPACE}${NUM} : ${ADDR_VM[$NUM]}"
done

echo "ADDR_VM[1]=\$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print \$2}') && ssh  -o StrictHostKeyChecking=no yc-user@\${ADDR_VM[1]}"

echo "$START_DATE - " $(date)