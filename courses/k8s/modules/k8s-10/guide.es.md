# Proyecto final: revivir un despliegue roto

Hay dos aplicaciones de comercio electrónico desplegadas (`shop`, `cart`), pero **no hay nada en marcha.** Hay tres
fallos distintos sembrados. Este proyecto final no trata de conceptos nuevos: es práctica con las herramientas de
diagnóstico que ya conoces (`kubectl get`, `describe`, `logs`, `get events`) para **encontrar y corregir las causas
por tu cuenta.**

Empieza con un vistazo general:

Revisa todos los recursos:

```bash
kubectl get deploy,pods,svc
```

- Los tipos separados por comas se listan de una vez. Recorre el `READY` de los Deployments, el `STATUS` de los Pods y los Services para localizar qué falla.

Revisa los eventos recientes:

```bash
kubectl get events --sort-by=.lastTimestamp | tail -20
```

- `kubectl get events` — lo que ha ocurrido en el namespace (planificación, descargas de imágenes, fallos, …).
- `--sort-by=.lastTimestamp` — ordena por última aparición; `| tail -20` — solo las 20 líneas más recientes.

> Referencia: [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/) ·
> [Troubleshoot Applications](https://kubernetes.io/docs/tasks/debug/debug-application/)

## 1. Corregir el fallo de descarga de imagen

Los Pods de `shop` están en `ImagePullBackOff`/`ErrImagePull`. Averigua por qué.

Comprueba el estado de los Pods de shop:

```bash
kubectl get pods -l app=shop
```

- `ImagePullBackOff`/`ErrImagePull` en `STATUS` — el nodo no puede descargar la imagen y espaciando cada vez más los reintentos.

Busca la causa en los eventos:

```bash
kubectl describe pod -l app=shop | grep -A5 -i events   # aparece una etiqueta "not found"
```

- Los `Events` al final de `describe` indican el fallo de la forma más directa; `grep -A5 -i events` muestra solo esa parte.

Comprueba la etiqueta de imagen actual:

```bash
kubectl get deploy shop -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

- `{.spec.template.spec.containers[0].image}` — el nombre:etiqueta de la imagen que usa el Deployment para sus Pods.

La etiqueta de la imagen no existe. Cámbiala por una válida:

Sustituye la etiqueta de la imagen:

```bash
kubectl set image deploy/shop web=nginx:1.26
```

- `kubectl set image deploy/shop web=nginx:1.26` — sustituye la imagen del contenedor llamado `web`; la plantilla cambia y se despliegan Pods nuevos.

Espera a que termine el despliegue:

```bash
kubectl rollout status deploy/shop
```

- Espera a que todos los Pods nuevos estén Ready. Si se queda colgado, `Ctrl+C` y vuelve a usar `describe` para ver por qué.

Cuando `shop` esté 2/2 Ready, ① estará resuelto.

## 2. Corregir el selector del Service

Los Pods ya están en marcha, pero el Service `shop` no envía tráfico. Revisa sus endpoints.

Comprueba los endpoints:

```bash
kubectl get endpoints shop            # <none>: no hay Pods asociados
```

- `<none>` en `ENDPOINTS` significa que ningún Pod Ready coincide con el selector del Service.

Comprueba el selector del Service:

```bash
kubectl get svc shop -o jsonpath='{.spec.selector}'; echo   # app=shopX (errata)
```

- `{.spec.selector}` — la condición de etiquetas que usa el Service para elegir Pods, en JSON.

Comprueba las etiquetas reales de los Pods:

```bash
kubectl get pods -l app=shop --show-labels                  # la etiqueta real es app=shop
```

- `--show-labels` — añade una columna `LABELS` con todas las etiquetas de cada Pod; compárala con el selector carácter a carácter.

El selector del Service no coincide con las etiquetas de los Pods. Corrígelo:

Corrige el selector:

```bash
kubectl patch svc shop --type=merge -p '{"spec":{"selector":{"app":"shop"}}}'
```

- `kubectl patch` — edita solo algunos campos de un recurso en el sitio.
- `--type=merge` — fusiona con el objeto el JSON indicado con `-p` (JSON merge patch).
- `-p '{"spec":{"selector":{"app":"shop"}}}'` — el parche contiene solo lo que cambia; las comillas simples evitan que la shell lo interprete.

Vuelve a comprobar los endpoints:

```bash
kubectl get endpoints shop            # ahora con IPs de Pods
```

Cuando los endpoints tengan contenido, ② estará resuelto.

## 3. Corregir el ConfigMap que falta

El Pod de `cart` está atascado en `CreateContainerConfigError`. Averigua por qué.

Comprueba el estado del Pod de cart:

```bash
kubectl get pods -l app=cart
```

- `CreateContainerConfigError` — la imagen está, pero no se puede construir la configuración del contenedor (un ConfigMap/Secret referenciado, …).

Busca la causa en los eventos:

```bash
kubectl describe pod -l app=cart | grep -A5 -i events   # configmap "cart-config" not found
```

- Los eventos nombran el objeto que falta (`configmap "cart-config" not found`).

Comprueba el envFrom referenciado:

```bash
kubectl get deploy cart -o jsonpath='{.spec.template.spec.containers[0].envFrom}'; echo
```

- `{...envFrom}` — los ConfigMaps/Secrets que el contenedor importa enteros como variables de entorno.

Hace referencia a un ConfigMap `cart-config` que no existe. Créalo y el kubelet arrancará el
Pod:

Crea el ConfigMap:

```bash
kubectl create configmap cart-config --from-literal=CURRENCY=KRW --from-literal=TAX_RATE=0.1
```

- Dos opciones `--from-literal=clave=valor` crean un ConfigMap con dos claves. En cuanto existe, el reintento del kubelet arranca el contenedor.

Espera a que termine el despliegue:

```bash
kubectl rollout status deploy/cart
```

Cuando `cart` esté 1/1 Ready, ③ estará resuelto: los tres fallos reparados.

```bash
kubectl get deploy,svc,endpoints      # comprobación final
```

- Un último vistazo al READY de los Deployments, los Services y los endpoints para confirmar que los tres fallos están corregidos.
