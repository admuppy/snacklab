# Gestión de CPU y memoria

Cuando llega un aviso de que un servidor va "lento", lo primero que miras es la **CPU y la memoria**. Este módulo cubre las herramientas para observar los recursos, el ajuste de la prioridad de los procesos y el techo real que imponen a un contenedor/pod los **límites de memoria de cgroup y el OOM killer**.

> Este entorno de laboratorio es un **contenedor (pod)** que ejecuta systemd. Los límites de recursos se gestionan igual que en un pod real de k8s (cgroup v2 gestionado por systemd); iremos señalando dónde difiere un servidor físico cuando corresponda.

Primero, un vistazo rápido al estado actual.

Comprueba el número de CPUs:

```
nproc
```

- `nproc` — número de CPUs (núcleos) disponibles para el proceso actual; dentro de un contenedor refleja los límites de cgroup y de afinidad.

Comprueba el estado de la memoria:

```
free -h
```

- `free` — uso de memoria y swap; `-h` en unidades Gi/Mi.
- La columna `available` (lo que pueden obtener realmente los procesos nuevos, incluida la caché recuperable) importa más que `free`.

Tres resúmenes de 1 segundo:

```
vmstat 1 3
```

- `vmstat <intervalo> <número>` — 3 muestras con 1 s de separación. La primera línea es la media desde el arranque, así que lee a partir de la segunda.
- `r` procesos ejecutables, `si/so` swap de entrada/salida, `us/sy/id/wa` % de CPU de usuario/kernel/inactiva/espera de E/S.

Una instantánea de top:

```
top -b -n1 | head -12
```

- `top -b` — salida en texto plano (batch) en lugar de la pantalla interactiva, `-n1` — una sola iteración. `| head -12` conserva el resumen y los primeros procesos.

## Observar los recursos

`free` resume la memoria; `vmstat` condensa memoria, swap y CPU en una línea. Los números en bruto están en `/proc/meminfo` y `/proc/cpuinfo`.

| Comando | Qué muestra |
|---|---|
| `free -h` | memoria total/usada/disponible, swap |
| `vmstat 1` | memoria, swap de entrada/salida (si/so) y CPU cada segundo |
| `nproc` | número de CPUs disponibles aquí |
| `cat /proc/meminfo` | MemTotal, MemAvailable, ... en bruto |

Tarea: toma una instantánea del total de memoria y del número de CPUs actuales. Guarda en `~/work/snapshot.txt` la **línea MemTotal de /proc/meminfo** y una línea **`cpus=<nproc>`**.

Prepara el directorio de trabajo:

```
mkdir -p ~/work
```

- `mkdir -p` — crea los directorios padre necesarios y no falla si ya existe.

Guarda la línea MemTotal:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — selecciona la línea de memoria total y la guarda con `>` (archivo nuevo).

Añade la línea cpus:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — `$( )` se expande dentro de comillas dobles y da una cadena como `cpus=4`.
- `>>` — **añade** al archivo (`>` lo sobrescribiría).

Verifica el contenido guardado:

```
cat ~/work/snapshot.txt
```

- Confirma que están las dos líneas (MemTotal, cpus=…).

Una vez guardado, pulsa **[Comprobar]**.

## Prioridad y afinidad de CPU

Cuando la CPU escasea, no puedes tratar a todos los procesos por igual. El **valor nice** (-20 alta … 19 baja) fija la prioridad en el planificador, y **taskset** fija en qué núcleos se ejecuta un proceso (afinidad de CPU).

| Comando | Función |
|---|---|
| `nice -n 19 CMD` | arranca un proceso nuevo con prioridad baja |
| `renice -n 5 -p PID` | cambia el valor nice de un proceso en marcha |
| `taskset -c 0 CMD` | lo ejecuta fijado a la CPU 0 |
| `taskset -pc PID` | consulta/cambia la afinidad de un proceso en marcha |

