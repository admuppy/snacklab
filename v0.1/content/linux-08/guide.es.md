# Proyecto final: revivir un servicio caído

Las 2 de la madrugada y salta el aviso: **"lab-app no arranca."** Este módulo es un escenario final en el que gestionas un incidente real de principio a fin usando todo lo aprendido hasta ahora (systemd, journald, seguimiento de señales y puertos, permisos de archivo).

Esta vez no se te darán todos los comandos: el **orden del diagnóstico** es el objetivo de aprendizaje. Si te atascas, recuerda las herramientas de los módulos anteriores: `systemctl status/cat`, `journalctl -u`, `sudo ss -ltnp`, `ls -l`, `sudo -u <usuario>`.

Empieza por evaluar la situación.

```
systemctl status lab-app --no-pager
```

- Busca la primera pista en la línea `Active:` y en las últimas líneas de log. `--no-pager` imprime sin less.

## Diagnosticar el fallo de arranque — 203/EXEC

Cuando status no basta, el journal sabe la respuesta.

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <unidad>` — solo los logs de esa unidad; `| tail -20` se centra en las 20 líneas más recientes.

`status=203/EXEC`: el código que ya viste en linux-06. Averigua **qué intentaba ejecutar la unidad** cuando falló.

```
systemctl cat lab-app
```

- Muestra el archivo de la unidad tal cual. Fíjate en `ExecStart=` (qué se ejecuta) y en `User=` (quién lo ejecuta).

Compara la ruta del intérprete en ExecStart con lo que existe realmente en este sistema (`ls /usr/bin/python3*`). Estará apuntando a una versión que no existe: un accidente habitual cuando un script de despliegue se escribió para otro servidor.

Tarea: corrige ExecStart para que apunte a un intérprete que exista y haz `daemon-reload`. Una vez corregido, pulsa **[Comprobar]**.

> start todavía no funcionará: los incidentes rara vez tienen una sola capa. Pasa al siguiente paso.

## Resolver un conflicto de puertos

Ahora, al arrancarlo, aparece otro error.

Intenta arrancar el servicio:

```
sudo systemctl start lab-app
```

- Vuelve a intentarlo tras la corrección; si falla, el siguiente log te dirá la nueva causa.

Revisa el log de errores:

```
journalctl -u lab-app --no-pager | tail -5
```

- Solo importa el log de ese último intento, así que bastan las 5 últimas líneas.

`Address already in use`: **otra cosa ha ocupado** el 8080 que necesita lab-app. Usa lo aprendido en linux-02 y linux-07 sobre el seguimiento de puertos para encontrar al culpable.

```
sudo ss -ltnp | grep 8080
```

- Encuentra el socket que escucha en 8080 y su proceso (`users:(("nombre",pid=…))`). Anota el PID.

Para llegar desde un PID a su unidad, `systemctl status <PID>` es muy práctico. El culpable es una unidad heredada que está pendiente de retirarse. Detenerla no basta: volverá tras un reinicio, así que **también debes deshabilitarla**.

Tarea: tumba al intruso con `disable --now` y arranca lab-app. Cuando lab-app esté active, pulsa **[Comprobar]**.

## Resolver un problema de permisos

El servicio está en marcha... pero aún no hemos terminado.

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — incluye la línea de estado (`HTTP/1.0 404 …`) y las cabeceras antes del cuerpo.

**404**, y sin embargo el archivo existe claramente (`ls -l /srv/lab-app/`). ¿Por qué?

Dos pistas. ① La unidad tiene `User=labapp`: el servicio se ejecuta como labapp, no como root. ② index.html es `root:root 600`: **labapp no puede leerlo.** Este servidor (http.server) devuelve 404 cuando no puede abrir un archivo. Un problema de permisos de manual: "el archivo existe pero da 404".

Acostúmbrate a verificar las sospechas: lee el archivo como ese usuario.

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <usuario> <comando>` — ejecuta el comando como ese usuario: lees el archivo exactamente con los permisos que tiene el servicio.

Tarea: corrige el propietario o los permisos para que labapp pueda leerlo (con la mentalidad de linux-01: no lo abras más de lo necesario). Cuando curl devuelva `LAB APP OK`, pulsa **[Comprobar]**.

## Evitar que se repita y cerrar

La recuperación es un conjunto de dos: "que funcione ahora" + **"que siga funcionando la próxima vez."** La lista de comprobación:

1. ¿Está lab-app **habilitado**? (una recuperación que vuelve a morir al reiniciar no es una recuperación)
2. Conserva la respuesta final como prueba: guárdala en `~/work/final.txt`

Habilita el arranque al iniciar:

```
sudo systemctl enable lab-app
```

- `enable` — registra el arranque automático al iniciar (crea el enlace simbólico); no afecta al servicio en marcha. Compruébalo con `systemctl is-enabled lab-app`.

Guarda la respuesta final:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- Guarda con `>` en un archivo el cuerpo que devuelve `curl -s`.

Verifica el contenido guardado:

```
cat ~/work/final.txt
```

- Confirma que la respuesta guardada dice `LAB APP OK`.

Pulsa **[Comprobar]** y habrás completado el itinerario de Linux. Recuerda: el triple fallo que has resuelto hoy (ruta equivocada → conflicto de puertos → permisos) es la combinación más habitual en los informes de incidentes reales, y los tres **los sabían antes que nadie el journal, ss y ls -l**.
