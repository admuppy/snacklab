# CPU- und Speicherverwaltung

Wird ein Server als „langsam" gemeldet, schaust du zuerst auf **CPU und Speicher**. Dieses Modul behandelt die Werkzeuge zur Beobachtung von Ressourcen, das Anpassen der Prozesspriorität und die tatsächliche Obergrenze, die **cgroup-Speicherlimits und der OOM-Killer** einem Container/Pod setzen.

> Diese Lab-Umgebung ist ein **Container (Pod)**, in dem systemd läuft. Ressourcenlimits werden genauso behandelt wie in einem echten k8s-Pod (cgroup v2, verwaltet von systemd) — wo ein physischer Server sich unterscheidet, weisen wir an der jeweiligen Stelle darauf hin.

Zuerst ein kurzer Blick auf den aktuellen Zustand.

CPU-Anzahl prüfen:

```
nproc
```

- `nproc` — Anzahl der CPUs (Kerne), die dem aktuellen Prozess zur Verfügung stehen; im Container spiegelt sie cgroup- und Affinitätslimits wider.

Speicherstatus prüfen:

```
free -h
```

- `free` — Speicher- und Swap-Nutzung; `-h` in Gi/Mi-Einheiten.
- Die Spalte `available` — was neue Prozesse tatsächlich bekommen können (einschließlich freigebbarem Cache) — ist wichtiger als `free`.

Drei Zusammenfassungen im Sekundentakt:

```
vmstat 1 3
```

- `vmstat <Intervall> <Anzahl>` — 3 Messungen im Abstand von 1 s. Die erste Zeile ist der Durchschnitt seit dem Booten, lies also ab der zweiten.
- `r` lauffähige Prozesse, `si/so` Swap ein/aus, `us/sy/id/wa` CPU-Anteil Benutzer/Kernel/Leerlauf/IO-Warten.

Ein top-Schnappschuss:

```
top -b -n1 | head -12
```

- `top -b` — Textausgabe (Batch) statt interaktivem Bildschirm, `-n1` — ein Durchlauf. `| head -12` behält die Zusammenfassung und die obersten Prozesse.

## Ressourcen beobachten

`free` fasst den Speicher zusammen; `vmstat` bündelt Speicher, Swap und CPU in einer Zeile. Die Rohwerte liegen in `/proc/meminfo` und `/proc/cpuinfo`.

| Befehl | Was er zeigt |
|---|---|
| `free -h` | gesamter/genutzter/verfügbarer Speicher, Swap |
| `vmstat 1` | Speicher, Swap ein/aus (si/so) und CPU im Sekundentakt |
| `nproc` | Anzahl der hier verfügbaren CPUs |
| `cat /proc/meminfo` | Rohwerte MemTotal, MemAvailable, ... |

Aufgabe: Halte einen Schnappschuss des aktuellen Gesamtspeichers und der CPU-Anzahl fest. Speichere die **MemTotal-Zeile aus /proc/meminfo** und eine Zeile **`cpus=<nproc>`** in `~/work/snapshot.txt`.

Arbeitsverzeichnis vorbereiten:

```
mkdir -p ~/work
```

- `mkdir -p` — legt fehlende übergeordnete Verzeichnisse an und schlägt nicht fehl, wenn es schon existiert.

MemTotal-Zeile speichern:

```
grep MemTotal /proc/meminfo > ~/work/snapshot.txt
```

- `grep MemTotal /proc/meminfo` — wählt die Zeile mit dem Gesamtspeicher und speichert sie mit `>` (neue Datei).

cpus-Zeile anhängen:

```
echo "cpus=$(nproc)" >> ~/work/snapshot.txt
```

- `"cpus=$(nproc)"` — `$( )` wird auch in doppelten Anführungszeichen expandiert und ergibt einen String wie `cpus=4`.
- `>>` — **hängt** an die Datei an (`>` würde überschreiben).

Gespeicherten Inhalt prüfen:

```
cat ~/work/snapshot.txt
```

- Prüfe, dass beide Zeilen (MemTotal, cpus=…) vorhanden sind.

