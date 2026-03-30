#!/bin/bash
set -e
START_DATE=$(date)
SSH_KEY=~/.ssh/id_rsa.pub
# 3 VM для кластера Patroni+Postgres 3 VM для кластера etcd
NAMESPACE='otus'
QUANTITY=6
QUANT_ETCD=3
FIRST_POSTGRES=1
LAST_POSTGRES=4
FIRST_PATRONI=1
LAST_PATRONI=3

FIRST_HAPROXY=5
LAST_HAPROXY=5
TEST_VM=6
#системы резервного копирования <-> номера vm
BACKUP_PGBASEBACKUP=1
BACKUP_WALG=2
BACKUP_PROBACKUP=3
#vm для восстановления БД
RESTORED_POSTGRES=4
# Имена ресурсов
VMN="vm-${NAMESPACE}"
NET="net-${NAMESPACE}"
SUBNET="subnet-${NAMESPACE}"
DNS_ZONE="dns-${NAMESPACE}"

echo "Создание инфраструктуры в Yandex Cloud"
echo "Создаётся network ${NET}"
if ! yc vpc network show --name ${NET} 2>/dev/null; then
  yc vpc network create --name ${NET}  2>/dev/null && echo "Создан network ${NET}"
else
  echo "Работает network ${NET}"
fi
echo "Создаётся subnet ${SUBNET}"
if ! yc vpc subnet show --name ${SUBNET} 2>/dev/null; then
  yc vpc subnet create --name ${SUBNET} --range 192.168.0.0/24 --network-name ${NET}  2>/dev/null > /dev/null && echo "Создана subnet ${SUBNET}"
else
  echo "Работает subnet ${SUBNET}"
fi

echo "Создаётся DNS ZONE ${DNS_ZONE}"
if ! yc dns zone show --name ${DNS_ZONE} 2>/dev/null; then
  NET_ID=$(yc vpc network show --name ${NET} --format=json | jq -r ".id") && \
  yc dns zone create --name dns-otus --zone staging. --private-visibility ${NET_ID}  2>/dev/null && echo "Создана dns ${DNS_ZONE}"
else
  echo "Работает dns ${DNS_ZONE}"
fi

PIDS=()
echo "Создаются $QUANTITY VM"
for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="${VMN}${NUM}"
  if ! yc compute instance show --name ${VM_NAME} 2>/dev/null; then
    ( yc compute instance create --name ${VM_NAME} --hostname ${VM_NAME} --cores 2 --memory 2 --preemptible=true \
    --create-boot-disk size=10G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
    --network-interface subnet-name=${SUBNET},nat-ip-version=ipv4 --ssh-key $SSH_KEY > /dev/null && echo "Создана ${VM_NAME}" ) &
    PIDS+=($!);
  else
    echo "Работает ${VM_NAME}"
  fi
done

for PID in "${PIDS[@]}"; do
  wait $PID;
done

