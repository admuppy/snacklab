# Procesos y señales

Cuando un servidor va lento o se comporta de forma extraña, lo primero es **mirar sus procesos**. En este módulo explorarás procesos con ps y /proc, los controlarás con señales, ejecutarás tareas separadas de la terminal y localizarás el proceso que ocupa un puerto.

En el entorno del laboratorio ya se están ejecutando tres demonios como unidades de systemd.

| Proceso | Qué es |
|---|---|
| `lab-worker` | Un worker corriente: tu objetivo en el paso 1 |
| `lab-stubborn` | Algo parecido a un zombi que **ignora SIGTERM**: lo eliminarás en el paso 2 |
| `lab-listener` | Algo que ocupa 127.0.0.1:5555: lo localizarás en el paso 4 |

## Explorar procesos — ps y /proc

Empieza revisando todos los procesos.

Revisa la lista completa:

```
ps aux | head
```

- `ps aux` — procesos de todos los usuarios (`a`, y `x`: también los que no tienen terminal), con usuario, CPU%, MEM% y comando (`u`).
- `| head` — solo las 10 primeras líneas.

Míralos en forma de árbol:

```
ps -ef --forest | head -30
```

- `ps -ef` — todos los procesos (`-e`) en formato completo (`-f`), con PID y PPID.
- `--forest` — dibuja las relaciones padre/hijo como un árbol con sangría; `head -30` conserva las 30 primeras líneas.

Busquemos `lab-worker`. `pgrep -f` compara el patrón con la línea de comandos completa y devuelve los PIDs.

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <patrón>` — imprime solo los PIDs de los procesos que coinciden.
- `-f` — compara con la **línea de comandos completa** (ruta y argumentos), no solo con el nombre del proceso.

Todo lo que muestra ps sale del **sistema de archivos /proc**. Mira tú mismo dentro del directorio del PID (cmdline está separado por NUL(\0), así que conviértelo con tr para leerlo).

Guarda el PID en una variable:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — sustitución de comandos; guarda la salida (el PID) en la variable de shell `pid`, que luego se usa como `$pid`.
- `| head -1` — conserva solo el primer PID si coinciden varios.

Lista el directorio del PID:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — un directorio virtual en el que el kernel expone la información del proceso como archivos: `cmdline` (argumentos), `status` (estado, memoria), `fd/` (archivos abiertos), `environ` (entorno), …

Lee cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — traduce los caracteres NUL de la entrada a espacios.
- `< archivo` — pasa el archivo por stdin; `; echo` añade un salto de línea final.

Tarea: guarda los resultados en archivos.

- `~/work/worker.pid` — el PID de lab-worker
- `~/work/worker.cmdline` — el contenido de `/proc/<PID>/cmdline` (convertido con tr)

Crea el directorio de trabajo:

```
mkdir -p ~/work
```

- `mkdir -p` — crea los directorios padre necesarios y no falla si ya existe.

Guarda el PID:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` imprime la variable; `> archivo` guarda esa salida en el archivo (sobrescribe).

Guarda el cmdline:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- El mismo comando `tr` que ejecutaste antes, esta vez guardado en un archivo con `>`.

Una vez guardado, pulsa **[Comprobar]**.

## Controlar procesos con señales

`kill` no es un comando que mate procesos: **envía señales**.

| Señal | Número | Comportamiento |
|---|---|---|
| SIGTERM | 15 | La predeterminada. Un proceso **puede ignorarla o limpiar antes de salir** |
| SIGKILL | 9 | El kernel elimina el proceso de inmediato. **No se puede ignorar**, sin opción de limpiar |
| SIGHUP | 1 | Por convención, se usa a menudo para "recargar la configuración" |

`lab-stubborn` está escrito para capturar e ignorar TERM e INT. Compruébalo tú mismo.

Confirma que está en marcha:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- Un PID significa que está vivo; sin salida (código de salida 1) significa que no existe ese proceso.

Envía SIGTERM:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — envía una señal a los procesos que coinciden (`pgrep` + `kill`).
- `-TERM` — la señal (SIGTERM, 15); `-f` compara con la línea de comandos completa.
- `sudo` — el proceso pertenece a otro usuario (root), así que hacen falta permisos de administrador.

