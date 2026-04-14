#!/bin/bash
apt update
#apt upgrade -y
apt install -y lsb_release wget gpg
mkdir -p 755 /etc/apt/keyrings

sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
#wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/your-repo-key.gpg
apt update
apt -y install postgresql
apt install unzip && apt -y install mc

bash