# Cadenas de procesamiento de texto

La mitad de la operación de Linux consiste en **leer logs**. Encadena grep, awk y sed con tuberías y podrás sacar respuestas de cientos de miles de líneas de log en segundos.

El entorno del laboratorio tiene preparado un log de accesos de un servidor web de 2.000 líneas. Primero, mira su forma.

Mira las 5 primeras líneas:

```
head -5 /var/log/lab/access.log
```

- `head -5 <archivo>` — imprime solo las 5 primeras líneas (igual que `-n 5`).

Cuenta el total de líneas:

```
wc -l /var/log/lab/access.log
```

- `wc -l <archivo>` — cuenta líneas (word count, modo línea); `-w` cuenta palabras y `-c` bytes.

La estructura de una línea (números de campo separados por espacios):

| Campo | Contenido | Ejemplo |
|---|---|---|
| $1 | IP del cliente | `192.168.14.23` |
| $6~$8 | Petición (`"METHOD path HTTP/1.1"`) | `"GET /api/users HTTP/1.1"` |
| $9 | Código de estado | `200` |
| $10 | Bytes de respuesta | `1532` |

## Encontrar errores con grep

grep es una herramienta que **selecciona las líneas** que coinciden con un patrón. Busquemos errores del servidor (5xx). Un `grep 500` ingenuo también encuentra líneas cuyo número de bytes es 500: debes coincidir **solo en la posición del código de estado**.

```
grep -E '" 5[0-9]{2} ' /var/log/lab/access.log | head
```

- `grep -E` — regex extendida; `5[0-9]{2}` es un número de tres cifras que empieza por 5.
- `'" 5[0-9]{2} '` — la comilla y los espacios que la rodean fijan la coincidencia en la posición del código de estado. Todo el patrón va entre comillas simples para que la shell no lo toque.

La clave es anclar el contexto alrededor de la coincidencia, de modo que solo cuente un 5xx tras `"` y un espacio. `-c` imprime solo el número de líneas coincidentes.

Tarea: guarda el número de líneas con error 5xx en `~/work/err5xx.count`.

Guarda el recuento de líneas 5xx:

```
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
```

- `-c` — imprime el **número** de líneas coincidentes en lugar de las líneas; combinado con `-E` queda `-Ec`.
- `> ~/work/err5xx.count` — guarda ese número en un archivo.

Verifica el valor guardado:

```
cat ~/work/err5xx.count
```

- `cat` — imprime el archivo para confirmar el número guardado.

Una vez guardado, pulsa **[Comprobar]**.

## Extracción de campos y agregación con awk

awk trabaja con líneas **divididas en campos**. `$1` es el primer campo (la IP).

```
awk '{print $1}' /var/log/lab/access.log | head
```

- `awk '{print $1}'` — divide cada línea en campos separados por espacios e imprime el primero (la IP). La acción dentro de `{ }` se ejecuta para cada línea.

Añade el clásico pipeline de agregación `sort | uniq -c | sort -rn` y obtendrás una tabla de frecuencias.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn
```

- `sort` — agrupa las IPs idénticas; `uniq -c` — colapsa los duplicados consecutivos y antepone el recuento.
- `sort -rn` — ordenación numérica (`-n`) inversa (`-r`) → la IP con más peticiones arriba.

> `uniq -c` solo cuenta duplicados **adyacentes**, así que `sort` debe ir primero.

Tarea: guarda **solo la IP con más peticiones** (solo la cadena de la IP, sin el recuento) en `~/work/top-ip.txt`. Toma la primera línea con `head -1` y vuelve a extraer solo el campo de la IP con awk.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
```

- `head -1` — conserva la primera línea (`  123 1.2.3.4`).
- `awk '{print $2}'` — toma su segundo campo (la IP) y lo guarda con `>`.

Una vez guardado, pulsa **[Comprobar]**.

## Edición de flujo con sed

Hay que compartir este log con terceros, pero las IPs de los clientes son datos personales y deben **enmascararse**. La sustitución de sed (`s/patrón/reemplazo/`) lo resuelve.

Usa una regex para capturar la IPv4 al principio de cada línea. Con `-E` (regex extendida) puedes usar directamente el cuantificador `{1,3}`.

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log | head -3
```

- `sed -E 's/patrón/reemplazo/'` — reemplaza la primera coincidencia de cada línea e imprime el resultado (el archivo no cambia).
- `^` — inicio de línea, `[0-9]{1,3}` — de 1 a 3 cifras, `\.` — un punto literal; juntos, la dirección IPv4 al inicio de la línea.

Tarea: guarda en `~/work/access-redacted.log` una copia del log completo con las IPs reemplazadas por `REDACTED`. El número de líneas debe coincidir con el original (sustitución, no borrado).

Guarda la copia enmascarada:

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
```

- Aplica la misma sustitución a todo el archivo y guarda una copia nueva. `-i` editaría el original en el sitio, pero aquí lo conservamos.

Cuenta las líneas enmascaradas:

```
grep -c REDACTED ~/work/access-redacted.log
```

- Cuenta las líneas que contienen `REDACTED`; debería coincidir con el número de líneas original de `wc -l`.

Una vez guardado, pulsa **[Comprobar]**.

## Todo el pipeline junto

El final es una pregunta del mundo real: **"¿Cuántos bytes en total se transfirieron en las respuestas correctas (200) a peticiones bajo la ruta /api?"**

Un solo awk puede filtrar y agregar a la vez: una condición selecciona las líneas, una variable acumula y el bloque `END` imprime.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log
```

- `$7 ~ /regex/` — ¿coincide el campo 7 con la regex? Una `/` dentro de la regex se escapa como `\/`.
- La variable `s` empieza en 0 sin declararla; el bloque `END` se ejecuta una vez tras leer todas las líneas.

Desglosado:

| Pieza | Significado |
|---|---|
| `$7 ~ /^\/api\//` | el campo de la ruta empieza por `/api` |
| `&& $9 == 200` | y el estado es 200 |
| `{s += $10}` | acumula el campo de bytes en s |
| `END {print s}` | imprime el total tras leerlo todo |

Tarea: guarda este total en `~/work/api-bytes.txt` y pulsa **[Comprobar]**.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log > ~/work/api-bytes.txt
```

- El mismo comando de antes, con la salida guardada en un archivo mediante `>`.
