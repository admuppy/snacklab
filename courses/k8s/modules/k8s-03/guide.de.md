# ConfigMaps und Secrets

Konfiguration gehört nicht in den Code. Eine **ConfigMap** enthält Klartext-Konfiguration; ein **Secret** enthält
sensible Werte (Passwörter, Tokens) base64-kodiert. Beide lassen sich als **Umgebungsvariablen** oder als
**Dateien in einem Volume** in einen Pod einspeisen.

> Referenz: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. Eine ConfigMap anlegen

Lege eine ConfigMap `app-config` mit den Schlüsseln `APP_MODE` und `APP_GREETING` an.

ConfigMap anlegen:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — legt die ConfigMap `app-config` imperativ an. Ein abschließender `\` verteilt einen Befehl auf mehrere Zeilen.
- `--from-literal=Schlüssel=Wert` — fügt ein Schlüssel/Wert-Paar direkt hinzu; wiederholbar. Werte mit Leerzeichen in Anführungszeichen setzen.
- Aus Dateien `--from-file=<Pfad>`, aus einer env-Datei `--from-env-file=<Pfad>`.

Inhalt ansehen:

```bash
kubectl get cm app-config -o yaml
```

- `cm` ist die Kurzform von `configmap`. `-o yaml` zeigt das gespeicherte Objekt unverändert (Schlüssel/Werte unter `data:`).

Prüfe mit `kubectl describe cm app-config`, dass beide Schlüssel angekommen sind.

## 2. Ein Secret anlegen

Lege ein **Opaque**-Secret `app-secret` mit dem Schlüssel `DB_PASSWORD` an. `create secret generic`
kodiert den Wert automatisch in base64.

Secret anlegen:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — legt ein Secret vom Typ `Opaque` für beliebige Schlüssel/Werte an (weitere Typen: `tls`, `docker-registry`).
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — der Wert wird beim Speichern automatisch base64-kodiert. Einfache Anführungszeichen verhindern, dass die Shell Sonderzeichen interpretiert.

Kodierten Wert prüfen:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — holt nur den Wert eines Schlüssels (einen base64-String) aus `data` des Secrets.

Dekodieren und prüfen:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — dekodiert (`-d`) das base64 zurück in den Originalwert. Wer das Secret lesen darf, sieht den Klartext.

> Hinweis: Secret-Daten sind kodiert, nicht verschlüsselt. Im Betrieb schränkt man den Zugriff mit
> etcd-Verschlüsselung und RBAC ein — [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. In einem Pod verwenden

Lege einen Pod `app` an, der die **ConfigMap als Umgebungsvariablen (envFrom)** einspeist und das
**Secret als Dateien** unter `/etc/app-secret` einhängt.

Pod anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: default }
spec:
  containers:
    - name: app
      image: nginx:1.26
      envFrom:
        - configMapRef: { name: app-config }
      volumeMounts:
        - { name: secret-vol, mountPath: /etc/app-secret, readOnly: true }
  volumes:
    - name: secret-vol
      secret: { secretName: app-secret }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `envFrom.configMapRef` — speist **jeden Schlüssel** der ConfigMap als gleichnamige Umgebungsvariable ein (für einen einzelnen Schlüssel `env[].valueFrom.configMapKeyRef`).
- `volumes[].secret` + `volumeMounts` — hängt jeden Secret-Schlüssel als Datei `/etc/app-secret/<Schlüssel>` ein.

Warten, bis Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — wartet, bis die `Ready`-Bedingung des Pods wahr ist.
- `--timeout=60s` — bricht danach mit einem Fehler ab.

Umgebungsvariablen prüfen:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → Umgebungsvariablen
```

- `kubectl exec app -- <Befehl>` — führt einen Befehl im laufenden Container aus; alles nach `--` läuft im Container.
- `printenv A B` — gibt nur die genannten Umgebungsvariablen aus.

Secret-Datei prüfen:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → Datei
```

- Ein als Volume eingehängtes Secret erscheint als bereits dekodierte Klartextdateien; jeder Schlüsselname ist ein Dateiname.

Geschafft, wenn die Umgebungsvariablen sichtbar sind und die Datei `/etc/app-secret/DB_PASSWORD` existiert.

> Referenz: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
