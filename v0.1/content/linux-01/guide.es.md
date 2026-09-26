# Permisos de archivo y bits especiales

El primer paso de la seguridad en Linux son los **permisos de archivo**. Este módulo cubre los permisos básicos (rwx) y el umask, bits especiales como setgid y sticky, el control de acceso detallado con ACLs y, por último, una auditoría práctica: encontrar y corregir permisos peligrosos en un sistema real.

Comprobemos el usuario actual. `learner` es un usuario normal con acceso a sudo.

```
id
```

- `id` — el UID del usuario actual, su grupo primario (`gid`) y todos los grupos a los que pertenece (`groups`).

Debes poder pasar de una notación de permisos a la otra.

| Notación | Ejemplo | Significado |
|---|---|---|
| Simbólica | `rwxr-x---` | propietario rwx / grupo r-x / otros nada |
| Octal | `750` | suma de r=4, w=2, x=1 |

## Permisos básicos y umask

Cuando se crea un archivo, sus permisos por defecto los decide el **umask**.

Comprueba el umask actual:

```
umask
```

- `umask` — bits de permiso que se **quitan** a los archivos/directorios nuevos. El habitual `0022` quita la escritura a grupo/otros → archivos 644, directorios 755.

Crea un archivo y mira qué permisos recibe realmente:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

- `touch` — crea un archivo vacío (o solo actualiza su fecha). `&&` — ejecuta el siguiente comando solo si este tuvo éxito.
- `stat -c %a` — formato personalizado (`-c`) que imprime solo los permisos en octal (`%a`).

Ahora crea un espacio de trabajo al que solo tú puedas acceder. Requisitos:

- directorio `~/work` — modo **700** (rwx solo para el propietario)
- archivo `~/work/secret.txt` — cualquier contenido, modo **600** (rw solo para el propietario)

Crea el directorio de trabajo con modo 700:

```
mkdir -p ~/work && chmod 700 ~/work
```

- `mkdir -p` — crea los directorios padre necesarios, sin error si ya existe.
- `chmod 700` — modo octal: propietario rwx (7), grupo/otros nada (0).

Crea el archivo secreto:

```
echo "top secret" > ~/work/secret.txt
```

- `echo "…" > archivo` — escribe la cadena en el archivo (se crea si no existe y se sobrescribe si existe). Los permisos del archivo nuevo siguen el umask.

Pon el modo del archivo en 600:

```
chmod 600 ~/work/secret.txt
```

- `600` — propietario rw (6 = 4+2), nada para grupo/otros. En simbólico: `chmod u=rw,go= <archivo>`.

Confírmalo con `stat` y pulsa **[Comprobar]**.

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

- `%a` permisos en octal, `%n` nombre de archivo; una línea por cada archivo indicado.

> El bit `x` de un directorio significa "permiso de paso (entrada)". Aunque tengas `r` en un directorio, sin `x` no puedes llegar a sus archivos; lo volveremos a ver en el paso de ACL.

## setgid y el bit sticky

Dos bits especiales que usarás a menudo en directorios compartidos por un equipo:

| Bit | Octal | Efecto en un directorio |
|---|---|---|
| setgid | 2000 | los archivos creados dentro **heredan el grupo del directorio** |
| sticky | 1000 | solo el **propietario** puede borrar un archivo (como en `/tmp`) |

Crea el directorio compartido `/srv/share` para el grupo `share`. Requisitos:

- Crear el grupo: `share`
- directorio `/srv/share`, grupo propietario `share`
- Modo **3775** = setgid(2000) + sticky(1000) + 775

Crea el grupo:

```
sudo groupadd -f share
```

- `groupadd` — crea un grupo; `-f` termina con éxito sin avisar si ya existe.

Crea el directorio compartido:

```
sudo mkdir -p /srv/share
```

- `/srv` pertenece a root, de ahí el `sudo`.

Asigna el grupo propietario share:

```
sudo chgrp share /srv/share
```

- `chgrp <grupo> <ruta>` — cambia solo el grupo propietario; usa `chown usuario:grupo` para cambiar ambos.

Pon el modo 3775 con los bits especiales:

```
sudo chmod 3775 /srv/share
```

