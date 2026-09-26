#!/bin/bash
set -e
mkdir -p ~/work && chmod 700 ~/work
echo "top secret" > ~/work/secret.txt && chmod 600 ~/work/secret.txt
sudo groupadd -f share
sudo mkdir -p /srv/share && sudo chgrp share /srv/share && sudo chmod 3775 /srv/share
setfacl -m u:audit:r ~/work/secret.txt
setfacl -m u:audit:x ~ ~/work
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt 2>/dev/null || true
sudo chmod 640 /opt/lab/perm/danger.conf
