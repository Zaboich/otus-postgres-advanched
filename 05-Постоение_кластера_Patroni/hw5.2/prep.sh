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

PIDS=()
echo "Создаются $QUANTITY VM"
for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  if ! yc compute instance show --name ${VM_NAME} 2>/dev/null; then
    ( yc compute instance create --name ${VM_NAME} --hostname ${VM_NAME} --cores 2 --memory 4 \
    --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
    --network-interface subnet-name=${SUBNET},nat-ip-version=ipv4 --ssh-key $SSH_KEY && echo "Создана ${VM_NAME}" ) &
    PIDS+=($!);
  else
    echo "Работает ${VM_NAME}"
  fi
done

# Ждем завершения всех фоновых процессов удаления
for PID in "${PIDS[@]}"; do
  wait $PID;
done

wait

for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  IP_VM=$(yc compute instance show --name ${VM_NAME} | grep -E ' +address' | tail -n 1 | awk '{print $2}')
  ADDR_VM[$NUM]=${IP_VM}
done
# Массив ip созданных VM
export ADDR_VM
sleep 30
echo "$START_DATE - " $(date)
echo "Созданы все VM"
echo "------------------------------------------------"



# Устанавливаем программы
if [[ "$IS_INSTALL" == "Y" || "$IS_INSTALL" == "y" ]]; then

  # Установка ETCD на машины 1-3
  echo "Установка ETCD на VM 1-3";
  PIDS=()
  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Установка ETCD ";
    # Параллельный запуск установки ETCD на VM-otus 1-3
    ( ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_etcd.sh &&  echo "${VM_NAME} Установлен и подготовлен ETCD. Сервис etcd остановлен"; ) &
    PIDS+=($!);
  done;

  # Ждем завершения всех фоновых процессов
  for PID in "${PIDS[@]}"; do
    wait $PID;
  done

  wait
  sleep 5

  echo "$START_DATE - " $(date)
  echo "Установлены ETCD"
  echo "------------------------------------------------"

  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Запуск ETCD ";
    # Вызывается команда старта сервиса без ожидания результата, чтобы стартовать etcd на всех серверах кластера
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'nohup sudo systemctl start etcd  > /dev/null 2>&1 &';
    echo "${VM_NAME} Запущен ETCD";
  done;
  echo "Ожидаение c для согласования кластера ETCD"
  sleep 5;
  echo "------------------------------------------------"

  # Проверка состояния кластера
  for NUM in $(seq 1 1 $QUANT_ETCD); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Состояние ETCD";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'etcdctl endpoint status --cluster -w table';
  done;

  wait

  echo "$START_DATE - " $(date)
  echo "Запущен кластер ETCD"
  echo "------------------------------------------------"

  # На VM 4-6  Устанавливается Postgresql 18 и Patroni. Оба сервиса настраиваются и останавиливаются
  echo "Установка Postgresql на 3 VM";
  PIDS=()
  for NUM in $(seq $(($FIRST_POSTGRES)) 1 $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    # параллельный запроск установки
    (ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh && echo "${VM_NAME} Установлен и подготовлен Postgres" ) &
    PIDS+=($!);
  done;

  # Ждем завершения всех фоновых процессов
  for PID in "${PIDS[@]}"; do
      wait $PID;
  done

  wait

  echo "Установка Patroni на 3 VM";
  PIDS=()
  for NUM in $(seq $(($FIRST_POSTGRES)) 1 $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"

    echo "${VM_NAME} загрузка шаблона файла конфигурации Patroni";
    scp ./patroni.yml yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.yml

    echo "${VM_NAME} загрузка файла сервиса Patroni";
    scp ./patroni.service yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.service && ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'sudo mv /tmp/patroni.service /etc/systemd/system/patroni.service';
    echo "${VM_NAME} Загружен файл службы patroni.service";

    # параллельный запроск установки
    (ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_patroni.sh && echo "${VM_NAME} Установлен и подготовлен Patroni. Сервис patroni остановлен") &
    PIDS+=($!);

  done;

  # Ждем завершения всех фоновых процессов
  for PID in "${PIDS[@]}"; do
        wait $PID;
      done
  PIDS=()

  # Стартуем Leader Node для кластера Patroni vm 4
  echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Запуск Patroni как Leader node";
  # Каталог данных очищается, класстер инициализирует пустую БД
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$FIRST_POSTGRES]} 'bash -s ' < ./init_patroni_leader.sh;
  sleep 10
  ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
  echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Patroni Leader node запущен";
  echo "------------------------------------------------";

  # Стартуем Patroni на всех репликах vm 5-6
  for NUM in $(seq $(($FIRST_POSTGRES+1)) 1  $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
    echo "${VM_NAME} Запуск Patroni как Replica node";
    (ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./init_patroni_replica.sh && echo "${VM_NAME} Запущен Patroni") &
    PIDS+=($!);
  done;

  for PID in "${PIDS[@]}"; do
        wait $PID;
      done
  PIDS=()

fi

  # Проверка состояния кластера
  for NUM in $(seq $FIRST_POSTGRES 1 $QUANTITY); do
    VM_NAME="vm-${NAMESPACE}${NUM}"
#    echo "${VM_NAME} Состояние сервиса Patroni";
#    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} 'systemctl status patroni';
    echo "${VM_NAME} Список нод в кластере Patroni";
    ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
  done;

  echo "$START_DATE - " $(date)
  echo "Запущен кластер Patroni"
  echo "------------------------------------------------"

  # В Leader cоздаём БД Demo и заполняем данными
  echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Заполняем Leader данными";
  (ssh -o StrictHostKeyChecking=no yc-user@${ADDR_VM[$FIRST_POSTGRES]} 'bash -s ' < ./leader_upload_data.sh && echo "БД на Leader заполнена") &
  sleep 10

  echo "$START_DATE - " $(date)
  echo "Запущена загрузка данных в Leader"
  echo "------------------------------------------------"
  echo "Проверяем состояние класстера"

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