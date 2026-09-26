# NetworkPolicy: microsegmentación

Por defecto, todos los Pods de un clúster pueden hablar con todos los demás. Una **NetworkPolicy** es un
cortafuegos a nivel de Pod: para los Pods elegidos por etiqueta define qué **orígenes (from) / destinos
(to)** se permiten. Las reglas son una **lista de permitidos**: en cuanto una política "selecciona" un Pod, ese Pod
solo acepta el tráfico permitido explícitamente (todo lo demás se deniega).

Este laboratorio ya tiene un servidor `web` (+Service `web`) y un Pod cliente `client` (etiqueta
`app=client`). k3s aplica las NetworkPolicies de verdad.

Comprueba el Pod web:

```bash
kubectl get pod -l app=web -o wide
```

- `-l app=web` selecciona los Pods del servidor y `-o wide` muestra sus IPs. Las NetworkPolicies seleccionan Pods con esta misma etiqueta.

Comprueba el Pod cliente:

```bash
kubectl get pod client -o wide
```

- El Pod cliente. Comprueba su etiqueta `app=client` con `kubectl get pod client --show-labels`: la regla de permiso del paso 3 se basa en ella.

> Referencia: [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

## 1. Verificar la conectividad base

Sin ninguna política, confirma que el cliente llega a web y guarda esa referencia en
`~/work/baseline.txt`; la compararás en los pasos 2 y 3.

Prueba la conectividad client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # respuesta de nginx
```

- `kubectl exec client -- …` — envía la petición desde **dentro** del Pod cliente, de modo que el origen es el cliente.
- `wget -q -T 3 -O- http://web` — pide el Service `web` con un tiempo de espera de 3 s (`-T 3`) y escribe la respuesta en la salida estándar (`-O-`).
- `| head -1` — muestra solo la primera línea.

Crea un directorio para el registro:

```bash
mkdir -p ~/work
```

- `mkdir -p` — crea los directorios intermedios que hagan falta y no falla si ya existe.

Guarda la respuesta base:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web > ~/work/baseline.txt
```

- `> archivo` — guarda (sobrescribe) la salida estándar del comando en un archivo. La salida de `kubectl exec` vuelve a tu terminal, así que el archivo se crea en local.

Comprueba el contenido guardado:

```bash
head -1 ~/work/baseline.txt
```

- `head -1 <archivo>` — imprime solo la primera línea del archivo.

Ver la primera línea del HTML de nginx (`<!DOCTYPE html>`) significa que está abierto.

## 2. Denegar todo el tráfico entrante (default-deny)

Crea una política que **seleccione** los Pods `web` pero **no tenga reglas de ingress**: se bloquea todo el
tráfico entrante hacia los Pods seleccionados.

Crea la política default-deny:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
EOF
```

- `cat <<'EOF' | kubectl apply -f -` — pasa a kubectl por stdin el YAML hasta la línea `EOF`. `-f -` significa "leer stdin en vez de un archivo"; entrecomillar `'EOF'` impide que la shell expanda los `$` del cuerpo.
- `podSelector` — los Pods a los que se aplica la política (`app=web`); un selector vacío `{}` significa todos los Pods del namespace.
- `policyTypes: [Ingress]` sin reglas `ingress:` → se deniega todo el tráfico entrante a los Pods seleccionados.

Verifica que está bloqueado (se espera un timeout):

```bash
kubectl exec client -- wget -q -T 3 -t 1 -O- http://web    # timeout (bloqueado)
```

- `-t 1` — un solo intento. Si está bloqueado termina con `timed out` a los 3 s (los paquetes se descartan en silencio, sin rechazo).

Cuando `wget` agota el tiempo, la política ha cortado el tráfico.

## 3. Permitir desde un origen concreto

Ahora añade una política que permita el puerto 80 solo desde Pods con la etiqueta `app=client`. Las políticas se
suman, así que este permiso se superpone al default-deny y solo pasa el cliente.

Crea la política de permiso:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-allow-client, namespace: default }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: client } }
      ports:
        - { protocol: TCP, port: 80 }
EOF
```

- `ingress[].from[].podSelector` — permite como origen solo los Pods etiquetados `app=client` del mismo namespace.
- `ports` — puerto/protocolo permitido (TCP 80). `from` y `ports` en la misma entrada deben cumplirse ambos.
- Las políticas se suman (O lógico), así que este permiso se aplica además del default-deny.

Vuelve a probar client → web:

```bash
kubectl exec client -- wget -q -T 3 -O- http://web | head -1   # vuelve a funcionar
```

Lo has logrado cuando se restablece client → web. Prueba desde otro Pod sin la etiqueta `app=client` y
seguirá bloqueado: eso es microsegmentación.

> Referencia: [Declare Network Policy (walkthrough)](https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/)
