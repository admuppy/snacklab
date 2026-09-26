# Planificación: afinidad, taints y DaemonSets

El planificador decide qué nodo ejecuta un Pod. **nodeAffinity/nodeSelector** hace que un Pod *prefiera*
ciertos nodos; **taints/tolerations** hacen que un nodo *rechace* los Pods que no lo toleran: son herramientas
opuestas. Un **DaemonSet** coloca un Pod en cada nodo (que cumpla las condiciones).

Este clúster tiene un solo nodo. Obtén su nombre con:

```bash
node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo "$node"
```

- `$( ... )` — sustitución de comandos; `{.items[0].metadata.name}` extrae el nombre del primer nodo en la variable de shell `node`.
- `; echo "$node"` — lo imprime para confirmarlo. Los comandos siguientes lo usan como `"$node"`.

> Referencia: [Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) ·
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

## 1. Etiquetas de nodo y nodeAffinity

Etiqueta el nodo con `disktype=ssd` y crea el Pod `affine` que, mediante una nodeAffinity
`requiredDuringScheduling`, solo se coloca en nodos con esa etiqueta.

Etiqueta el nodo:

```bash
kubectl label node "$node" disktype=ssd
```

- `kubectl label <recurso> <nombre> clave=valor` — añade una etiqueta. Usa `--overwrite` para cambiar una clave existente y `clave-` para quitarla.

Crea el Pod con nodeAffinity:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: affine }
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - { key: disktype, operator: In, values: ["ssd"] }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `requiredDuringSchedulingIgnoredDuringExecution` — **debe** cumplirse al planificar; los Pods ya en ejecución no se desalojan si la etiqueta cambia después.
- `matchExpressions: {key: disktype, operator: In, values: [ssd]}` — solo cumplen los nodos cuya etiqueta `disktype` vale `ssd` (otros operadores: `NotIn`, `Exists`, …).

Comprueba dónde quedó el Pod:

```bash
kubectl get pod affine -o wide      # la columna NODE = nuestro nodo
```

- La columna `NODE` de `-o wide` muestra en qué nodo se colocó el Pod.

Si quitas la etiqueta (`kubectl label node "$node" disktype-`), un nuevo Pod igual queda en `Pending`;
pruébalo.

## 2. Taints y tolerations

Añade al nodo un **taint** `lab=demo:NoSchedule` y los Pods que no lo **toleran** no podrán
planificarse. Solo `tolerant`, que lleva una toleration, se coloca.

Aplica el taint al nodo:

```bash
kubectl taint nodes "$node" lab=demo:NoSchedule
```

- `kubectl taint nodes <nodo> clave=valor:efecto` — aplica un taint al nodo. Efectos: `NoSchedule` (rechaza Pods nuevos), `PreferNoSchedule` (evitar si es posible), `NoExecute` (también desaloja Pods en ejecución).
- Se quita añadiendo `-`: `kubectl taint nodes "$node" lab=demo:NoSchedule-`

Un Pod sin toleration se queda en Pending (demostración):

```bash
kubectl run notol --image=nginx:1.26; kubectl get pod notol      # Pending
```

- `;` — ejecuta el siguiente comando cuando termina el primero, así ves el estado del Pod justo después de crearlo.
- Sin toleration se queda en `Pending`; `kubectl describe pod notol` muestra `untolerated taint` en los eventos.

Borra el Pod de demostración:

```bash
kubectl delete pod notol
```

- `kubectl delete pod <nombre>` — borra el Pod. Si dejas el Pod de prueba, estorbará en comprobaciones posteriores.

Crea el Pod con toleration:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: tolerant }
spec:
  tolerations:
    - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
  containers:
    - { name: app, image: nginx:1.26 }
EOF
```

- `tolerations` — taints que este Pod puede tolerar; `key`, `value` y `effect` deben coincidir con el taint del nodo.
- `operator: Equal` compara también el valor; `Exists` acepta cualquier valor para la clave.

Comprueba el estado del Pod:

```bash
kubectl get pod tolerant -o wide     # Running
```

- Gracias a la toleration puede colocarse en el nodo con taint y pasa a `Running`.

> `NoSchedule` solo bloquea Pods nuevos; `NoExecute` además desaloja los Pods existentes que no toleran
> el taint.

## 3. DaemonSet

Un **DaemonSet** mantiene un Pod en cada nodo (recolectores de logs, agentes de nodo). Como aplicamos al nodo
el taint `lab`, el Pod del DaemonSet **también necesita una toleration** para colocarse.

Crea el DaemonSet:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-agent }
spec:
  selector: { matchLabels: { app: node-agent } }
  template:
    metadata: { labels: { app: node-agent } }
    spec:
      tolerations:
        - { key: lab, operator: Equal, value: demo, effect: NoSchedule }
      containers:
        - name: agent
          image: busybox:1.36
          args: ["/bin/sh","-c","sleep 3600"]
          resources: { requests: { cpu: "10m", memory: "16Mi" } }
EOF
```

- `kind: DaemonSet` — sin `replicas`; mantiene exactamente un Pod en cada nodo elegible.
- `selector.matchLabels` debe coincidir con `template.metadata.labels`.
- Por el taint `lab` del nodo, aquí también hacen falta las mismas `tolerations`.

Comprueba el estado del DaemonSet:

```bash
kubectl get ds node-agent           # DESIRED=CURRENT=READY=1
```

- `ds` es la abreviatura de `daemonset`. `DESIRED` — nodos que deberían ejecutar un Pod, `CURRENT` — Pods creados, `READY` — Pods listos.

Lo has logrado cuando `DESIRED` y `READY` igualan el número de nodos (1).

> Referencia: [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
