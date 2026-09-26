# systemd-Dienste und journald

In linux-02 haben wir einen Daemon mit nohup gestartet, aber echte Daemons sind allesamt **systemd-Units** — automatischer Start beim Booten, Neustart nach Absturz und Logs, die journald einsammelt. In diesem Modul schreibst du Units selbst, diagnostizierst und reparierst eine kaputte Unit mit dem Journal und ersetzt cron durch einen Timer.

Verschaffe dir jetzt einen Überblick über die Units im System.

Dienst-Units auflisten:

```
systemctl list-units --type=service --no-pager | head -15
```

- `systemctl list-units` — im Speicher geladene Units; `--type=service` nur Dienste, `--no-pager` ohne less ausgeben.
- `| head -15` — die ersten 15 Zeilen. Spalten: LOAD (Datei geladen), ACTIVE (übergeordneter Zustand), SUB (detaillierter Zustand).

Status des cron-Dienstes prüfen:

```
systemctl status cron --no-pager
```

- `systemctl status <Unit>` — Zustand (`Active:`), Haupt-PID, cgroup-Prozessbaum und die letzten Logzeilen auf einem Bildschirm.

## Eine Dienst-Unit schreiben

Die kleinste Dienst-Unit braucht nur drei Abschnitte.

| Abschnitt | Rolle |
|---|---|
| `[Unit]` | Beschreibung, Abhängigkeiten (Description, After, …) |
| `[Service]` | wie ausgeführt wird (ExecStart, Restart, User, …) |
| `[Install]` | wo sie beim Aktivieren eingehängt wird (WantedBy) |

Aufgabe: Lege `hello-web.service` an, das auf Port 8080 einen statischen HTTP-Server betreibt.

```
sudo tee /etc/systemd/system/hello-web.service <<'EOF'
[Unit]
Description=hello web

[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 127.0.0.1

[Install]
WantedBy=multi-user.target
EOF
```

- `sudo tee <Datei> <<'EOF'` — den Heredoc-Text schreibt `tee`, das als root läuft (`sudo cat > Datei` scheitert, weil deine eigene Shell die Umleitung ausführt).
- `/etc/systemd/system/` — Ort für vom Admin angelegte Unit-Dateien; sie haben Vorrang vor Paket-Units (`/usr/lib/systemd/system/`).
- `ExecStart=` — der auszuführende Befehl (absoluter Pfad). `WantedBy=multi-user.target` — beim Aktivieren wird die Unit in das normale Boot-Target eingehängt.

Nach dem Anlegen oder Ändern einer Unit-Datei **immer daemon-reload** — systemd liest die Dateien nicht direkt, sondern nutzt die im Speicher geladene Kopie.

systemd neu laden:

```
sudo systemctl daemon-reload
```

- `systemctl daemon-reload` — lässt systemd die Unit-Dateien neu einlesen. Dienste werden dabei nicht neu gestartet.

Aktivieren und sofort starten:

```
sudo systemctl enable --now hello-web
```

- `enable` — verlinkt die Unit in ihr `WantedBy`-Target, damit sie beim Booten startet; `--now` — führt zusätzlich sofort `start` aus.
- Das Suffix `.service` kann entfallen.

Dienststatus prüfen:

```
systemctl status hello-web --no-pager
```

- `Active: active (running)` mit einer Haupt-PID (`python3`) heißt: korrekt gestartet.

Antwort testen:

```
curl -s http://127.0.0.1:8080/ | head -3
```

- `curl -s` — sendet die HTTP-Anfrage ohne Fortschrittsbalken und gibt den Body aus; `| head -3` behält die ersten 3 Zeilen (HTML der Verzeichnisliste).

`enable --now` heißt „für den Start beim Booten registrieren + jetzt starten". Siehst du eine Antwort, **[Prüfen]** drücken.

## Eine kaputte Unit mit journald reparieren

Eine Unit namens `lab-report.service` ist ausgerollt, startet aber nicht. Überzeuge dich selbst.

Dienst zu starten versuchen:

```
sudo systemctl start lab-report
```

