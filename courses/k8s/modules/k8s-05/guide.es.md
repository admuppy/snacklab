# Peticiones y límites de recursos y QoS

Asigna a los contenedores **requests** (el mínimo que reserva el planificador) y **limits** (el techo: la CPU
se limita y la memoria se mata por OOM al superarlo). Su combinación sitúa al Pod en una de tres
**clases de QoS**, que decide el **orden de desalojo** cuando el nodo está bajo presión: primero se desaloja
`BestEffort`, luego `Burstable` y por último `Guaranteed`.

> Referencia: [Resource Management for Pods](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ·
> [Pod QoS Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)

## 1. Un Pod con QoS Guaranteed

Cuando todos los contenedores fijan **requests y limits iguales para cpu y memoria**, el Pod es
`Guaranteed`, la clase más protegida.

Crea el Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: guaranteed }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "250m", memory: "64Mi" }
        limits:   { cpu: "250m", memory: "64Mi" }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `resources.requests` — el mínimo que el planificador reserva en un nodo; `limits` — el techo estricto.
- `cpu: "250m"` — milinúcleos (1000m = 1 CPU); `memory: "64Mi"` — mebibytes binarios.
- Requests y limits iguales hacen que el Pod sea `Guaranteed`.

Comprueba la clase de QoS:

```bash
kubectl get pod guaranteed -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — extrae la clase de QoS (`Guaranteed`/`Burstable`/`BestEffort`) registrada en el estado del Pod.

## 2. Un Pod con QoS Burstable

Con requests fijados pero limits mayores (o solo parcialmente fijados), el Pod es `Burstable`: normalmente
usa sus requests y puede dispararse hasta sus limits cuando hay capacidad.

Crea el Pod:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: burstable }
spec:
  containers:
    - name: app
      image: nginx:1.26
      resources:
        requests: { cpu: "100m", memory: "32Mi" }
        limits:   { cpu: "500m", memory: "128Mi" }
EOF
```

- los limits (500m/128Mi) son mayores que los requests (100m/32Mi) → reserva poco y sube hasta los limits cuando el nodo tiene margen (`Burstable`).

Comprueba la clase de QoS:

```bash
kubectl get pod burstable -o jsonpath='{.status.qosClass}'; echo
```

- `{.status.qosClass}` — extrae la clase de QoS (`Guaranteed`/`Burstable`/`BestEffort`) registrada en el estado del Pod.

> Sin requests ni limits un Pod es `BestEffort` — prueba `kubectl run be --image=nginx:1.26`
> y después `kubectl get pod be -o jsonpath='{.status.qosClass}'`.

## 3. Valores por defecto con LimitRange

Un **LimitRange** fija requests/limits por defecto para un namespace, de modo que los Pods tengan límites de
recursos aunque un desarrollador los olvide. Debe existir **antes** que el Pod para que se inyecten los valores.

Crea el LimitRange:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: mem-defaults }
spec:
  limits:
    - type: Container
      default:        { memory: "128Mi", cpu: "200m" }   # limits por defecto
      defaultRequest: { memory: "64Mi",  cpu: "100m" }   # requests por defecto
EOF
```

- `kind: LimitRange` — reglas de recursos aplicadas a los contenedores creados en este namespace.
- `default` — limits que se rellenan cuando un contenedor no fija ninguno; `defaultRequest` — lo mismo para requests.
- Los valores se inyectan **al crear el Pod**, así que los Pods existentes no cambian.

Crea un Pod sin limits explícitos; el LimitRange los rellena:

```bash
kubectl run defaulted --image=nginx:1.26
```

- `kubectl run <nombre> --image=<imagen>` — crea un único Pod directamente, sin Deployment. Aquí los recursos se omiten a propósito.

Comprueba los recursos inyectados:

```bash
kubectl get pod defaulted -o jsonpath='{.spec.containers[0].resources}'; echo
```

- `{.spec.containers[0].resources}` — imprime como JSON todo el bloque de recursos del primer contenedor; los valores que no escribiste los rellenó el LimitRange.

Lo has logrado cuando el Pod `defaulted` tiene `resources.limits.memory` en `128Mi`.

> Referencia: [Configure Default Memory Requests and Limits (LimitRange)](https://kubernetes.io/docs/tasks/administer-cluster/manage-resources/memory-default-namespace/)
