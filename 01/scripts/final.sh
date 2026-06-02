#!/bin/bash

set -e

cd /home/vagrant/services/

echo "[INFO] Checking and adding labels to nodes..."

if ! sudo docker node inspect manager01 | grep -q '"role": "db"'; then
    echo "[INFO] Adding label role=db to manager01"
    sudo docker node update --label-add role=db manager01
else
    echo "[INFO] Label role=db already exists on manager01"
fi

if ! sudo docker node inspect worker01 | grep -q '"role": "app"'; then
    echo "[INFO] Adding label role=app to worker01"
    sudo docker node update --label-add role=app worker01
else
    echo "[INFO] Label role=app already exists on worker01"
fi

if ! sudo docker node inspect worker02 | grep -q '"role": "app"'; then
    echo "[INFO] Adding label role=app to worker02"
    sudo docker node update --label-add role=app worker02
else
    echo "[INFO] Label role=app already exists on worker02"
fi

# echo "[INFO] Starting the service"
# sudo docker stack deploy -c docker-compose.yml service