Wenn gespeichert, **[Prüfen]** drücken.

## Priorität und CPU-Affinität

Wenn die CPU knapp ist, kannst du nicht jeden Prozess gleich behandeln. Der **nice-Wert** (-20 hoch … 19 niedrig) legt die Scheduler-Priorität fest, und **taskset** bestimmt, auf welchen Kernen ein Prozess läuft (CPU-Affinität).

| Befehl | Rolle |
|---|---|
| `nice -n 19 CMD` | neuen Prozess mit niedriger Priorität starten |
| `renice -n 5 -p PID` | nice-Wert eines laufenden Prozesses ändern |
| `taskset -c 0 CMD` | an CPU 0 gebunden ausführen |
| `taskset -pc PID` | Affinität eines laufenden Prozesses anzeigen/ändern |

Aufgabe: Starte eine CPU-Last (`stress-ng --cpu 1`) **an CPU 0 gebunden** mit **nice 19** (die nachgiebigste Priorität) im Hintergrund. Das ist das klassische Muster, um Batch-Arbeit laufen zu lassen, ohne andere Dienste zu stören.

```
taskset -c 0 nice -n 19 stress-ng --cpu 1 --timeout 1800s >/dev/null 2>&1 &
```

- `taskset -c 0 <Befehl>` — führt den Befehl an CPU 0 gebunden aus (`-c` nimmt eine CPU-Liste wie `0,2` oder `0-3`).
- `nice -n 19 <Befehl>` — läuft mit nice 19 (niedrigste Priorität). Beide Wrapper lassen sich stapeln.
- `stress-ng --cpu 1 --timeout 1800s` — Lastgenerator, der eine CPU 30 Minuten lang zu 100 % auslastet.
- `>/dev/null 2>&1 &` — Ausgabe verwerfen und im Hintergrund ausführen.

Prüfe, ob er wirklich so gestartet wurde — `top` sollte `NI` 19 zeigen und die Affinität CPU 0 sein.

PID des Lastprozesses speichern:

```
pid=$(pgrep -f 'stress-ng.*--cpu' | head -1)
```

- `pgrep -f 'stress-ng.*--cpu'` — Regex-Suche in der gesamten Befehlszeile (`.*` = beliebige Zeichen). `head -1` speichert die erste PID in `pid`.

nice-Wert prüfen:

```
ps -o pid,ni,comm -p "$pid"
```

- `ps -o pid,ni,comm` — nur die Spalten PID, nice-Wert (`NI`) und Befehlsname; `-p "$pid"` für genau diesen Prozess.

CPU-Affinität prüfen:

```
taskset -pc "$pid"
```

- `taskset -p <PID>` — zeigt die Affinität eines laufenden Prozesses; `-c` gibt eine CPU-Liste statt einer Bitmaske aus.

Über /proc gegenprüfen:

```
grep Cpus_allowed_list /proc/$pid/status
```

- `Cpus_allowed_list` in `/proc/<PID>/status` — der Kernel-Eintrag, auf welchen CPUs der Prozess laufen darf; er sollte zu taskset passen.

Sind `NI=19` und die Affinität `0`, **[Prüfen]** drücken. (Lass die Last weiterlaufen — sie beeinflusst den nächsten Schritt nicht.)

## cgroup-Speicherlimits und OOM

Unter Linux setzt **cgroup v2** die CPU-/Speicherobergrenzen für eine Prozessgruppe durch. Container-Ressourcenlimits, `MemoryMax=` eines systemd-Dienstes und **`resources.limits.memory` eines k8s-Pods bauen alle darauf auf**. Hier **legst du eine speicherbegrenzte cgroup an**, überschreitest das Limit und beobachtest, wie der **OOM-Killer** des Kernels zuschlägt.

Sieh dir zuerst den cgroup-Baum und seine Controller an.

Dateisystemtyp prüfen:

```
stat -fc %T /sys/fs/cgroup        # muss cgroup2fs sein
```

