ДОБАВЛЕНИЕ ДИСКА К ВМ:

-- Создаем новый диск для ВМ:
```
yc compute disk-type list

yc compute disk create \
    --name disk-otus1 \
    --type network-hdd \
    --size 5 \
    --description "second disk for otus-vm"

yc compute disk list
yc compute instance list
```

-- Подключим новый диск к нашей ВМ:
```
yc compute instance attach-disk otus-vm \
    --disk-name new-disk \
    --mode rw \
    --auto-delete

yc compute instance list
```

-- Также должен появится новый диск vdb:
```
sudo lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL
```
-- Создадим разделы с помощью fdisk.
```
sudo fdisk /dev/vdb
```

-- В меню программы fdisk: (чтобы получить список доступных команд, нажмите клавишу M)
```
--     Создайте новый раздел — нажмите N.
--     Укажите, что раздел будет основным — нажмите P.
--     Появится предложение выбрать номер раздела. Нажмите Enter, чтобы создать первый раздел.
--     Номера первого и последнего секторов раздела оставьте по умолчанию — два раза нажмите Enter.
--     Убедитесь, что раздел успешно создан. Для этого нажмите клавишу P и выведите список разделов диска.
--     Для сохранения внесенных изменений нажмите клавишу W.
```

-- Отформатируем диск в нужную файловую систему, с помощью утилиты mkfs (файловую систему возьмем EXT4):
```
sudo mkfs.ext4 /dev/vdb1
```

-- Смонтируем раздел диска vdc1 в папку /mnt/vdc1, с помощью утилиты mount:
```
sudo mkdir /mnt/vdb1
sudo mount /dev/vdb1 /mnt/vdb1
```

-- Разрешим запись на диск всем пользователям, с помощью утилиты chmod:
```
sudo chmod a+w /mnt/vdb1
```

-- Посмотрим на процессы PostgreSQL:
```
ps -xf
```

-- Табличное пространство:
```
sudo su postgres
cd /mnt/vdb1
mkdir tmptblspc
```

