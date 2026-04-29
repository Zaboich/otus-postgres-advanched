#!/bin/bash
set -e
#minikube start --driver=docker

#sleep 30

echo "Запуск Postgres по описанию "

kubectl apply -f deploy-postgres-18.yaml

echo "Deployment Postgres запущен"


sleep 30



echo "Старт контейнера psql-client"

docker compose -f psql-client/docker-compose.yml up -d

#exit 0

POD_NAME=$(kubectl get po -n pg-ns -o json | jq '.items[0].metadata.name' -r)

echo "Старт kubectl port-forward"
(kubectl port-forward $POD_NAME --address 0.0.0.0 -n pg-ns 5432:5432 > /dev/null 2>&1) &
PID_PORT=$!;
sleep 5

echo "------------------------------------------------"


#echo "Create .pgpass "
#docker compose -f psql-client/docker-compose.yml exec psql-client bash -c 'echo "*:*:*:postgres:postgres" > /root/.pgpass && chmod 600 /root/.pgpass'

echo "Создаём БД через клиента psql Create DATABASE "
docker compose -f psql-client/docker-compose.yml exec psql-client psql  -h host.loc -p 5432 -U postgres -w -c "CREATE DATABASE test_db;"

echo "Создаём TABLE через клиента psql Create TABLE test"
docker compose -f psql-client/docker-compose.yml exec psql-client psql -h host.loc -p 5432 -U postgres -w -d test_db -c "CREATE TABLE test (id SERIAL, data VARCHAR(255));"

echo "Добавляем данные через клиента psql INSERT test "
docker compose -f psql-client/docker-compose.yml exec psql-client psql -h host.loc -p 5432 -U postgres -w -d test_db -c "INSERT INTO test (data) VALUES ('first row');"

echo "Запрашиваем данные через клиента psql SELECT "
docker compose -f psql-client/docker-compose.yml exec psql-client psql -h host.loc -p 5432 -U postgres -w -d test_db -c "SELECT * FROM test;"

sudo kill "${PID_PORT}"

echo "Удаляем POD postgres "
kubectl delete pod ${POD_NAME} -n pg-ns

sleep 10

POD_NAME=$(kubectl get po -n pg-ns -o json | jq '.items[0].metadata.name' -r)

echo "Старт kubectl port-forward"
(kubectl port-forward $POD_NAME --address 0.0.0.0 -n pg-ns 5432:5432 > /dev/null 2>&1) &
PID_PORT=$!;
sleep 5

echo "Повторно запрашиваем данные после восстановления POD: SELECT data "
docker compose -f psql-client/docker-compose.yml exec psql-client psql -h host.loc -p 5432 -U postgres -w -d test_db -c "SELECT * FROM test;"


sudo kill "${PID_PORT}"

kubectl delete deploy deployment-postgres-18 -n pg-ns
kubectl delete pvc postgres-pvc -n pg-ns
kubectl delete service postgres-service -n pg-ns
kubectl delete secret postgres-secret -n pg-ns
kubectl delete configmap postgres-config -n pg-ns
kubectl delete ns pg-ns