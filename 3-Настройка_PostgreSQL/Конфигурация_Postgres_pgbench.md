-- Создаем сетевую инфраструктуру для VM:
```shell
yc vpc network create --name net-otus1 &&\
yc vpc subnet create --name subnet-otus1 --range 192.168.1.0/24 --network-name net-otus1 && \
sleep 10 &&\
yc compute instance create --name vm-otus1 --hostname vm-otus1 --cores 2 --memory 4 \
--create-boot-disk size=15G,type=network-hdd,image-folder-id=standard-images,image-family=ubuntu-2404-lts \
--network-interface subnet-name=subnet-otus1,nat-ip-version=ipv4 --ssh-key ~/.ssh/id_rsa.pub &&\
sleep 10 &&\
yc compute instance list

ADDR_VM1=$(yc compute instance show --name vm-otus1 | grep -E ' +address' | tail -n 1 | awk '{print $2}') && \
ssh  -o StrictHostKeyChecking=no yc-user@$ADDR_VM1
```
На виртуальной машине
```shell
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
sleep 2 &&\
sudo apt update && sudo apt -y install postgresql
```
```shell
pg_lsclusters

sudo nano /etc/postgresql/14/main/postgresql.conf
sudo nano /etc/postgresql/14/main/pg_hba.conf
```

```shell
sudo -u postgres psql -c "alter user postgres password 'postgres'";

export PGPASSWORD=postgres
echo "localhost:5432:*:postgres:${PGPASSWORD}" > .pgpass
`chmod 0600 ~/.pgpass`

psql -h localhost -U postgres
```

--Посмотрим расположение конфиг файла через psql и idle  
```
show config_file;

               config_file               
-----------------------------------------
 /etc/postgresql/18/main/postgresql.conf

```
--Так же посмоттреть через функцию:
```
select current_setting('config_file');
```

--Далее смотрим структуру файла postgresql.conf (комменты, единицы измерения и т.д)
```
nano postgresql.conf
```
--смотрим системное представление 
```
select * from pg_settings;
```

--Далее рассмторим параметры которые требуют рестарт сервера
```sql
select * from pg_settings where context = 'postmaster';
```
--И изменим параметры max_connections через конфиг файл и проверим;
```sql
\x
select * from pg_settings where name='max_connections';
```
--Смотрим pending_restart
```sql
select pg_reload_conf();
```
```sql
alter system set max_connections = '300';
```
```shell
sudo pg_ctlcluster 18 main restart
```

--Смотрим по параметрам вьюху
```sql
select count(*) from pg_settings;
select unit, count(*) from pg_settings group by unit order by 2 desc;
select category, count(*) from pg_settings group by category order by 2 desc;
select context, count(*) from pg_settings group by context order by 2 desc;
select source, count(*) from pg_settings group by source order by 2 desc;

select * from pg_settings where source = 'override';
```

--Переходим ко вью pg_file_settings;
```sql
select count(*) from pg_file_settings;
select sourcefile, count(*) from pg_file_settings group by sourcefile;

select * from pg_file_settings;
```
--Далее пробуем преминить параметр с ошибкой, смотри что их этого получается
```sql
select * from pg_file_settings where name='work_mem';
```
```shell
sudo journalctl -u postgresql@18-main.service
```
--Смотрим проблему с единицами измерения
```sql
select setting || ' x ' || coalesce(unit, 'units') from pg_settings where name = 'work_mem';

select setting || ' x ' || coalesce(unit, 'units') from pg_settings where name = 'max_connections';
```

--Далее говорим о том как задать параметр с помощью alter system
```sql
alter system set work_mem = '4mB';
select * from pg_file_settings where name='max_connections';

alter system set max_connections = '300';
```
--Сбросить параметр
```SQL 
alter system reset max_connections;
alter system reset work_mem;
```



## Далее говорим про set config в рамках транзакции

--Установка параметров во время исполнения
--Для изменения параметров во время сеанса можно использовать команду SET:
```
set work_mem to '24mb';
```
--Или функцию set_config:
```
select set_config('work_mem', '32mb', false);
```

--Третий параметр функции говорит о том, нужно ли устанавливать значение только для текущей транзакции (true)
--или до конца работы сеанса (false). 
Это важно при работе приложения через пул соединений, когда в одном сеансе могут выполняться транзакции разных пользователей.


--И для конкретных пользователей и бд
```sql
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
```

--Так же можно добавить свой параметр:


## Далее превреям работу pgbench. 
Инициализируем необходимые нам таблицы в бд
```shell
sudo su postgres
```

-- инициализация 
```
sudo -u postgres pgbench -i postgres -s 10
```
-- запуск бенчмарка 
```
sudo -u postgres pgbench -c 50 -j 2 -P 10 -T 60 postgres
```

