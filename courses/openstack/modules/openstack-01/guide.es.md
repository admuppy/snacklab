# Arranca tu primera instancia

Este laboratorio se ejecuta en **tu propio OpenStack todo en uno** (Caracal) dentro del pod. keystone,
glance, neutron y nova se ejecutan aquí, y la terminal ya tiene configuradas credenciales de
administrador: usa directamente la CLI `openstack` (también existe el alias `os`).

> Nota: en este laboratorio nova usa el **controlador fake**: las instancias "arrancan" como simples máquinas
> de estados sin una VM real detrás, así que se inician al instante y apenas consumen recursos.
> El acceso por consola y SSH no funciona, pero el flujo de API/CLI es idéntico al de un OpenStack real.

### Leer el catálogo de servicios

OpenStack no es un solo programa, sino **un conjunto de servicios con funciones distintas**. Cada uno tiene su
propia API REST, y se encuentran entre sí a través del **catálogo de servicios** que mantiene keystone.
`openstack service list` muestra lo que está registrado en ese catálogo.

Estos son los servicios que verás en este laboratorio:

| Servicio | Tipo | Qué hace |
|---|---|---|
| keystone | identity | Autenticación y autorización. Emite el token que comprueban todos los demás servicios |
| glance | image | Guarda y sirve las imágenes de disco a partir de las que se crean las instancias |
| neutron | network | Red virtual: redes, subredes, puertos |
| nova | compute | Ciclo de vida de las instancias: crear, arrancar, detener, borrar |
| placement | placement | Registra qué host tiene aún capacidad (vCPU, RAM, disco) para que nova pueda ubicar instancias |

Comprueba el catálogo de servicios:

```bash
openstack service list
```

- `openstack <objeto> <acción>` — la forma básica de la CLI de OpenStack; aquí el objeto es `service` y la acción `list`.
- Lista los servicios registrados en el catálogo de servicios de keystone. Para las URL de los endpoints usa `openstack endpoint list`.

`Name` es el nombre del servicio y `Type` la cadena estándar de su función. La CLI resuelve los
endpoints por **tipo**: `openstack image list` busca el tipo `image` y llama a glance. Dicho de otro modo,
la primera palabra de un comando (`image`, `network`, `server`, …) corresponde a un tipo de esta tabla.

### Leer la lista de servicios de cómputo

nova también está **dividido en varios procesos**. `openstack compute service list` muestra cuáles
están vivos y en qué host.

| Componente | Qué hace |
|---|---|
| nova-scheduler | Elige **en qué host de cómputo** cae una instancia nueva; placement reduce los candidatos |
| nova-conductor | Se encarga del acceso a la base de datos y de las tareas largas para que los nodos de cómputo nunca toquen la BD directamente |
| nova-compute | Maneja el hipervisor para arrancar y detener instancias. Hay uno en cada host de cómputo |

Comprueba el host de cómputo:

```bash
openstack compute service list
```

- Muestra los procesos en segundo plano de nova (scheduler, conductor, compute) con su host, `Status` (enabled/disabled) y `State` (up/down).

`State` es `up` cuando el proceso está vivo; `Status` indica si un operador lo ha deshabilitado.
Es la primera tabla que hay que mirar cuando las instancias no se pueden planificar: nada llega a un host
cuyo nova-compute está `down`.

**nova-api no aparece en esta lista.** Los servicios de API se ejecutan como servidores web y aparecen como
endpoints en el catálogo de servicios; lo que ves aquí son los procesos en segundo plano. Este laboratorio es todo
en uno, así que los tres componentes muestran el mismo nombre de host.

