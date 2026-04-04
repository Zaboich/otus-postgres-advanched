#!/usr/bin/env bash
set -euo pipefail
export LANGUAGE="C.UTF-8"
export LC_ALL="C.UTF-8"


# ================= НАСТРОЙКИ =================
# Замените на актуальные значения
SERVER1=$1
SERVER2=$2
SSH_USER=yc-user
KEY_NAME="id_ed25519_auto"
DIR_SOURCE="/mnt/backup"
DIR_DEST=${DIR_SOURCE}
# =============================================

echo "Копирование каталога ${DIR_SOURCE} с сервера ${SERVER1} на ${SERVER2}."

echo "Генерация SSH-ключа на ${SERVER1} ... "
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SSH_USER}@${SERVER1} "mkdir -p ~/.ssh && ssh-keygen -t ed25519 -f ~/.ssh/$KEY_NAME -N '' -C 'auto-script-key'"
PUB_KEY=$(ssh ${SSH_USER}@${SERVER1} "cat ~/.ssh/${KEY_NAME}.pub")

if [[ -z "$PUB_KEY" ]]; then
  echo "Не удалось прочитать публичный ключ с Server1."
  exit 1
fi

# Безопасное добавление ключа с правильными правами
echo "$PUB_KEY" | ssh ${SSH_USER}@${SERVER2} "sudo -u postgres
  mkdir -p ~/.ssh
  cat >> ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
"

echo "📦 [3/3] Копирование директории с Server1 на Server2..."
# Используем rsync для надёжного копирования.
# Если rsync не установлен на Server1, замените на: scp -i ~/.ssh/$KEY_NAME -o StrictHostKeyChecking=no -r $DIR_TO_COPY $SERVER2:$DIR_DEST/
ssh ${SSH_USER}@${SERVER1} "sudo rsync -avz \
  -e 'ssh -i /home/yc-user/.ssh/$KEY_NAME -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
  $DIR_SOURCE postgres@${SERVER2}:$DIR_DEST"

echo "✅ Операция завершена успешно."

# Опционально: удалить сгенерированный ключ с Server1 после копирования
# ssh "$SERVER1" "rm -f ~/.ssh/$KEY_NAME ~/.ssh/${KEY_NAME}.pub"