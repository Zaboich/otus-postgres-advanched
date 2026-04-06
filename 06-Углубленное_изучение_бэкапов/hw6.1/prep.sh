#!/bin/bash
set -e
START_DATE=$(date)
SSH_KEY=~/.ssh/id_rsa.pub
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
# 3 VM для кластера Patroni+Postgres 3 VM для кластера etcd
export YC_CLI_INITIALIZATION_SILENCE=true
export NAMESPACE='otus'
export QUANTITY=2
QUANT_ETCD=0
export FIRST_POSTGRES=1
export LAST_POSTGRES=2
FIRST_PATRONI=0
LAST_PATRONI=0
FIRST_HAPROXY=0
LAST_HAPROXY=0
export TEST_VM=2
#системы резервного копирования <-> номера vm
BACKUP_PGBASEBACKUP=0
export BACKUP_WALG=1
BACKUP_PROBACKUP=0
export APP_WORKTIME=600
#vm для восстановления БД
export RESTORED_POSTGRES=2
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

#echo "Создаются дополнительные диски для хранения резервных копий"
#for NUM in $(seq ${FIRST_POSTGRES} 1 ${FIRST_POSTGRES}); do
#  VM_NAME="${VMN}${NUM}"
#  if ! yc compute disk get disk-${NUM} 2>/dev/null; then
#    ( yc compute disk create --name disk-${NUM} --type network-hdd --size 5 > /dev/null && echo "Создан disk-${NUM}" ) &
#    PIDS+=($!);
#  else
#    echo "Exists disk-${NUM}"
#  fi
#done
#
#for PID in "${PIDS[@]}"; do
#  wait $PID;
#done


PIDS=()
echo "Создаются $QUANTITY VM"
for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="${VMN}${NUM}"
  if ! yc compute instance show --name ${VM_NAME} 2>/dev/null; then
    ( export YC_CLI_INITIALIZATION_SILENCE=true && yc compute instance create --name ${VM_NAME} --hostname ${VM_NAME} --cores 2 --memory 4 \
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


echo "Созданы все VM и Disk. Ожидание 30 сек"
sleep 20

#echo "Дополнительные диски подлкючаются к VM, которые будут репликами основной БД"
#echo "Для теста устанавливается режим --auto-delete. В работе диск с резервными копиями не должен удаляться при удалении VM"
#for NUM in $(seq ${FIRST_PATRONI} 1 ${LAST_PATRONI}); do
#  VM_NAME="${VMN}${NUM}"
#  ( yc compute instance attach-disk ${VMN}${NUM} --disk-name disk-${NUM} --mode rw --auto-delete && echo "disk-${NUM} attached to ${VMN}${NUM}" ) &
#  PIDS+=($!);
#done
#
#for PID in "${PIDS[@]}"; do
#  wait $PID;
#done


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

echo "Установка Postgresql на VM от $FIRST_POSTGRES до ${LAST_POSTGRES}";
PIDS=()
for NUM in $(seq $(($FIRST_POSTGRES)) 1 ${LAST_POSTGRES}); do
  VM_NAME="${VMN}${NUM}"
  # параллельный запроск установки
  (ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh && echo "${VM_NAME} / ${ADDR_VM[$NUM]} Установлен и подготовлен Postgres" ) &
  PIDS+=($!);
done;

#echo "Установка client psql на дополнительной VM ${VMN}${TEST_VM} ${ADDR_VM[$TEST_VM]}"
#(ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./install_psql-client.sh && echo "${VMN}${TEST_VM} Установлен client psql" ) &

# Ждем завершения всех фоновых процессов
for PID in "${PIDS[@]}"; do
    wait $PID;
done
echo "Установлен Postgresql"
echo "------------------------------------------------"

echo "${VMN}${BACKUP_WALG} Установка и настройка WAL-G"
echo "Монтирование диска для резервных копий"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} 'bash -s ' < ./mount_disk_backup.sh && echo "${VMN}${BACKUP_WALG} / ${ADDR_VM[$BACKUP_WALG]} Монтирован диск для хранения резервных копий"

