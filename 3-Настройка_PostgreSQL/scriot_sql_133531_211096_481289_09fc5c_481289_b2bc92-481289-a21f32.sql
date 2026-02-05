-- Создаем сетевую инфраструктуру для VM:
yc vpc network create --name otus-net --description "otus-net" && \
yc vpc subnet create --name otus-subnet --range 192.168.0.0/24 --network-name otus-net --description "otus-subnet" && \
yc compute instance create --name otus-vm --hostname otus-vm --cores 2 --memory 4 --create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2004-lts --network-interface subnet-name=otus-subnet,nat-ip-version=ipv4 --ssh-key ~/.ssh/yc_key.pub 

yc compute instances list

vm_ip_address=$(yc compute instance show --name otus-vm | grep -E ' +address' | tail -n 1 | awk '{print $2}') && ssh -o StrictHostKeyChecking=no -i ~/.ssh/yc_key yc-user@$vm_ip_address 

ssh -o StrictHostKeyChecking=no -i ~/.ssh/yc_key yc-user@$vm_ip_address

sudo apt update && sudo apt upgrade -y -q && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && sudo apt-get update && sudo apt -y install postgresql-14 

pg_lsclusters

sudo nano /etc/postgresql/14/main/postgresql.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf

sudo -u postgres psql
alter user postgres password 'postgres';

sudo pg_ctlcluster 14 main restart


--Посмотрим расположение конфиг файла через psql и idle
show config_file;


--Так же посмоттреть через функцию:
select current_setting('config_file');


--Далее смотрим структуру файла postgresql.conf (комменты, единицы измерения и т.д)
nano postgresql.conf

--смотрим системное представление 
select * from pg_settings;


--Далее рассмторим параметры которые требуют рестарт сервера

select * from pg_settings where context = 'postmaster';

--И изменим параметры max_connections через конфиг файл и проверим;

select * from pg_settings where name='max_connections';

--Смотрим pending_restart

select pg_reload_conf();

alter system set max_connections = '300';


--Смотрим по параметрам вьюху
select count(*) from pg_settings;
select unit, count(*) from pg_settings group by unit order by 2 desc;
select category, count(*) from pg_settings group by category order by 2 desc;
select context, count(*) from pg_settings group by context order by 2 desc;
select source, count(*) from pg_settings group by source order by 2 desc;

select * from pg_settings where source = 'override';


--Переходим ко вью pg_file_settings;
select count(*) from pg_file_settings;
select sourcefile, count(*) from pg_file_settings group by sourcefile;

select * from pg_file_settings;

--Далее пробуем преминить параметр с ошибкой, смотри что их этого получается
select * from pg_file_settings where name='work_mem';

-- sudo journalctl -u postgresql@14-main.service

--Смотрим проблему с единицами измерения

select setting || ' x ' || coalesce(unit, 'units')
from pg_settings
where name = 'work_mem';

select setting || ' x ' || coalesce(unit, 'units')
from pg_settings
where name = 'max_connections';


--Далее говорим о том как задать параметр с помощью alter system

alter system set work_mem = '4mB';
select * from pg_file_settings where name='max_connections';

alter system set max_connections = '300';

--Сбросить параметр
alter system reset max_connections;
alter system reset work_mem;


--Далее говорим про set config в рамках транзакции

--Установка параметров во время исполнения
--Для изменения параметров во время сеанса можно использовать команду SET:

set work_mem to '24mb';
--Или функцию set_config:
select set_config('work_mem', '32mb', false);


--Третий параметр функции говорит о том, нужно ли устанавливать значение только для текущей транзакции (true)
--или до конца работы сеанса (false). Это важно при работе приложения через пул соединений, когда в одном сеансе
--могут выполняться транзакции разных пользователей.


--И для конкретных пользователей и бд
create database test;
alter database test set work_mem='8 MB';

create user test with login password 'test';
alter user test set work_mem='16 MB';

select coalesce(role.rolname, 'database wide') as role,
       coalesce(db.datname, 'cluster wide') as database,
       setconfig as what_changed
from pg_db_role_setting role_setting
left join pg_roles role on role.oid = role_setting.setrole
left join pg_database db on db.oid = role_setting.setdatabase;


--Так же можно добавить свой параметр:


--Далее превреям работу pgbench. Инициализируем необходимые нам таблицы в бд

-- sudo su postgres
-- инициализация pgbench -i postgres
-- запуск бенчмарка pgbench -c 50 -j 2 -P 10 -T 60 postgres

/*
-c Клиенты. Число имитируемых клиентов, то есть число одновременных сеансов базы данных. Значение по умолчанию — 1.
-j Потоки. Число рабочих потоков в pgbench. Использовать нескольких потоков может быть полезно на многопроцессорных компьютерах. Клиенты распределяются по доступным потокам равномерно, насколько это возможно. Значение по умолчанию — 1.
-P Сек. Выводить отчёт о прогрессе через заданное число секунд (сек). Выдаваемый отчёт включает время, прошедшее с момента запуска, скорость (в TPS) с момента предыдущего отчёта, а также среднее время ожидания транзакций и стандартное отклонение. В режиме ограничения скорости (-R) время ожидания вычисляется относительно назначенного времени запуска транзакции, а не фактического времени её начала, так что оно включает и среднее время отставания от графика.
-T Cекунды. Выполнять тест с ограничением по времени (в секундах), а не по числу транзакций для каждого клиента. Параметры -t и -T являются взаимоисключающими.
*/


