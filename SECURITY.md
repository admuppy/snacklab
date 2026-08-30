# Security Policy

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/admuppy/snacklab/security/advisories/new)
rather than opening a public issue. We aim to acknowledge reports within a week.

## Scope and threat model

SnackLab intentionally runs learner workloads as **privileged pods** (systemd / k3s
need it). This is a documented design trade-off, not a vulnerability in itself:

- The trust boundary is *the cluster*. A malicious learner inside a privileged pod can
  in principle obtain node credentials. Deployments for untrusted audiences must use
  the bundled learner NetworkPolicy on an enforcing CNI (Calico/Cilium) and ideally a
  dedicated, tainted node pool. See the "Security model" section of the README.

In scope for reports:

- Escapes that defeat the documented isolation controls (learner NetworkPolicy,
  namespace ResourceQuota) when they are correctly deployed.
- Portal issues: auth bypass, session hijacking, privilege escalation to admin,
  injection via content or grading pipelines.

Out of scope:

- Consequences of running learner pods privileged on a cluster **without** the
  recommended isolation (that is a deployment choice).
- Denial of service by a learner within their own session's resource limits.
