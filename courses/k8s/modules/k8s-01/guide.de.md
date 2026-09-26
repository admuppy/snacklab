# Deployments und Rollouts

Mit einem **Deployment** deklarierst du den Sollzustand einer Gruppe von Pods (Replicas, Image); der
Controller führt den Cluster dorthin und verwaltet **unterbrechungsfreie Rolling Updates** und **Rollbacks**,
wenn sich das Image ändert.

Dieses Lab läuft auf **deinem eigenen Single-Node-k3s-Cluster** im Pod. Du kannst `kubectl` direkt im
Terminal verwenden (Alias `k` und Autovervollständigung sind eingerichtet), und `KUBECONFIG` ist bereits
gesetzt.

Knoten prüfen:

```bash
kubectl get nodes          # ein Ready-Knoten
```

- `kubectl get <Ressource>` — der grundlegende Abfragebefehl; listet Ressourcen als Tabelle auf.
- `nodes` — die Maschinen im Cluster. `STATUS` muss `Ready` sein, damit dort Pods eingeplant werden.

Aktuellen Kontext prüfen:

```bash
kubectl config current-context
```

- `kubectl config` — Unterbefehle für die kubeconfig-Datei (mit welchem Cluster und Benutzer kubectl spricht).
- `current-context` — gibt den Namen des Kontexts (Cluster + Benutzer + Namespace) aus, den kubectl gerade nutzt.

> Referenz: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Ein Deployment anlegen (3 Replicas)

Lege ein Deployment namens `web` mit 3 Replicas von `nginx:1.25` an.

Deployment anlegen:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — legt das Deployment `web` imperativ an, ganz ohne YAML. Die Pods erhalten automatisch das Label `app=web`.
- `--image=nginx:1.25` — Container-Image der Pod-Vorlage (`Name:Tag`).
- `--replicas=3` — Anzahl der Pods, die dauerhaft laufen sollen (`spec.replicas`).

Auf den Rollout warten:

```bash
kubectl rollout status deploy/web            # warten, bis alle Ready sind
```

- `kubectl rollout status` — wartet, bis der Rollout fertig ist (alle neuen Pods Ready), und zeigt den Fortschritt.
- `deploy/web` — die Form `<Art>/<Name>`; `deploy` ist die Kurzform von `deployment`.

Deployment prüfen:

```bash
kubectl get deploy web
```

- `READY` — bereite/gewünschte Pods, `UP-TO-DATE` — Pods aus der neuesten Vorlage, `AVAILABLE` — Pods, die Traffic bedienen können.

Pods auflisten:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — Label-Selektor; nur Pods mit dem Label `app=web`.
- `-o wide` — zusätzliche Spalten wie Pod-IP und den Knoten, auf dem der Pod läuft.

Geschafft, wenn die Spalte `READY` von `kubectl get deploy web` `3/3` zeigt. Prüfe das erzeugte
ReplicaSet mit `kubectl get rs`.

## 2. Rolling Update

Hebe das Image auf `nginx:1.26` an. Das Deployment erzeugt ein neues ReplicaSet und tauscht die Pods
schrittweise aus (Standard `maxUnavailable=25%`, `maxSurge=25%`) – ohne Ausfallzeit.

Image aktualisieren:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # Image in allen Containern ersetzen
```

- `kubectl set image deploy/web <Container>=<Image>` — ändert nur das Image in der Pod-Vorlage; eine geänderte Vorlage startet einen neuen Rollout.
- `'*=nginx:1.26'` — `*` steht für alle Container. Die einfachen Anführungszeichen verhindern, dass die Shell `*` zu Dateinamen expandiert.

Auf den Rollout warten:

```bash
kubectl rollout status deploy/web             # auf den Rollout warten
```

Events prüfen:

```bash
kubectl describe deploy web | grep -A2 Events # den Austausch in den Events verfolgen
```

- `kubectl describe` — gut lesbare Details einer Ressource, einschließlich der letzten Events.
- `| grep -A2 Events` — behält die Zeile `Events` und die 2 Zeilen danach (After); man sieht, wie altes und neues ReplicaSet skaliert werden.

ReplicaSets prüfen:

```bash
kubectl get rs                                # altes/neues ReplicaSet nebeneinander → nur das neue hat 3
```

- `rs` — Kurzform von ReplicaSet. Jede Vorlagenänderung erzeugt ein neues ReplicaSet; das alte wird auf 0 skaliert und für Rollbacks aufbewahrt.

Fertig, wenn `kubectl rollout status` `successfully rolled out` ausgibt.

> Referenz: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. Rollback

Angenommen, das Release war fehlerhaft: **Kehre zur vorherigen Revision zurück.** Das Deployment
speichert eine Revisionshistorie, daher geht der Rollback sofort.

Revisionen auflisten:

```bash
kubectl rollout history deploy/web           # Revisionen auflisten
```

- `kubectl rollout history` — listet die Revisionen (Vorlagenänderungen), die das Deployment aufbewahrt.
- Mit `--revision=<N>` siehst du, was eine bestimmte Revision enthielt.

Zur vorherigen Revision zurückkehren:

```bash
kubectl rollout undo deploy/web              # zurück zur vorherigen (nginx:1.25)
```

- `kubectl rollout undo` — startet einen neuen Rollout mit der Pod-Vorlage der vorherigen Revision. Der Rollback selbst wird als neue Revision erfasst.

Auf den Rollout warten:

```bash
kubectl rollout status deploy/web
```

Aktuelles Image prüfen:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — gibt nur die per JSONPath-Ausdruck gewählten Felder aus; `{.spec.template.spec.containers[0].image}` ist das Image des ersten Containers.
- `; echo` — die jsonpath-Ausgabe endet ohne Zeilenumbruch; so steht der Prompt wieder in einer eigenen Zeile.

Geschafft, wenn das Image wieder `nginx:1.25` ist und eine weitere Revision erfasst wurde. Für eine
bestimmte Revision verwende `kubectl rollout undo deploy/web --to-revision=<N>`.

> Referenz: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
