#!/bin/bash
set -e
START_DATE=$(date)
SSH_KEY=~/.ssh/id_rsa.pub
# 3 VM для кластера Patroni+Postgres 3 VM для кластера etcd
NAMESPACE='otus'
QUANTITY=8
QUANT_ETCD=3 #$(($QUANTITY/2))
FIRST_POSTGRES=4 #$((QUANT_ETCD+1))
LAST_POSTGRES=6
FIRST_HAPROXY=7 #$((FIRST_POSTGRES+QUANT_ETCD))
LAST_HAPROXY=7
TEST_VM=8
NET="net-${NAMESPACE}"
SUBNET="subnet-${NAMESPACE}"
DNS_ZONE="dns-${NAMESPACE}"

echo "Создание инфраструктуры в Yandex Cloud"
echo "Создаётся network ${NET}"
if ! yc vpc network show --name ${NET} 2>/dev/null; then
  yc vpc network create --name ${NET} && \
  echo "Создан network ${NET}"
else
  echo "Работает network ${NET}"
fi
echo "Создаётся subnet ${SUBNET}"
if ! yc vpc subnet show --name ${SUBNET} 2>/dev/null; then
  yc vpc subnet create --name ${SUBNET} --range 192.168.0.0/24 --network-name ${NET} > /dev/null && \
  echo "Создана subnet ${SUBNET}"
else
  echo "Работает subnet ${SUBNET}"
fi

echo "Создаётся DNS ZONE ${DNS_ZONE}"
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
    --network-interface subnet-name=${SUBNET},nat-ip-version=ipv4 --ssh-key $SSH_KEY > /dev/null && echo "Создана ${VM_NAME}" ) &
    PIDS+=($!);
  else
    echo "Работает ${VM_NAME}"
  fi
done

for PID in "${PIDS[@]}"; do
  wait $PID;
done

#wait

for NUM in $(seq 1 1 $QUANTITY); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  ADDR_VM[$NUM]=$(yc compute instance show --name ${VM_NAME} | grep -E ' +address' | tail -n 1 | awk '{print $2}')
  echo "${VM_NAME} : ${ADDR_VM[$NUM]}"
done
# Массив ip созданных VM
export ADDR_VM
echo "Созданы все VM. Ожидание 30 сек"
sleep 30
echo "$START_DATE - $(date)"
echo "------------------------------------------------"
echo "Инфраструктура подготовлена"
echo "Устанавливаем программы"

# Установка ETCD на машины 1-3
echo "Установка ETCD на VM 1-3";
PIDS=()
for NUM in $(seq 1 1 $QUANT_ETCD); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
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
echo "------------------------------------------------"
echo "Запуск ETCD на всех нодах";
for NUM in $(seq 1 1 $QUANT_ETCD); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  # Вызывается команда старта сервиса без ожидания результата, чтобы стартовать etcd на всех серверах кластера
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'nohup sudo systemctl start etcd  > /dev/null 2>&1 &';
  echo "${VM_NAME} / ${ADDR_VM[$NUM]} Запущен ETCD";
done;
echo "Ожидание 20c для согласования кластера ETCD"
sleep 20;
echo "------------------------------------------------"

# Проверка состояния кластера
for NUM in $(seq 1 1 $QUANT_ETCD); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} / ${ADDR_VM[$NUM]} Состояние ETCD";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'etcdctl endpoint status --cluster -w table';
done;

#wait

echo "$START_DATE - $(date)"
echo "Запущен кластер ETCD"
echo "------------------------------------------------"

# На VM 4-6  Устанавливается Postgresql 18 и Patroni. Оба сервиса настраиваются и останавиливаются
echo "Установка Postgresql на 3 VM";
PIDS=()
for NUM in $(seq $(($FIRST_POSTGRES)) 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  # параллельный запроск установки
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_postgresql.sh && echo "${VM_NAME} / ${ADDR_VM[$NUM]} Установлен и подготовлен Postgres" ) &
  PIDS+=($!);
done;

echo "Установка client psql на дополнительной VM vm-${NAMESPACE}${TEST_VM} ${ADDR_VM[$TEST_VM]}"
(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./install_psql-client.sh && echo "vm-${NAMESPACE}${TEST_VM} Установлен client psql" ) &

# Ждем завершения всех фоновых процессов
for PID in "${PIDS[@]}"; do
    wait $PID;
done

echo "Установлен Postgresql"
echo "------------------------------------------------"

