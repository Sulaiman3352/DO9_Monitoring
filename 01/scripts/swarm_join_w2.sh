#!/bin/bash
set -e
echo "[INFO] Waiting for Swarm token..."
# Loop until the token file exists (created by manager)
while [ ! -f /home/vagrant/scripts/swarm_token ]; do
    sleep 2
done

TOKEN=$(cat /home/vagrant/scripts/swarm_token)
echo "[INFO] Joining Swarm..."
docker swarm join --advertise-addr 192.168.56.12 --token "$TOKEN" 192.168.56.10:2377
echo "[INFO] Node joined Swarm."
