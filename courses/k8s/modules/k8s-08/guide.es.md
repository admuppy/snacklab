# RBAC: control de acceso con mínimo privilegio

**RBAC (Role-Based Access Control)** decide "quién (sujeto) puede hacer qué (verbo) sobre qué
recurso". Un **Role** es un conjunto de permisos dentro de un namespace, un **ClusterRole** abarca todo el
clúster y un **RoleBinding/ClusterRoleBinding** asigna esos permisos a un usuario, un grupo o una
**ServiceAccount**. La regla guía es el **mínimo privilegio**: conceder solo lo necesario.

> Referencia: [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) ·
> [ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)

## 1. Crear una ServiceAccount

Crea una **ServiceAccount** `deployer`: la identidad que usa un Pod (aplicación) para autenticarse ante el
servidor de API.

Crea la ServiceAccount:

```bash
kubectl create serviceaccount deployer
```

- `kubectl create serviceaccount <nombre>` — crea una ServiceAccount en el namespace actual (`default`). Los Pods la usan mediante `spec.serviceAccountName`.
- Una ServiceAccount nueva no tiene permisos; se conceden con un RoleBinding.

Confirma que existe:

```bash
kubectl get sa deployer
```

- `sa` es la abreviatura de `serviceaccount`.

## 2. Role y RoleBinding

Crea un Role `pod-reader` que permita acceso de **solo lectura** (get/list/watch) a `pods` y un
RoleBinding `read-pods` que lo asigne a `deployer`.

Crea el Role y el RoleBinding:

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

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `---` — separa varios objetos (Role, RoleBinding) creados con un solo apply.
- `rules[].apiGroups: [""]` — el grupo de API core (pods, services, secrets, …). `resources` — objetivos, `verbs` — acciones permitidas.
- `subjects` — quién recibe los permisos (aquí una ServiceAccount); `roleRef` — qué Role. `roleRef` no se puede cambiar después de crearlo.

Revisa el RoleBinding:

```bash
kubectl describe rolebinding read-pods
```

- Muestra de un vistazo qué Role (`Role:`) está asignado a qué sujetos (`Subjects:`).

## 3. Verificar con auth can-i

Usa `kubectl auth can-i ... --as=<sujeto>` para probar los permisos efectivos. `deployer` debería
poder **listar** pods (yes) pero no **borrarlos** (no).

Define la variable del sujeto:

```bash
SA=system:serviceaccount:default:deployer
```

- El nombre de usuario de una ServiceAccount tiene la forma `system:serviceaccount:<namespace>:<nombre>`; la variable de shell `SA` evita teclearlo.

Prueba a listar pods:

```bash
kubectl auth can-i list   pods --as=$SA     # yes
```

- `kubectl auth can-i <verbo> <recurso>` — responde `yes`/`no` según si esa petición está permitida.
- `--as=$SA` — comprueba suplantando (impersonate) a ese sujeto en lugar de usar tus permisos de administrador.

Prueba a borrar pods:

```bash
kubectl auth can-i delete pods --as=$SA     # no
```

- `delete` no está en los `verbs` del Role, así que debe dar `no`.

Prueba a listar secrets:

```bash
kubectl auth can-i list   secrets --as=$SA  # no (no está en el Role)
```

- El Role solo cubre `pods`, así que cualquier otro recurso (`secrets`) da `no` sea cual sea el verbo. Ve la lista completa con `kubectl auth can-i --list --as=$SA`.

Lo has logrado cuando `list pods`→yes y `delete pods`→no, lo que confirma el mínimo privilegio.

> Referencia: [Checking API Access (`kubectl auth can-i`)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)
