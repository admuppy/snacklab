# Netzwerkdiagnose

„Ich erreiche den Dienst nicht" läuft fast immer auf eine von vier Ursachen hinaus — **falsche IP, Port nicht offen, falsche Bindung oder Name wird nicht aufgelöst.** In diesem Modul lernst du die Werkzeuge, die diese vier der Reihe nach diagnostizieren: ip, ss, curl, getent.

In der Lab-Umgebung läuft ein API-Dienst namens `lab-api` — und es gibt eine offene Meldung, dass er „von außen nicht erreichbar" ist. Am Ende hast du die Ursache gefunden und behoben.

## Schnittstellen und IPs untersuchen

Netzwerkdiagnose beginnt mit **wer bin ich** (meine IP). Das moderne Standardwerkzeug ist `ip` (ifconfig ist im Ruhestand).

Schnittstellen auflisten:

```
ip link
```

- `ip link` — Netzwerkschnittstellen (L2) mit Zustand (`UP`/`DOWN`), MAC-Adresse und MTU.

IPv4-Adressen anzeigen:

```
ip -4 addr show
```

- `ip addr show` — IP-Adressen pro Schnittstelle; `-4` nur IPv4. Angezeigt als Adresse/Präfixlänge (CIDR), z. B. `inet 10.x.x.x/24`.

Routing-Tabelle anzeigen:

```
ip route
```

- `ip route` — die Routing-Tabelle; die Zeile `default via <Gateway>` ist die Standardroute nach draußen.

Ein Container zeigt meist zwei Schnittstellen: `lo` (Loopback) und `eth0`. Eine skriptfreundliche Extraktion in einer Zeile:

eth0 in einer Zeile ausgeben:

```
ip -4 -o addr show eth0
```

- `-o` — eine Schnittstelle pro **Zeile** (oneline), leicht mit `grep`/`awk` weiterzuverarbeiten.
- `show eth0` — nur diese Schnittstelle.

Nur das CIDR-Feld extrahieren:

```
ip -4 -o addr show eth0 | awk '{print $4}'
```

- `awk '{print $4}'` — behält nur das 4. durch Leerraum getrennte Feld (`10.x.x.x/24`).

Aufgabe: Speichere die IPv4-Adresse von eth0 — **nur die Adresse, ohne CIDR** — in `~/work/myip.txt`. Entferne Suffixe wie `/24` mit `cut -d/ -f1`.

Suffix entfernen und speichern:

```
ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1 > ~/work/myip.txt
```

- `cut -d/ -f1` — an `/` trennen (`-d`) und Feld 1 behalten (`-f1`) → die Adresse.
- `> ~/work/myip.txt` — speichert das Ergebnis in einer Datei.

Gespeicherten Inhalt prüfen:

```
cat ~/work/myip.txt
```

- Gibt die gespeicherte Adresse aus. Spätere Befehle verwenden sie als `$(cat ~/work/myip.txt)`.

Wenn gespeichert, **[Prüfen]** drücken.

## Lauschende Sockets aufspüren

Nächste Frage: **Was lauscht auf welchem Port.** Die wichtigsten `ss`-Optionen:

| Option | Bedeutung |
|---|---|
| `-l` | nur lauschende Sockets |
| `-t` / `-u` | TCP / UDP |
| `-n` | numerische Ports (keine Auflösung von Dienstnamen) |
| `-p` | Prozesse anzeigen (für die anderer Benutzer ist sudo nötig) |

```
sudo ss -ltnp
```

- Die Optionskombination aus der Tabelle. `Local Address:Port` sagt, wo gelauscht wird, `users:((…))`, welcher Prozess es ist.

Aufgabe: Finde die **Portnummer**, auf der `lab-api.service` lauscht, und speichere sie in `~/work/api-port.txt`. Ein guter Weg ist, bei der Haupt-PID der Unit zu beginnen.

Haupt-PID von lab-api anzeigen:

```
systemctl show -p MainPID --value lab-api
```

- `systemctl show -p MainPID --value <Unit>` — gibt nur die PID des Hauptprozesses der Unit aus.

Lauschenden Socket dieser PID finden:

```
sudo ss -ltnp | grep "pid=$(systemctl show -p MainPID --value lab-api)"
```

- `$( … )` wird auch in doppelten Anführungszeichen expandiert → es entsteht `grep "pid=1234"`, das nur die Socket-Zeilen dieser PID behält.

Lies den Port aus `127.0.0.1:Port` in der Spalte Local Address ab. Speichere ihn und drücke **[Prüfen]**.

## Ein Bindungsproblem diagnostizieren und beheben

