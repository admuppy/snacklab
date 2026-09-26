# Diagnóstico de red

"No llego al servicio" casi siempre se reduce a una de cuatro causas: **IP equivocada, puerto no abierto, enlace (bind) incorrecto o nombre que no se resuelve.** En este módulo aprenderás las herramientas que diagnostican esas cuatro por orden: ip, ss, curl, getent.

El entorno del laboratorio ejecuta un servicio de API llamado `lab-api`, y hay abierta una incidencia que dice que "no se puede acceder desde fuera". Al final habrás encontrado y corregido la causa.

## Inspeccionar interfaces e IPs

El diagnóstico de red empieza por **quién soy** (mi IP). La herramienta estándar moderna es `ip` (ifconfig está retirado).

Lista las interfaces:

```
ip link
```

- `ip link` — interfaces de red (L2) con su estado (`UP`/`DOWN`), dirección MAC y MTU.

Muestra las direcciones IPv4:

```
ip -4 addr show
```

- `ip addr show` — direcciones IP por interfaz; `-4` solo IPv4. Se muestran como dirección/longitud de prefijo (CIDR), p. ej. `inet 10.x.x.x/24`.

Muestra la tabla de rutas:

```
ip route
```

- `ip route` — la tabla de rutas; la línea `default via <puerta de enlace>` es la ruta por defecto hacia fuera.

Un contenedor suele mostrar dos interfaces: `lo` (loopback) y `eth0`. Una extracción en una línea, cómoda para scripts:

Imprime eth0 en una línea:

```
ip -4 -o addr show eth0
```

- `-o` — una interfaz por **línea** (oneline), fácil de procesar con `grep`/`awk`.
- `show eth0` — solo esa interfaz.

Extrae solo el campo CIDR:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

- `awk '{print $4}'` — conserva solo el 4.º campo separado por espacios (`10.x.x.x/24`).

Tarea: guarda en `~/work/myip.txt` la dirección IPv4 de eth0, **solo la dirección, sin CIDR**. Quita sufijos como `/24` con `cut -d/ -f1`.

Quita el sufijo y guárdala:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

- `cut -d/ -f1` — divide por `/` (`-d`) y conserva el campo 1 (`-f1`) → la dirección.
- `> ~/work/myip.txt` — guarda el resultado en un archivo.

Verifica el contenido guardado:

```
cat ~/work/myip.txt
```

- Imprime la dirección guardada. Los comandos siguientes la reutilizan como `$(cat ~/work/myip.txt)`.

Una vez guardado, pulsa **[Comprobar]**.

## Localizar los sockets en escucha

Siguiente pregunta: **qué escucha en qué puerto.** Las opciones esenciales de `ss`:

| Opción | Significado |
|---|---|
| `-l` | solo sockets en escucha |
| `-t` / `-u` | TCP / UDP |
| `-n` | puertos numéricos (sin traducir a nombre de servicio) |
| `-p` | muestra los procesos (hace falta sudo para los de otros usuarios) |

```
sudo ss -ltnp
```

- La combinación de opciones de la tabla. `Local Address:Port` indica dónde escucha y `users:((…))` qué proceso.

Tarea: averigua el **número de puerto** en el que escucha `lab-api.service` y guárdalo en `~/work/api-port.txt`. Partir del PID principal de la unidad es un buen camino.

Muestra el PID principal de lab-api:

```
systemctl show -p MainPID --value lab-api
```

- `systemctl show -p MainPID --value <unidad>` — imprime solo el PID del proceso principal de la unidad.

Busca el socket en escucha de ese PID:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

- `$( … )` también se expande dentro de comillas dobles → queda `grep "pid=1234"`, que conserva solo las líneas de socket de ese PID.

Lee el puerto en `127.0.0.1:puerto` de la columna Local Address. Guárdalo y pulsa **[Comprobar]**.

## Diagnosticar y corregir un problema de enlace