Tarea: ejecuta en segundo plano una carga de CPU (`stress-ng --cpu 1`) **fijada a la CPU 0** con **nice 19** (la prioridad que más cede). Es el patrón clásico para ejecutar trabajo por lotes sin molestar a otros servicios.

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <comando>` — ejecuta el comando fijado a la CPU 0 (`-c` admite una lista de CPUs como `0,2` o `0-3`).
- `nice -n 19 <comando>` — lo ejecuta con nice 19 (la prioridad más baja). Ambos envoltorios se pueden apilar.
- `stress-ng --cpu 1 --timeout 1800s` — generador de carga que pone una CPU al 100 % durante 30 minutos.
- `>/dev/null 2>&1 &` — descarta la salida y lo ejecuta en segundo plano.

Confirma que de verdad se lanzó así: comprueba que `top` muestra un `NI` de 19 y que la afinidad es la CPU 0.

Guarda el PID del proceso de carga:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — busca con una regex en la línea de comandos completa (`.*` = cualquier carácter). `head -1` guarda el primer PID en `pid`.

Comprueba el valor nice:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — solo las columnas de PID, valor nice (`NI`) y nombre del comando; `-p "$pid"` para ese único proceso.

Comprueba la afinidad de CPU:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — muestra la afinidad de un proceso en marcha; `-c` imprime una lista de CPUs en lugar de una máscara de bits.

Compruébalo también en /proc:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `Cpus_allowed_list` en `/proc/<PID>/status` — el registro del kernel de las CPUs en las que puede ejecutarse el proceso; debería coincidir con taskset.

Si `NI=19` y la afinidad es `0`, pulsa **[Comprobar]**. (Deja la carga en marcha: no afecta al siguiente paso.)

## Límites de memoria de cgroup y OOM

En Linux, los techos de CPU/memoria de un grupo de procesos los impone **cgroup v2**. Los límites de recursos de los contenedores, el `MemoryMax=` de un servicio de systemd y **el `resources.limits.memory` de un pod de k8s funcionan todos sobre esto**. Aquí **crearás un cgroup con límite de memoria**, lo sobrepasarás y verás actuar al **OOM Killer** del kernel.

Primero mira el árbol de cgroups y sus controladores.

Comprueba el tipo de sistema de archivos:

```
stat -fc %T /sys/fs/cgroup        # debe ser cgroup2fs
```

- `stat -f` — información sobre el **sistema de archivos** que contiene la ruta, en lugar del archivo; `-c %T` imprime solo el nombre del tipo. `cgroup2fs` significa cgroup v2.

Comprueba los controladores disponibles:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- Controladores disponibles en este cgroup (`cpu`, `memory`, `io`, `pids`, …). Debe estar `memory` para poder fijar un límite de memoria.

> 💡 Este pod comparte el **espacio de nombres de cgroup del host**, así que `/sys/fs/cgroup` es el árbol de todo el nodo. Hacer `mkdir` a mano ahí **contaminaría el nodo** y chocaría con otros pods. Por eso dejamos que systemd cree el cgroup limitado **dentro del propio slice del pod**: exactamente igual que k8s reserva un cgroup por pod.

Tarea: pon un límite de **24M de memoria y 0 de swap** a un slice llamado `lab.slice` y ejecuta dentro un proceso que reserve 200MB para provocar un OOM.

```
# pon un techo de memoria al slice (--runtime = hasta el reinicio, sin escribir en disco)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <unidad> clave=valor…` — cambia las propiedades de recursos de una unidad en marcha (aquí un slice).
- `MemoryMax=24M` — el límite estricto `memory.max` del cgroup; `MemorySwapMax=0` — sin escapatoria hacia el swap.
- `--runtime` — temporal; se guarda en `/run` y desaparece tras el reinicio.

Ahora reserva de más dentro de ese slice. `systemd-run --slice=lab.slice --scope` crea un scope transitorio bajo el slice y ejecuta ahí tu comando.

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — ejecuta el comando en tu terminal pero dentro de un nuevo scope (cgroup) transitorio; `--slice=lab.slice` lo coloca bajo el slice limitado.
- `python3 -c "…"` — una línea que reserva 200 arrays de bytes de 4 MB (≈800 MB). La `\` final continúa la línea.

Verás `Killed`: el kernel mató el proceso en cuanto superó el límite de 24M. El rastro queda en el `memory.events` del slice. systemd te dice la ruta real del cgroup del slice.

Guarda la ruta del cgroup del slice:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — imprime la ruta del cgroup del slice (`/…/lab.slice`); anteponiendo `/sys/fs/cgroup` se obtiene el directorio real, que se guarda en `cg`.

Comprueba el límite de memoria:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — el límite estricto de memoria del cgroup en bytes: 24M = 24×1024×1024 = 25165824.

Comprueba los eventos OOM:

```
cat "$cg/memory.events"     # busca la línea oom_kill
```

- `memory.events` — contadores acumulados de eventos de memoria: `max` veces que se alcanzó el límite, `oom` eventos OOM, `oom_kill` procesos matados por OOM.

Si ves `oom_kill 1` (o más), el OOM ocurrió de verdad. Una vez confirmado, pulsa **[Comprobar]** para completar el módulo. (`lab.slice` se mantiene mientras viva el pod y se limpia automáticamente cuando el pod desaparece.)
