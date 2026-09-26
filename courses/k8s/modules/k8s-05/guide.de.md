# Ressourcen-Requests, Limits und QoS

Gib Containern **Requests** (das Minimum, das der Scheduler reserviert) und **Limits** (die Obergrenze — CPU wird
gedrosselt, Speicher bei Überschreitung per OOM beendet). Ihre Kombination ordnet einen Pod einer von drei
**QoS-Klassen** zu, die unter Knotendruck die **Verdrängungsreihenfolge** bestimmt: Zuerst wird `BestEffort`
verdrängt, dann `Burstable`, zuletzt `Guaranteed`.

> Referenz: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Ein Pod mit QoS Guaranteed

Setzen alle Container **gleiche Requests und Limits für CPU und Speicher**, ist der Pod
`Guaranteed` — die am besten geschützte Klasse.

Pod anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `resources.requests` — das Minimum, das der Scheduler auf einem Knoten reserviert; `limits` — die harte Obergrenze.
- `cpu: "250m"` — Millicores (1000m = 1 CPU); `memory: "64Mi"` — binäre Mebibyte.
- Gleiche Requests und Limits machen den Pod `Guaranteed`.

QoS-Klasse prüfen:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — holt die im Pod-Status erfasste QoS-Klasse (`Guaranteed`/`Burstable`/`BestEffort`).

## 2. Ein Pod mit QoS Burstable

Sind Requests gesetzt, die Limits aber höher (oder nur teilweise gesetzt), ist der Pod `Burstable`: Er nutzt
normalerweise seine Requests und kann bei freier Kapazität bis zu seinen Limits hochgehen.

Pod anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

- Die Limits (500m/128Mi) sind größer als die Requests (100m/32Mi) → reserviert wenig und geht bis zu den Limits, wenn der Knoten Luft hat (`Burstable`).

QoS-Klasse prüfen:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — holt die im Pod-Status erfasste QoS-Klasse (`Guaranteed`/`Burstable`/`BestEffort`).

> Ganz ohne Requests/Limits ist ein Pod `BestEffort` — probiere `kubectl run be --image=nginx:1.26`
> und dann `kubectl get pod be -o jsonpath='{.status.qosClass}'`.

## 3. Standardwerte per LimitRange

Eine **LimitRange** legt Standard-Requests/-Limits für einen Namespace fest, sodass Pods auch dann
Ressourcengrenzen haben, wenn Entwickler sie vergessen. Sie muss **vor** dem Pod existieren, damit die
Standardwerte eingefügt werden.

LimitRange anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # Standard-Limits
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # Standard-Requests
EOF
```

- `kind: LimitRange` — Ressourcenregeln für Container, die in diesem Namespace angelegt werden.
- `default` — Limits, die eingesetzt werden, wenn ein Container keine setzt; `defaultRequest` — dasselbe für Requests.
- Standardwerte werden **beim Anlegen des Pods** eingefügt; bestehende Pods ändern sich nicht.

Einen Pod ohne explizite Limits anlegen — die LimitRange füllt sie aus:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <Name> --image=<Image>` — legt direkt einen einzelnen Pod an, ohne Deployment. Die Ressourcen werden hier absichtlich weggelassen.

Eingefügte Ressourcen prüfen:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — gibt den gesamten resources-Block des ersten Containers als JSON aus; die Werte, die du nicht geschrieben hast, hat die LimitRange eingesetzt.

Geschafft, wenn beim Pod `defaulted` `resources.limits.memory` auf `128Mi` steht.

> Referenz: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
