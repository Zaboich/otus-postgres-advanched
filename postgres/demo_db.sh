
#Скачиваю файл "Демонстрационная база данных PostgresPro"
curl https://edu.postgrespro.ru/demo-20250901-6m.sql.gz -o demo-20250901-6m.sql.gz

# demo-20250901-3m.sql.gz
# demo-20250901-1y.sql.gz
# demo-20250901-2y.sql.gz

#Загрузить дамп в БД
sudo -u postgres psql -c "CREATE DATABASE demo;"
gunzip -c demo-20250901-6m.sql.gz | psql -h localhost -U postgres
