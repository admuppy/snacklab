# Servicios de systemd y journald

En linux-02 lanzamos un demonio con nohup, pero en el mundo real todos los demonios son **unidades de systemd**: arranque automático al iniciar, reinicio si mueren y logs recogidos por journald. En este módulo escribirás unidades tú mismo, diagnosticarás y repararás una unidad rota con el journal y sustituirás cron por un temporizador.

Revisa ahora las unidades del sistema.

Lista las unidades de servicio:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — unidades cargadas en memoria; `--type=service` solo servicios, `--no-pager` imprime sin less.
- `| head -15` — las 15 primeras líneas. Columnas: LOAD (archivo cargado), ACTIVE (estado general), SUB (estado detallado).

Comprueba el estado del servicio cron:

```
systemctl status cron --no-pager
```

- `systemctl status <unidad>` — estado (`Active:`), PID principal, árbol de procesos del cgroup y las últimas líneas de log en una sola pantalla.

## Escribir una unidad de servicio

La unidad de servicio más pequeña necesita solo tres secciones.

| Sección | Función |
|---|---|
| `[Unit]` | descripción, dependencias (Description, After, …) |
| `[Service]` | cómo se ejecuta (ExecStart, Restart, User, …) |
| `[Install]` | dónde se engancha al habilitarla (WantedBy) |

Tarea: crea `hello-web.service`, que ejecuta un servidor HTTP estático en el puerto 8080.

```
sudo tee /etc/systemd/system/hello-web.service <<'EOF'
[Unit]
Description=hello web

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
```

- `sudo tee <archivo> <<'EOF'` — el cuerpo del heredoc lo escribe `tee`, que se ejecuta como root (`sudo cat > archivo` falla porque la redirección la hace tu propia shell).
- `/etc/systemd/system/` — donde viven las unidades creadas por el administrador; tienen prioridad sobre las de los paquetes (`/usr/lib/systemd/system/`).
- `ExecStart=` — el comando que se ejecuta (ruta absoluta). `WantedBy=multi-user.target` — al habilitarla, se engancha al objetivo de arranque normal.

Después de crear o editar un archivo de unidad, **haz siempre daemon-reload**: systemd no lee los archivos directamente, sino la copia cargada en memoria.

Recarga systemd:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — hace que systemd vuelva a leer los archivos de unidad. No reinicia servicios.

Habilítalo e inícialo ya:

```
sudo systemctl enable --now hello-web
```

- `enable` — enlaza la unidad en su objetivo `WantedBy` para que arranque al iniciar; `--now` — además la `start` en ese momento.
- El sufijo `.service` se puede omitir.

Comprueba el estado del servicio:

```
systemctl status hello-web --no-pager
```

- `Active: active (running)` con un PID principal (`python3`) significa que arrancó correctamente.

Prueba la respuesta:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — envía la petición HTTP sin barra de progreso e imprime el cuerpo; `| head -3` conserva las 3 primeras líneas (el HTML del listado del directorio).

`enable --now` significa "registrar para arrancar al iniciar + arrancar ahora". Cuando veas una respuesta, pulsa **[Comprobar]**.

## Reparar una unidad rota con journald

Hay desplegada una unidad llamada `lab-report.service`, pero no arranca. Compruébalo tú mismo.

Intenta arrancar el servicio:

```
sudo systemctl start lab-report
```

- `systemctl start` — arranca el servicio ahora (independientemente de que esté habilitado al inicio). Si falla, imprime `Job … failed` y sugiere comandos para investigarlo.

Mira el estado del fallo:

```
systemctl status lab-report --no-pager
```

- Fíjate en `Active: failed` y en la línea `code=exited, status=…` para ver el código del fallo.

La investigación se hace con **journalctl**. Usa `-u` para elegir la unidad, junto con `-e` (ir al final) o `--no-pager`.

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — lee los logs de journald. `-u <unidad>` solo esa unidad, `--no-pager` imprime directamente, `| tail -20` las 20 últimas líneas.
- Síguelo en vivo con `-f`, solo el arranque actual con `-b`, una ventana de tiempo con `--since "10 min ago"`.

Deberías ver `status=203/EXEC`, un código de salida clásico de systemd que significa **que el ejecutable de ExecStart no se puede ejecutar** (errata en la ruta, falta de permiso de ejecución, problema con el shebang). Compara la ruta a la que apunta la unidad con los archivos reales.

Muestra la ruta a la que apunta la unidad:

```
systemctl cat lab-report
```

- `systemctl cat <unidad>` — los archivos de unidad que systemd usa de verdad (incluidos los drop-ins), con sus rutas. Revisa la línea `ExecStart=`.

Comprueba los archivos reales:

```
ls -l /opt/lab/bin/
```

- `ls -l` — nombres de archivo junto con los permisos (¿está puesta la `x`?). Compáralos carácter a carácter con la ruta de la unidad.

Tarea: corrige la ruta de ExecStart (no olvides daemon-reload) y arranca el servicio.

Edita el archivo de la unidad:

```
sudo vim /etc/systemd/system/lab-report.service
```

- Los archivos de unidad pertenecen a root, así que se abren con `sudo`. vim: `i` para insertar, `Esc` → `:wq` para guardar y salir.
- Si olvidas `daemon-reload` después, systemd seguirá fallando con la ruta antigua.

Recarga systemd:

```
sudo systemctl daemon-reload
```

Arranca el servicio:

```
sudo systemctl start lab-report
```

Sigue el log:

```
tail -f /var/log/lab/report.log   # sal con Ctrl-C
```

- `tail -f` — sigue el final del archivo e imprime las líneas nuevas según aparecen: la prueba de que el servicio está trabajando de verdad.

Cuando esté active (running), pulsa **[Comprobar]**.

## Autorreparación con la política Restart

Los procesos mueren: OOM, bugs, errores. `Restart=` de systemd es la red de seguridad que los recupera automáticamente.

| Valor | Condición de reinicio |
|---|---|
| `no` (por defecto) | nunca |
| `on-failure` | solo tras una salida anómala (código≠0, señal) |
| `always` | siempre, incluso tras una salida limpia |

Tarea: añade `Restart=on-failure` y `RestartSec=1` a hello-web. Puedes editar directamente el archivo de la unidad o, mejor aún, usar un **drop-in** que no toque el original (`systemctl edit` es interactivo, así que aquí escribimos el archivo directamente).

Crea el directorio del drop-in:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<unidad>.d/` — un directorio de drop-ins; los archivos `*.conf` que contiene sobrescriben la unidad original y sobreviven a las actualizaciones del paquete.

Escribe el archivo del drop-in:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- Solo las claves que se añaden en `[Service]`. `Restart=on-failure` reinicia tras salidas anómalas, `RestartSec=1` espera 1 s antes.

Recarga systemd:

```
sudo systemctl daemon-reload
```

Reinicia el servicio:

```
sudo systemctl restart hello-web
```

- `restart` — stop y luego start, así que el proceso vuelve con el nuevo drop-in aplicado.

Comprobemos que de verdad vuelve. Mata el PID principal con SIGKILL y revisa el estado unos segundos después.

Muestra el PID principal:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — imprime las propiedades de la unidad como `clave=valor`; `-p MainPID` elige una y `--value` quita el prefijo `MainPID=`.

Mata el proceso:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- `kill -9` (SIGKILL) sobre el PID principal obtenido con `$( ... )`: una terminación forzada que no se puede capturar. Es una salida anómala, así que se aplica `on-failure`.

Comprueba el estado al cabo de un momento:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- `sleep 3` da tiempo al reinicio (RestartSec=1) y después muestra las 5 primeras líneas del estado. `Main PID` debería ser distinto del anterior.

Si vuelve a estar active con un PID nuevo, ha funcionado: pulsa **[Comprobar]**. (La comprobación repite el mismo experimento una vez más.)

## Tareas periódicas con temporizadores

El sustituto de cron en systemd es el **temporizador (timer)**. Los logs quedan en el journal y los fallos se gestionan como unidades, así que la mayoría de las tareas periódicas en las distribuciones modernas son temporizadores. Se configura por parejas: **un servicio (qué hacer) + un temporizador (cuándo)**.

Tarea: crea un temporizador `lab-tick` que registre la hora en `/var/log/lab/tick.log` cada minuto.

Escribe la unidad de servicio (qué hacer):

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — una tarea que se ejecuta hasta terminar; cuando el comando sale, cuenta como éxito y vuelve a inactiva.
- `bash -c '…'` — la redirección (`>>`, añadir) es una función de la shell, así que se ejecuta a través de bash. `date -Is` imprime una marca de tiempo ISO 8601.

Escribe la unidad del temporizador (cuándo):

```
sudo tee /etc/systemd/system/lab-tick.timer <<'EOF'
[Unit]
Description=lab tick every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
```

- `OnCalendar=*-*-* *:*:00` — sintaxis de calendario `año-mes-día hora:minuto:segundo`: el segundo 0 de cada minuto = cada minuto.
- `AccuracySec=1s` — reduce el retraso de arranque permitido (1 min por defecto) a 1 s.
- Un temporizador arranca el `.service` del mismo nombre (`lab-tick.service`); `WantedBy=timers.target` se usa al habilitarlo.

Recarga systemd:

```
sudo systemctl daemon-reload
```

Habilita y arranca el temporizador:

```
sudo systemctl enable --now lab-tick.timer
```

- Escribe `.timer` completo; sin sufijo, el nombre se toma como `.service`.

`Type=oneshot` es para tareas que "se ejecutan una vez y terminan". Fíjate en que lo que habilitas es **el temporizador, no el servicio**. Confirma que está registrado y pulsa **[Comprobar]** para completar el módulo.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — temporizadores activos con sus horas de ejecución `NEXT` y `LAST`.
- `grep -E 'NEXT|lab-tick'` — conserva la cabecera y la línea de lab-tick (`|` es O lógico en regex extendida).