scp ${SSH_OPTIONS} ./walg.json yc-user@${ADDR_VM[BACKUP_WALG]}:/tmp/walg.json && echo "${VMN}${BACKUP_WALG} загружен файл шаблона конфигурации WAL-G";
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} 'bash -s ' < ./install_walg.sh && echo "${VMN}${BACKUP_WALG} / ${ADDR_VM[$BACKUP_WALG]} Установлен и подготовлен WAL-G и конфигурации бекапирования Postgres"
echo "WAL-G подготовлен на ${VMN}${BACKUP_WALG}"
echo "------------------------------------------------"
echo "${VMN}${TEST_VM} Установка и настройка WAL-G"
echo "Монтирование диска для резервных копий"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./mount_disk_backup.sh && echo "${VMN}${TEST_VM} / ${ADDR_VM[$TEST_VM]} Монтирован диск для хранения резервных копий"

scp ${SSH_OPTIONS} ./walg.json yc-user@${ADDR_VM[TEST_VM]}:/tmp/walg.json && echo "${VMN}${TEST_VM} загружен файл шаблона конфигурации WAL-G";
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./install_walg.sh && echo "${VMN}${TEST_VM} / ${ADDR_VM[$TEST_VM]} Установлен и подготовлен WAL-G и конфигурации бекапирования Postgres"
echo "WAL-G подготовлен на ${VMN}${TEST_VM}"
echo "------------------------------------------------"

echo "${VMN}${BACKUP_WALG} Создание клиентского приложения, которое будет создавать нагрузку на БД"
scp ${SSH_OPTIONS} ./app2.py yc-user@${ADDR_VM[BACKUP_WALG]}:/tmp/app2.py && echo "${VMN}${BACKUP_WALG} загружен файл приложения";
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} 'bash -s ' < ./install_python.sh && echo "${VMN}${BACKUP_WALG} Установлен и подготовлен venv Python для запуска приложения"
echo "------------------------------------------------"
echo "Установлены все необходимые программы. Начинается тестирование"
echo "$START_DATE - $(date)"
echo "------------------------------------------------"

echo "${VMN}${BACKUP_WALG} Создание первой резевной копии WAL-G"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "bash -s " < walg_create_backup.sh
echo "$START_DATE - $(date)"
echo "------------------------------------------------"

echo "Cоздаём БД Demo и заполняем данными"
(ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "bash -s " < ./upload_data.sh > /dev/null && echo "Дамп БД загружен")
sleep 5

echo -e "${VMN}${BACKUP_WALG} Запрашиваются данные из таблицы БД. \nSQL Запрос возвращает количество строк в таблице bookings SELECT count(*) FROM bookings;"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "sudo -u postgres psql -d demo -w -c 'SELECT count(*) FROM bookings;'"
echo "$START_DATE - $(date)"
echo "Закончена подготовка БД."
echo "$START_DATE - $(date)"
echo "------------------------------------------------"

echo "${VMN}${BACKUP_WALG} Создание второй резевной копии WAL-G"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "bash -s " < walg_create_backup.sh
echo "$START_DATE - $(date)"
echo "------------------------------------------------"

echo "Переносим файлы резервной копии на VM ${VMN}${TEST_VM} и проверяем восстановление"
echo "${VMN}${BACKUP_WALG} Копирование каталога backup на тестовый сервер, для развёртывания резервной копии"
./ssh_copy_file.sh ${ADDR_VM[$BACKUP_WALG]} ${ADDR_VM[TEST_VM]} "/mnt/backup/" && echo "${VMN}${BACKUP_WALG} каталог backup скопирован на ${VMN}${TEST_VM}"
echo "$START_DATE - $(date)"
echo "------------------------------------------------"
echo "${VMN}${TEST_VM} Запускаем скрипт восстановления из резервной копиии (до точки LATEST): "
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./walg_restore_backup.sh && echo "${VMN}${TEST_VM} / ${ADDR_VM[$TEST_VM]} Развёрнута резерная копия. Postgres стартовал"
echo "$START_DATE - $(date)"
echo "------------------------------------------------"
sleep 5
echo -e "${VMN}${TEST_VM} Запрашиваются данные из таблицы БД. \nSQL Запрос возвращает количество строк в таблице bookings SELECT count(*) FROM bookings;"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} "export LANGUAGE='C.UTF-8' && export LC_ALL='C.UTF-8' && sudo -u postgres psql -d demo -w -c 'SELECT count(*) FROM bookings;'"

