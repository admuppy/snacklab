# RBAC – Zugriffssteuerung mit minimalen Rechten

**RBAC (Role-Based Access Control)** legt fest, „wer (Subjekt) was (Verb) mit welcher Ressource tun darf".
Eine **Role** bündelt Berechtigungen innerhalb eines Namespace, eine **ClusterRole** gilt clusterweit, und ein
**RoleBinding/ClusterRoleBinding** weist diese Berechtigungen einem Benutzer, einer Gruppe oder einem
**ServiceAccount** zu. Leitregel ist **Least Privilege** — nur vergeben, was nötig ist.

> Referenz: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. Einen ServiceAccount anlegen

Lege einen **ServiceAccount** `deployer` an — die Identität, mit der sich ein Pod (eine Anwendung) beim
API-Server authentifiziert.

ServiceAccount anlegen:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <Name>` — legt einen ServiceAccount im aktuellen Namespace (`default`) an. Pods nutzen ihn über `spec.serviceAccountName`.
- Ein neuer ServiceAccount hat keine Berechtigungen; sie werden per RoleBinding vergeben.

Prüfen, ob er existiert:

```bash
kubectl get sa deployer
```

- `sa` ist die Kurzform von `serviceaccount`.

## 2. Role und RoleBinding

Lege eine Role `pod-reader` an, die **nur lesenden** Zugriff (get/list/watch) auf `pods` erlaubt, und ein
RoleBinding `read-pods`, das sie `deployer` zuweist.

Role und RoleBinding anlegen:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: pod-reader, namespace: default }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: read-pods, namespace: default }
subjects:
  - { kind: ServiceAccount, name: deployer, namespace: default }
roleRef:
  { kind: Role, name: pod-reader, apiGroup: rbac.authorization.k8s.io }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — übergibt kubectl das YAML bis zur Zeile `EOF` über stdin. `-f -` bedeutet „stdin statt Datei lesen"; das Quoting von `'EOF'` verhindert, dass die Shell `$` im Text expandiert.
- `---` — trennt mehrere Objekte (Role, RoleBinding), die mit einem apply angelegt werden.
- `rules[].apiGroups: [""]` — die Core-API-Gruppe (pods, services, secrets, …). `resources` — Ziele, `verbs` — erlaubte Aktionen.
- `subjects` — wer die Berechtigungen erhält (hier ein ServiceAccount); `roleRef` — welche Role. `roleRef` lässt sich nach dem Anlegen nicht ändern.

RoleBinding ansehen:

```bash
kubectl describe rolebinding read-pods
```

- Zeigt auf einen Blick, welche Role (`Role:`) an welche Subjekte (`Subjects:`) gebunden ist.

## 3. Mit auth can-i überprüfen

Mit `kubectl auth can-i ... --as=<Subjekt>` testest du die tatsächlichen Berechtigungen. `deployer` soll
Pods **auflisten** dürfen (yes), aber nicht **löschen** (no).

Subjekt-Variable setzen:

```bash
SA=system:serviceaccount:default:deployer
```

- Der Benutzername eines ServiceAccounts hat die Form `system:serviceaccount:<Namespace>:<Name>`; die Shell-Variable `SA` erspart das Tippen.

Auflisten von Pods testen:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <Verb> <Ressource>` — antwortet mit `yes`/`no`, ob diese Anfrage erlaubt ist.
- `--as=$SA` — prüft, indem es dieses Subjekt imitiert (impersonate), statt deine Admin-Rechte zu nutzen.

Löschen von Pods testen:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` steht nicht in den `verbs` der Role, also muss hier `no` herauskommen.

Auflisten von Secrets testen:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (nicht in der Role)
```

- Die Role deckt nur `pods` ab, daher ist jede andere Ressource (`secrets`) unabhängig vom Verb `no`. Die vollständige Liste zeigt `kubectl auth can-i --list --as=$SA`.

Geschafft, wenn `list pods`→yes und `delete pods`→no ergibt — Least Privilege greift.

> Referenz: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
