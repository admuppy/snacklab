# SnackLab

**Self-hosted, browser-only hands-on lab portal** — disposable real environments,
automated grading, mock exams.

*[한국어 README](README.ko.md)*

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Node](https://img.shields.io/badge/node-%E2%89%A518-brightgreen)
![Kubernetes](https://img.shields.io/badge/kubernetes-v1.27%2B-326CE5)
![Modules](https://img.shields.io/badge/modules-24-orange)
![i18n](https://img.shields.io/badge/i18n-7_locales-purple)

Each learner gets an **isolated, disposable environment** created on demand — a
privileged pod running systemd, with a full single-node k3s cluster or an all-in-one
OpenStack inside it when the track needs one. A self-hosted alternative to
Isovalent Labs / Killercoda-style platforms.

Built for:

- **HR / L&D teams** evaluating a tool to grow in-house engineering skills and
  measure learning progress — auto-graded steps and exam scores give objective,
  per-learner results out of the box
- **Onboarding new team members** — a ready-made, self-paced path through Linux,
  Kubernetes, and OpenStack fundamentals, no workstation setup required
- **Certification study groups** — realistic timed CKA / CKAD / CKS mock exams
- **Platform / infra teams** that need a self-hosted, air-gap-friendly lab the
  whole organization can share

## 🚀 Try it in 60 seconds

No cluster needed — the `sim` driver fakes sessions so you can explore the whole UI:

```bash
git clone https://github.com/admuppy/snacklab && cd snacklab/prototype
npm ci
DRIVER=sim node server.js
# open http://localhost:3000
```

Requires Node.js ≥ 18; the only runtime dependencies are express and ws.

## Why SnackLab?

- 🧑‍💻 **Zero-install for learners** — guide, terminal, and grading all run in the browser.
- ⚙️ **Real environments, not simulations** — systemd PID1 pods for Linux tracks, a
  genuine single-node k3s cluster *inside a pod* for Kubernetes tracks, a real
  OpenStack control plane for the OpenStack track.
- ✅ **Automated grading** — per-step check scripts with localized pass/fail messages;
  exam mode adds partial credit and one-shot full-exam scoring.
- 📝 **Mock exams that feel real** — 120-minute CKA/CKAD/CKS runs with real exam
  domain weighting, pass badges, per-question explanations, and an "exam language"
  prompt limiting the UI to what the real exams offer (en·ja·zh-CN).
- 🌏 **i18n first** — 7 UI locales (ko·en·ja·zh-CN·zh-TW·es·de); guides and grading
  messages localized with sane fallbacks.
- ⚡ **Warm pool** — pre-provisioned learner pods for instant session start, tunable
  live from the admin dashboard.
- 🔌 **Air-gap friendly** — learner images boot offline; one `imageRegistry` value
  re-points everything at a private registry.
- 📦 **Two deployment modes** — a Kubernetes Helm chart, or a single-host
  [Docker Compose stack](compose/) with no Kubernetes required.

## Tracks

| Track | Modules | Environment |
|---|---|---|
| Linux intermediate | linux-01 – 09 (permissions, processes, text, Bash, accounts, systemd, networking, capstone, resources) | systemd PID1 pod |
| Kubernetes deep-dive | k8s-01 – 10 (workloads, services, config, probes, resources, scheduling, storage, RBAC, NetworkPolicy, troubleshooting) | single-node k3s in a pod |
| CKA / CKAD / CKS mock exams | cka-01 · ckad-01 · cks-01 (120 min, 15–16 questions each) | single-node k3s in a pod |
| OpenStack essentials | openstack-01 – 02 (service catalog, networks, instance lifecycle, projects; building and uploading qcow2 images) | all-in-one OpenStack (Caracal) in a pod, nova fake driver |

The OpenStack track runs keystone·glance·neutron·nova with the **fake virt driver**:
instances "boot" as pure state machines, so the whole cloud idles at ~0.05 CPU /
2.8 GiB while the API/CLI workflow stays identical to real OpenStack.

## Architecture

```
┌────────────────┐  HTTPS / WebSocket  ┌────────────────────────────────┐
│    Browser     │◄───────────────────►│   Portal (Node.js single       │
│ guide·terminal │                     │   server.js)                   │
│ catalog·admin  │                     │ auth(local/OIDC) · i18n ·      │
└────────────────┘                     │ grading · exam mode · warm pool│
                                       └───────────┬────────────────────┘
                       course bundles              │ session driver
                  (content images → /courses)      │ sim | pod | docker
                                                   │
                 ┌─────────────────────────────────┼─────────────────────┐
                 ▼                                 ▼                     ▼
        ┌────────────────┐              ┌────────────────────┐ ┌──────────────────┐
        │  Linux track   │              │  K8s / exam tracks │ │ OpenStack track  │
        │ systemd PID1   │              │ single-node k3s    │ │ all-in-one cloud │
        │ pod            │              │ inside the pod     │ │ (fake driver)    │
        └────────────────┘              └────────────────────┘ └──────────────────┘
                one disposable privileged pod per learner session
           (terminal & checks go through `kubectl exec` — no sshd, no ingress)
```

- **Drivers**: `pod` (learner pods on Kubernetes), `docker` (privileged sibling
  containers via the docker socket), `sim` (no backend — UI development).
- **Content**: course bundles (`course.json` + modules) ship as tiny content images
  that init-containers copy into the portal's `/courses` volume — content updates
  never rebuild the portal or learner images.

## Repository layout

```
prototype/           the app — the entire portal is one Node.js server.js (express + ws)
  userctl.js         local account CLI
  public/            static UI (catalog / lab / admin, i18n.js)
  content/           built-in content (linux-01 – 09)
courses/             course bundles (k8s·cka·cks·ckad·openstack) — course.json + modules/, shipped as content images
k8s-lab/             learner environment image with embedded k3s (incl. air-gap slimming filter)
openstack-lab/       learner environment image with pre-baked all-in-one OpenStack (fake driver)
learner/             Linux-track learner environment image
portal/              portal image Dockerfile
chart/               Helm chart (values.yaml = defaults, values-example.yaml = production example)
compose/             single-host Docker Compose deployment (docker driver, no Kubernetes)
deploy/              learner pod template, course E2E verification script
build.sh / deploy.sh in-cluster kaniko build & helm deploy helpers
```

## Installing on Kubernetes

### Requirements

| | Minimum | Notes |
|---|---|---|
| Kubernetes | v1.27+ | any CNCF-conformant distro (k3s, kubeadm, RKE2, EKS, ...) |
| Architecture | amd64 | learner images are currently built for amd64 |
| Privileged pods | required | learner pods run systemd (and k3s / OpenStack) as PID 1 |
| CNI | NetworkPolicy-enforcing CNI (Calico, Cilium) strongly recommended | the chart ships a learner-isolation NetworkPolicy; it is a no-op on CNIs that don't enforce (e.g. plain flannel) |
| StorageClass | optional | only for progress/badge persistence; any dynamic provisioner works (local-path, Longhorn, NFS, Ceph, ...) |
| Registry | any | anything the cluster can pull from (see `imageRegistry` below) |

### Recommended sizing

The portal itself is tiny (100m CPU / 256Mi requests). Capacity planning is driven by
**concurrent learner sessions**:

| Session type | Requests | Limits | Measured steady state |
|---|---|---|---|
| Linux track pod | 250m CPU / 1Gi / 2Gi ephemeral | 2 CPU / 4Gi / 8Gi ephemeral | light |
| k3s-in-pod (k8s / exam tracks) | 500m / 1Gi | 2 CPU / 4Gi | ~1 CPU, 1.5–2.5 GiB |
| OpenStack all-in-one pod | 500m / 2Gi | 2 CPU / 6Gi | ~0.05 CPU idle, 2.8 GiB |

Rules of thumb:

- **Evaluation / small team**: 1 node, 4 vCPU / 8 GiB → 2–3 concurrent k3s or
  OpenStack sessions.
- **Classroom (~10 concurrent)**: 16 vCPU / 32 GiB total across nodes.
- Ephemeral disk: budget ~1 GiB per active exam session (measured: a full CKA run
  writes ~756 MiB); the chart caps each pod at 8 Gi.
- Session boot: k3s and OpenStack pods bootstrap in ~10–40 s once the image is cached
  on a node; first pull per node takes minutes (images are 1–3 GiB) — the warm pool
  hides both.
- A ResourceQuota and LimitRange for the lab namespace are included and enabled by default.

### Install

```bash
helm upgrade --install lab ./chart -n snacklab --create-namespace \
  --set auth.adminPassword='<initial admin password>' \
  -f chart/values-example.yaml   # copy & edit for your site first
```

With `auth.mode: local` the portal creates the first admin account on first boot:
user `adminUsers[0]` (default `admin`), password `auth.adminPassword`
(default **`ChangeMe`** — change it right after logging in). The account is written to
`users.json` on the sessions volume and only when that file does not exist yet, so later
changes to `adminPassword` are ignored; manage accounts from the admin dashboard
(`/admin.html`).

Optional Secrets:

- `auth.usersExistingSecret` — seed `users.json` from a Secret instead of the generated
  admin (key `users.json`, made with `node prototype/userctl.js add <user> --admin`).
  Like the generated admin it is copied only on first boot.
- `auth.cookieSecretExistingSecret` — cookie signing key (key `cookieSecret`) so logins
  survive portal restarts; without it a random key is generated per pod.

```bash
kubectl -n snacklab create secret generic lab-cookie \
  --from-literal=cookieSecret=$(openssl rand -hex 32)
```

If you point the chart at a Secret that does not exist, the portal pod fails with
`MountVolume.SetUp failed for volume "users" : secret "lab-users" not found` (or a
`CreateContainerConfigError` for the cookie Secret) — create it, then
`kubectl -n snacklab rollout restart deploy/lab-snacklab`.

To try the portal without login, use `--set auth.mode=off` (internal demos only).

Key values (see `chart/values.yaml` for the full list):

- `imageRegistry` — registry prefix for course/learner images; point at your own
  registry for air-gapped installs.
- `driver` — `pod` (real sessions) or `sim` (no cluster needed).
- `auth.mode` — `auto` | `off` | `local` | `oidc`.
- `courses` — content images to mount (k8s / cka / cks / ckad / openstack, or your own).
- `persistence.*` — progress/badge storage; `storageClass: ''` uses the cluster
  default, `accessModes` is overridable for NFS-style (RWX-only) provisioners.
- `warmPool.*` — warm pool size and behaviour.
- `session.*` — TTL, idle timeout, per-user and global session caps.

### Building images

Builds run inside the cluster with kaniko (no docker daemon needed):

```bash
export REGISTRY=registry.example.com/snacklab   # or put it in ./build.env
./build.sh v1.x                # portal image
./build.sh learner v2          # Linux learner environment
./build.sh k8s-lab v1          # k3s learner environment
./build.sh openstack-lab v1    # OpenStack learner environment
./build.sh k8s-course v1       # course content images (cka/cks/ckad/openstack-course likewise)
./deploy.sh v1.x               # helm upgrade with chart/values-live.yaml
```

### Verifying content

Content is validated end-to-end in a real learner pod
(bootstrap → pre-check all FAIL → solution → post-check all PASS):

```bash
./deploy/e2e-course.sh courses/k8s
./deploy/e2e-course.sh courses/openstack
./deploy/e2e-course.sh courses/cka cka-01
```

## Docker Compose (single host, no Kubernetes)

The portal can also run as a plain container that spawns each learner session as a
privileged sibling container via the docker socket — same learner images, same
content, no cluster:

```bash
cd compose
./build-images.sh
docker compose up -d --build
# open http://localhost:3000
```

Isolation is weaker than the Kubernetes deployment (the trust boundary is the whole
host) — see [compose/README.md](compose/README.md) for details, sizing, and auth setup.

## How it compares

| | SnackLab | Hosted playgrounds (Killercoda, Instruqt, ...) | Local VMs / kind |
|---|---|---|---|
| Self-hosted / air-gapped | ✅ | ❌ | ✅ |
| Zero learner setup (browser only) | ✅ | ✅ | ❌ |
| Your own content + grading | ✅ | limited / paid tiers | manual |
| Exam mode (weighting, partial credit, badges) | ✅ | ❌ | ❌ |
| Per-learner isolated k8s / OpenStack | ✅ | ✅ | one per machine |
| Cost | your hardware | subscription | your hardware |

## Security model

Learner pods are **privileged** (systemd and k3s require it). The trust boundary is
"shares the cluster": a determined user inside a learner pod can in principle reach node
credentials. For anything beyond a fully-trusted audience:

- keep the bundled learner NetworkPolicy enabled (blocks all ingress; egress limited to
  DNS and public 80/443, with RFC1918/link-local ranges blocked) **and** run a CNI that
  enforces it;
- consider a dedicated, tainted node pool for learner pods;
- verify your node/pod/service CIDRs fall within `learner.networkPolicy.blockedCidrs`.

See the comments in `chart/values.yaml` and
`chart/templates/networkpolicy-learner.yaml` for details.

## Writing content

A module is `meta.json + guide.md (+ locales) + bootstrap.sh + checks/*.sh + solution.sh`
(+ `explain.md` for exam questions). Check scripts print message keys only; the portal
renders them per-locale via `checks/messages.json`. Full conventions:
[docs/content-authoring-conventions.md](docs/content-authoring-conventions.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and PRs welcome — content contributions
(new modules/tracks and translations) are especially appreciated.

## License

[Apache License 2.0](LICENSE)