Vielleicht ist es dir in der ss-Ausgabe schon aufgefallen — die Local Address von lab-api ist `127.0.0.1:9090`. Er ist **nur an Loopback gebunden**, funktioniert also innerhalb dieses Containers, liefert von außen (andere Pods, der Knoten) aber connection refused. Reproduziere es.

Über Loopback verbinden:

```
curl -s http://127.0.0.1:9090/status.json        # klappt
```

- `curl -s <URL>` — stille Anfrage, gibt nur den Body aus. Über Loopback (`127.0.0.1`) klappt die Verbindung.

Über die Container-IP verbinden:

```
curl -s --max-time 3 http://$(cat ~/work/myip.txt):9090/status.json   # schlägt fehl!
```

- `--max-time 3` — begrenzt die gesamte Anfrage auf 3 s, statt zu warten.
- `$(cat ~/work/myip.txt)` — setzt die gespeicherte Container-IP in die URL ein.

Derselbe Prozess, unterschiedliche Ergebnisse — je nachdem, **über welche Adresse die Anfrage hereinkommt**. Die Bindung muss auf `0.0.0.0` (alle Schnittstellen) geändert werden.

Aufgabe: Ändere in der Unit-Datei `--bind 127.0.0.1` in `--bind 0.0.0.0` und starte neu.

Unit-Datei bearbeiten:

```
sudo vim /etc/systemd/system/lab-api.service
```

- Suche `--bind 127.0.0.1` in der Zeile `ExecStart=` und ändere es. vim: `i` zum Einfügen, `Esc` → `:wq` zum Speichern und Beenden.

systemd neu laden:

```
sudo systemctl daemon-reload
```

- Du hast die Unit-Datei bearbeitet, also muss systemd sie neu einlesen.

Dienst neu starten:

```
sudo systemctl restart lab-api
```

- Startet den Prozess mit der neuen Bindungsadresse neu.

Bindungsadresse prüfen:

```
sudo ss -ltn | grep 9090
```

- Prozessnamen werden nicht gebraucht, daher ohne `-p`. `0.0.0.0:9090` heißt, er nimmt auf allen Schnittstellen an.

Erneut über die Container-IP verbinden:

```
curl -s http://$(cat ~/work/myip.txt):9090/status.json   # klappt jetzt
```

- Sende dieselbe Anfrage noch einmal; diesmal sollte eine Antwort kommen.

Zeigt es `0.0.0.0:9090` und antwortet über die Container-IP, **[Prüfen]** drücken.

## Namensauflösung — hosts und DNS

Das letzte Puzzleteil ist **Name → IP**. Die Auflösungsreihenfolge ist meist `/etc/hosts` → DNS (die Nameserver in `/etc/resolv.conf`), und diese Reihenfolge regelt die Zeile `hosts:` in `/etc/nsswitch.conf`.

DNS-Server-Einstellungen prüfen:

```
cat /etc/resolv.conf
```

- `nameserver` — abzufragende DNS-Server; `search` — Domains, die nacheinander an kurze Namen angehängt werden.

Regel für die Auflösungsreihenfolge prüfen:

```
grep hosts /etc/nsswitch.conf
```

- `hosts: files dns` — Namen zuerst aus `files` (=`/etc/hosts`) auflösen, dann über `dns`.

Die Nachschlagewerkzeuge dienen unterschiedlichen Zwecken: `nslookup`/`dig` fragen **direkt einen DNS-Server**, während `getent hosts` dem **tatsächlichen Auflösungsweg des Systems** folgt (einschließlich der hosts-Datei). Was Anwendungen sehen, ist das getent-Ergebnis.

Aufgabe: Mache lab-api unter dem Namen `api.lab.local` erreichbar. Den DNS-Server kannst du nicht ändern, also trage ihn in `/etc/hosts` ein.

Namen in hosts eintragen:

```
echo '127.0.0.1 api.lab.local' | sudo tee -a /etc/hosts
```

- `tee -a` — **hängt an**, statt zu überschreiben. Vergisst du `-a`, besteht die ganze hosts-Datei nur noch aus einer Zeile!
- Format: `<IP> <Name> [Aliase…]`.

Über den Systemweg auflösen:

```
getent hosts api.lab.local
```

- `getent hosts <Name>` — löst in nsswitch-Reihenfolge auf (einschließlich hosts-Datei) — dieselbe Antwort, die Anwendungen bekommen.

Per Name verbinden:

```
curl -s http://api.lab.local:9090/status.json
```

- Anfrage per Name statt per IP; curl nutzt den System-Resolver, daher greift der Eintrag in `/etc/hosts`.

Kommt eine Antwort, **[Prüfen]** drücken — Modul abgeschlossen.
