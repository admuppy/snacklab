#!/bin/bash
set -e
mkdir -p ~/work
id deploy >/dev/null 2>&1 || sudo useradd -m -s /bin/bash deploy
sudo groupadd -f ops
sudo usermod -aG ops deploy
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy >/dev/null
sudo chmod 440 /etc/sudoers.d/deploy
sudo visudo -cf /etc/sudoers.d/deploy
sudo usermod -L olduser
sudo chage -M 90 deploy
