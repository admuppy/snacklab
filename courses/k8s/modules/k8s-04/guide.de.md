# Probes und Selbstheilung

Der kubelet überwacht die Gesundheit von Containern mit drei Probes. Schlägt eine **livenessProbe** fehl, wird
der Container **neu gestartet** (Selbstheilung); schlägt eine **readinessProbe** fehl, wird der Pod aus den
Service-Endpunkten **herausgenommen** und erhält keinen Traffic. (Eine startupProbe schützt langsam startende Anwendungen.)

Der Container dieses Labs legt beim Start `/tmp/healthy` an und **löscht die Datei nach 30 Sekunden.**
Beide Probes prüfen diese Datei, daher schlägt nach 30 s die Liveness fehl, und du kannst den automatischen Neustart beobachten.

> Referenz: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. Eine livenessProbe definieren

Wende das folgende Deployment `web` an. Seine `livenessProbe` führt alle 5 s `cat /tmp/healthy` aus und
startet den Container nach einem einzigen Fehlschlag neu.

Deployment anwenden:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web, namespace: default }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          args: ["/bin/sh","-c","touch /tmp/healthy; sleep 30; rm -f /tmp/healthy; sleep 600"]
          livenessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 1
          readinessProbe:
            exec: { command: ["cat","/tmp/healthy"] }
            initialDelaySeconds: 3
            periodSeconds: 5
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `livenessProbe.exec.command` — führt diesen Befehl im Container aus; Exit-Code 0 bedeutet gesund (es gibt auch `httpGet`- und `tcpSocket`-Probes).
- `initialDelaySeconds` — Wartezeit vor der ersten Prüfung, `periodSeconds` — Intervall, `failureThreshold: 1` — Neustart nach einem einzigen Fehlschlag.
- Das Shell-Skript in `args` löscht `/tmp/healthy` nach 30 s, um absichtlich einen Fehler auszulösen.

Pod prüfen:

```bash
kubectl get pod -l app=web
```

- `READY` spiegelt die Readiness wider; `RESTARTS` zählt Neustarts durch Liveness-Fehlschläge.

## 2. Eine readinessProbe definieren

Das obige Manifest enthält auch eine `readinessProbe`. Ist der Pod bereit, zeigt er
`READY 1/1`.

Pod-Status prüfen:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — zusätzliche Spalten wie Pod-IP, Knoten und Readiness Gates.

Readiness-Probe ansehen:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — Details (einschließlich Probe-Einstellungen) der per Label ausgewählten Pods.
- `grep -A3 -i readiness` — Suche ohne Beachtung der Groß-/Kleinschreibung (`-i`) nach `readiness` plus die 3 Zeilen danach.

Solange die Readiness-Probe besteht, ist der Pod Ready; sobald die Datei weg ist, fällt er kurz auf
`READY 0/1` und ist nach dem Neustart wieder Ready.

## 3. Fehler auslösen → automatischer Neustart

Sobald die Datei verschwindet (nach 30 s), beginnt die Liveness zu scheitern. Beobachte den Pod, und `RESTARTS`
steigt.

Pod beobachten:

```bash
kubectl get pod -l app=web -w        # RESTARTS geht von 0 → 1 (Ctrl+C zum Beenden)
```

- `-w` (`--watch`) — statt nach einer Auflistung zu beenden, wird bei jeder Änderung eine neue Zeile ausgegeben. Mit `Ctrl+C` verlassen.

Probe-Events prüfen:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` ist ODER in einfachen regulären Ausdrücken; zeigt Probe-Fehlschläge (`Liveness`), beendete Container (`Killing`) und Neustarts (`Started`) zusammen.

Geschafft, sobald `RESTARTS` mindestens 1 ist. Um es sofort auszulösen, lösche die Datei selbst:
`kubectl exec deploy/web -- rm -f /tmp/healthy`.

> Referenz: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