- En un modo octal de cuatro dígitos, el primero contiene los bits especiales: `3` = setgid (2) + sticky (1). El resto, `775`, es rwx para propietario/grupo y r-x para otros.

Comprueba el resultado. En notación simbólica, setgid aparece como `s` en la posición del grupo y sticky como `t` en la última posición (`drwxrwsr-t`).

Comprueba el modo y el grupo propietario:

```
stat -c '%a %G %n' /srv/share
```

- `%G` — el nombre del grupo propietario.

Mira la notación simbólica:

```
ls -ld /srv/share
```

- `ls -ld` — el propio directorio (`-d`), no su contenido, en forma simbólica (`drwxrwsr-t`).

Cuando esté bien, pulsa **[Comprobar]**.

## Acceso detallado con ACLs

`rwx` solo tiene tres casillas: propietario/grupo/otros. "Permitir leer este archivo a **un único usuario concreto**" se resuelve con una **ACL** (Access Control List).

En el sistema ya existe una cuenta de auditoría llamada `audit`. Abre a `audit` el `~/work/secret.txt` del paso 1 en **solo lectura**.

Concede a audit una ACL de lectura:

```
setfacl -m u:audit:r ~/work/secret.txt
```

- `setfacl -m` — añade/modifica una entrada ACL con el formato `u:<usuario>:<permisos>` (`g:` para grupos).

Comprueba las entradas ACL:

```
getfacl ~/work/secret.txt
```

- `getfacl` — muestra propietario, grupo, todas las entradas ACL y la `mask` (los permisos ACL máximos).

Pero con eso no basta: para que `audit` **llegue** de verdad al archivo, debe poder atravesar los directorios de la ruta (`~` y `~/work`). Un directorio 700 bloquea a audit.

Concede solo el permiso de paso (x) mediante ACL:

```
setfacl -m u:audit:x ~ ~/work
```

- Dar solo `x` en un directorio permite **atravesarlo** sin listarlo (r). Se aplica a las dos rutas (`~`, `~/work`) a la vez.

Compruébalo desde el punto de vista de audit.

Lectura — debería funcionar:

```
sudo -u audit cat ~/work/secret.txt
```

- `sudo -u <usuario> <comando>` — ejecuta el comando como otro usuario para verificar los permisos reales.

Escritura — debería fallar:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

- `sh -c '…'` — arranca una shell completa como audit para que la redirección (`>>`) también se ejecute con los permisos de audit.
- `~learner` — el directorio personal de learner (para audit, `~` sería su propio directorio personal).

Los archivos con ACL muestran un `+` tras los bits de permiso en `ls -l`. Confírmalo y pulsa **[Comprobar]**.

## Auditoría y reparación de permisos

Por último, una tarea del mundo real. Los ejecutables con el bit **SUID** (4000) se ejecutan con los privilegios del propietario (normalmente root), así que son la máxima prioridad en cualquier auditoría.

Busca todos los archivos SUID del sistema y guarda la lista:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

- `find /` — búsqueda recursiva desde la raíz. `-xdev` — no entra en otros sistemas de archivos (/proc, …).
- `-perm -4000` — archivos que **incluyen** el bit SUID (`-` = "tiene todos estos bits"). `-type f` — solo archivos normales.
- `> ~/work/suid.txt` — guarda la lista en un archivo.

Muestra la lista:

```
cat ~/work/suid.txt
```

- `cat` — imprime la lista guardada de archivos SUID.

Piensa por qué `passwd` es SUID: un usuario normal tiene que poder actualizar `/etc/shadow`, que pertenece a root.

Segunda tarea: `/opt/lab/perm/danger.conf` es un archivo de configuración con una contraseña de base de datos, pero se entregó con modo **666** (¡cualquiera puede leerlo y escribirlo!).

Comprueba los permisos actuales:

```
ls -l /opt/lab/perm/
```

- `ls -l` — comprueba los permisos (`-rw-rw-rw-` = 666), el propietario y el grupo.

Repáralo a 640:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

- `640` — propietario rw, grupo r, otros nada: la aplicación puede seguir leyendo a través de su grupo y el resto queda fuera.

Tras la reparación, pulsa **[Comprobar]** para completar el módulo.
