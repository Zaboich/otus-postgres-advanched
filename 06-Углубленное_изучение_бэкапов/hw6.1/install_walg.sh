#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
# общая часть имён хостов
HOSTNAME=$(hostname)
NUM=${HOSTNAME: -1}

echo "Создается каталог для хранения резервных копий. Owner - postgres"
sudo mkdir -p /mnt/backup && sudo chown -R postgres:postgres /mnt/backup

echo "Загрузка Wal-G"
curl -L https://github.com/wal-g/wal-g/releases/download/v3.0.8/wal-g-pg-24.04-amd64 -o wal-g

sudo mv wal-g /usr/local/bin/
sudo chmod ugo+x /usr/local/bin/wal-g
sudo wal-g --version

echo "wal-g установлен"

if [ ! -f /tmp/walg.json ]; then
  echo "Файл конфигурации /tmp/walg.json не найден. Выход";
  exit 1;
fi
echo "Файл конфигурации Wal-G переносится в HOMEDIR пользователя postgres"
sudo mv /tmp/walg.json /var/lib/postgresql/.walg.json
sudo chown postgres:postgres /var/lib/postgresql/.walg.json
sudo chmod 600 /var/lib/postgresql/.walg.json

echo "Добавление параметров конфигурации для резервного копирования в postgres "
echo "wal_level=replica" | sudo -u postgres tee -a /etc/postgresql/18/main/conf.d/wal-g.conf
echo "archive_mode=on"   | sudo -u postgres tee -a /etc/postgresql/18/main/conf.d/wal-g.conf
echo "archive_timeout=60"| sudo -u postgres tee -a /etc/postgresql/18/main/conf.d/wal-g.conf
echo "archive_command = '/usr/local/bin/wal-g wal-push %p'"| sudo -u postgres tee -a /etc/postgresql/18/main/conf.d/wal-g.conf
echo "restore_command = '/usr/local/bin/wal-g wal-fetch %f %p'"| sudo -u postgres tee -a /etc/postgresql/18/main/conf.d/wal-g.conf

sudo systemctl restart postgresql

