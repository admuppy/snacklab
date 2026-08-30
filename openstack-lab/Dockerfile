# SnackLab — OpenStack learner environment image (snacklab-openstack)
#
# Same "systemd PID1 privileged pod" skeleton as k8s-lab, but with an all-in-one
# OpenStack (Ubuntu 24.04 = Caracal/2024.1 packages) fully pre-baked: packages,
# config, DB schemas, keystone identity + endpoints, flavors and a cirros image
# are all created at BUILD time, so a session boot only has to start services.
#
# Performance choices (the whole point of this image):
#   - nova-compute runs the **fake virt driver** — instances "boot" without any
#     VM, so a session costs no more than the idle control plane (~2-2.5 GiB).
#     nova-compute-ironic is installed purely to satisfy the nova-compute
#     dependency without dragging in libvirt/qemu; the driver is overridden to
#     fake.FakeDriver in nova-compute.conf.
#   - every endpoint is http://127.0.0.1:<port> — hostname-independent, so the
#     DB baked at build time stays valid whatever the pod is called at runtime.
#   - single worker per API service, small mariadb buffer pool, no memcached,
#     no horizon/heat/swift/cinder (cinder needs host loop devices — the same
#     host-global-resource problem that killed the linux LVM module).
#   - RabbitMQ state is wiped after the bake: it re-initialises on first boot
#     (NODENAME pinned to rabbit@localhost so the pod hostname never matters).
#
# Build context = repository root (./build.sh openstack-lab [tag]).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    LANG=C.UTF-8

# Keep package maintainer scripts from starting services inside the build.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
 && chmod +x /usr/sbin/policy-rc.d

