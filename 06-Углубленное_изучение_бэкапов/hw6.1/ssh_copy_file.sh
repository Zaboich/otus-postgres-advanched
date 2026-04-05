#!/usr/bin/env bash
set -euo pipefail

# ================= НАСТРОЙКИ =================
# Укажите внешние IP или FQDN из Яндекс.Облака
VM1="yc-user@$1"
VM2="yc-user@$2"
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

KEY_NAME="id_ed25519_yc_vm1_to_vm2"
SRC_DIR=$3
DST_DIR=$SRC_DIR
# =============================================
echo "Перенос каталога $SRC_DIR с VM1 $1 на VM2 $2"
if [[ ! $(ssh ${SSH_OPTIONS} ${VM1} "[ -f ~/.ssh/${KEY_NAME} ] && echo y ") ]]; then
  echo "Генерация SSH-ключа на VM1..."
  ssh ${SSH_OPTIONS} ${VM1} \
  "mkdir -p ~/.ssh && ssh-keygen -t ed25519 -f ~/.ssh/$KEY_NAME -N '' -C 'yc-vm1-to-vm2-auto'"

  echo "Добавление публичного ключа на VM2 $2"
  PUB_KEY=$(ssh ${SSH_OPTIONS} ${VM1} "cat ~/.ssh/${KEY_NAME}.pub")
  echo "$PUB_KEY" | ssh ${SSH_OPTIONS} ${VM2} \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
fi

# Проверяем наличие rsync (в минимальных образах YC его может не быть)
#ssh ${SSH_OPTIONS} ${VM1} "command -v rsync &>/dev/null || sudo apt update && sudo apt install -y rsync  2>/dev/null "
#ssh ${SSH_OPTIONS} ${VM2} "command -v rsync &>/dev/null || sudo apt update && sudo apt install -y rsync  2>/dev/null "

echo "Копирование $SRC_DIR ..."
# sudo rsync на VM1 позволяет читать директорию с правами 700 postgres:postgres
# --rsync-path='sudo rsync' запускает rsync от root на VM2 для сохранения метаданных
ssh ${SSH_OPTIONS} ${VM1} "sudo rsync -avz --rsync-path='sudo rsync' \
  -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null  -i /home/yc-user/.ssh/$KEY_NAME' \
  ${SRC_DIR} ${VM2}:${DST_DIR}"

# 4. Фиксируем права и владельца на VM2 (на случай, если rsync создал файлы от root)
ssh ${SSH_OPTIONS} ${VM2} "sudo chown -R postgres:postgres $DST_DIR && sudo chmod -R 700 $DST_DIR"

echo "На VM2 $2 директория $DST_DIR:"
ssh ${SSH_OPTIONS} ${VM2} "sudo ls -ld $DST_DIR && sudo ls -l $DST_DIR | head -5"

# Опционально: удалить временный ключ
# ssh ${VM1} "rm -f ~/.ssh/$KEY_NAME ~/.ssh/${KEY_NAME}.pub"
# ssh ${VM2} "sed -i '/yc-vm1-to-vm2-auto/d' ~/.ssh/authorized_keys"