echo "Установка Patroni на 3 VM";
PIDS=()
for NUM in $(seq $(($FIRST_POSTGRES)) 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"

  echo "${VM_NAME} загрузка шаблона файла конфигурации Patroni";
   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./patroni.yml yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.yml

  echo "${VM_NAME} загрузка файла сервиса Patroni";
   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./patroni.service yc-user@${ADDR_VM[$NUM]}:/tmp/patroni.service && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'sudo mv /tmp/patroni.service /etc/systemd/system/patroni.service';
  echo "${VM_NAME} Загружен файл службы patroni.service";

  # параллельный запроск установки
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
echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Запуск Patroni как Leader node";
# Каталог данных очищается, класстер инициализирует пустую БД
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$FIRST_POSTGRES]} 'bash -s ' < ./init_patroni_leader.sh;

echo "Ожидание 10 сек на инициализацию кластера Patroni"
sleep 10

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
echo ""vm-${NAMESPACE}${FIRST_POSTGRES}" Patroni Leader node запущен";
echo "------------------------------------------------";

echo "Стартуем Patroni на всех репликах vm 5, 6"
for NUM in $(seq $(($FIRST_POSTGRES+1)) 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} Запуск Patroni как Replica node";
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./init_patroni_replica.sh && echo "${VM_NAME} Запущен Patroni") &
  PIDS+=($!);
done;

for PID in "${PIDS[@]}"; do
  wait $PID;
done
PIDS=()

echo "Запущен Patroni на всех машинах кластера"
echo "------------------------------------------------"


echo "Проверка состояния кластера"
for NUM in $(seq ${FIRST_POSTGRES} 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} Список нод в кластере Patroni";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} \
  '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;

echo "$START_DATE - $(date)"
echo "Запущен кластер Patroni"
echo "------------------------------------------------"

echo "Подготовка балансировщика Haproxy"
echo "Внешний адрес сервера Haproxy ${ADDR_VM[$FIRST_HAPROXY]}"
for NUM in $(seq ${FIRST_HAPROXY} 1 ${LAST_HAPROXY}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
   scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ./haproxy.cfg yc-user@${ADDR_VM[$NUM]}:/tmp/haproxy.cfg
  echo "${VM_NAME} Установка Haproxy";
  (ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} 'bash -s ' < ./install_haproxy.sh \
  && echo "${VM_NAME} Haproxy запущен")
done;

echo "------------------------------------------------"
echo "В Leader cоздаём БД Demo и заполняем данными"
echo "С тестовой vm-${NAMESPACE}${TEST_VM} загружаем дамп, подключение к БД производися через сервер Haproxy";
(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} 'bash -s ' < ./upload_data.sh > /dev/null && echo "Дамп БД загружен")
sleep 5
echo "$START_DATE - $(date)"


echo "Проверка состояния кластера после загрузки дампа"
for NUM in $(seq ${FIRST_POSTGRES} 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} кластер:";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;
echo "------------------------------------------------"
echo "Этап проверки доступности БД с тестовой VM"
echo -e "Запрашиваются данные из таблицы БД, запрос выполнятся с тестовой vm-${NAMESPACE}${TEST_VM} ${ADDR_VM[$TEST_VM]} через внешний IP Haproxy. \nSQL Запрос SELECT * FROM airplanes_data;"
# Haproxy проксирует запрос Лидеру кластера (primary node)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} "psql -h ${ADDR_VM[$FIRST_HAPROXY]} -U postgres -d demo -w -c 'SELECT * FROM airplanes_data;'"
echo "------------------------------------------------"

echo "Определяем Patroni cluster Leader http запросом к vm-${NAMESPACE}$FIRST_POSTGRES  http://${ADDR_VM[$FIRST_POSTGRES]}:8008/patroni"
NUM_LEADER_FIRST=$(curl -v http://${ADDR_VM[$FIRST_POSTGRES]}:8008/cluster | jq -r '.members[] | select(.role == "leader") | .name' | tail -c 2)

echo "Patroni cluster Leader - vm-${NAMESPACE}$NUM_LEADER_FIRST ${ADDR_VM[$NUM_LEADER_FIRST]}"
echo "Принудительная остановка Patroni Leader node"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM_LEADER_FIRST]} 'sudo systemctl stop patroni' \
&& echo "Остановлен сервис Patroni на vm Leader "
echo "------------------------------------------------"
echo "Ожидание 5 сек для перестроения кластера."
sleep 5
echo "------------------------------------------------"

echo "Проверка состояния кластера после остановки лидера"
for NUM in $(seq ${FIRST_POSTGRES} 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} кластер:";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;
echo "------------------------------------------------"

