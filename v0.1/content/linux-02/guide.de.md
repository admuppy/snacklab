# Prozesse und Signale

Wenn ein Server langsam ist oder sich seltsam verhält, **siehst du dir als Erstes seine Prozesse an**. In diesem Modul erkundest du Prozesse mit ps und /proc, steuerst sie mit Signalen, lässt Jobs losgelöst vom Terminal laufen und spürst den Prozess auf, der einen Port belegt.

In der Lab-Umgebung laufen bereits drei Daemons als systemd-Units.

| Prozess | Was er ist |
|---|---|
| `lab-worker` | Ein gewöhnlicher Worker — dein Ziel in Schritt 1 |
| `lab-stubborn` | Ein zombieartiges Ding, das **SIGTERM ignoriert** — wird in Schritt 2 erledigt |
| `lab-listener` | Etwas, das 127.0.0.1:5555 belegt — wird in Schritt 4 aufgespürt |

## Prozesse erkunden — ps und /proc

Verschaffe dir zuerst einen Überblick über alle Prozesse.

Die vollständige Liste überfliegen:

```
ps aux | head
```

- `ps aux` — Prozesse aller Benutzer (`a`, und `x`: auch solche ohne Terminal), mit Benutzer, CPU%, MEM% und Befehl (`u`).
- `| head` — nur die ersten 10 Zeilen.

Als Baum anzeigen:

```
ps -ef --forest | head -30
```

- `ps -ef` — alle Prozesse (`-e`) im Vollformat (`-f`) mit PID und PPID.
- `--forest` — zeichnet Eltern-/Kind-Beziehungen als eingerückten Baum; `head -30` behält die ersten 30 Zeilen.

Suchen wir `lab-worker`. `pgrep -f` vergleicht das Muster mit der gesamten Befehlszeile und gibt PIDs zurück.

```
pgrep -f /opt/lab/bin/lab-worker
```

- `pgrep <Muster>` — gibt nur die PIDs passender Prozesse aus.
- `-f` — vergleicht mit der **gesamten Befehlszeile** (Pfad und Argumente), nicht nur mit dem Prozessnamen.

Alles, was ps anzeigt, stammt aus dem **Dateisystem /proc**. Sieh selbst in das PID-Verzeichnis (cmdline ist durch NUL(\0) getrennt, daher mit tr umwandeln, um es zu lesen).

PID in einer Variablen speichern:

```
pid=$(pgrep -f /opt/lab/bin/lab-worker | head -1)
```

- `$( ... )` — Befehlssubstitution; speichert die Ausgabe (die PID) in der Shell-Variablen `pid`, später als `$pid` verwendet.
- `| head -1` — behält nur die erste PID, falls mehrere passen.

PID-Verzeichnis auflisten:

```
ls /proc/$pid/
```

- `/proc/<PID>/` — ein virtuelles Verzeichnis, in dem der Kernel Prozessinformationen als Dateien bereitstellt: `cmdline` (Argumente), `status` (Zustand, Speicher), `fd/` (offene Dateien), `environ` (Umgebung), …

cmdline lesen:

```
tr '\0' ' ' < /proc/$pid/cmdline; echo
```

- `tr '\0' ' '` — übersetzt NUL-Zeichen der Eingabe in Leerzeichen.
- `< Datei` — gibt die Datei über stdin ein; `; echo` fügt einen abschließenden Zeilenumbruch hinzu.

Aufgabe: Speichere die Ergebnisse in Dateien.

- `~/work/worker.pid` — die PID von lab-worker
- `~/work/worker.cmdline` — der Inhalt von `/proc/<PID>/cmdline` (mit tr umgewandelt)

Arbeitsverzeichnis anlegen:

```
mkdir -p ~/work
```

- `mkdir -p` — legt fehlende übergeordnete Verzeichnisse an und schlägt nicht fehl, wenn es schon existiert.

PID speichern:

```
echo "$pid" > ~/work/worker.pid
```

- `echo "$pid"` gibt die Variable aus; `> Datei` speichert diese Ausgabe in der Datei (überschreibt).

cmdline speichern:

```
tr '\0' ' ' < /proc/$pid/cmdline > ~/work/worker.cmdline
```

- Derselbe `tr`-Befehl wie oben, diesmal mit `>` in eine Datei gespeichert.

Wenn gespeichert, **[Prüfen]** drücken.

## Prozesse mit Signalen steuern

`kill` ist kein Befehl, der Prozesse tötet — er **sendet Signale**.

| Signal | Nummer | Verhalten |
|---|---|---|
| SIGTERM | 15 | Der Standard. Ein Prozess **kann es ignorieren oder vor dem Beenden aufräumen** |
| SIGKILL | 9 | Der Kernel entfernt den Prozess sofort. **Nicht ignorierbar**, keine Chance zum Aufräumen |
| SIGHUP | 1 | Wird per Konvention oft für „Konfiguration neu laden" verwendet |

`lab-stubborn` ist so geschrieben, dass es TERM und INT per trap abfängt und ignoriert. Überzeuge dich selbst.

Prüfen, ob er läuft:

```
pgrep -f /opt/lab/bin/lab-stubborn
```

- Eine PID heißt, er lebt; keine Ausgabe (Exit-Code 1) heißt, es gibt keinen solchen Prozess.

SIGTERM senden:

```
sudo pkill -TERM -f /opt/lab/bin/lab-stubborn
```

