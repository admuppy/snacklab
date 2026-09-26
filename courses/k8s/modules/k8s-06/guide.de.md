# Scheduling – Affinity, Taints, DaemonSets

Der Scheduler entscheidet, auf welchem Knoten ein Pod läuft. **nodeAffinity/nodeSelector** lässt einen Pod
bestimmte Knoten *bevorzugen*; **Taints/Tolerations** lassen einen Knoten Pods *abweisen*, die ihn nicht
tolerieren — gegensätzliche Werkzeuge. Ein **DaemonSet** platziert auf jedem (passenden) Knoten einen Pod.

Dieser Cluster hat einen einzigen Knoten. Seinen Namen erhältst du so:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — Befehlssubstitution; `{.items[0].metadata.name}` holt den Namen des ersten Knotens in die Shell-Variable `node`.
- `; echo "$node"` — gibt ihn zur Kontrolle aus. Spätere Befehle verwenden ihn als `"$node"`.

> Referenz: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. Knoten-Labels und nodeAffinity

Versieh den Knoten mit dem Label `disktype=ssd` und lege den Pod `affine` an, der per
`requiredDuringScheduling`-nodeAffinity nur auf Knoten mit diesem Label landet.

Knoten labeln:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <Ressource> <Name> Schlüssel=Wert` — fügt ein Label hinzu. Mit `--overwrite` einen vorhandenen Schlüssel ändern, mit `Schlüssel-` entfernen.

Pod mit nodeAffinity anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `requiredDuringSchedulingIgnoredDuringExecution` — **muss** beim Scheduling erfüllt sein; bereits laufende Pods werden nicht verdrängt, wenn sich das Label später ändert.
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — nur Knoten, deren Label `disktype` den Wert `ssd` hat, kommen infrage (weitere Operatoren: `NotIn`, `Exists`, …).

Platzierung des Pods prüfen:

```bash
kubectl get pod affine -o wide      # Spalte NODE = unser Knoten
```

- Die Spalte `NODE` aus `-o wide` zeigt, auf welchem Knoten der Pod gelandet ist.

Entfernst du das Label (`kubectl label node "$node" disktype-`), bleibt ein neuer solcher Pod `Pending` —
probier es aus.

## 2. Taints und Tolerations

Versieh den Knoten mit dem **Taint** `lab=demo:NoSchedule`, dann können Pods, die ihn nicht **tolerieren**,
nicht eingeplant werden. Nur `tolerant` mit einer Toleration landet dort.

Knoten mit Taint versehen:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <Knoten> Schlüssel=Wert:Effekt` — versieht den Knoten mit einem Taint. Effekte: `NoSchedule` (neue Pods abweisen), `PreferNoSchedule` (möglichst meiden), `NoExecute` (auch laufende Pods verdrängen).
- Entfernen durch angehängtes `-`: `kubectl taint nodes "$node" lab=demo:NoSchedule-`

Ein Pod ohne Toleration bleibt Pending (Demo):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — führt den nächsten Befehl aus, sobald der erste fertig ist; so siehst du den Status direkt nach dem Anlegen.
- Ohne Toleration bleibt er `Pending`; `kubectl describe pod notol` zeigt in den Events `untolerated taint`.

Demo-Pod löschen:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <Name>` — löscht den Pod. Bleibt der Test-Pod liegen, stört er spätere Prüfungen.

Pod mit Toleration anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `tolerations` — Taints, die dieser Pod toleriert; `key`, `value` und `effect` müssen zum Taint des Knotens passen.
- `operator: Equal` vergleicht auch den Wert; `Exists` akzeptiert jeden Wert für den Schlüssel.

Pod-Status prüfen:

```bash
kubectl get pod tolerant -o wide     # Running
```

- Dank der Toleration darf er auf dem Knoten mit Taint landen und wird `Running`.

> `NoSchedule` blockiert nur neue Pods; `NoExecute` verdrängt zusätzlich bestehende Pods, die den Taint
> nicht tolerieren.

## 3. DaemonSet

Ein **DaemonSet** hält auf jedem Knoten einen Pod (Log-Sammler, Knoten-Agenten). Da wir den Knoten mit
`lab` versehen haben, braucht auch der DaemonSet-Pod **eine Toleration**, um platziert zu werden.

DaemonSet anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
        - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
      containers:
        - name: agent
          image: busybox:1.36
          args: ["/bin/sh","-c","sleep 3600"]
          resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF
```

- `kind: DaemonSet` — kein `replicas`; hält auf jedem geeigneten Knoten genau einen Pod.
- `selector.matchLabels` muss zu `template.metadata.labels` passen.
- Wegen des `lab`-Taints auf dem Knoten werden auch hier dieselben `tolerations` benötigt.

DaemonSet-Status prüfen:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` ist die Kurzform von `daemonset`. `DESIRED` — Knoten, die einen Pod haben sollen, `CURRENT` — angelegte Pods, `READY` — bereite Pods.

Geschafft, wenn `DESIRED` und `READY` der Knotenzahl (1) entsprechen.

> Referenz: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
