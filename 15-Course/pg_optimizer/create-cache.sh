#! /bin/bash

set -e

docker network create pg_tuner_net || true

echo "{'shared_buffers': '10GB', 'work_mem': '4MB', 'maintenance_work_mem': '128MB', 'max_parallel_workers_per_gather': 7, 'random_page_cost': '1.1066253973163394', 'effective_cache_size': '8192MB', 'wal_buffers': '128MB', 'max_wal_size': '4096MB'}"

#docker run -d --name pg_db --network pg_tuner_net --memory 12G --cpus 8 -u postgres -e POSTGRES_PASSWORD=password_test -e POSTGRES_USER=postgres -p 5432:5432 -v pg_bench:/var/lib/postgresql/data postgres:18-alpine -c shared_buffers=10GB -c work_mem=4MB -c maintenance_work_mem=128MB -c max_parallel_workers_per_gather=7 -c random_page_cost=1.1066253973163394 -c effective_cache_size=8192MB -c wal_buffers=128MB -c max_wal_size=4096MB

#docker run -d --name pg_client --network pg_tuner_net --memory 2G --cpus 2 postgres:18-alpine tail -f /dev/null

#sleep 5
docker exec pg_db psql -U postgres -d benchdb -c 'VACUUM ANALYZE;'

echo "Running pgbench (warmup) from client container..."
docker exec -e PGPASSWORD=password_test pg_client pgbench -U postgres -h pg_db -c 32 -j 2 -T 120 -P 30 benchdb

sleep 5

docker exec pg_db psql -U postgres -d benchdb -c 'VACUUM ANALYZE;'

sleep 5

echo "Running pgbench Tests from client container..."
docker exec -e PGPASSWORD=password_test pg_client pgbench -U postgres -h pg_db -c 64 -j 2 -T 600 -P 60 benchdb