echo "Создаются дополнительные диски для хранения резервных копий"
for NUM in $(seq ${FIRST_PATRONI} 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"
  if ! yc compute disk get disk-${NUM} 2>/dev/null; then
    ( yc compute disk create --name disk-${NUM} --type network-hdd --size 5 > /dev/null && echo "Создан disk-${NUM}" ) &
    PIDS+=($!);
  else
    echo "Exists disk-${NUM}"
  fi
done

for PID in "${PIDS[@]}"; do
  wait $PID;
done
echo "Созданы все VM и Disk. Ожидание 30 сек"
sleep 30

echo "Дополнительные диски подлкючаются к VM, которые будут репликами основной БД"
echo "Для теста устанавливается режим --auto-delete. В работе диск с резервными копиями не должен удаляться при удалении VM"
for NUM in $(seq ${FIRST_PATRONI} 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"
  ( yc compute instance attach-disk vm-otus${NUM} --disk-name disk-${NUM} --mode rw --auto-delete && echo "disk-${NUM} attached to ${VMN}${NUM}" ) &
  PIDS+=($!);
done

for PID in "${PIDS[@]}"; do
  wait $PID;
done


echo "Список созданных VM"
for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="${VMN}${NUM}"
  ADDR_VM[$NUM]=$(yc compute instance show --name ${VM_NAME} | grep -E ' +address' | tail -n 1 | awk '{print $2}')
  echo "${VM_NAME} : ${ADDR_VM[$NUM]}"
done
# Массив ip созданных VM
export ADDR_VM

echo "$START_DATE - $(date)"
echo "------------------------------------------------"
echo "Инфраструктура подготовлена"
echo "Устанавливаем программы"

# Установка ETCD на машины 1-3
echo "Установка ETCD на VM 1-3";
PIDS=()
for NUM in $(seq ${FIRST_PATRONI} 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"
  echo "${VM_NAME} / ${ADDR_VM[$NUM]} Установка ETCD ";
  # Параллельный запуск установки ETCD на VM-otus 1-3
  ( ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_etcd.sh &&  echo "${VM_NAME} Установлен и подготовлен ETCD. Сервис etcd остановлен"; ) &
  PIDS+=($!);
done;

# Ждем завершения всех фоновых процессов
for PID in "${PIDS[@]}"; do
  wait $PID;
done

#wait
sleep 5

echo "$START_DATE - $(date)"
echo "Подготовлены ноды ETCD"
echo "Запуск ETCD на всех нодах";
for NUM in $(seq ${FIRST_PATRONI} 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"
  # Вызывается команда старта сервиса без ожидания результата, чтобы стартовать etcd на всех серверах кластера
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'nohup sudo systemctl start etcd  > /dev/null 2>&1 &';
  echo "${VMN}${NUM} / ${ADDR_VM[$NUM]} Запущен ETCD";
done;
echo "------------------------------------------------"

echo "Установка Postgresql на VM";
PIDS=()
for NUM in $(seq $(($FIRST_POSTGRES)) 1 ${LAST_POSTGRES}); do
  VM_NAME="${VMN}${NUM}"
  # параллельный запроск установки
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh && echo "${VM_NAME} / ${ADDR_VM[$NUM]} Установлен и подготовлен Postgres" ) &
  PIDS+=($!);
done;

echo "Установка client psql на дополнительной VM ${VMN}${TEST_VM} ${ADDR_VM[$TEST_VM]}"
(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./install_psql-client.sh && echo "${VMN}${TEST_VM} Установлен client psql" ) &

# Ждем завершения всех фоновых процессов
for PID in "${PIDS[@]}"; do
    wait $PID;
done
echo "Установлен Postgresql"
echo "------------------------------------------------"

echo "Установка и настройка WAL-G на реплику Postgres  vm-otus${BACKUP_WALG}"
echo "Монтирование диска для резервных копий"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$BACKUP_WALG]} 'bash -s ' < ./mount_disk_backup.sh && echo "vm-otus${BACKUP_WALG} / ${ADDR_VM[$BACKUP_WALG]} Монтирован диск для хранения резервных копий"

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./walg.json yc-user@${ADDR_VM[BACKUP_WALG]}:/tmp/walg.json && echo "${VMN}${BACKUP_WALG} загружен файл шаблона конфигурации WAL-G";
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$BACKUP_WALG]} 'bash -s ' < ./install_walg.sh && echo "vm-otus${BACKUP_WALG} / ${ADDR_VM[$BACKUP_WALG]} Установлен и подготовлен WAL-G и конфигурации бекапирования Postgres"

echo "------------------------------------------------"
echo "Установка Patroni на 3 VM";
PIDS=()
for NUM in $(seq $(($FIRST_PATRONI)) 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"

  echo "${VM_NAME} загрузка шаблона файла конфигурации Patroni";
   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./patroni.yml yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.yml

  echo "${VM_NAME} загрузка файла сервиса Patroni";
   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./patroni.service yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.service && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'sudo mv /tmp/patroni.service /etc/systemd/system/patroni.service';
  echo "${VM_NAME} Загружен файл службы patroni.service";

  # параллельный запрос установки
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_patroni.sh && echo "${VM_NAME} Установлен и подготовлен Patroni. Сервис patroni остановлен") &
  PIDS+=($!);

