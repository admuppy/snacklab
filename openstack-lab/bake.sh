#!/bin/bash
# Build-time bake: everything DevStack does at "stack time" happens here, once,
# inside the image build — so a learner session only starts services.
#
# Runs inside a kaniko RUN step (no systemd, no init): mariadb, rabbitmq,
# keystone (apache), glance-api and nova-api are started as plain processes,
# used for seeding, then shut down. RabbitMQ state is wiped afterwards so the
# first real boot re-initialises it cleanly.
set -euxo pipefail

PASS=snacklab
export OS_AUTH_URL=http://127.0.0.1:5000/v3 \
       OS_PROJECT_DOMAIN_NAME=Default OS_USER_DOMAIN_NAME=Default \
       OS_PROJECT_NAME=admin OS_USERNAME=admin OS_PASSWORD=$PASS \
       OS_REGION_NAME=RegionOne OS_IDENTITY_API_VERSION=3

# ── mariadb up ────────────────────────────────────────────
[ -d /var/lib/mysql/mysql ] || mariadb-install-db --user=mysql >/dev/null
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld
mysqld_safe --skip-syslog &
for i in $(seq 1 60); do mysqladmin ping >/dev/null 2>&1 && break; sleep 1; done
mysqladmin ping

for db in keystone glance placement nova_api nova nova_cell0 neutron; do
  user=${db%%_*}   # nova_api/nova_cell0 -> nova
  mysql -e "CREATE DATABASE IF NOT EXISTS $db;
            GRANT ALL PRIVILEGES ON $db.* TO '$user'@'localhost' IDENTIFIED BY '$PASS';
            GRANT ALL PRIVILEGES ON $db.* TO '$user'@'%' IDENTIFIED BY '$PASS';"
done

# ── rabbitmq up (guest/guest on loopback is enough for all-in-one) ──
mkdir -p /run/rabbitmq && chown rabbitmq:rabbitmq /run/rabbitmq
su -s /bin/sh rabbitmq -c 'rabbitmq-server -detached'
for i in $(seq 1 60); do su -s /bin/sh rabbitmq -c 'rabbitmqctl status' >/dev/null 2>&1 && break; sleep 1; done

# ── keystone: schema, fernet, bootstrap, apache up ────────
su -s /bin/sh keystone -c 'keystone-manage db_sync'
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password "$PASS" \
  --bootstrap-admin-url http://127.0.0.1:5000/v3 \
  --bootstrap-internal-url http://127.0.0.1:5000/v3 \
  --bootstrap-public-url http://127.0.0.1:5000/v3 \
  --bootstrap-region-id RegionOne
apache2ctl start
for i in $(seq 1 30); do curl -sf http://127.0.0.1:5000/v3 >/dev/null && break; sleep 1; done
curl -sf http://127.0.0.1:5000/v3 >/dev/null

# ── identity: service project/users + service catalog ─────
openstack project create --domain Default --description 'Service project' service
for svc in glance placement nova neutron; do
  openstack user create --domain Default --password "$PASS" "$svc"
  openstack role add --project service --user "$svc" admin
done
openstack service create --name glance    --description 'Image'      image
openstack service create --name placement --description 'Placement'  placement
openstack service create --name nova      --description 'Compute'    compute
openstack service create --name neutron   --description 'Networking' network
for ep in public internal admin; do
  openstack endpoint create --region RegionOne image     $ep http://127.0.0.1:9292
  openstack endpoint create --region RegionOne placement $ep http://127.0.0.1:8778
  openstack endpoint create --region RegionOne compute   $ep http://127.0.0.1:8774/v2.1
  openstack endpoint create --region RegionOne network   $ep http://127.0.0.1:9696
done

# ── glance: schema, temporary API, cirros upload ──────────
su -s /bin/sh glance -c 'glance-manage db_sync'
mkdir -p /var/lib/glance/images && chown glance:glance /var/lib/glance/images
su -s /bin/sh glance -c 'glance-api &'
for i in $(seq 1 30); do curl -s http://127.0.0.1:9292/ >/dev/null && break; sleep 1; done
openstack image create cirros --file /opt/cirros.img \
  --disk-format qcow2 --container-format bare --public
rm -f /opt/cirros.img

# ── placement / nova: schemas, cells, flavors ─────────────
su -s /bin/sh placement -c 'placement-manage db sync'
su -s /bin/sh nova -c 'nova-manage api_db sync'
su -s /bin/sh nova -c 'nova-manage cell_v2 map_cell0 --database_connection "mysql+pymysql://nova:'$PASS'@127.0.0.1/nova_cell0"'
su -s /bin/sh nova -c 'nova-manage cell_v2 create_cell --name cell1' || true
su -s /bin/sh nova -c 'nova-manage db sync'
su -s /bin/sh nova -c 'nova-api &'
for i in $(seq 1 30); do curl -s http://127.0.0.1:8774/ >/dev/null && break; sleep 1; done
openstack flavor create m1.tiny  --id 1 --vcpus 1 --ram 512  --disk 1
openstack flavor create m1.small --id 2 --vcpus 1 --ram 2048 --disk 20

# ── neutron: schema only (server first runs under systemd) ──
su -s /bin/sh neutron -c 'neutron-db-manage \
  --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head'

# ── shutdown + cleanup ────────────────────────────────────
pkill -f nova-api || true
pkill -f glance-api || true
apache2ctl stop || true
su -s /bin/sh rabbitmq -c 'rabbitmqctl stop' || true
mysqladmin shutdown
sleep 2
# Fresh rabbit on first boot; logs from the bake are noise.
rm -rf /var/lib/rabbitmq/mnesia /var/log/rabbitmq/* \
       /var/log/keystone/* /var/log/glance/* /var/log/nova/* /var/log/apache2/*