echo "Определяем Новый Patroni cluster Leader http запросом к работающей vm-${NAMESPACE}$LAST_POSTGRES  http://${ADDR_VM[$LAST_POSTGRES]}:8008/patroni"
NUM_LEADER_SECOND=$(curl -v http://${ADDR_VM[$LAST_POSTGRES]}:8008/cluster | jq -r '.members[] | select(.role == "leader") | .name' | tail -c 2)
echo "Новый Patroni cluster Leader - vm-${NAMESPACE}$NUM_LEADER_SECOND ${ADDR_VM[$NUM_LEADER_SECOND]}"

if [[ -z "$NUM_LEADER_SECOND" ]]; then echo "Не удалось определить нового лидера кластера."; exit 1; fi

echo "------------------------------------------------"

echo "Ожидание 30 сек для обновления данных о лидере кластера в Haproxy."
sleep 30

echo -e "Повторно запрашиваются данные из таблицы БД, через внешний IP Haproxy,\n запрос выполнятся с тестовой vm-${NAMESPACE}${TEST_VM} ${ADDR_VM[$TEST_VM]} через внешний IP Haproxy. \nSQL Запрос SELECT * FROM airplanes_data;"
# Haproxy проксирует запрос новому Лидеру кластера (primary node). Возможна ситуация, что кластер не успеет перестроится или Haproxy не опредит нового лидера
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} "psql -h ${ADDR_VM[$FIRST_HAPROXY]} -U postgres -d demo -w -c 'SELECT * FROM airplanes_data;'"

echo "Запуск Patroni на vm-${NAMESPACE}$NUM_LEADER_FIRST / ${ADDR_VM[$NUM_LEADER_FIRST]}"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM_LEADER_FIRST]} 'sudo systemctl start patroni' \
&& echo "Запущен сервис Patroni на vm-${NAMESPACE}$NUM_LEADER_FIRST / ${ADDR_VM[$NUM_LEADER_FIRST]}"

echo "------------------------------------------------"

echo "Проверка состояния кластера после запуска vm-${NAMESPACE}$NUM_LEADER_FIRST"
for NUM in $(seq ${FIRST_POSTGRES} 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} кластер:";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;


echo "Switchover Переключение кластера на работу с первоначальным Leader"
#echo "(Имена нод в кластере Patroni соответсвуют hostname VM)"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$FIRST_POSTGRES]} \
"/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml switchover --leader vm-$NAMESPACE$NUM_LEADER_SECOND --candidate vm-$NAMESPACE$NUM_LEADER_FIRST --force";

sleep 5
echo "------------------------------------------------"

echo -e "Проверяем Patroni cluster Leader после switchover \n http запросом к vm-${NAMESPACE}$LAST_POSTGRES  http://${ADDR_VM[$LAST_POSTGRES]}:8008/patroni"
NUM_LEADER_THIRD=$(curl -v http://${ADDR_VM[$LAST_POSTGRES]}:8008/cluster | jq -r '.members[] | select(.role == "leader") | .name' | tail -c 2)
echo "Новый Patroni cluster Leader - vm-${NAMESPACE}$NUM_LEADER_SECOND ${ADDR_VM[$NUM_LEADER_SECOND]}"

if [[ -z "$NUM_LEADER_THIRD" ]]; then echo "Не удалось определить нового лидера кластера."; exit 1; fi

echo "------------------------------------------------"

echo "Проверка состояния кластера после switchover vm-${NAMESPACE}$NUM_LEADER_FIRST"
for NUM in $(seq ${FIRST_POSTGRES} 1 ${LAST_POSTGRES}); do
  VM_NAME="vm-${NAMESPACE}${NUM}"
  echo "${VM_NAME} кластер:";
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$NUM]} '/opt/patroni/bin/patronictl -c /etc/patroni/patroni.yml list';
done;

echo "------------------------------------------------"

echo "Ожидание 30 сек для обновления данных о лидере кластера в Haproxy после switchover"
sleep 30

echo -e "После switchover запрашиваются данные из таблицы БД, через внешний IP Haproxy,\n запрос выполнятся с тестовой vm-${NAMESPACE}${TEST_VM} ${ADDR_VM[$TEST_VM]} через внешний IP Haproxy. \nSQL Запрос SELECT * FROM airplanes_data;"
# Haproxy проксирует запрос новому Лидеру кластера (primary node). Возможна ситуация, что кластер не успеет перестроится или Haproxy не опредит нового лидера
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@${ADDR_VM[$TEST_VM]} "psql -h ${ADDR_VM[$FIRST_HAPROXY]} -U postgres -d demo -w -c 'SELECT * FROM airplanes_data;'"


for NUM in $(seq 1 1 $QUANTITY); do
  echo "VM vm-${NAMESPACE}${NUM} : ${ADDR_VM[$NUM]}"
done

echo "ADDR_VM[1]=\$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print \$2}') && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null yc-user@\${ADDR_VM[1]}"

echo "$START_DATE - $(date)"