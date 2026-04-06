#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}

# TIMESTAMP точки восстановления. latest - последняя доступная точка WAL файлов
RECOVERY_TIMESTAMP=${1:-latest}

#sudo systemctl stop postgresql && echo "${HOSTNAME} остановлен сервис Postgres"
sudo pg_ctlcluster 18 main stop && echo "${HOSTNAME} остановлен cluster Postgres main"

sudo rm -rf /var/lib/postgresql/18/main/  && echo "${HOSTNAME} удалена директория данных Postgres"


echo "${HOSTNAME} Список резервных копий WAL-G:"
sudo -u postgres /usr/local/bin/wal-g backup-list

echo "${HOSTNAME} WAL-G восстановление из резервной копии LATEST"
sudo -u postgres  /usr/local/bin/wal-g backup-fetch /var/lib/postgresql/18/main LATEST && echo "${HOSTNAME} резевная копиия WAL-G восстановлена в директорию данных"

if [ ! -f /var/lib/postgresql/18/main/recovery.signal ]; then
  sudo -u postgres touch /var/lib/postgresql/18/main/recovery.signal && echo "${HOSTNAME} создан файл recovery.signal";
else
  echo "${HOSTNAME} файл recovery.signal сущесвует";
fi

# recovery_target_timeline = 'latest' timestamp до которого надо восстановиться
# recovery_target_action = 'promote' Действие после восстановления (promote переведет базу в режим read-write)
echo "Устанавливаем время точку восстановления - ${RECOVERY_TIMESTAMP}"
echo "
recovery_target_timeline = ${RECOVERY_TIMESTAMP}
recovery_target_action = promote
" | sudo -u postgres tee -a /var/lib/postgresql/18/main/postgresql.auto.conf


sudo chown -R postgres:postgres /var/lib/postgresql/

echo "${HOSTNAME} Стартуем Postgres"
sudo pg_ctlcluster 18 main start && echo "${HOSTNAME} стартовал сервис Postgres"