- `pkill` — sendet passenden Prozessen ein Signal (`pgrep` + `kill`).
- `-TERM` — das Signal (SIGTERM, 15); `-f` vergleicht mit der gesamten Befehlszeile.
- `sudo` — der Prozess gehört einem anderen Benutzer (root), daher sind Admin-Rechte nötig.

Prüfen, ob er noch lebt:

```
sleep 1; pgrep -f /opt/lab/bin/lab-stubborn   # lebt noch
```

- `sleep 1` — eine Sekunde warten, bis das Signal verarbeitet ist, dann führt `;` die Prüfung erneut aus.

Ein Hinweis: Dieser Prozess wird von einer **systemd-Unit** (lab-stubborn.service) verwaltet. Du könntest den Prozess einfach mit kill -9 beenden, aber ein von einer Unit verwalteter Prozess wird sauber auf Unit-Ebene behandelt. `systemctl stop` sendet jedoch zuerst TERM und wartet auf das Timeout (standardmäßig 90 s), was hier zu langsam ist — **sende SIGKILL stattdessen direkt über die Unit**.

SIGKILL über die Unit senden:

```
sudo systemctl kill -s KILL lab-stubborn
```

- `systemctl kill <Unit>` — sendet ein Signal an **jeden Prozess** der Unit.
- `-s KILL` — das Signal ist SIGKILL (9), das ein Prozess nicht abfangen kann; er wird sofort entfernt.

Beendigung prüfen:

```
pgrep -f /opt/lab/bin/lab-stubborn || echo "terminated"
```

- `A || B` — führt B nur aus, wenn A scheitert (Exit-Code ≠ 0); findet `pgrep` nichts, wird die Meldung ausgegeben.

Ist er tot, **[Prüfen]** drücken.

## Vom Terminal losgelöste Hintergrundausführung

Ein im Terminal mit `&` gestarteter Prozess erhält SIGHUP und stirbt, wenn das Terminal die Verbindung trennt. Damit er das Ende der Sitzung überlebt, nutze **nohup** (HUP ignorieren + Ausgabe umleiten) oder **setsid** (in eine neue Sitzung abkoppeln).

`/opt/lab/bin/lab-batch` ist ein Batch-Job, der alle 10 Sekunden einen Zeitstempel in die als erstes Argument übergebene Datei schreibt. Starte ihn losgelöst vom Terminal und schicke sein Log nach `~/work/batch.log`.

```
nohup /opt/lab/bin/lab-batch ~/work/batch.log >/dev/null 2>&1 &
```

- `nohup <Befehl>` — ignoriert SIGHUP, sodass der Befehl nach dem Schließen des Terminals weiterläuft.
- `>/dev/null 2>&1` — stdout verwerfen und stderr (2) an dieselbe Stelle wie stdout (1) schicken.
- Das abschließende `&` startet ihn im Hintergrund und gibt den Prompt sofort zurück.

Prüfe den Elternprozess. Ist er von der Shell gelöst und verwaist, übernimmt ihn PID 1 (in diesem Pod systemd).

```
ps -o pid,ppid,cmd -p $(pgrep -f /opt/lab/bin/lab-batch)
```

- `ps -o pid,ppid,cmd` — wählt die Spalten: PID, Eltern-PID und Befehl.
- `-p $(pgrep ...)` — nur die PID(s), die die Befehlssubstitution liefert.

Log prüfen:

```
tail ~/work/batch.log
```

- `tail <Datei>` — die letzten 10 Zeilen; mit `tail -f` fortlaufend verfolgen (Ctrl+C zum Beenden).

Ist die PPID 1 und wächst das Log, **[Prüfen]** drücken.

> Im Betrieb ist für solche Daemons eine systemd-Unit (oder `systemd-run`) die richtige Antwort — behandelt im Modul linux-06.

## Den Prozess aufspüren, der einen Port belegt

„Wer hält diesen Port?" ist die häufigste Diagnosefrage. Finde mit `ss` (socket statistics) den Besitzer von Port 5555. Für Prozessnamen brauchst du `-p`, für Prozesse anderer Benutzer sudo.

Alle lauschenden Sockets auflisten:

```
sudo ss -ltnp
```

- `ss` — Socket-Statistik (Nachfolger von netstat). `-l` nur lauschende, `-t` TCP, `-n` numerische Ports, `-p` zeigt den zugehörigen Prozess.

Nur Port 5555 abfragen:

```
sudo ss -ltnp sport = :5555
```

- `sport = :5555` — ein Filterausdruck: nur Sockets, deren Quellport (lokal) 5555 ist.

`lsof` liefert dieselbe Antwort.

```
sudo lsof -i :5555
```

- `lsof` — listet offene Dateien auf (Sockets sind unter Linux Dateien); `-i :5555` — nur Netzwerkverbindungen auf Port 5555.

Aufgabe: Speichere den **Prozessnamen**, der Port 5555 belegt, in `~/work/port-owner.txt`.

Prozessnamen extrahieren und speichern:

```
sudo ss -ltnp sport = :5555 | grep -o 'python3' | head -1 > ~/work/port-owner.txt
```

- `grep -o` — gibt **nur den passenden Teil** aus, nicht die ganze Zeile — holt den Namen aus `users:(("python3",pid=…))`.
- `head -1` behält einen, und `>` speichert ihn.

Gespeicherten Inhalt prüfen:

```
cat ~/work/port-owner.txt
```

- `cat <Datei>` — gibt den Inhalt der Datei aus.

Wenn du wissen willst, was dieses python3 eigentlich ist, durchsuche /proc anhand seiner PID — genau die Technik aus Schritt 1. Wenn gespeichert, **[Prüfen]** drücken.
