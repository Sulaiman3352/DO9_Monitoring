#!/bin/bash

cd /home/vagrant/docker/
export DOCKER_BUILDKIT=1

echo "Starting Docker Compose build..."
docker compose build --progress=plain --no-cache
#DOCKER_BUILDKIT=0 docker compose build
docker compose up -d
