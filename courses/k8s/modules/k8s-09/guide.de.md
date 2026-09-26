# NetworkPolicy – Mikrosegmentierung

Standardmäßig kann in einem Cluster jeder Pod mit jedem anderen sprechen. Eine **NetworkPolicy** ist eine
Firewall auf Pod-Ebene: Für per Label ausgewählte Pods legt sie fest, welche **Quellen (from) / Ziele
(to)** erlaubt sind. Regeln sind eine **Allow-Liste** — sobald eine Policy einen Pod „auswählt", akzeptiert dieser
nur noch ausdrücklich erlaubten Traffic (alles andere wird abgelehnt).

In diesem Lab laufen bereits ein Server `web` (+Service `web`) und ein Client-Pod `client` (Label
`app=client`). k3s setzt NetworkPolicies tatsächlich durch.

web-Pod prüfen:

```bash
kubectl get pod -l app=web -o wide
```

- `-l app=web` wählt die Server-Pods aus, `-o wide` zeigt ihre IPs. NetworkPolicies wählen Pods über genau dieses Label aus.

Client-Pod prüfen:

```bash
kubectl get pod client -o wide
```

- Der Client-Pod. Prüfe sein Label `app=client` mit `kubectl get pod client --show-labels` — die Allow-Regel in Schritt 3 basiert darauf.

> Referenz: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. Grundlegende Verbindung prüfen

Prüfe ohne Policy, dass der Client web erreicht, und speichere diese Ausgangslage in
`~/work/baseline.txt` — du vergleichst in Schritt 2 und 3 damit.

Verbindung client → web testen:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # nginx-Antwort
```

- `kubectl exec client -- …` — sendet die Anfrage **aus dem** Client-Pod heraus, sodass der Client die Quelle ist.
- `wget -q -T 3 -O- http://web` — fragt den Service `web` mit 3 s Timeout (`-T 3`) an und schreibt die Antwort auf die Standardausgabe (`-O-`).
- `| head -1` — zeigt nur die erste Zeile.

Verzeichnis für die Aufzeichnung anlegen:

```bash
mkdir -p ~/work
```

- `mkdir -p` — legt fehlende übergeordnete Verzeichnisse an und schlägt nicht fehl, wenn es schon existiert.

Ausgangsantwort speichern:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> Datei` — speichert (überschreibt) die Standardausgabe des Befehls in einer Datei. Die Ausgabe von `kubectl exec` kommt in deinem Terminal an, also entsteht die Datei lokal.

Gespeicherten Inhalt prüfen:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <Datei>` — gibt nur die erste Zeile der Datei aus.

Erscheint die erste Zeile des nginx-HTML (`<!DOCTYPE html>`), ist die Verbindung offen.

## 2. Standardmäßig ablehnen (default-deny)

Lege eine Policy an, die die `web`-Pods **auswählt**, aber **keine Ingress-Regeln** hat — jeglicher eingehende
Traffic zu den ausgewählten Pods wird blockiert.

default-deny-Policy anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `podSelector` — die Pods, für die die Policy gilt (`app=web`); ein leerer Selektor `{}` bedeutet alle Pods im Namespace.
- `policyTypes: [Ingress]` ohne `ingress:`-Regeln → jeglicher eingehende Traffic zu den ausgewählten Pods wird abgelehnt.

Blockade prüfen (Timeout erwartet):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # Timeout (blockiert)
```

- `-t 1` — ein einziger Versuch. Bei Blockade endet er nach 3 s mit `timed out` (Pakete werden still verworfen, nicht abgewiesen).

Läuft `wget` in den Timeout, hat die Policy den Traffic unterbunden.

## 3. Von einer bestimmten Quelle erlauben

Füge jetzt eine Policy hinzu, die Port 80 nur von Pods mit dem Label `app=client` erlaubt. Policies wirken
additiv, daher legt sich diese Erlaubnis über das default-deny, und nur der Client kommt durch.

Allow-Policy anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

- `ingress[].from[].podSelector` — erlaubt als Quelle nur Pods mit dem Label `app=client` im selben Namespace.
- `ports` — erlaubter Port/Protokoll (TCP 80). Stehen `from` und `ports` im selben Eintrag, müssen beide zutreffen.
- Policies sind additiv (ODER), daher gilt diese Erlaubnis zusätzlich zum default-deny.

client → web erneut testen:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # funktioniert wieder
```

Geschafft, wenn client → web wieder funktioniert. Teste von einem anderen Pod ohne das Label `app=client`, und
es bleibt blockiert — das ist Mikrosegmentierung.

> Referenz: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
