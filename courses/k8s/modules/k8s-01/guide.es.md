# Deployments y despliegues progresivos

Un **Deployment** te permite declarar el estado deseado de un conjunto de Pods (réplicas, imagen); el
controlador converge hacia él y gestiona **actualizaciones progresivas sin interrupción** y **reversiones**
cuando cambia la imagen.

Este laboratorio se ejecuta en **tu propio clúster k3s de un solo nodo** dentro del pod. Puedes usar `kubectl`
directamente desde la terminal (el alias `k` y el autocompletado están configurados) y `KUBECONFIG` ya está
exportado.

Comprueba el nodo:

```bash
kubectl get nodes          # un nodo Ready
```

- `kubectl get <recurso>` — el comando básico de consulta; muestra los recursos en forma de tabla.
- `nodes` — las máquinas del clúster. `STATUS` debe ser `Ready` para que se programen Pods en ellas.

Comprueba el contexto actual:

```bash
kubectl config current-context
```

- `kubectl config` — subcomandos para el archivo kubeconfig (a qué clúster y con qué usuario habla kubectl).
- `current-context` — muestra el nombre del contexto (clúster + usuario + namespace) que kubectl usa ahora.

> Referencia: [Deployments (k8s.io)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

## 1. Crear un Deployment (3 réplicas)

Crea un Deployment llamado `web` con 3 réplicas de `nginx:1.25`.

Crea el Deployment:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
```

- `kubectl create deployment web` — crea el Deployment `web` de forma imperativa, sin YAML. Los Pods reciben automáticamente la etiqueta `app=web`.
- `--image=nginx:1.25` — imagen de contenedor de la plantilla del Pod (`nombre:etiqueta`).
- `--replicas=3` — número de Pods que se mantienen en ejecución (`spec.replicas`).

Espera a que termine el despliegue:

```bash
kubectl rollout status deploy/web            # espera hasta que todo esté Ready
```

- `kubectl rollout status` — espera a que termine el despliegue (todos los Pods nuevos Ready) y muestra el progreso.
- `deploy/web` — la forma `<tipo>/<nombre>`; `deploy` es la abreviatura de `deployment`.

Comprueba el Deployment:

```bash
kubectl get deploy web
```

- `READY` — Pods listos/deseados, `UP-TO-DATE` — Pods creados con la plantilla más reciente, `AVAILABLE` — Pods capaces de atender tráfico.

Lista los pods:

```bash
kubectl get pods -l app=web -o wide
```

- `-l app=web` — selector de etiquetas; solo los Pods etiquetados `app=web`.
- `-o wide` — añade columnas extra como la IP del Pod y el nodo donde se ejecuta.

Lo has logrado cuando la columna `READY` de `kubectl get deploy web` muestra `3/3`. Comprueba el ReplicaSet
que creó con `kubectl get rs`.

## 2. Actualización progresiva

Sube la imagen a `nginx:1.26`. El Deployment crea un nuevo ReplicaSet y sustituye los Pods de pocos en
pocos (por defecto `maxUnavailable=25%`, `maxSurge=25%`) sin interrupción del servicio.

Actualiza la imagen:

```bash
kubectl set image deploy/web '*=nginx:1.26'   # cambia la imagen de todos los contenedores
```

- `kubectl set image deploy/web <contenedor>=<imagen>` — cambia solo la imagen de la plantilla del Pod; una plantilla modificada inicia un nuevo despliegue.
- `'*=nginx:1.26'` — `*` significa todos los contenedores. Las comillas simples evitan que la shell expanda `*` a nombres de archivo.

Espera a que termine el despliegue:

```bash
kubectl rollout status deploy/web             # espera al despliegue
```

Revisa los eventos:

```bash
kubectl describe deploy web | grep -A2 Events # observa la sustitución en los eventos
```

- `kubectl describe` — detalles legibles de un recurso, incluidos los eventos recientes.
- `| grep -A2 Events` — conserva la línea `Events` y las 2 líneas posteriores (After); verás cómo se escalan el ReplicaSet antiguo y el nuevo.

Comprueba los ReplicaSets:

```bash
kubectl get rs                                # conviven el antiguo y el nuevo → el nuevo tiene 3
```

- `rs` — abreviatura de ReplicaSet. Cada cambio de plantilla crea un nuevo ReplicaSet; el antiguo se escala a 0 y se conserva para las reversiones.

Terminado cuando `kubectl rollout status` imprime `successfully rolled out`.

> Referencia: [Updating a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

## 3. Reversión

Supón que esa versión salió mal y **vuelve a la revisión anterior.** El Deployment guarda un
historial de revisiones, así que la reversión es inmediata.

Lista las revisiones:

```bash
kubectl rollout history deploy/web           # lista de revisiones
```

- `kubectl rollout history` — lista las revisiones (cambios de plantilla) que guarda el Deployment.
- Añade `--revision=<N>` para ver qué contenía una revisión concreta.

Vuelve a la revisión anterior:

```bash
kubectl rollout undo deploy/web              # vuelve a la anterior (nginx:1.25)
```

- `kubectl rollout undo` — inicia un nuevo despliegue con la plantilla de Pod de la revisión anterior. La propia reversión se registra como una nueva revisión.

Espera a que termine el despliegue:

```bash
kubectl rollout status deploy/web
```

Comprueba la imagen actual:

```bash
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `-o jsonpath='{...}'` — imprime solo los campos seleccionados con una expresión JSONPath; `{.spec.template.spec.containers[0].image}` es la imagen del primer contenedor.
- `; echo` — la salida de jsonpath no termina en salto de línea; así el prompt queda en su propia línea.

Lo has logrado cuando la imagen vuelve a ser `nginx:1.25` y se ha registrado una revisión más. Para ir
a una revisión concreta usa `kubectl rollout undo deploy/web --to-revision=<N>`.

> Referencia: [Rolling Back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