# ── packages ──────────────────────────────────────────────
# systemd base (same trim as k8s-lab) + OpenStack control plane + OVS.
# neutron-openvswitch-agent is what makes port binding succeed for fake
# instances; l3/dhcp agents power router / floating-IP / DHCP lab content.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus \
      sudo bash-completion ca-certificates tzdata \
      coreutils util-linux procps psmisc lsof \
      iproute2 iputils-ping net-tools curl kmod \
      jq vim-tiny nano less \
      mariadb-server rabbitmq-server \
      python3-pymysql python3-openstackclient \
      keystone glance placement-api \
      nova-api nova-conductor nova-scheduler nova-compute-ironic nova-compute \
      neutron-server neutron-plugin-ml2 \
      neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent \
      openvswitch-switch \
 && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/info/*

# ── configuration (overwrites the package-shipped defaults) ──
COPY openstack-lab/conf/mariadb-snacklab.cnf /etc/mysql/mariadb.conf.d/99-snacklab.cnf
COPY openstack-lab/conf/keystone.conf        /etc/keystone/keystone.conf
COPY openstack-lab/conf/glance-api.conf      /etc/glance/glance-api.conf
COPY openstack-lab/conf/placement.conf       /etc/placement/placement.conf
COPY openstack-lab/conf/nova.conf            /etc/nova/nova.conf
COPY openstack-lab/conf/nova-compute.conf    /etc/nova/nova-compute.conf
COPY openstack-lab/conf/neutron.conf         /etc/neutron/neutron.conf
COPY openstack-lab/conf/ml2_conf.ini         /etc/neutron/plugins/ml2/ml2_conf.ini
COPY openstack-lab/conf/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini
COPY openstack-lab/conf/l3_agent.ini         /etc/neutron/l3_agent.ini
COPY openstack-lab/conf/dhcp_agent.ini       /etc/neutron/dhcp_agent.ini
# neutron_sudoers covers neutron-rootwrap but not the -daemon variant the
# dhcp/l3 agents use; without this they busy-loop on sudo denials.
RUN printf 'neutron ALL = (root) NOPASSWD: /usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf\n' \
      > /etc/sudoers.d/91-neutron-daemon \
 && chmod 0440 /etc/sudoers.d/91-neutron-daemon && visudo -c >/dev/null \
 && echo 'NODENAME=rabbit@localhost' > /etc/rabbitmq/rabbitmq-env.conf \
 && chown keystone:keystone /etc/keystone/keystone.conf \
 && chown glance:glance /etc/glance/glance-api.conf \
 && chown placement:placement /etc/placement/placement.conf \
 && chown nova:nova /etc/nova/nova.conf /etc/nova/nova-compute.conf \
 && chown -R neutron:neutron /etc/neutron

# Trim the wsgi fleets: keystone/placement each default to 5 processes
# (~100 MiB apiece); 1 process × 4 threads is plenty for a single learner.
# Measured effect of this + no metadata services: 3.65 GiB → 2.75 GiB idle.
RUN sed -i 's/processes=5 threads=1/processes=1 threads=4/' \
      /etc/apache2/sites-enabled/keystone.conf \
      /etc/apache2/sites-enabled/placement-api.conf \
 && systemctl mask neutron-metadata-agent

# cirros — the canonical tiny lab image, baked so glance is pre-populated offline.
ARG CIRROS_VERSION=0.6.2
RUN curl -fsSL "https://download.cirros-cloud.net/${CIRROS_VERSION}/cirros-${CIRROS_VERSION}-x86_64-disk.img" \
      -o /opt/cirros.img

# ── bake: schemas, identity, endpoints, flavors, image ────
# Starts mariadb/rabbit/keystone/glance-api/nova-api temporarily inside this
# build step, seeds everything, then shuts them down (see bake.sh).
COPY openstack-lab/bake.sh /tmp/bake.sh
RUN bash /tmp/bake.sh && rm -f /tmp/bake.sh

# ── systemd: container adjustments + service enablement ───
RUN systemctl mask \
      systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
      systemd-modules-load.service \
      systemd-networkd.service systemd-resolved.service \
      sys-kernel-config.mount sys-kernel-debug.mount sys-kernel-tracing.mount \
 && systemctl set-default multi-user.target \
 && systemctl enable mariadb rabbitmq-server apache2 openvswitch-switch \
      glance-api nova-api nova-conductor nova-scheduler nova-compute \
      neutron-server neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent
# openstack-netinit: one-shot that loads the openvswitch module (host /lib/modules
# is mounted by the learner pod template, same as the k3s br_netfilter dance) and
# creates br-ex for provider/external-network labs.
COPY openstack-lab/openstack-netinit.service /etc/systemd/system/openstack-netinit.service
RUN systemctl enable openstack-netinit.service

# ── learner account (uid 1000, NOPASSWD sudo) + CLI env ───
RUN userdel -r ubuntu 2>/dev/null || true; \
    useradd -m -s /bin/bash -u 1000 learner \
 && install -m 0440 /dev/null /etc/sudoers.d/90-learner \
 && echo 'learner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-learner
# Admin credentials for the openstack CLI, applied to login shells (terminal and
# checks both go through `su - learner`). The lab is single-user and disposable,
# so a fixed well-known password is fine.
RUN printf '%s\n' \
      'export OS_AUTH_URL=http://127.0.0.1:5000/v3' \
      'export OS_PROJECT_DOMAIN_NAME=Default' \
      'export OS_USER_DOMAIN_NAME=Default' \
      'export OS_PROJECT_NAME=admin' \
      'export OS_USERNAME=admin' \
      'export OS_PASSWORD=snacklab' \
      'export OS_REGION_NAME=RegionOne' \
      'export OS_IDENTITY_API_VERSION=3' \
      'alias os=openstack' \
      > /etc/profile.d/openstack.sh \
 && chmod 0644 /etc/profile.d/openstack.sh

# ── entrypoint: cgroup-namespace isolation before systemd ──
# Same rationale as k8s-lab: privileged pods inherit the host cgroup namespace
# and systemd should manage its own subtree only (see entrypoint.sh).
COPY openstack-lab/entrypoint.sh /usr/local/bin/lab-init
RUN chmod 0755 /usr/local/bin/lab-init

STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/usr/local/bin/lab-init"]
