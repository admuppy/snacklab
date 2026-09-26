# Abschluss – ein kaputtes Deployment retten

Zwei E-Commerce-Anwendungen (`shop`, `cart`) sind bereitgestellt, aber **nichts läuft.** Drei verschiedene
Fehler sind eingebaut. In diesem Abschlussprojekt geht es nicht um neue Konzepte, sondern um Übung mit den
Diagnosewerkzeugen, die du gelernt hast (`kubectl get`, `describe`, `logs`, `get events`), um **die Ursachen
selbst zu finden und zu beheben.**

Verschaffe dir zuerst einen Überblick:

Alle Ressourcen überblicken:

```bash
kubectl get deploy,pods,svc
```

- Durch Kommas getrennte Arten werden in einem Rutsch aufgelistet. Sieh dir Deployment-`READY`, Pod-`STATUS` und die Services an, um zu erkennen, was nicht stimmt.

Letzte Events prüfen:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — was im Namespace passiert ist (Scheduling, Image-Pulls, Fehler, …).
- `--sort-by=.lastTimestamp` — nach letztem Auftreten sortieren; `| tail -20` — nur die 20 neuesten Zeilen.

> Referenz: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. Den Image-Pull-Fehler beheben

Die `shop`-Pods sind in `ImagePullBackOff`/`ErrImagePull`. Finde heraus, warum.

Status der shop-Pods prüfen:

```bash
kubectl get pods -l app=shop
```

- `ImagePullBackOff`/`ErrImagePull` in `STATUS` — der Knoten kann das Image nicht laden und wartet zwischen den Versuchen immer länger.

Ursache in den Events finden:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # ein "not found"-Tag taucht auf
```

- Die `Events` ganz unten in `describe` nennen den Fehler am direktesten; `grep -A5 -i events` zeigt nur diesen Teil.

Aktuellen Image-Tag prüfen:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — Image-Name:Tag, den das Deployment für seine Pods verwendet.

Den Image-Tag gibt es nicht. Ändere ihn auf einen gültigen Tag:

Image-Tag ersetzen:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — ersetzt das Image des Containers namens `web`; die Vorlage ändert sich, also werden neue Pods ausgerollt.

Auf den Rollout warten:

```bash
kubectl rollout status deploy/shop
```

- Wartet, bis alle neuen Pods Ready sind. Hängt es, `Ctrl+C` und mit `describe` erneut nach der Ursache suchen.

Ist `shop` 2/2 Ready, ist ① gelöst.

## 2. Den Service-Selektor beheben

Die Pods laufen jetzt, aber der Service `shop` leitet keinen Traffic weiter. Prüfe seine Endpunkte.

Endpunkte prüfen:

```bash
kubectl get endpoints shop            # <none> — keine Pods verbunden
```

- `<none>` unter `ENDPOINTS` bedeutet, dass kein Ready-Pod zum Service-Selektor passt.

Service-Selektor prüfen:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (Tippfehler)
```

- `{.spec.selector}` — die Label-Bedingung, mit der der Service Pods auswählt, als JSON.

Tatsächliche Pod-Labels prüfen:

```bash
kubectl get pods -l app=shop --show-labels                  # tatsächliches Label ist app=shop
```

- `--show-labels` — fügt eine Spalte `LABELS` mit allen Labels jedes Pods hinzu; vergleiche sie Zeichen für Zeichen mit dem Selektor.

Der Service-Selektor passt nicht zu den Pod-Labels. Korrigiere ihn:

Selektor korrigieren:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — ändert nur einige Felder einer Ressource direkt.
- `--type=merge` — führt das mit `-p` übergebene JSON mit dem Objekt zusammen (JSON Merge Patch).
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — der Patch enthält nur, was sich ändert; einfache Anführungszeichen verhindern, dass die Shell ihn interpretiert.

Endpunkte erneut prüfen:

```bash
kubectl get endpoints shop            # jetzt mit Pod-IPs gefüllt
```

Sind die Endpunkte gefüllt, ist ② gelöst.

## 3. Die fehlende ConfigMap beheben

Der `cart`-Pod hängt in `CreateContainerConfigError`. Finde heraus, warum.

Status des cart-Pods prüfen:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — das Image ist da, aber die Container-Konfiguration (eine referenzierte ConfigMap/ein Secret, …) lässt sich nicht erstellen.

Ursache in den Events finden:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- Die Events nennen das fehlende Objekt (`configmap "cart-config" not found`).

Referenziertes envFrom prüfen:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — die ConfigMaps/Secrets, die der Container komplett als Umgebungsvariablen importiert.

Es wird eine ConfigMap `cart-config` referenziert, die es nicht gibt. Lege sie an, und der kubelet startet den
Pod:

ConfigMap anlegen:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- Zwei `--from-literal=Schlüssel=Wert`-Optionen erzeugen eine ConfigMap mit zwei Schlüsseln. Sobald sie existiert, startet der kubelet beim nächsten Versuch den Container.

Auf den Rollout warten:

```bash
kubectl rollout status deploy/cart
```

Ist `cart` 1/1 Ready, ist ③ gelöst — alle drei Fehler behoben.

```bash
kubectl get deploy,svc,endpoints      # letzte Kontrolle
```

- Ein letzter Blick auf Deployment-READY, Services und Endpunkte, um zu bestätigen, dass alle drei Fehler behoben sind.