Comprueba que sigue vivo:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # sigue vivo
```

- `sleep 1` — espera un segundo a que se procese la señal y luego `;` vuelve a lanzar la comprobación.

Un detalle: este proceso lo gestiona una **unidad de systemd** (lab-stubborn.service). Podrías hacer kill -9 al proceso sin más, pero un proceso gestionado por una unidad debe tratarse, como es debido, a nivel de unidad. Sin embargo, `systemctl stop` envía primero TERM y espera al tiempo límite (90 s por defecto), algo demasiado lento para este caso; en su lugar, **envía SIGKILL directamente a través de la unidad**.

Envía SIGKILL a través de la unidad:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <unidad>` — envía una señal a **todos los procesos** de la unidad.
- `-s KILL` — la señal es SIGKILL (9), que un proceso no puede capturar, así que se elimina de inmediato.

Confirma que ha terminado:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "terminated"
```

- `A || B` — ejecuta B solo si A falla (código de salida ≠ 0); cuando `pgrep` no encuentra nada, se imprime el mensaje.

Cuando haya muerto, pulsa **[Comprobar]**.

## Ejecución en segundo plano separada de la sesión

Un proceso lanzado con `&` en una terminal recibe SIGHUP y muere cuando la terminal se desconecta. Para que sobreviva al final de la sesión, usa **nohup** (ignora HUP + redirige la salida) o **setsid** (lo separa en una sesión nueva).

`/opt/lab/bin/lab-batch` es una tarea por lotes que escribe una marca de tiempo cada 10 segundos en el archivo indicado como primer argumento. Lánzala separada de la terminal y envía su log a `~/work/batch.log`.

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <comando>` — ignora SIGHUP para que el comando siga en marcha tras cerrar la terminal.
- `>/dev/null 2>&1` — descarta stdout y envía stderr (2) al mismo sitio que stdout (1).
- El `&` final lo ejecuta en segundo plano y devuelve el prompt de inmediato.

Comprueba el proceso padre. Una vez separado de la shell y huérfano, lo adopta el PID 1 (systemd en este pod).

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — elige las columnas: PID, PID del padre y comando.
- `-p $(pgrep ...)` — solo los PIDs que produce la sustitución de comandos.

Revisa el log:

```
tail ~/work/batch.log
```

- `tail <archivo>` — las 10 últimas líneas; usa `tail -f` para seguirlo en vivo (Ctrl+C para parar).

Si el PPID es 1 y el log va creciendo, pulsa **[Comprobar]**.

> En producción, la respuesta correcta para demonios como este es una unidad de systemd (o `systemd-run`); lo verás en el módulo linux-06.

## Localizar el proceso que ocupa un puerto

"¿Quién tiene ocupado este puerto?" es la pregunta de diagnóstico más habitual. Usa `ss` (socket statistics) para encontrar al dueño del puerto 5555. Necesitas `-p` para ver los nombres de los procesos, y sudo para ver los de otros usuarios.

Lista todos los sockets en escucha:

```
sudo ss -ltnp
```

- `ss` — estadísticas de sockets (sucesor de netstat). `-l` solo en escucha, `-t` TCP, `-n` puertos numéricos, `-p` muestra el proceso propietario.

Consulta solo el puerto 5555:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — una expresión de filtro: solo los sockets cuyo puerto de origen (local) es 5555.

`lsof` da la misma respuesta.

```
sudo lsof -i :5555
```

- `lsof` — lista los archivos abiertos (en Linux los sockets son archivos); `-i :5555` — solo las conexiones de red del puerto 5555.

Tarea: guarda el **nombre del proceso** que ocupa el puerto 5555 en `~/work/port-owner.txt`.

Extrae y guarda el nombre del proceso:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — imprime **solo la parte que coincide**, no la línea entera; saca el nombre de `users:(("python3",pid=…))`.
- `head -1` conserva uno y `>` lo guarda.

Verifica el contenido guardado:

```
cat ~/work/port-owner.txt
```

- `cat <archivo>` — imprime el contenido del archivo.

Si tienes curiosidad por saber qué es realmente este python3, rebusca en /proc con su PID: exactamente la técnica del paso 1. Una vez guardado, pulsa **[Comprobar]**.