echo "Сравниваем количество строк в таблице bookings на серверах ${VMN}${TEST_VM} и ${VMN}${BACKUP_WALG} (вручную)"
echo "------------------------------------------------"

echo "${VMN}${BACKUP_WALG} Запускаем приложение, которое каждые 0.1 секунду добавляет запись в таблицу booking"
(ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "source /opt/app/bin/activate; python /tmp/app2.py 6000;" && echo "${VMN}${BACKUP_WALG} Приложение-клиент остановлено") &
echo "$(date)"
echo "${VMN}${BACKUP_WALG} Приложение продолжает работать. Ожидаем ${APP_WORKTIME} сек и останавливаем сервис posgres, при этом приложение остановится после ошибки запроса SQL"
sleep ${APP_WORKTIME} && echo "Прошло ${APP_WORKTIME} сек. $(date)"

echo -e "${VMN}${BACKUP_WALG} Перед остановкой Postgres, Запрашиваются количество строк из таблицы bookings"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[BACKUP_WALG]} "export LANGUAGE='C.UTF-8' && export LC_ALL='C.UTF-8' && sudo -u postgres psql -d demo -w -c 'SELECT count(*) FROM bookings;'"
echo "------------------------------------------------"
echo -e "${VMN}${BACKUP_WALG} Останавливается Postgres для имитации аварийной остановки"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "sudo pg_ctlcluster 18 main stop" && echo "${VMN}${BACKUP_WALG} остановлен кластер Postgres main"

echo "------------------------------------------------"
echo "${VMN}${BACKUP_WALG} Повторно копируем каталог backup на тестовый сервер ${VMN}${TEST_VM}"
# Важно полностью восстановить каталог /mnt/backup/ в соответствии с vm1
./ssh_copy_file.sh ${ADDR_VM[$BACKUP_WALG]} ${ADDR_VM[TEST_VM]} "/mnt/backup/" && echo "${VMN}${BACKUP_WALG} каталог backup скопирован на ${VMN}${TEST_VM}"
echo "$START_DATE - $(date)"
echo "------------------------------------------------"

echo "${VMN}${TEST_VM} Запускаем скрипт восстановления из резервной копиии (до точки LATEST) "
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./walg_restore_backup.sh && echo "${VMN}${TEST_VM} / ${ADDR_VM[$TEST_VM]} Развёрнута резерная копия. Postgres стартовал"
sleep 5
echo "------------------------------------------------"
echo -e "${VMN}${TEST_VM} Запрашиваются данные из таблицы БД. \nSQL Запрос возвращает количество строк в таблице bookings SELECT count(*) FROM bookings;"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$TEST_VM]} "export LANGUAGE='C.UTF-8' && export LC_ALL='C.UTF-8' && sudo -u postgres psql -d demo -w -c 'SELECT count(*) FROM bookings;'"

echo "------------------------------------------------"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "sudo pg_ctlcluster 18 main start" && echo "${VMN}${BACKUP_WALG} стартовал кластер Postgres main"
sleep 10
echo "------------------------------------------------"
echo -e "${VMN}${BACKUP_WALG} Запрашиваются данные из таблицы БД. \nSQL Запрос возвращает количество строк в таблице bookings SELECT count(*) FROM bookings;"
ssh ${SSH_OPTIONS} yc-user@${ADDR_VM[$BACKUP_WALG]} "export LANGUAGE='C.UTF-8' && export LC_ALL='C.UTF-8' && sudo -u postgres psql -d demo -w -c 'SELECT count(*) FROM bookings;'"

echo "Сравниваем количество строк в таблице bookings на серверах после второго теста ${VMN}${TEST_VM} и ${VMN}${BACKUP_WALG} (вручную)"

echo "------------------------------------------------"
echo "$START_DATE - $(date)"
#./delete.sh