- `stat -f` — Informationen über das **Dateisystem**, in dem der Pfad liegt, statt über die Datei; `-c %T` gibt nur den Typnamen aus. `cgroup2fs` bedeutet cgroup v2.

Verfügbare Controller prüfen:

```
cat /sys/fs/cgroup/cgroup.controllers
```

- In dieser cgroup verfügbare Controller (`cpu`, `memory`, `io`, `pids`, …). `memory` muss vorhanden sein, um ein Speicherlimit zu setzen.

> 💡 Dieser Pod teilt den **cgroup-Namensraum des Hosts**, `/sys/fs/cgroup` ist also der Baum des gesamten Knotens. Ein manuelles `mkdir` dort würde **den Knoten verunreinigen** und mit anderen Pods kollidieren. Deshalb lassen wir systemd die begrenzte cgroup **innerhalb des eigenen Slice des Pods** anlegen — genau so, wie k8s pro Pod eine cgroup einrichtet.

Aufgabe: Setze einem Slice namens `lab.slice` ein Limit von **24M Speicher und 0 Swap** und lass darin einen Prozess laufen, der 200MB belegt, um einen OOM auszulösen.

```
# dem Slice eine Speicherobergrenze setzen (--runtime = bis zum Neustart, nicht auf Platte geschrieben)
sudo systemctl set-property --runtime lab.slice MemoryMax=24M MemorySwapMax=0
```

- `systemctl set-property <Unit> Schlüssel=Wert…` — ändert Ressourceneigenschaften einer laufenden Unit (hier ein Slice).
- `MemoryMax=24M` — das harte Limit `memory.max` der cgroup; `MemorySwapMax=0` — kein Ausweichen in den Swap.
- `--runtime` — temporär; wird unter `/run` abgelegt und ist nach einem Neustart weg.

Belege jetzt innerhalb dieses Slice zu viel Speicher. `systemd-run --slice=lab.slice --scope` legt unter dem Slice einen transienten Scope an und führt deinen Befehl darin aus.

```
sudo systemd-run --slice=lab.slice --scope \
  python3 -c "b=[bytearray(4*1024*1024) for _ in range(200)]"
```

- `systemd-run --scope` — führt den Befehl in deinem Terminal aus, aber innerhalb eines neuen transienten Scopes (cgroup); `--slice=lab.slice` legt ihn unter den begrenzten Slice.
- `python3 -c "…"` — ein Einzeiler, der 200 Byte-Arrays zu je 4 MB (≈800 MB) belegt. Der abschließende `\` setzt die Zeile fort.

Du wirst `Killed` sehen — der Kernel hat den Prozess in dem Moment beendet, in dem er das 24M-Limit überschritt. Die Spur steht in `memory.events` des Slice. systemd verrät dir den tatsächlichen cgroup-Pfad des Slice.

cgroup-Pfad des Slice speichern:

```
cg=/sys/fs/cgroup$(systemctl show -p ControlGroup --value lab.slice)
```

- `systemctl show -p ControlGroup --value lab.slice` — gibt den cgroup-Pfad des Slice aus (`/…/lab.slice`); mit vorangestelltem `/sys/fs/cgroup` ergibt sich das echte Verzeichnis, gespeichert in `cg`.

Speicherlimit prüfen:

```
cat "$cg/memory.max"        # 25165824 (=24M)
```

- `memory.max` — das harte Speicherlimit der cgroup in Bytes: 24M = 24×1024×1024 = 25165824.

OOM-Events prüfen:

```
cat "$cg/memory.events"     # nach der oom_kill-Zeile suchen
```

- `memory.events` — kumulierte Zähler für Speicherereignisse: `max` Erreichen des Limits, `oom` OOM-Ereignisse, `oom_kill` durch OOM beendete Prozesse.

Siehst du `oom_kill 1` (oder mehr), ist tatsächlich ein OOM aufgetreten. Wenn bestätigt, **[Prüfen]** drücken, um das Modul abzuschließen. (`lab.slice` bleibt bestehen, solange der Pod lebt, und wird automatisch aufgeräumt, wenn der Pod verschwindet.)
