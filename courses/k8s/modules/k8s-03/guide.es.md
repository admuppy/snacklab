# ConfigMaps y Secrets

Mantén la configuración fuera del código. Un **ConfigMap** guarda configuración en claro; un **Secret** guarda
valores sensibles (contraseñas, tokens) codificados en base64. Ambos pueden inyectarse en un Pod como
**variables de entorno** o como **archivos en un volumen**.

> Referencia: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) ·
> [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

## 1. Crear un ConfigMap

Crea un ConfigMap `app-config` con las claves `APP_MODE` y `APP_GREETING`.

Crea el ConfigMap:

```bash
kubectl create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=APP_GREETING="hello from configmap"
```

- `kubectl create configmap app-config` — crea el ConfigMap `app-config` de forma imperativa. La `\` final continúa un mismo comando en varias líneas.
- `--from-literal=clave=valor` — añade un par clave/valor directamente; se puede repetir. Entrecomilla los valores con espacios.
- Desde archivos usa `--from-file=<ruta>`; desde un archivo env usa `--from-env-file=<ruta>`.

Revisa el contenido:

```bash
kubectl get cm app-config -o yaml
```

- `cm` es la abreviatura de `configmap`. `-o yaml` muestra el objeto guardado tal cual (claves/valores bajo `data:`).

Confirma que están las dos claves con `kubectl describe cm app-config`.

## 2. Crear un Secret

Crea un Secret **Opaque** `app-secret` con la clave `DB_PASSWORD`. `create secret generic`
codifica el valor en base64 automáticamente.

Crea el Secret:

```bash
kubectl create secret generic app-secret --from-literal=DB_PASSWORD='s3cr3t-pw'
```

- `kubectl create secret generic` — crea un Secret de tipo `Opaque` para claves/valores arbitrarios (otros tipos: `tls`, `docker-registry`).
- `--from-literal=DB_PASSWORD='s3cr3t-pw'` — el valor se codifica en base64 automáticamente al guardarlo. Las comillas simples evitan que la shell interprete caracteres especiales.

Comprueba el valor codificado:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}'; echo   # base64
```

- `{.data.DB_PASSWORD}` — extrae solo el valor de una clave (una cadena base64) del `data` del Secret.

Decodifícalo y compruébalo:

```bash
kubectl get secret app-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
```

- `| base64 -d` — decodifica (`-d`) el base64 al valor original. Cualquiera que pueda leer el Secret puede ver el texto en claro.

> Nota: los datos de un Secret están codificados, no cifrados. En producción, restringe el acceso con el cifrado
> de etcd y RBAC — [Good practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 3. Consumirlos en un Pod

Crea un Pod `app` que inyecte el **ConfigMap como variables de entorno (envFrom)** y monte el
**Secret como archivos** en `/etc/app-secret`.

Crea el Pod:

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

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `envFrom.configMapRef` — inyecta **todas las claves** del ConfigMap como variables de entorno con el mismo nombre (para una sola clave usa `env[].valueFrom.configMapKeyRef`).
- `volumes[].secret` + `volumeMounts` — monta cada clave del Secret como un archivo `/etc/app-secret/<clave>`.

Espera a que esté Ready:

```bash
kubectl wait --for=condition=Ready pod/app --timeout=60s
```

- `kubectl wait --for=condition=Ready pod/app` — espera hasta que la condición `Ready` del Pod sea verdadera.
- `--timeout=60s` — se rinde con un error pasado ese tiempo.

Comprueba las variables de entorno:

```bash
kubectl exec app -- printenv APP_MODE APP_GREETING     # ConfigMap → variables de entorno
```

- `kubectl exec app -- <comando>` — ejecuta un comando dentro del contenedor en marcha; todo lo que va después de `--` se ejecuta en el contenedor.
- `printenv A B` — imprime solo las variables de entorno indicadas.

Comprueba el archivo del Secret:

```bash
kubectl exec app -- cat /etc/app-secret/DB_PASSWORD    # Secret → archivo
```

- Un Secret montado como volumen aparece como archivos en claro ya decodificados; cada nombre de clave es un nombre de archivo.

Lo has logrado cuando las variables de entorno son visibles y existe el archivo `/etc/app-secret/DB_PASSWORD`.

> Referencia: [Configure a Pod to Use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) ·
> [Using Secrets as files](https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod)
