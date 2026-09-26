# SnackLab on Docker Compose

Single-host deployment without Kubernetes: the portal runs as a container, mounts the
docker socket, and spawns each learner session as a **privileged sibling container**
(systemd PID 1; for Kubernetes tracks, a full single-node k3s inside the container).
Course content is bind-mounted straight from this repository — no content images needed.

## Requirements

- Linux host, amd64, Docker Engine 24+ with Compose v2 (`docker compose`).
- `/lib/modules` present on the host (Kubernetes tracks modprobe `ip_tables` /
  `br_netfilter` from inside the learner container).
- RAM/CPU sized to your concurrency: roughly 1 CPU / 2–2.5 GiB per active
  k3s session; a 4 vCPU / 8 GiB VM handles 2–3.

## Quick start

```bash
git clone https://github.com/admuppy/snacklab && cd snacklab/compose
./build-images.sh              # or rely on pulls from $IMAGE_REGISTRY
cp .env.example .env           # optional — tune port, limits, locale
docker compose up -d --build
# open http://localhost:3000
```

By default auth is off (everyone is anonymous; `admin` features need an account).
To enable local accounts:

```bash
docker compose exec -e USERS_FILE=/app/v0.1/sessions/users.json \
  portal node userctl.js add admin
docker compose restart portal
```

## Security

The portal holds the docker socket (root-equivalent on the host) and learner
containers are privileged — a determined learner can escape to the host. Treat the
**whole host** as the trust boundary: run the stack on a dedicated VM, don't co-host
other workloads, and only serve audiences you trust. The Kubernetes deployment
(../chart) offers stronger isolation options (NetworkPolicy, dedicated node pools).

## Notes

- Warm pool: `warmpod-*` containers are pre-booted learner environments; they survive
  portal restarts and are re-used. Adjust live from the admin dashboard.
- Sessions and accounts persist in the `snacklab_sessions` volume; learner containers
  are disposable (`lab-*`, removed on expiry and at portal startup).
- Set `IMAGE_REGISTRY`/`LEARNER_IMAGE` in `.env` to use your own registry; images
  already present locally under those tags are never pulled.
