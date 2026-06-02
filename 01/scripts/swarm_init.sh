#!/bin/bash
set -e
echo "[INFO] Initializing Docker Swarm..."
# Initialize Swarm on the private IP
docker swarm init --advertise-addr 192.168.56.10

# Export the worker token to the shared folder
echo "[INFO] Saving worker join token..."
docker swarm join-token -q worker > /home/vagrant/scripts/swarm_token

echo "[INFO] Manager initialized."

# create a network interface for docker 
docker network create \
  --driver overlay \
  --attachable \
  myapp_internal-network
  
echo "[INFO] Network interface created for docker."