--Далее генерируем необходимые параметры в pgtune
--И вставляем их в папку conf.d заранее прописав ее в параметры

--CONFIG FILE INCLUDES (postgresql.conf)
--include_dir = 'conf.d'

-- cd /etc/postgresql/14/main/conf.d
-- nano pgtune.conf
select * from pg_file_settings where name='work_mem';

--1. Transaction type: <builtin: TPC-B (sort of)>
--   - Этот параметр указывает на тип транзакций, которые выполнялись во время тестирования. В данном случае, используется встроенный тип транзакций, который напоминает TPC-B (Transaction Processing Performance Council Benchmark B). TPC-B - это стандартный бенчмарк для тестирования производительности систем управления базами данных.
--
--2. Scaling factor: 1
--   - Этот параметр указывает на масштаб фактора базы данных, на которой выполнялся тест. Значение 1 означает, что размер базы данных соответствует масштабному фактору 1.
--
--3. Query mode: simple
--   - Этот параметр указывает на режим выполнения запросов. В данном случае, используется простой режим выполнения запросов.
--
--4. Number of clients: 50
--   - Этот параметр указывает на количество одновременных клиентских соединений, которые использовались во время тестирования.
--
--5. Number of threads: 2
--   - Этот параметр указывает на количество потоков, которые использовались для выполнения теста.
--
--6. Duration: 60 s
--   - Этот параметр указывает на продолжительность тестирования в секундах.
--
--7. Number of transactions actually processed: 15582
--   - Этот параметр указывает на общее количество транзакций, которые были фактически обработаны во время тестирования.
--
--8. Latency average = 68.898 ms
--   - Этот параметр указывает на среднее время ожидания выполнения запроса в миллисекундах.
--
--9. Latency stddev = 84.853 ms
--   - Этот параметр указывает на стандартное отклонение времени ожидания выполнения запроса в миллисекундах.
--
--10. Initial connection time = 54.246 ms
--   - Этот параметр указывает на среднее время установления начального соединения с базой данных в миллисекундах.
--
--11. TPS = 259.338590 (without initial connection time)
--   - Этот параметр указывает на количество транзакций в секунду (Transactions Per Second), которое было обработано во время тестирования, за исключением времени установления начального соединения.
--
--Эти параметры предоставляют информацию о производительности базы данных PostgreSQL во время выполнения теста pgbench.

--transaction type: <builtin: TPC-B (sort of)>
--scaling factor: 1
--query mode: simple
--number of clients: 50
--number of threads: 2
--duration: 60 s
--number of transactions actually processed: 25460
--latency average = 117.817 ms
--latency stddev = 155.701 ms
--initial connection time = 83.676 ms
--tps = 423.657804 (without initial connection time)

--transaction type: <builtin: TPC-B (sort of)>
--scaling factor: 1
--query mode: simple
--number of clients: 50
--number of threads: 2
--duration: 60 s
--number of transactions actually processed: 24757
--latency average = 121.176 ms
--latency stddev = 156.666 ms
--initial connection time = 86.111 ms
--tps = 411.643884 (without initial connection time)

-- Удаляем вм, сети и переменную:
yc compute instance delete otus-vm && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net && unset vm_ip_address


-- ДОБАВЛЕНИЕ ДИСКА К ВМ:

-- Создаем новый диск для ВМ:
yc compute disk-type list

yc compute disk create \
    --name new-disk \
    --type network-hdd \
    --size 5 \
    --description "second disk for otus-vm"

yc compute disk list
yc compute instance list

-- Подключим новый диск к нашей ВМ:
yc compute instance attach-disk otus-vm \
    --disk-name new-disk \
    --mode rw \
    --auto-delete

yc compute instance list

-- Также должен появится новый диск vdb:
sudo lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT,LABEL

-- Создадим разделы с помощью fdisk.
sudo fdisk /dev/vdb

-- В меню программы fdisk: (чтобы получить список доступных команд, нажмите клавишу M)
--     Создайте новый раздел — нажмите N.
--     Укажите, что раздел будет основным — нажмите P.
--     Появится предложение выбрать номер раздела. Нажмите Enter, чтобы создать первый раздел.
--     Номера первого и последнего секторов раздела оставьте по умолчанию — два раза нажмите Enter.
--     Убедитесь, что раздел успешно создан. Для этого нажмите клавишу P и выведите список разделов диска.
--     Для сохранения внесенных изменений нажмите клавишу W.

-- Отформатируем диск в нужную файловую систему, с помощью утилиты mkfs (файловую систему возьмем EXT4):
sudo mkfs.ext4 /dev/vdb1

-- Смонтируем раздел диска vdc1 в папку /mnt/vdc1, с помощью утилиты mount:
sudo mkdir /mnt/vdb1
sudo mount /dev/vdb1 /mnt/vdb1

-- Разрешим запись на диск всем пользователям, с помощью утилиты chmod:
sudo chmod a+w /mnt/vdb1

-- Посмотрим на процессы PostgreSQL:
ps -xf

-- Табличное пространство:
sudo su postgres
cd /mnt/vdb1
mkdir tmptblspc


