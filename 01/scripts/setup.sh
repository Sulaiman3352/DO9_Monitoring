#!/bin/bash

echo "Add Docker's official GPG key:"
sudo apt update
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings -y
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "Add the repository to Apt sources:"
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

set -e
sudo usermod -aG docker vagrant
sudo systemctl restart docker
sudo chmod 666 /var/run/docker.sock

echo "done installing all needed packages"

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "min-api-version": "1.24"
}
EOF
systemctl restart docker

echo "[info] Created daemon file"