- `systemctl start` — startet den Dienst jetzt (unabhängig von der Aktivierung beim Booten). Bei einem Fehler gibt es `Job … failed` aus und schlägt Befehle zur Untersuchung vor.

Fehlerstatus ansehen:

```
systemctl status lab-report --no-pager
```

- Achte auf `Active: failed` und die Zeile `code=exited, status=…` mit dem Fehlercode.

Untersucht wird mit **journalctl**. Wähle mit `-u` die Unit und nutze dazu `-e` (ans Ende springen) oder `--no-pager`.

```
journalctl -u lab-report --no-pager | tail -20
```

- `journalctl` — liest journald-Logs. `-u <Unit>` nur diese Unit, `--no-pager` direkt ausgeben, `| tail -20` die letzten 20 Zeilen.
- Live verfolgen mit `-f`, nur der aktuelle Boot mit `-b`, ein Zeitfenster mit `--since "10 min ago"`.

Du solltest `status=203/EXEC` sehen — ein klassischer systemd-Exit-Code, der bedeutet: **Die ExecStart-Datei kann nicht ausgeführt werden** (Tippfehler im Pfad, fehlendes Ausführungsrecht, Shebang-Problem). Vergleiche den Pfad, auf den die Unit zeigt, mit den tatsächlichen Dateien.

Pfad anzeigen, auf den die Unit zeigt:

```
systemctl cat lab-report
```

- `systemctl cat <Unit>` — die Unit-Datei(en), die systemd tatsächlich nutzt (einschließlich Drop-ins), mit ihren Pfaden. Prüfe die Zeile `ExecStart=`.

Tatsächliche Dateien prüfen:

```
ls -l /opt/lab/bin/
```

- `ls -l` — Dateinamen zusammen mit Rechten (ist `x` gesetzt?). Vergleiche Zeichen für Zeichen mit dem Pfad der Unit.

Aufgabe: Korrigiere den ExecStart-Pfad (daemon-reload nicht vergessen) und starte den Dienst.

Unit-Datei bearbeiten:

```
sudo vim /etc/systemd/system/lab-report.service
```

- Unit-Dateien gehören root, daher mit `sudo` öffnen. vim: `i` zum Einfügen, `Esc` → `:wq` zum Speichern und Beenden.
- Vergisst du danach `daemon-reload`, scheitert systemd weiter mit dem alten Pfad.

systemd neu laden:

```
sudo systemctl daemon-reload
```

Dienst starten:

```
sudo systemctl start lab-report
```

Log verfolgen:

```
tail -f /var/log/lab/report.log   # mit Ctrl-C beenden
```

- `tail -f` — folgt dem Dateiende und gibt neue Zeilen aus, sobald sie erscheinen — der Beweis, dass der Dienst wirklich arbeitet.

Ist er active (running), **[Prüfen]** drücken.

## Selbstheilung mit der Restart-Richtlinie

Prozesse sterben — OOM, Bugs, Fehler. systemds `Restart=` ist das Sicherheitsnetz, das sie automatisch zurückholt.

| Wert | Neustart-Bedingung |
|---|---|
| `no` (Standard) | nie |
| `on-failure` | nur nach abnormalem Ende (Code≠0, Signal) |
| `always` | immer, auch nach sauberem Ende |

Aufgabe: Füge hello-web `Restart=on-failure` und `RestartSec=1` hinzu. Du kannst die Unit-Datei direkt bearbeiten oder, besser, ein **Drop-in** nutzen, das das Original unberührt lässt (`systemctl edit` ist interaktiv, daher schreiben wir die Datei hier direkt).

Drop-in-Verzeichnis anlegen:

```
sudo mkdir -p /etc/systemd/system/hello-web.service.d
```

- `<Unit>.d/` — ein Drop-in-Verzeichnis; die `*.conf`-Dateien darin überschreiben die Original-Unit und überstehen Paket-Updates daran.

Drop-in-Datei schreiben:

```
sudo tee /etc/systemd/system/hello-web.service.d/restart.conf <<'EOF'
[Service]
Restart=on-failure
RestartSec=1
EOF
```

- Nur die Schlüssel, die unter `[Service]` hinzukommen. `Restart=on-failure` startet nach abnormalem Ende neu, `RestartSec=1` wartet vorher 1 s.

