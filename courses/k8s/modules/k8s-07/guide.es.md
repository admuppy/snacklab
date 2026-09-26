# Almacenamiento: PV, PVC y StatefulSet

Cuando un Pod muere, sus archivos se van con él. Para un almacenamiento duradero pides un
**PersistentVolume (PV)** — el almacenamiento real — mediante una **PersistentVolumeClaim (PVC)** — una
petición de "esta cantidad". Una **StorageClass** **aprovisiona dinámicamente** un PV cuando aparece una PVC.

Este k3s incluye una StorageClass por defecto `local-path`. Usa
`volumeBindingMode: WaitForFirstConsumer`, así que el PV se crea y se vincula solo **cuando se planifica un Pod
que consume la PVC**; al principio la PVC está en `Pending`, y es lo esperado.

```bash
kubectl get storageclass         # local-path (default)
```

- `storageclass` (abreviado `sc`) — configuración del aprovisionador que crea PVs bajo demanda. La marcada `(default)` se usa cuando una PVC no indica clase.
- La columna `VOLUMEBINDINGMODE` muestra `WaitForFirstConsumer`.

> Referencia: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) ·
> [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)

## 1. Crear una PVC

Crea una PVC `data` que pida 100Mi. Usa la StorageClass por defecto.

Crea la PVC:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 100Mi } }
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `accessModes: [ReadWriteOnce]` — montable en lectura/escritura por un solo nodo (RWO); para compartir entre nodos se usa `ReadWriteMany` (RWX).
- `resources.requests.storage: 100Mi` — tamaño solicitado. Se omite `storageClassName`, así que se usa la clase por defecto.

Comprueba el estado de la PVC:

```bash
kubectl get pvc data       # STATUS es Pending (WaitForFirstConsumer)
```

- `pvc` es la abreviatura de `persistentvolumeclaim`. Si `STATUS` pasa de `Pending` → `Bound`, está vinculada a un PV; la columna `VOLUME` indica a cuál.

`Pending` es correcto mientras no haya un Pod que la consuma. Se vinculará cuando un Pod la monte en el siguiente paso.

## 2. Montar, vincular y escribir

Crea el Pod `writer`, que monta la PVC `data` en `/data`. Cuando el Pod se planifica, la PVC pasa a
`Bound` y el contenedor escribe `/data/marker.txt`.

Crea el Pod que monta la PVC:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      args: ["/bin/sh","-c","echo 'persisted by writer' > /data/marker.txt; sleep 3600"]
      volumeMounts: [{ name: vol, mountPath: /data }]
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
```

- `volumes[].persistentVolumeClaim.claimName: data` — enlaza el volumen del Pod con la PVC `data`.
- `volumeMounts[].mountPath: /data` — lo monta en `/data` dentro del contenedor, que escribe un archivo nada más arrancar.

Espera a que el Pod esté Ready:

```bash
kubectl wait --for=condition=Ready pod/writer --timeout=90s
```

- `kubectl wait --for=condition=Ready` — espera a que el Pod esté Ready; `--timeout=90s` deja margen para aprovisionar el volumen.

Comprueba que la PVC está vinculada:

```bash
kubectl get pvc data                       # ahora Bound
```

Lee el archivo escrito:

```bash
kubectl exec writer -- cat /data/marker.txt
```

- `kubectl exec <pod> -- <comando>` — ejecuta un comando en el contenedor; aquí lee el archivo escrito en la PVC.

Lo has logrado cuando la PVC está `Bound` y se puede leer `/data/marker.txt`. Borra y vuelve a crear el Pod
(montando la misma PVC) y comprueba que el archivo sigue ahí: eso es persistencia.

## 3. StatefulSet con volumeClaimTemplates

Un **StatefulSet** da a cada Pod un nombre estable (web-0, web-1…) y su propia **PVC dedicada**.
Declarada en `volumeClaimTemplates`, se crea automáticamente una PVC por Pod (nombre: `<plantilla>-<pod>`,
aquí `www-web-0`).

Crea el StatefulSet:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web-h
  replicas: 1
  selector: { matchLabels: { app: sts-web } }
  template:
    metadata: { labels: { app: sts-web } }
    spec:
      containers:
        - name: app
          image: nginx:1.26
          volumeMounts: [{ name: www, mountPath: /usr/share/nginx/html }]
  volumeClaimTemplates:
    - metadata: { name: www }
      spec:
        accessModes: ["ReadWriteOnce"]
        resources: { requests: { storage: 100Mi } }
EOF
```

- `kind: StatefulSet` — los Pods reciben nombres ordinales fijos (`web-0`, `web-1`, …) y se crean/borran en orden.
- `serviceName: web-h` — el Service headless que proporciona DNS por Pod (`web-0.web-h`).
- `volumeClaimTemplates` — una plantilla que genera una PVC por Pod. Las PVCs sobreviven al borrado del Pod y se vuelven a enlazar al mismo Pod.

Espera a que termine el despliegue:

```bash
kubectl rollout status statefulset/web --timeout=120s
```

- `kubectl rollout status statefulset/web` — igual que con los Deployments, puedes esperar al despliegue de un StatefulSet.
- `--timeout=120s` — deja tiempo para aprovisionar el PV y descargar la imagen.

Comprueba la PVC creada automáticamente:

```bash
kubectl get pvc                 # www-web-0 está Bound
```

- `kubectl get pvc` sin nombre — todas las PVCs del namespace, incluida `www-web-0` generada desde la plantilla.

Lo has logrado cuando el Pod `web-0` está Ready y la PVC creada automáticamente `www-web-0` está `Bound`.

> Referencia: [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
