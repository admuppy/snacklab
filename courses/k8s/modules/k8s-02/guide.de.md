# Services und Cluster-Netzwerk

Pods sterben und kommen mit neuen IPs zurück. Ein **Service** wählt per Label eine Gruppe von Pods aus und gibt
ihnen eine stabile virtuelle IP, einen DNS-Namen und Lastverteilung. In diesem Lab stellst du das bestehende
Deployment `web` (Label `app=web`, 2 Replicas) über drei Service-Typen bereit.

Deployment prüfen:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — prüft, dass das bereitzustellende Deployment existiert und alle Pods `READY` sind.

Backend-Pods prüfen:

```bash
kubectl get pods -l app=web -o wide     # IPs der Backend-Pods
```

- `-l app=web` — listet die Pods mit demselben Label auf, das der Service-Selektor verwenden wird.
- `-o wide` — zeigt die Spalte mit der Pod-IP; vergleiche sie später mit den Service-Endpunkten.

> Referenz: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. Mit ClusterIP bereitstellen

Der Standardtyp **ClusterIP** erzeugt eine virtuelle IP, die nur innerhalb des Clusters erreichbar ist.
Nenne den Service `web`, Port 80.

Service anlegen:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — legt einen Service an und übernimmt den Pod-Selektor des Deployments (`app=web`).
- `--name=web` — der Service-Name, der zugleich sein DNS-Name wird.
- `--port=80` — Port, auf dem der Service lauscht; `--target-port=80` — Container-Port, an den der Traffic weitergeleitet wird.
- Ohne `--type` ist der Standard `ClusterIP`.

Service prüfen:

```bash
kubectl get svc web
```

- `svc` ist die Kurzform von `service`. `CLUSTER-IP` ist die nur clusterintern erreichbare virtuelle IP.

Endpunkte prüfen:

```bash
kubectl get endpoints web           # vom Selektor gewählte Pod-IP:Port-Liste
```

- `endpoints` — die Backends (Pod-IP:Port), an die der Service tatsächlich Traffic sendet. Nur **Ready**-Pods, die zum Selektor passen, erscheinen hier.

Aus dem Cluster heraus testen:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — startet einen Wegwerf-Test-Pod namens `t`.
- `--restart=Never --rm -it` — läuft einmal ohne Neustarts, hängt dein Terminal an (`-it`), damit du die Ausgabe siehst, und löscht den Pod danach (`--rm`).
- Alles nach `--` ist der Befehl, der im Container ausgeführt wird. Der abschließende `\` setzt denselben Befehl in der nächsten Zeile fort.
- `wget -qO- <URL>` — lädt still (`-q`) und schreibt auf die Standardausgabe (`-O-`) statt in eine Datei.
- `web.default.svc.cluster.local` — DNS-Name des Service in der Form `<Service>.<Namespace>.svc.cluster.local`.

Das Routing funktioniert, sobald `kubectl get endpoints web` Pod-IPs anzeigt. Leere Endpunkte bedeuten, dass der
Selektor (`app=web`) nicht zu den Pod-Labels passt.

## 2. Mit NodePort bereitstellen

**NodePort** öffnet auf jedem Knoten einen festen Port (Standard 30000–32767), damit der Service auch von
außerhalb des Clusters erreichbar ist. Lege den Service `web-np` an.

NodePort-Service anlegen:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — öffnet zusätzlich zur ClusterIP **denselben Port auf jedem Knoten** (automatisch aus 30000–32767 gewählt) für Zugriffe von außerhalb des Clusters.
- `--name=web-np` — ein anderer Name, damit es keinen Konflikt mit dem Service `web` gibt.

Zugewiesenen Port prüfen:

```bash
kubectl get svc web-np                          # PORT(S) zeigt 80:3xxxx/TCP
```

- In `PORT(S)` `80:3xxxx/TCP` ist die erste Zahl der Service-Port, die zweite der auf den Knoten geöffnete nodePort.

nodePort in einer Variablen speichern:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — Befehlssubstitution; speichert die Ausgabe des Befehls in der Shell-Variablen `np`.
- `{.spec.ports[0].nodePort}` — JSONPath für den nodePort des ersten Port-Eintrags.

Direkt auf dem Knoten zugreifen:

```bash
curl -s http://127.0.0.1:$np | head -1          # direkt auf dem Knoten (diesem Pod) aufrufen
```

- `curl -s` — sendet die HTTP-Anfrage still (ohne Fortschrittsbalken); `$np` wird zum oben gespeicherten nodePort.
- `127.0.0.1` — in diesem Lab ist dein Terminal der Knoten, daher die eigene Adresse des Knotens.
- `| head -1` — zeigt nur die erste Zeile der Antwort.

Geschafft, wenn ein nodePort `80:3xxxx/TCP` zugewiesen ist und curl die nginx-Antwort liefert.

## 3. Headless Service und DNS

Ein **Headless Service** (`clusterIP: None`) hat weder virtuelle IP noch Proxy; eine DNS-Abfrage liefert
direkt die **IP jedes Pods** als A-Records. Wird für die Adressierung einzelner Pods genutzt (z. B. StatefulSets).

Headless Service anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: web-h, namespace: default }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `clusterIP: None` — deklariert einen Headless Service: keine virtuelle IP; die IPs der ausgewählten Pods landen direkt im DNS.

CLUSTER-IP prüfen:

```bash
kubectl get svc web-h                 # CLUSTER-IP ist None
```

- `CLUSTER-IP` `None` bedeutet headless; kube-proxy verteilt dafür keine Last.

DNS-Abfrage testen:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # ein A-Record pro Pod
```

- `kubectl run t --image=busybox:1.36` — startet einen Wegwerf-Test-Pod namens `t`.
- `--restart=Never --rm -it` — läuft einmal ohne Neustarts, hängt dein Terminal an (`-it`), damit du die Ausgabe siehst, und löscht den Pod danach (`--rm`).
- Alles nach `--` ist der Befehl, der im Container ausgeführt wird. Der abschließende `\` setzt denselben Befehl in der nächsten Zeile fort.
- `nslookup <Name>` — fragt das DNS ab und gibt die A-Records (IPs) aus. Ein Headless Service liefert einen pro Pod.

Geschafft, wenn `CLUSTER-IP` `None` ist und nslookup eine IP pro Pod liefert.

> Referenz: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