systemd neu laden:

```
sudo systemctl daemon-reload
```

Dienst neu starten:

```
sudo systemctl restart hello-web
```

- `restart` — stop und dann start, sodass der Prozess mit dem neuen Drop-in zurückkommt.

Testen wir, ob er wirklich zurückkommt. Beende die Haupt-PID mit SIGKILL und prüfe den Status ein paar Sekunden später.

Haupt-PID anzeigen:

```
systemctl show -p MainPID --value hello-web
```

- `systemctl show` — gibt Unit-Eigenschaften als `Schlüssel=Wert` aus; `-p MainPID` wählt eine, `--value` entfernt das Präfix `MainPID=`.

Prozess beenden:

```
sudo kill -9 $(systemctl show -p MainPID --value hello-web)
```

- `kill -9` (SIGKILL) auf die Haupt-PID aus `$( ... )` — ein nicht abfangbares erzwungenes Beenden. Das ist ein abnormales Ende, also greift `on-failure`.

Status nach einem Moment prüfen:

```
sleep 3; systemctl status hello-web --no-pager | head -5
```

- `sleep 3` gibt dem Neustart (RestartSec=1) Zeit und zeigt dann die ersten 5 Statuszeilen. `Main PID` sollte sich von vorher unterscheiden.

Ist er mit neuer PID wieder active, hat es geklappt — **[Prüfen]** drücken. (Die Prüfung führt dasselbe Experiment noch einmal durch.)

## Periodische Jobs mit Timern

Der systemd-Ersatz für cron ist der **Timer**. Logs landen im Journal und Fehler werden als Units verwaltet, daher sind die meisten periodischen Jobs auf modernen Distributionen Timer. Die Einrichtung ist ein Paar: **ein Dienst (was zu tun ist) + ein Timer (wann)**.

Aufgabe: Lege einen Timer `lab-tick` an, der jede Minute die Uhrzeit nach `/var/log/lab/tick.log` schreibt.

Dienst-Unit (was zu tun ist) schreiben:

```
sudo tee /etc/systemd/system/lab-tick.service <<'EOF'
[Unit]
Description=lab tick

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'date -Is >> /var/log/lab/tick.log'
EOF
```

- `Type=oneshot` — ein Job, der bis zum Ende läuft; endet der Befehl, zählt das als Erfolg und die Unit wird wieder inaktiv.
- `bash -c '…'` — Umleitung (`>>`, anhängen) ist eine Shell-Funktion, daher läuft es über bash. `date -Is` gibt einen ISO-8601-Zeitstempel aus.

Timer-Unit (wann) schreiben:

```
sudo tee /etc/systemd/system/lab-tick.timer <<'EOF'
[Unit]
Description=lab tick every minute

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
```

- `OnCalendar=*-*-* *:*:00` — Kalendersyntax `Jahr-Monat-Tag Stunde:Minute:Sekunde`: Sekunde 0 jeder Minute = jede Minute.
- `AccuracySec=1s` — verringert die erlaubte Startverzögerung (Standard 1 min) auf 1 s.
- Ein Timer startet den gleichnamigen `.service` (`lab-tick.service`); `WantedBy=timers.target` wird beim Aktivieren genutzt.

systemd neu laden:

```
sudo systemctl daemon-reload
```

Timer aktivieren und starten:

```
sudo systemctl enable --now lab-tick.timer
```

- `.timer` ausschreiben; ohne Suffix wird der Name als `.service` verstanden.

`Type=oneshot` ist für Jobs, die „einmal laufen und fertig sind". Beachte: Aktiviert wird **der Timer, nicht der Dienst**. Prüfe, dass er registriert ist, und drücke **[Prüfen]**, um das Modul abzuschließen.

```
systemctl list-timers --no-pager | grep -E 'NEXT|lab-tick'
```

- `systemctl list-timers` — aktive Timer mit ihren Laufzeiten `NEXT` und `LAST`.
- `grep -E 'NEXT|lab-tick'` — behält die Kopfzeile und die lab-tick-Zeile (`|` ist ODER in erweiterten regulären Ausdrücken).