> Referencia: [Documentación de la CLI de OpenStack](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. Crear una red y una subred

Empieza con una red de proyecto a la que conectar la instancia.

Crea la red `net1`:

```bash
openstack network create net1
```

- Crea la red virtual L2 `net1` en neutron. Todavía no tiene rango IP, así que las instancias no podrían obtener dirección: la subred del siguiente comando la proporciona.

Crea la subred `subnet1` en `net1` con el rango `192.168.100.0/24`:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — la red a la que pertenece la subred.
- `--subnet-range 192.168.100.0/24` — el CIDR; la puerta de enlace (`.1` por defecto) y el rango DHCP se derivan automáticamente.
- El último argumento `subnet1` es el nombre de la subred.

Lista las redes para verificar:

```bash
openstack network list
```

- Cuando la columna `Subnets` muestra el ID de la nueva subred, la red está lista.

## 2. Arrancar una instancia (ACTIVE)

Arranca la instancia `vm1` a partir de la imagen precargada `cirros` con el flavor `m1.tiny`.

Lista las imágenes disponibles:

```bash
openstack image list
```

- Imágenes registradas en glance. Solo las imágenes con `Status` `active` pueden usarse para crear instancias.

Lista los flavors:

```bash
openstack flavor list
```

- Un flavor es una plantilla de tamaño de hardware (vCPU, RAM, disco) para instancias; `m1.tiny` es el más pequeño.

Arranca la instancia:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — tamaño de hardware, `--image cirros` — imagen de disco que se arranca, `--network net1` — red en la que se crea y conecta un puerto.
- El último argumento `vm1` es el nombre de la instancia. El comando solo envía la petición y vuelve (`BUILD`), así que comprueba el estado por separado.

Observa hasta que el estado sea `ACTIVE` (puede tardar unos segundos):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <nombre>` — detalles de una instancia.
- `-c <columna>` — muestra solo las columnas (campos) elegidas; se puede repetir. `addresses` muestra la IP asignada, p. ej. `net1=192.168.100.x`.

## 3. Listar instancias de todos los proyectos

El `openstack server list` que has usado hasta ahora solo muestra **las instancias de tu propio proyecto**.

Un **proyecto** es la unidad que posee recursos en OpenStack (antes se llamaba tenant).
Redes, instancias, volúmenes e imágenes pertenecen todos a un proyecto, y las cuotas se aplican por
proyecto. Los usuarios acceden a un proyecto mediante un **rol**, y los tokens se emiten "como" un proyecto; por eso
la misma persona ve recursos distintos según el proyecto con el que haya iniciado sesión.

Mira a qué proyecto pertenece tu token actual:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — obtiene un token de keystone con tus credenciales actuales y muestra sus detalles.
- `-c project_id -f value` — solo la columna `project_id`, impresa como valor sin bordes de tabla (`-f value`); práctico en scripts.

Este laboratorio ya tiene proyectos como `admin`, `service` y `demo`. Lístalos:

```bash
openstack project list
```

- Proyectos (ID y nombre) de keystone; relaciona aquí el `project_id` del comando anterior con un nombre.

`--all-projects` pide **los recursos de todos los proyectos a la vez**. Es una opción de operador para
ver toda la nube, así que requiere el rol admin; un usuario normal obtiene un error de permisos.

Las columnas por defecto no incluyen el proyecto. Como aquí se trata de ver quién es dueño de qué, elige
esa columna explícitamente con `-c 'Project ID'`. (`--long` es otra opción distinta que añade detalles operativos
como el estado de la tarea y el host.)

Incluye el ID del proyecto:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `--all-projects` — lista las instancias de todos los proyectos (requiere el rol admin).
- `-c <columna>` — muestra solo las columnas (campos) elegidas; se puede repetir. Entrecomilla los nombres de columna con espacios (`'Project ID'`).

Guarda el resultado en un archivo para la evaluación:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — imprime valores separados por espacios en lugar de una tabla.
- `> ~/all-servers.txt` — guarda (sobrescribe) esa salida en un archivo; el script de comprobación lo lee.

> Referencia: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. Detener la instancia (SHUTOFF)

Termina el ciclo de vida deteniendo la instancia.

Detén la instancia:

```bash
openstack server stop vm1
```

- Apaga la instancia. Su disco, su IP y demás recursos se mantienen, y `openstack server start vm1` la vuelve a encender. Para eliminarla por completo usa `openstack server delete`.

Verifica que el estado sea `SHUTOFF`:

```bash
openstack server show vm1 -c status
```

- Confirma que `status` ha cambiado a `SHUTOFF`; si aún no, vuelve a ejecutarlo al cabo de unos segundos.