done;

# Ждем завершения всех фоновых процессов
for PID in "${PIDS[@]}"; do
      wait $PID;
    done
PIDS=()

echo "Установлен Patroni"
echo "------------------------------------------------"

# Стартуем Leader Node для кластера Patroni vm 4
echo ""${VMN}${FIRST_PATRONI}" Запуск Patroni как Leader node";
# Каталог данных очищается, класстер инициализирует пустую БД
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$FIRST_PATRONI]} 'bash -s ' < ./init_patroni_leader.sh;
sleep 10
echo ""${VMN}${FIRST_PATRONI}" Patroni Leader node запущен";
echo "Стартуем Patroni на всех репликах vm 5, 6"
for NUM in $(seq $(($FIRST_PATRONI+1)) 1 ${LAST_PATRONI}); do
  VM_NAME="${VMN}${NUM}"
  echo "${VM_NAME} Запуск Patroni как Replica node";
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./init_patroni_replica.sh && echo "${VM_NAME} Запущен Patroni") &
  PIDS+=($!);
done;

for PID in "${PIDS[@]}"; do
  wait $PID;
done
PIDS=()
sleep 5
echo "Проверка состояния кластера"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$FIRST_PATRONI]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';

echo "$START_DATE - $(date)"
echo "Запущен кластер Patroni"
echo "------------------------------------------------"

echo "Подготовка балансировщика Haproxy ${VMN}${FIRST_HAPROXY}"
echo "Внешний адрес сервера Haproxy ${ADDR_VM[$FIRST_HAPROXY]}"
for NUM in $(seq ${FIRST_HAPROXY} 1 ${LAST_HAPROXY}); do
  VM_NAME="${VMN}${NUM}"
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./haproxy.cfg yc-user@${ADDR_VM[$NUM]}:/tmp/haproxy.cfg
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} \
  "export FIRST_PATRONI=${ADDR_VM[$FIRST_PATRONI]}; export LAST_PATRONI=${ADDR_VM[$LAST_PATRONI]}; bash -s " < ./install_haproxy.sh \
  && echo "${VM_NAME} Haproxy запущен"
done;
echo "$START_DATE - $(date)"
echo "------------------------------------------------"


echo "Cоздаём БД Demo и заполняем данными"
echo "С тестовой ${VMN}${TEST_VM} загружаем дамп, подключение к БД производися через сервер Haproxy";
(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} "export IP_HAPROXY=${ADDR_VM[$FIRST_HAPROXY]}; bash -s " < ./upload_data.sh > /dev/null && echo "Дамп БД загружен")
sleep 5

echo -e "Запрашиваются данные из таблицы БД, запрос выполнятся с тестовой ${VMN}${TEST_VM} ${ADDR_VM[$TEST_VM]} через внешний IP Haproxy. \nSQL Запрос SELECT * FROM airplanes_data;"
# Haproxy проксирует запрос Лидеру кластера (primary node)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} "psql -h ${ADDR_VM[$FIRST_HAPROXY]} -U postgres -d demo -w -c 'SELECT * FROM airplanes_data;'"
echo "$START_DATE - $(date)"
echo "Закончена подготовка БД."
echo "------------------------------------------------"

echo "vm-otus${BACKUP_WALG} Создание первой резевной копии WAL-G"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$BACKUP_WALG]} "sudo -u postgres /usr/local/bin/wal-g backup-push /var/lib/postgresql/18/main" && echo echo "vm-otus${BACKUP_WALG} резевноая копиия WAL-G подготовлена"

echo "vm-otus${BACKUP_WALG} Проверка списка резевных копии WAL-G"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$BACKUP_WALG]} "sudo -u postgres /usr/local/bin/wal-g backup-list"


echo "$START_DATE - $(date)"