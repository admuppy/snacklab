# Ein qcow2-Image erstellen und hochladen

Jede Instanz startet aus einem **Image** — einer Disk mit Betriebssystem, eingefroren in eine
einzelne Datei und von glance verwahrt. In diesem Lab erstellst du Disk-Dateien selbst, konvertierst sie zwischen
Formaten, lädst eine zu glance hoch und bootest daraus eine Instanz.

**qcow2** (QEMU Copy On Write 2) ist das mit OpenStack am häufigsten genutzte Disk-Format. Zwei
Eigenschaften sind hier wichtig:

- **Sparse-Zuweisung** — eine Disk mit 1 GiB virtueller Größe belegt nur so viel Dateiplatz, wie tatsächlich
  Daten geschrieben wurden; so bleiben Images beim Transport klein.
- **Sie trägt Metadaten** — Backing Files, Snapshots und Kompression stecken in der Datei.

**raw** dagegen ist die schlichte Byte-für-Byte-Abbildung der Disk. Es hat keine Struktur, ist daher
einfach und spart eine I/O-Schicht, aber die Datei belegt meist die volle virtuelle Größe. Eine übliche
Aufteilung im Betrieb lautet: „qcow2 ausliefern, raw speichern".

> Referenz: [Virtual Machine Image Guide](https://docs.openstack.org/image-guide/) ·
> [Convert between image formats](https://docs.openstack.org/image-guide/convert-images.html)

> Hinweis: nova läuft in diesem Lab mit dem Fake-Treiber, daher bootet in der Instanz kein echtes
> Betriebssystem. Geprüft wird der gesamte Weg von einer Disk-Datei über ein registriertes Image bis zu einer
> daraus erstellten Instanz.

Gearbeitet wird in `~/images`, das der Bootstrap bereits angelegt hat, ebenso wie das Netz `net1`, an das die
Instanz angeschlossen wird.

## 1. Eine leere qcow2-Disk erstellen

`qemu-img` ist das Werkzeug zum Erstellen und Konvertieren von Disk-Images. Beginne mit einer leeren qcow2-Disk, um zu
sehen, wie sich das Format verhält.

Leere qcow2-Disk mit 1 GiB virtueller Größe erstellen:

```bash
qemu-img create -f qcow2 ~/images/blank.qcow2 1G
```

- `qemu-img create` — erstellt eine neue Disk-Image-Datei.
- `-f qcow2` — das Format der Datei, dann der Pfad und zuletzt `1G` — die virtuelle Größe, die der Gast sieht.

Gerade erstellte Disk ansehen:

```bash
qemu-img info ~/images/blank.qcow2
```

- `qemu-img info` — zeigt die Metadaten des Images: Format (`file format`), virtuelle Größe, tatsächliche Größe, Cluster-Größe, …

`virtual size` ist die Disk, die der Gast sieht; `disk size` ist, was die Datei tatsächlich belegt. Die
neue Disk enthält keine Daten, daher liegen beide weit auseinander — das ist Sparse-Zuweisung.

Größe auf der Platte prüfen:

```bash
ls -lh ~/images/blank.qcow2
```

- `ls -l` — ausführliche Auflistung (Rechte, Eigentümer, Größe, Zeit); `-h` — lesbare Größen (K/M/G).
- Das ist die scheinbare Größe der Datei; die tatsächlich belegten Blöcke zeigt `du -h`.

## 2. Disk-Formate konvertieren (qcow2 ↔ raw)

Jetzt arbeitest du mit einer Disk, auf der wirklich ein Betriebssystem liegt: Hole das Image `cirros` aus glance und
konvertiere es.

Formate des registrierten Images prüfen:

```bash
openstack image show cirros -c disk_format -c container_format -c size
```

- `openstack image show <Name>` — Eigenschaften eines glance-Images; `-c` wählt die Spalten `disk_format`, `container_format` und `size` (Bytes).

`disk_format` ist das Format der Disk-Datei selbst (qcow2, raw, vmdk, …), während
`container_format` den Metadaten-Umschlag darum beschreibt. `bare` bedeutet, dass es keinen
Umschlag gibt — nur die Disk — und das verwendet so gut wie jeder.

Image-Datei herunterladen:

```bash
openstack image save cirros --file ~/images/cirros-src.img
```

- `openstack image save <Name> --file <Pfad>` — lädt die in glance gespeicherten Image-Daten in eine lokale Datei herunter (trotz des Namens ein Download).

Format der heruntergeladenen Datei prüfen:

```bash
qemu-img info ~/images/cirros-src.img
```

- Auch mit der Endung `.img` wird das echte Format am Inhalt erkannt; sieh dir die Zeile `file format` an.

qcow2 in raw konvertieren (`-f` ist das Eingabe-, `-O` das Ausgabeformat):

```bash
qemu-img convert -f qcow2 -O raw ~/images/cirros-src.img ~/images/cirros-raw.img
```

- `qemu-img convert` — kopiert ein Image in ein anderes Format (die Quelle bleibt unverändert).
- `-f qcow2` — Eingabeformat (kleines f), `-O raw` — Ausgabeformat (großes O), gefolgt von Quell- und Zielpfad.

raw-Disk ansehen:

```bash
qemu-img info ~/images/cirros-raw.img
```

- raw hat keine Metadaten, daher siehst du vor allem `file format: raw` und die Größen.

raw hat keine Struktur, daher liegt `disk size` nahe bei `virtual size`. Für den Transport ist das ungünstig, also
wird zurückkonvertiert.

raw zurück in qcow2 konvertieren:

```bash
qemu-img convert -f raw -O qcow2 ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Jetzt raw rein, qcow2 raus. Leere Blöcke werden nicht geschrieben, daher schrumpft die Datei wieder (mit `-c` wird zusätzlich komprimiert).

Alle drei Dateien nebeneinander vergleichen:

```bash
ls -lh ~/images/cirros-src.img ~/images/cirros-raw.img ~/images/cirros-lab.qcow2
```

- Listet mehrere Dateien auf einmal auf, um die Größen von Original, raw und zurückkonvertiertem qcow2 zu vergleichen.

## 3. Zu glance hochladen und eine Instanz booten

Registriere die qcow2-Datei bei glance. **Die angegebenen Formate müssen zur Datei passen**: Eine
qcow2-Datei als `--disk-format raw` hochzuladen klappt — und scheitert dann beim Booten.

Die übrigen Optionen bedeuten:

- `--min-disk` / `--min-ram` — Hinweise auf die mindestens benötigte Disk und den Speicher für dieses Image. nova
  filtert Flavors heraus, die sie nicht erfüllen.
- `--property` — beliebige Metadaten. Bekannte Schlüssel wie `os_distro` können in Scheduling und
  Hypervisor-Einstellungen einfließen.

qcow2-Datei als glance-Image registrieren:

```bash
openstack image create cirros-lab --disk-format qcow2 --container-format bare --min-disk 1 --min-ram 64 --property os_distro=cirros --file ~/images/cirros-lab.qcow2
```

- `openstack image create cirros-lab` — registriert ein neues glance-Image `cirros-lab`.
- `--disk-format qcow2 --container-format bare` — das echte Format der Datei und der Umschlag (keiner).
- `--min-disk 1 --min-ram 64` — minimale Disk (GB) und RAM (MB); `--property os_distro=cirros` — beliebige Metadaten.
- `--file <Pfad>` — die hochzuladende lokale Datei; `status` wird `active`, sobald der Upload fertig ist.

Ergebnis prüfen (`status` muss `active` sein):

```bash
openstack image show cirros-lab -c status -c disk_format -c container_format -c min_disk -c min_ram -c properties
```

- Wähle nur die Spalten, die du brauchst, um die registrierten Werte zu bestätigen; `--property`-Werte stehen unter `properties`.

Prüfen, ob es in der Image-Liste erscheint:

```bash
openstack image list
```

- Sobald `cirros-lab` als `active` erscheint, kann es für Instanzen verwendet werden.

Die Instanz `vm2` aus deinem eigenen Image booten:

```bash
openstack server create --flavor m1.tiny --image cirros-lab --network net1 vm2
```

- Gleiche Form wie in Modul 1, aber `--image cirros-lab` verweist auf dein eigenes Image. Der Flavor muss `--min-disk`/`--min-ram` erfüllen.

Status und verwendetes Image prüfen:

```bash
openstack server show vm2 -c status -c image
```

- Zeigt die Spalte `image` `cirros-lab` und seine ID, wurde die Instanz aus dem hochgeladenen Image gebaut.
