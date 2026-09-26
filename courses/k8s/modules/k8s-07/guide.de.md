# Storage – PV, PVC, StatefulSet

Stirbt ein Pod, sind seine Dateien weg. Für dauerhaften Speicher forderst du ein
**PersistentVolume (PV)** — den tatsächlichen Speicher — über einen **PersistentVolumeClaim (PVC)** an — eine
Anforderung über „so viel". Eine **StorageClass** **provisioniert dynamisch** ein PV, sobald ein PVC auftaucht.

Dieses k3s bringt die Standard-StorageClass `local-path` mit. Sie nutzt
`volumeBindingMode: WaitForFirstConsumer`, daher wird ein PV erst erzeugt und gebunden, **wenn ein Pod, der den
PVC nutzt, eingeplant wird** — anfangs ist der PVC `Pending`, und das ist so gewollt.

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass` (kurz `sc`) — Provisioner-Einstellungen, die PVs bei Bedarf erzeugen. Die mit `(default)` markierte wird genutzt, wenn ein PVC keine Klasse nennt.
- Die Spalte `VOLUMEBINDINGMODE` zeigt `WaitForFirstConsumer`.

> Referenz: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. Einen PVC anlegen

Lege einen PVC `data` an, der 100Mi anfordert. Er nutzt die Standard-StorageClass.

PVC anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 100Mi } }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `accessModes: [ReadWriteOnce]` — von einem einzigen Knoten les-/schreibbar einhängbar (RWO); für mehrere Knoten `ReadWriteMany` (RWX).
- `resources.requests.storage: 100Mi` — angeforderte Größe. `storageClassName` fehlt, also wird die Standardklasse genutzt.

PVC-Status prüfen:

```bash
kubectl get pvc data       # STATUS ist Pending (WaitForFirstConsumer)
```

- `pvc` ist die Kurzform von `persistentvolumeclaim`. Wechselt `STATUS` von `Pending` → `Bound`, ist er an ein PV gebunden; die Spalte `VOLUME` zeigt, an welches.

`Pending` ist richtig, solange kein Pod ihn nutzt. Er wird gebunden, sobald ihn im nächsten Schritt ein Pod einhängt.

## 2. Einhängen, binden und schreiben

Lege den Pod `writer` an, der den PVC `data` unter `/data` einhängt. Sobald der Pod eingeplant ist, wird der PVC
`Bound`, und der Container schreibt `/data/marker.txt`.

Pod anlegen, der den PVC einhängt:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      args: ["/bin/sh","-c","echo 'persisted by writer' > /data/marker.txt; sleep 3600"]
      volumeMounts: [{ name: vol, mountPath: /data }]
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
```

- `volumes[].persistentVolumeClaim.claimName: data` — verknüpft das Pod-Volume mit dem PVC `data`.
- `volumeMounts[].mountPath: /data` — hängt es im Container unter `/data` ein; der Container schreibt gleich beim Start eine Datei.

Warten, bis der Pod Ready ist:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — wartet, bis der Pod Ready ist; `--timeout=90s` lässt Zeit für die Volume-Provisionierung.

Prüfen, ob der PVC gebunden ist:

```bash
kubectl get pvc data                       # jetzt Bound
```

Geschriebene Datei lesen:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <Pod> -- <Befehl>` — führt einen Befehl im Container aus; hier wird die auf den PVC geschriebene Datei gelesen.

Geschafft, wenn der PVC `Bound` ist und `/data/marker.txt` lesbar ist. Lösche den Pod und lege ihn neu an
(mit demselben PVC) und prüfe, dass die Datei überlebt — das ist Persistenz.

## 3. StatefulSet mit volumeClaimTemplates

Ein **StatefulSet** gibt jedem Pod einen stabilen Namen (web-0, web-1…) und einen **eigenen PVC**.
In `volumeClaimTemplates` deklariert, wird pro Pod automatisch ein PVC angelegt (Namensschema: `<Vorlage>-<Pod>`,
hier `www-web-0`).

StatefulSet anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web-h
  replicas: 1
  selector: { matchLabels: { app: sts-web } }
  template:
    metadata: { labels: { app: sts-web } }
    spec:
      containers:
        - name: app
          image: nginx:1.26
          volumeMounts: [{ name: www, mountPath: /usr/share/nginx/html }]
  volumeClaimTemplates:
    - metadata: { name: www }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 100Mi } }
EOF
```

- `kind: StatefulSet` — Pods bekommen feste Ordinalnamen (`web-0`, `web-1`, …) und werden der Reihe nach angelegt/gelöscht.
- `serviceName: web-h` — der Headless Service, der DNS pro Pod liefert (`web-0.web-h`).
- `volumeClaimTemplates` — eine Vorlage, die pro Pod einen PVC erzeugt. PVCs überleben das Löschen des Pods und werden wieder an denselben Pod gebunden.

Auf den Rollout warten:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — wie bei Deployments kannst du auf den Rollout eines StatefulSets warten.
- `--timeout=120s` — lässt Zeit für PV-Provisionierung und Image-Pulls.

Automatisch angelegten PVC prüfen:

```bash
kubectl get pvc                 # www-web-0 ist Bound
```

- `kubectl get pvc` ohne Namen — alle PVCs im Namespace, einschließlich `www-web-0` aus der Vorlage.

Geschafft, wenn Pod `web-0` Ready und der automatisch angelegte PVC `www-web-0` `Bound` ist.

> Referenz: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
