# Crear y subir una imagen qcow2

Toda instancia parte de una **imagen**: un disco con un sistema operativo, congelado en un
único archivo y guardado por glance. En este laboratorio creas tú mismo archivos de disco, los conviertes entre
formatos, subes uno a glance y arrancas una instancia a partir de él.

**qcow2** (QEMU Copy On Write 2) es el formato de disco más usado con OpenStack. Aquí importan dos
propiedades:

- **Asignación dispersa (sparse)** — un disco con un tamaño virtual de 1 GiB solo ocupa en el archivo lo que
  realmente se ha escrito, lo que hace que las imágenes sean pequeñas de mover.
- **Lleva metadatos** — archivos de respaldo, instantáneas y compresión viven dentro del archivo.

**raw**, en cambio, es la disposición byte a byte del disco. No tiene estructura, así que es
sencillo y se ahorra una capa de E/S, pero el archivo suele ocupar todo el tamaño virtual. En producción es habitual
repartir así: "distribuir en qcow2, almacenar en raw".

> Referencia: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> Nota: en este laboratorio nova usa el controlador fake, así que ningún sistema operativo arranca de verdad dentro de la
> instancia. Lo que verificas es el camino completo desde un archivo de disco hasta una imagen registrada y una
> instancia creada a partir de ella.

El trabajo se hace en `~/images`, que el arranque inicial ya creó, junto con la red `net1` a la que
conectar la instancia.

## 1. Crear un disco qcow2 vacío

`qemu-img` es la herramienta que crea y convierte imágenes de disco. Empieza con un disco qcow2 vacío para ver
cómo se comporta el formato.

Crea un disco qcow2 vacío con un tamaño virtual de 1 GiB:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — crea un nuevo archivo de imagen de disco.
- `-f qcow2` — el formato del archivo, después la ruta y por último `1G`: el tamaño virtual que verá el invitado.

Inspecciona el disco que acabas de crear:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — muestra los metadatos de la imagen: formato (`file format`), tamaño virtual, tamaño real, tamaño de clúster, …

`virtual size` es el disco que verá el invitado; `disk size` es lo que ocupa realmente el archivo. El
disco nuevo no contiene datos, así que ambos difieren mucho: eso es la asignación dispersa.

Comprueba el tamaño en disco:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — listado detallado (permisos, propietario, tamaño, fecha); `-h` — tamaños legibles (K/M/G).
- Es el tamaño aparente del archivo; los bloques realmente usados se ven con `du -h`.

## 2. Convertir formatos de disco (qcow2 ↔ raw)

Ahora trabaja con un disco que sí contiene un sistema operativo: saca la imagen `cirros` de glance y conviértela.

Comprueba los formatos de la imagen registrada:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <nombre>` — propiedades de una imagen de glance; `-c` elige las columnas `disk_format`, `container_format` y `size` (bytes).

`disk_format` es el formato del propio archivo de disco (qcow2, raw, vmdk, …), mientras que
`container_format` describe el sobre de metadatos que lo envuelve. `bare` significa que no hay
sobre, solo el disco, y es lo que usa casi todo el mundo.

Descarga el archivo de la imagen:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <nombre> --file <ruta>` — descarga a un archivo local los datos de la imagen guardados en glance (pese al nombre, es una descarga).

Comprueba el formato del archivo descargado:

```bash
qemu-img info ~/images/cirros-src.img
```

- Aunque la extensión sea `.img`, el formato real se detecta por el contenido; mira la línea `file format`.

Convierte qcow2 a raw (`-f` es el formato de entrada, `-O` el de salida):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — copia una imagen a otro formato (el original no se toca).
- `-f qcow2` — formato de entrada (f minúscula), `-O raw` — formato de salida (O mayúscula), seguidos de las rutas de origen y destino.

Inspecciona el disco raw:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw no tiene metadatos, así que sobre todo verás `file format: raw` y los tamaños.

raw no tiene estructura, así que `disk size` queda cerca de `virtual size`. Eso es malo para distribuirlo, así que
vuelve a convertirlo.

Convierte raw de nuevo a qcow2:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Ahora entra raw y sale qcow2. Los bloques vacíos no se escriben, así que el archivo vuelve a encogerse (añade `-c` para comprimir también).

Compara los tres archivos lado a lado:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Lista varios archivos a la vez para comparar lado a lado los tamaños del original, del raw y del qcow2 reconvertido.

## 3. Subir a glance y arrancar una instancia

Registra el archivo qcow2 en glance. **Los formatos que declares deben coincidir con el archivo**: subir un
archivo qcow2 como `--disk-format raw` funciona, y después falla al arrancar.

Las demás opciones significan:

- `--min-disk` / `--min-ram` — indican el disco y la memoria mínimos que necesita esta imagen. nova
  descarta los flavors que no los cumplen.
- `--property` — metadatos arbitrarios. Claves conocidas como `os_distro` pueden influir en la planificación y en
  la configuración del hipervisor.

Registra el archivo qcow2 como imagen de glance:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — registra una nueva imagen de glance `cirros-lab`.
- `--disk-format qcow2 --container-format bare` — el formato real del archivo y el sobre (ninguno).
- `--min-disk 1 --min-ram 64` — disco (GB) y RAM (MB) mínimos; `--property os_distro=cirros` — metadatos arbitrarios.
- `--file <ruta>` — el archivo local que se sube; `status` pasa a `active` cuando termina la subida.

Comprueba el resultado (`status` debe ser `active`):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- Elige solo las columnas necesarias para confirmar los valores que registraste; los valores de `--property` aparecen en `properties`.

Confirma que aparece en la lista de imágenes:

```bash
openstack image list
```

- Cuando `cirros-lab` aparece como `active`, ya se puede usar para instancias.

Arranca la instancia `vm2` desde la imagen que has creado:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- Misma forma que en el módulo 1, pero `--image cirros-lab` apunta a tu propia imagen. El flavor debe cumplir `--min-disk`/`--min-ram`.

Comprueba su estado y la imagen que usó:

```bash
openstack server show vm2 -c status -c image
```

- Si la columna `image` muestra `cirros-lab` y su ID, la instancia se creó a partir de la imagen que subiste.
