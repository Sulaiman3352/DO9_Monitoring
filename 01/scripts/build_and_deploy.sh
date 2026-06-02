#!/bin/bash

set -e

echo "[INFO] Waiting for all nodes..."
sleep 15

echo "[INFO] Building images..."
cd /home/vagrant/docker/
export DOCKER_BUILDKIT=1

# Build images using docker compose
docker compose build

echo "[INFO] Deploying stack..."
docker stack deploy -c docker-compose.yml myapp

echo "[INFO] Deploying Portainer..."
curl -L https://downloads.portainer.io/ce2-19/portainer-agent-stack.yml -o portainer-stack.yml
docker stack deploy -c portainer-stack.yml portainer

sleep 10
echo "[INFO] Services deployed:"
docker service ls

echo "[INFO] Container distribution:"
docker node ps $(docker node ls -q)
