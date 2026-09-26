# Sondas y autorreparación

El kubelet vigila la salud de los contenedores con tres sondas. Cuando falla una **livenessProbe**, el
contenedor se **reinicia** (autorreparación); cuando falla una **readinessProbe**, el Pod se **retira**
de los endpoints del Service y deja de recibir tráfico. (Una startupProbe protege a las aplicaciones que arrancan despacio.)

El contenedor de este laboratorio crea `/tmp/healthy` al arrancar y **lo borra a los 30 segundos.**
Ambas sondas comprueban ese archivo, así que a los 30 s falla la liveness y puedes ver el reinicio automático.

> Referencia: [Liveness, Readiness, Startup Probes](https://kubernetes.io/docs/concepts/configuration/liveness-readiness-startup-probes/) ·
> [Configure Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

## 1. Definir una livenessProbe

Aplica el Deployment `web` de abajo. Su `livenessProbe` ejecuta `cat /tmp/healthy` cada 5 s y
reinicia el contenedor tras un solo fallo.

Aplica el Deployment:

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

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `livenessProbe.exec.command` — ejecuta este comando en el contenedor; el código de salida 0 significa sano (también existen sondas `httpGet` y `tcpSocket`).
- `initialDelaySeconds` — espera antes de la primera comprobación, `periodSeconds` — intervalo, `failureThreshold: 1` — reinicio tras un solo fallo.
- El script de shell de `args` borra `/tmp/healthy` a los 30 s para provocar un fallo a propósito.

Comprueba el Pod:

```bash
kubectl get pod -l app=web
```

- `READY` refleja la readiness; `RESTARTS` cuenta los reinicios provocados por fallos de liveness.

## 2. Definir una readinessProbe

El manifiesto de arriba también incluye una `readinessProbe`. Cuando el Pod está listo muestra
`READY 1/1`.

Comprueba el estado del Pod:

```bash
kubectl get pod -l app=web -o wide
```

- `-o wide` — añade columnas como la IP del Pod, el nodo y las readiness gates.

Inspecciona la sonda de readiness:

```bash
kubectl describe pod -l app=web | grep -A3 -i readiness
```

- `kubectl describe pod -l app=web` — detalles (incluida la configuración de sondas) de los Pods seleccionados por etiqueta.
- `grep -A3 -i readiness` — coincidencia sin distinguir mayúsculas (`-i`) con `readiness` más las 3 líneas siguientes.

Mientras la sonda de readiness pasa, el Pod está Ready; cuando el archivo desaparece baja brevemente a
`READY 0/1` y vuelve a Ready tras el reinicio.

## 3. Provocar el fallo → reinicio automático

En cuanto desaparece el archivo (a los 30 s) la liveness empieza a fallar. Observa el Pod y verás cómo sube
`RESTARTS`.

Observa el Pod:

```bash
kubectl get pod -l app=web -w        # RESTARTS pasa de 0 → 1 (Ctrl+C para salir)
```

- `-w` (`--watch`) — en lugar de salir tras un listado, imprime una línea nueva cada vez que algo cambia. Sal con `Ctrl+C`.

Revisa los eventos de las sondas:

```bash
kubectl describe pod -l app=web | grep -A2 -i "Liveness\|Killing\|Started"
```

- `grep "A\|B\|C"` — `\|` es O lógico en la regex básica; muestra a la vez los fallos de sonda (`Liveness`), las detenciones de contenedor (`Killing`) y los rearranques (`Started`).

Lo has logrado cuando `RESTARTS` vale al menos 1. Para provocarlo al instante, borra tú el archivo:
`kubectl exec deploy/web -- rm -f /tmp/healthy`.

> Referencia: [Define a liveness command](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command)
