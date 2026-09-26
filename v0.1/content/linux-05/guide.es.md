# Usuarios, grupos y sudo con mínimo privilegio

Cuando llega un nuevo compañero a un servidor, creas su cuenta, lo añades al grupo del equipo y le abres **solo el** sudo que necesita. Cuando se va, bloqueas la cuenta. Este módulo cubre todo ese ciclo de vida.

Primero, dónde vive la información de las cuentas.

| Archivo | Contenido |
|---|---|
| `/etc/passwd` | lista de usuarios (nombre:x:UID:GID:comentario:home:shell) |
| `/etc/shadow` | hashes de contraseña + política de caducidad (solo legible por root) |
| `/etc/group` | grupos y sus miembros |
| `/etc/sudoers`, `/etc/sudoers.d/` | reglas de permisos de sudo |

Consulta la cuenta learner:

```
getent passwd learner
```

- `getent <base de datos> <clave>` — consulta una entrada a través de NSS; imprime la línea de `learner` de la base de datos `passwd`.

Echa un vistazo al principio de shadow:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` solo lo puede leer root, de ahí el `sudo`. El segundo campo es el hash de la contraseña (`*` o `!` significa sin inicio de sesión por contraseña).

> `getent` consulta a través de NSS (incluidas fuentes externas como LDAP) en lugar de abrir los archivos directamente: un hábito más preciso que `cat /etc/passwd`.

## Crear usuarios

Crea la cuenta de despliegue `deploy`. Requisitos:

- crear un directorio personal (`-m`: sin él obtienes una cuenta sin home)
- shell de inicio `/bin/bash` (`-s`: muchas distribuciones usan sh por defecto)

Crea el usuario deploy:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — crea un usuario: `-m` crea el directorio personal (copiando `/etc/skel`), `-s /bin/bash` fija la shell de inicio y el último argumento es el nombre de usuario.
- La contraseña se establece aparte con `passwd deploy` (no hace falta en este laboratorio).

Comprueba la entrada de passwd:

```
getent passwd deploy
```

- De los campos separados por dos puntos, los dos últimos son el directorio personal y la shell: comprueba que sean `/home/deploy` y `/bin/bash`.

Comprueba el directorio personal:

```
ls -ld /home/deploy
```

- `ls -ld` — muestra el propio directorio (`-d`), no su contenido: permisos y propietario. El propietario debe ser `deploy`.

`useradd` es una herramienta de bajo nivel y **no te pregunta nada**. Si omites una opción, simplemente crea la cuenta tal cual, así que verificar después es obligatorio. Una vez verificado, pulsa **[Comprobar]**.

## Configurar grupos

Crea el grupo de operaciones `ops` y añade a deploy. Aquí hay una trampa clásica:

| Comando | Resultado |
|---|---|
| `usermod -aG ops deploy` | **añade** ops como grupo suplementario ✔ |
| `usermod -G ops deploy` | **sustituye** todos los grupos suplementarios por solo ops (¡se pierde todo lo demás!) |
| `usermod -g ops deploy` | **sustituye el grupo primario** (cambia el grupo por defecto de los archivos nuevos) |

`-G` sin `-a` (append) es un atajo hacia un incidente. Añádelo como grupo suplementario.

Crea el grupo ops:

```
sudo groupadd ops
```

- `groupadd <grupo>` — crea un grupo nuevo; se añade una línea a `/etc/group`.

Añádelo como grupo suplementario:

```
sudo usermod -aG ops deploy
```

- `usermod` — modifica un usuario existente. `-G ops` fija los grupos suplementarios y `-a` los **añade** a los existentes.
- Las sesiones ya iniciadas solo ven el grupo nuevo tras volver a iniciar sesión.

Verifica los grupos:

```
id deploy
```

- `id <usuario>` — UID, grupo primario (`gid=`) y todos los grupos (`groups=`) en una línea.

En la salida de `id`, aprende a distinguir `gid=` (primario) de `groups=` (todos). Una vez verificado, pulsa **[Comprobar]**.

## sudoers con mínimo privilegio

Queremos que deploy pueda consultar el estado de los servicios, pero **nada más**. La convención es no editar `/etc/sudoers` directamente, sino crear archivos complementarios (drop-ins) en `/etc/sudoers.d/`.

Sintaxis: `quién dónde=(como-quién) [NOPASSWD:] comandos`

Escribe la regla complementaria:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo 'regla' | sudo tee <archivo>` — con `sudo echo … > archivo` es tu propia shell la que hace la redirección y falla por permisos, así que escribe el archivo `tee`, que se ejecuta como root.
- La regla: `deploy`, en cualquier host (`ALL`), como cualquier usuario (`(ALL)`), sin contraseña (`NOPASSWD:`), solo puede ejecutar `systemctl status *`.

Pon el modo 440:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — solo lectura para el propietario (root) y el grupo. sudo rechaza los archivos sudoers en los que otros pueden escribir.

**Validar la sintaxis es obligatorio.** Un sudoers roto rompe el propio sudo y complica mucho la recuperación. `visudo -cf` es la red de seguridad.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — solo comprobación de sintaxis, `-f <archivo>` — el archivo que se comprueba; debería imprimir `parsed OK`.
- La forma normal de editar sudoers es `sudo visudo`, que comprueba antes de guardar.

Comprueba qué puede hacer realmente deploy.

Lista los permisos sudo de deploy:

```
sudo -l -U deploy
```

- `sudo -l` — lista los comandos sudo permitidos; `-U deploy` — para otro usuario (requiere root).

Comando permitido — debería funcionar:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # permitido
```

- `sudo -u deploy <comando>` — ejecuta el comando como deploy; dentro se vuelve a llamar a `sudo` para probar los permisos sudo de deploy.
- `sudo -n` — nunca pide contraseña (no interactivo); falla al instante si hiciera falta una.
- `--no-pager` — imprime directamente en lugar de pasar la salida a less.

Comando denegado — debería rechazarse:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # denegado
```

- `restart` no está en la regla, así que se rechaza. `2>&1` envía también el error a la tubería y `tail -1` muestra la última línea.

Si permitir/denegar se comporta como se espera, pulsa **[Comprobar]**.

## Bloqueo de cuentas y política de contraseñas

`olduser` pertenece a alguien que se ha ido. Borrarla (`userdel`) plantea problemas de limpieza de la propiedad de archivos, así que el primer paso habitual es **bloquearla**.

Bloquea la cuenta:

```
sudo usermod -L olduser
```

- `usermod -L` — bloquea la cuenta anteponiendo `!` al hash de shadow, lo que impide el inicio de sesión con contraseña. Se desbloquea con `-U`.

Comprueba el estado del bloqueo:

```
sudo passwd -S olduser
```

- `passwd -S <usuario>` — resumen del estado de la contraseña; segundo campo `L` bloqueada, `P` utilizable, `NP` sin contraseña.

Si el segundo campo de `passwd -S` es `L` (locked), ha funcionado. El bloqueo solo antepone `!` al hash en shadow, así que siempre puede revertirse con `-U`.

A continuación, aplica a deploy una **caducidad máxima de contraseña de 90 días**.

Aplica el máximo de 90 días:

```
sudo chage -M 90 deploy
```

- `chage` — cambia la política de caducidad de contraseñas; `-M 90` — antigüedad máxima de 90 días.

Verifica la política:

```
sudo chage -l deploy
```

- `chage -l` — lista la política actual: último cambio, caducidad, días mínimos/máximos, …

Cuando hayas confirmado ambas cosas, pulsa **[Comprobar]**: módulo completado.
