#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"

# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}

echo "${HOSTNAME} запуск создания резервной копии WAL-G"
sudo -u postgres /usr/local/bin/wal-g backup-push /var/lib/postgresql/18/main && echo "${HOSTNAME} резевная копиия WAL-G создана."

echo "${HOSTNAME} Список резервных копий WAL-G:"
sudo -u postgres /usr/local/bin/wal-g backup-list