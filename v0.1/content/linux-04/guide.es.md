# Scripting en Bash

Cuando una línea de comandos empieza a repetirse, es hora de convertirla en script. En este módulo aprenderás a escribir **no scripts que nunca mueren, sino scripts que mueren en cuanto algo va mal (fail-fast)**, porque un script que produce resultados erróneos en silencio es el más peligroso.

Todo va en `~/work/`. Usa vim o nano, como prefieras, o crea los archivos con un heredoc `cat > archivo <<'EOF'`.

## Un esqueleto de script seguro

Las dos primeras líneas de todo script son prácticamente fijas.

```
#!/bin/bash
set -euo pipefail
```

| Opción | Efecto |
|---|---|
| `-e` | sale de inmediato cuando falla un comando |
| `-u` | da error al usar variables no definidas (detecta erratas) |
| `-o pipefail` | un fallo en medio de una tubería cuenta como fallo |

Tarea: escribe `~/work/sysinfo.sh`. Requisitos:

- shebang de bash + `set -euo pipefail`
- imprime una línea `host=<nombre de host>` y una línea `uptime=<segundos>`
- permiso de ejecución

Escribe el script:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

- `cat > archivo <<'EOF'` … `EOF` — un heredoc: las líneas entre los dos `EOF` se pasan a `cat` y se guardan en el archivo con `>`. Entrecomillar `'EOF'` evita que `$(...)` se ejecute ahora, así que se guarda literalmente.
- `#!/bin/bash` — el shebang; indica al kernel qué intérprete ejecuta el archivo.
- `$(uname -n)` — nombre del host; `awk '{print $1}' /proc/uptime` — segundos desde el arranque (primer campo).

Hazlo ejecutable:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — añade el permiso de ejecución (x); sin él, `./script` falla con `Permission denied`.

Ejecútalo:

```
~/work/sysinfo.sh
```

- Al ejecutarlo por su ruta, lo ejecuta el `/bin/bash` del shebang (`bash archivo` funciona incluso sin el bit de ejecución).

Confirma que funciona y pulsa **[Comprobar]**.

## Argumentos y códigos de salida

Los argumentos del script llegan como `$1 $2 …`, y su número como `$#`. La convención ante una invocación incorrecta es **imprimir el uso en stderr y salir con un código distinto de cero**: quien lo llama (otros scripts, CI) debe poder detectar el fallo.

Tarea: escribe `~/work/logcut.sh <archivo_log> <estado>`.

- imprime el número de líneas con el código de estado indicado en el formato de `/opt/lab/data/app.log` (`… status=200 msg=…`)
- si no hay exactamente 2 argumentos: imprime el uso + código de salida 2

Escribe el script:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

- `usage() { …; }` — una función. `>&2` envía el mensaje a stderr y `exit 2` termina con el código de salida 2.
- `[ $# -eq 2 ] || usage` — si el número de argumentos (`$#`) no es 2, llama a usage (`||`). `[ ]` es el comando de condición (`test`).
- `grep -c "status=$2 " "$1"` — cuenta las líneas con el código de estado del argumento 2. Las variables van entre comillas dobles para que las rutas con espacios sigan siendo seguras.

Hazlo ejecutable:

```
chmod +x ~/work/logcut.sh
```

- Cada script nuevo necesita el bit de ejecución.

> `grep -c` sale con **código 1** cuando no hay coincidencias. Con `set -e` eso mata el script, así que `|| true` deja claro que "cero coincidencias está bien": mantén el fail-fast, pero no trates como fallo lo que no lo es.

Pruébalo y pulsa **[Comprobar]**.

Llamada normal: cuenta las líneas con 500:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- El primer argumento pasa a ser `$1` (archivo de log) y el segundo `$2` (código de estado).

Llamada sin argumentos: se espera el código de salida 2:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — código de salida del comando anterior; `;` lo ejecuta justo después para confirmar que usage salió con 2.

## Limpieza garantizada con trap

Un script que crea archivos temporales deja basura si muere a medias. `trap '…' EXIT` es un gancho de limpieza que siempre se ejecuta cuando termina el script, **tanto si sale con normalidad como por error**.

Tarea: escribe `~/work/withtmp.sh`.

- crea un directorio temporal con `mktemp -d` y cualquier archivo dentro
- borra el directorio temporal al salir mediante `trap`
- imprime la ruta del directorio temporal como **última línea de salida** (la verificación comprueba que esa ruta ya no existe)

Escribe el script:

```
cat > ~/work/withtmp.sh <<'EOF'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
date > "$tmp/scratch.txt"
echo "$tmp"
EOF
```

- `mktemp -d` — crea un directorio temporal con un nombre único e imprime su ruta.
- `trap 'comando' EXIT` — ejecuta el comando justo antes de que el script salga, sea cual sea el motivo; aquí, borrar el directorio temporal.
- `rm -rf "$tmp"` — borra el directorio con su contenido (`-r`) sin preguntar (`-f`). El cuerpo del trap va entre comillas simples, así que `$tmp` se expande al ejecutarse.

Hazlo ejecutable:

```
chmod +x ~/work/withtmp.sh
```

- Añade el bit de ejecución.

Ejecútalo y confirma el borrado:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" significa que funcionó
```

- `d=$(script)` — guarda la salida del script (la ruta temporal) en `d`.
- `ls -d "$d"` — busca el propio directorio; `2>&1` muestra también el mensaje de error. Ya debería haber desaparecido, así que se espera `No such file`.

Una vez confirmado, pulsa **[Comprobar]**.

## Arreglar un script roto

El final es lo que más harás en la vida real: **arreglar el script de otra persona**. `/opt/lab/bin/backup.sh` hace una copia de seguridad de un directorio en /tmp, pero muere cuando la ruta **contiene un espacio**.

Mira el script:

```
cat /opt/lab/bin/backup.sh
```

- Lee antes de arreglar: busca `$src` y `$dest` usados sin comillas.

Prepara un directorio de prueba con espacio en la ruta:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- La ruta contiene un espacio, así que va entre comillas dobles para seguir siendo un solo argumento; después `;` crea dentro un archivo de prueba.

Ejecútalo con la ruta con espacio:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # ¡falla!
```

- Pasas un único argumento entrecomillado, pero en cuanto el script usa `$src` sin comillas se vuelve a dividir en dos palabras (word splitting).

La causa es la **expansión de variables sin comillas**. Cuando `$src` es `/tmp/my app`, `cp -r $src/*` se divide en dos argumentos: `/tmp/my` y `app/*`. Es el más clásico de los fallos clásicos de los scripts de shell.

Tarea: cópialo a `~/work/backup-fixed.sh` y arréglalo.

- entrecomilla toda expansión de variable con `"…"` (`"$dest"`, `"$src"/*`: ¡el glob `*` queda fuera de las comillas!)
- añade `set -euo pipefail`
- ejecútalo con la ruta con espacio y confirma que funciona

Haz una copia:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <origen> <destino>` — deja el original intacto y pone una copia en tu directorio de trabajo.

Arréglalo en el editor:

```
vim ~/work/backup-fixed.sh
```

- vim: `i` para el modo de inserción y luego `Esc` → `:wq` para guardar y salir. Si lo prefieres, usa `nano` (`Ctrl+O` guardar, `Ctrl+X` salir).

Ejecútalo con la ruta con espacio para confirmarlo:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — ejecuta B solo si A tuvo éxito (código de salida 0); ver `OK` significa que el arreglo funciona.

Si funciona, pulsa **[Comprobar]**: módulo completado.
