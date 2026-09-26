# Services y red del clúster

Los Pods mueren y vuelven con IPs nuevas. Un **Service** selecciona un conjunto de Pods por etiqueta y les da
una IP virtual estable, un nombre DNS y balanceo de carga. En este laboratorio expones un Deployment existente
`web` (etiqueta `app=web`, 2 réplicas) mediante tres tipos de Service.

Comprueba el Deployment:

```bash
kubectl get deploy web
```

- `kubectl get deploy web` — confirma que existe el Deployment que vas a exponer y que todos los Pods están `READY`.

Comprueba los pods de backend:

```bash
kubectl get pods -l app=web -o wide     # IPs de los pods de backend
```

- `-l app=web` — lista los Pods con la misma etiqueta que usará el selector del Service.
- `-o wide` — muestra la columna de IP del Pod; compárala después con los endpoints del Service.

> Referencia: [Service (k8s.io)](https://kubernetes.io/docs/concepts/services-networking/service/) ·
> [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

## 1. Exponer con ClusterIP

El tipo por defecto **ClusterIP** crea una IP virtual accesible solo desde dentro del clúster.
Llama al Service `web`, puerto 80.

Crea el Service:

```bash
kubectl expose deployment web --name=web --port=80 --target-port=80
```

- `kubectl expose deployment web` — crea un Service reutilizando el selector de Pods del Deployment (`app=web`).
- `--name=web` — el nombre del Service, que también se convierte en su nombre DNS.
- `--port=80` — puerto en el que escucha el Service; `--target-port=80` — puerto del contenedor al que se reenvía el tráfico.
- Sin `--type`, el valor por defecto es `ClusterIP`.

Comprueba el Service:

```bash
kubectl get svc web
```

- `svc` es la abreviatura de `service`. `CLUSTER-IP` es la IP virtual accesible solo dentro del clúster.

Comprueba los endpoints:

```bash
kubectl get endpoints web           # lista IP:puerto de los pods elegidos por el selector
```

- `endpoints` — los backends (IP:puerto de Pod) a los que el Service envía realmente el tráfico. Solo aparecen los Pods **Ready** que coinciden con el selector.

Prueba desde dentro del clúster:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  wget -qO- http://web.default.svc.cluster.local
```

- `kubectl run t --image=busybox:1.36` — arranca un Pod de prueba desechable llamado `t`.
- `--restart=Never --rm -it` — se ejecuta una sola vez sin reinicios, conecta tu terminal (`-it`) para ver la salida y borra el Pod al terminar (`--rm`).
- Todo lo que va después de `--` es el comando que se ejecuta dentro del contenedor. La `\` final continúa el mismo comando en la línea siguiente.
- `wget -qO- <URL>` — descarga en silencio (`-q`) y escribe en la salida estándar (`-O-`) en lugar de un archivo.
- `web.default.svc.cluster.local` — nombre DNS del Service con la forma `<servicio>.<namespace>.svc.cluster.local`.

El enrutamiento funciona cuando `kubectl get endpoints web` muestra IPs de pods. Si los endpoints están vacíos,
el selector (`app=web`) no coincide con las etiquetas de los pods.

## 2. Exponer con NodePort

**NodePort** abre un puerto fijo (por defecto 30000–32767) en todos los nodos para que el Service sea accesible
desde fuera del clúster. Crea el Service `web-np`.

Crea el Service NodePort:

```bash
kubectl expose deployment web --name=web-np --type=NodePort --port=80 --target-port=80
```

- `--type=NodePort` — además del ClusterIP, abre **el mismo puerto en todos los nodos** (elegido automáticamente entre 30000–32767) para acceder desde fuera del clúster.
- `--name=web-np` — un nombre distinto para no chocar con el Service `web`.

Comprueba el puerto asignado:

```bash
kubectl get svc web-np                          # PORT(S) muestra 80:3xxxx/TCP
```

- En `PORT(S)` `80:3xxxx/TCP`, el primer número es el puerto del Service y el segundo el nodePort abierto en los nodos.

Guarda el nodePort en una variable:

```bash
np=$(kubectl get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
```

- `$( ... )` — sustitución de comandos; guarda la salida del comando en la variable de shell `np`.
- `{.spec.ports[0].nodePort}` — JSONPath del nodePort de la primera entrada de puertos.

Accede desde el nodo:

```bash
curl -s http://127.0.0.1:$np | head -1          # accede desde el nodo (este pod)
```

- `curl -s` — envía la petición HTTP en silencio (sin barra de progreso); `$np` se expande al nodePort guardado antes.
- `127.0.0.1` — en este laboratorio tu terminal es el nodo, así que usas la propia dirección del nodo.
- `| head -1` — muestra solo la primera línea de la respuesta.

Lo has logrado cuando se asigna un nodePort `80:3xxxx/TCP` y curl devuelve la respuesta de nginx.

## 3. Service headless y DNS

Un **Service headless** (`clusterIP: None`) no tiene IP virtual ni proxy; una consulta DNS devuelve
directamente la **IP de cada Pod** como registros A. Se usa para direccionar pods individuales (p. ej. StatefulSets).

Crea el Service headless:

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

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `clusterIP: None` — declara un Service headless: sin IP virtual; las IPs de los Pods seleccionados van directamente al DNS.

Comprueba el CLUSTER-IP:

```bash
kubectl get svc web-h                 # CLUSTER-IP es None
```

- Un `CLUSTER-IP` `None` significa headless; kube-proxy no lo balancea.

Prueba la consulta DNS:

```bash
kubectl run t --image=busybox:1.36 --restart=Never --rm -it -- \
  nslookup web-h.default.svc.cluster.local   # un registro A por pod
```

- `kubectl run t --image=busybox:1.36` — arranca un Pod de prueba desechable llamado `t`.
- `--restart=Never --rm -it` — se ejecuta una sola vez sin reinicios, conecta tu terminal (`-it`) para ver la salida y borra el Pod al terminar (`--rm`).
- Todo lo que va después de `--` es el comando que se ejecuta dentro del contenedor. La `\` final continúa el mismo comando en la línea siguiente.
- `nslookup <nombre>` — consulta el DNS e imprime los registros A (IPs). Un Service headless devuelve uno por Pod.

Lo has logrado cuando `CLUSTER-IP` es `None` y nslookup devuelve una IP por pod.

> Referencia: [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)
