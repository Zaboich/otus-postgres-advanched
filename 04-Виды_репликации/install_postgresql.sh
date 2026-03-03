#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LC_ALL="ru_RU.UTF-8,"
export LANGUAGE="ru_RU.UTF-8"
export LANG="ru_RU.UTF-8"
export LC_TIME="ru_RU.UTF-8",
export LC_MONETARY="ru_RU.UTF-8",
export LC_ADDRESS="ru_RU.UTF-8",
export LC_TELEPHONE="ru_RU.UTF-8",
export LC_NAME="ru_RU.UTF-8",
export LC_MEASUREMENT="ru_RU.UTF-8",
export LC_IDENTIFICATION="ru_RU.UTF-8",
export LC_NUMERIC="ru_RU.UTF-8",
export LC_PAPER="ru_RU.UTF-8",

sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update -q
sudo apt install -y -q postgresql mc