-c Клиенты. Число имитируемых клиентов, то есть число одновременных сеансов базы данных. Значение по умолчанию — 1.
-j Потоки. Число рабочих потоков в pgbench. Использовать нескольких потоков может быть полезно на многопроцессорных компьютерах. Клиенты распределяются по доступным потокам равномерно, насколько это возможно. Значение по умолчанию — 1.
-P Сек. Выводить отчёт о прогрессе через заданное число секунд (сек). Выдаваемый отчёт включает время, прошедшее с момента запуска, скорость (в TPS) с момента предыдущего отчёта, а также среднее время ожидания транзакций и стандартное отклонение. В режиме ограничения скорости (-R) время ожидания вычисляется относительно назначенного времени запуска транзакции, а не фактического времени её начала, так что оно включает и среднее время отставания от графика.
-T Cекунды. Выполнять тест с ограничением по времени (в секундах), а не по числу транзакций для каждого клиента. Параметры -t и -T являются взаимоисключающими.

### ⚙️ Ключевые параметры pgbench

| Параметр | Описание | Пример |
|----------|----------|--------|
| `-c N` | Количество одновременных клиентских соединений | `-c 32` |
| `-j N` | Количество рабочих потоков (должно быть ≤ `-c`) | `-j 8` |
| `-T N` | Продолжительность теста в секундах | `-T 300` |
| `-t N` | Фиксированное количество транзакций на клиента | `-t 10000` |
| `-s N` | Масштабный множитель при инициализации | `-s 50` |
| `-r` | Вывод статистики по времени выполнения отдельных запросов | `-r` |
| `-P N` | Периодичность вывода прогресса (сек) | `-P 10` |
| `-M querymode` | Режим выполнения: `simple`, `extended`, `prepared` | `-M prepared` |
| `-R rate` | Ограничение скорости (транзакций/сек на клиента) | `-R 100` |
| `-f script` | Использование кастомного скрипта вместо встроенного | `-f custom.sql` |
| `--latency-limit=N` | Отклонение транзакций, превышающих лимит (мс) | `--latency-limit=100` |
| `--rate=N` | Целевая скорость выполнения (TPS) | `--rate=1000` |
| `--progress-timestamp` | Вывод timestamps в прогресс-отчётах | `--progress-timestamp` |



pgbench — утилита нагрузочного тестирования PostgreSQL
pgbench — это встроенная утилита PostgreSQL для проведения стресс-тестов и оценки производительности СУБД. 
Она эмулирует параллельную работу множества клиентов, выполняя заданные SQL-запросы, и рассчитывает ключевые метрики производительности, главным образом TPS


Запуск со своим скриптом 
```
pgbench -c 16 -j 4 -T 60 -f custom.sql postgres
```
```
-- custom.sql
\set aid random(1, 100000 * :scale)
BEGIN;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + 100 WHERE aid = :aid;
COMMIT;
```

Постепенное увеличение нагрузки

```shell
for clients in 4 8 16 32 64; do \
sudo -u postgres pgbench -c $clients -j 4 -T 60 -P 10 postgres; \ 
done
```

Результат запуска на свежеустановленной Postgres 18 / Ubuntu 24.04
```
clients 4:

transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 4
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 34913
number of failed transactions: 0 (0.000%)
latency average = 6.873 ms
latency stddev = 9.257 ms
initial connection time = 10.396 ms
tps = 581.927453 (without initial connection time)

clients 8:
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 8
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 42526
number of failed transactions: 0 (0.000%)
latency average = 11.283 ms
latency stddev = 14.227 ms
initial connection time = 19.398 ms
tps = 708.747188 (without initial connection time)

clients 16:
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 16
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 55498
number of failed transactions: 0 (0.000%)
latency average = 17.291 ms
latency stddev = 27.001 ms
initial connection time = 34.988 ms
tps = 924.788568 (without initial connection time)

clients 32:
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 32
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 61079
number of failed transactions: 0 (0.000%)
latency average = 31.429 ms
latency stddev = 36.791 ms
initial connection time = 64.173 ms
tps = 1016.433188 (without initial connection time)

clients 64:
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 64
number of threads: 4
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 47710
number of failed transactions: 0 (0.000%)
latency average = 80.397 ms
latency stddev = 126.016 ms
initial connection time = 138.683 ms
tps = 794.714289 (without initial connection time)

```


## Далее генерируем необходимые параметры в pgtune
https://github.com/le0pard/pgtune
https://habr.com/ru/articles/217073/
--И вставляем их в папку conf.d заранее прописав ее в параметры

--`CONFIG FILE INCLUDES` (postgresql.conf)
--`include_dir = 'conf.d'`

-- cd /etc/postgresql/14/main/conf.d
-- nano pgtune.conf
```
select * from pg_file_settings where name='work_mem';
```
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