Quizá ya lo notaste en la salida de ss: la Local Address de lab-api es `127.0.0.1:9090`. Está **enlazado solo al loopback**, así que funciona dentro de este contenedor pero da connection refused desde fuera (otros pods, el nodo). Reprodúcelo.

Conéctate por loopback:

```
curl -s http://127.0.0.1:9090/status.json        # funciona
```

- `curl -s <URL>` — petición silenciosa que imprime solo el cuerpo. Por loopback (`127.0.0.1`) conecta.

Conéctate por la IP del contenedor:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # ¡falla!
```

- `--max-time 3` — limita toda la petición a 3 s en lugar de esperar.
- `$(cat ~/work/myip.txt)` — inserta en la URL la IP del contenedor que guardaste.

El mismo proceso da resultados distintos según **por qué dirección llega la petición**. Hay que cambiar el enlace a `0.0.0.0` (todas las interfaces).

Tarea: cambia `--bind 127.0.0.1` por `--bind 0.0.0.0` en el archivo de la unidad y reinicia.

Edita el archivo de la unidad:

```
sudo vim /etc/systemd/system/lab-api.service
```

- Busca `--bind 127.0.0.1` en la línea `ExecStart=` y cámbialo. vim: `i` para insertar, `Esc` → `:wq` para guardar y salir.

Recarga systemd:

```
sudo systemctl daemon-reload
```

- Has editado el archivo de la unidad, así que haz que systemd lo vuelva a leer.

Reinicia el servicio:

```
sudo systemctl restart lab-api
```

- Reinicia el proceso con la nueva dirección de enlace.

Comprueba la dirección de enlace:

```
sudo ss -ltn | grep 9090
```

- No hacen falta los nombres de proceso, así que sin `-p`. `0.0.0.0:9090` significa que acepta en todas las interfaces.

Vuelve a conectarte por la IP del contenedor:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # ahora funciona
```

- Envía la misma petición otra vez; esta vez debería responder.

Cuando muestre `0.0.0.0:9090` y responda por la IP del contenedor, pulsa **[Comprobar]**.

## Resolución de nombres — hosts y DNS

La última pieza es **nombre → IP**. El orden de resolución suele ser `/etc/hosts` → DNS (los servidores de nombres de `/etc/resolv.conf`), y ese orden lo rige la línea `hosts:` de `/etc/nsswitch.conf`.

Comprueba la configuración del servidor DNS:

```
cat /etc/resolv.conf
```

- `nameserver` — servidores DNS a los que se consulta; `search` — dominios que se prueban por orden tras los nombres cortos.

Comprueba la regla del orden de resolución:

```
grep hosts /etc/nsswitch.conf
```

- `hosts: files dns` — resuelve los nombres primero desde `files` (=`/etc/hosts`) y después con `dns`.

Las herramientas de consulta sirven para cosas distintas: `nslookup`/`dig` preguntan **directamente a un servidor DNS**, mientras que `getent hosts` sigue la **ruta de resolución real del sistema** (incluido el archivo hosts). Lo que ven las aplicaciones es el resultado de getent.

Tarea: haz que lab-api sea accesible con el nombre `api.lab.local`. No puedes cambiar el servidor DNS, así que regístralo en `/etc/hosts`.

Registra el nombre en hosts:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

- `tee -a` — **añade** en lugar de sobrescribir. ¡Si olvidas `-a`, todo el archivo hosts se queda en una sola línea!
- Formato: `<IP> <nombre> [alias…]`.

Resuélvelo por la ruta del sistema:

```
getent hosts api.lab.local
```

- `getent hosts <nombre>` — resuelve en el orden de nsswitch (incluido el archivo hosts): la misma respuesta que obtienen las aplicaciones.

Conéctate por nombre:

```
curl -s http://api.lab.local:9090/status.json
```

- Hace la petición por nombre en lugar de por IP; curl usa el resolvedor del sistema, así que se aplica la entrada de `/etc/hosts`.

Cuando obtengas una respuesta, pulsa **[Comprobar]**: módulo completado.
