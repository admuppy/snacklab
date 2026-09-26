# Textverarbeitungs-Pipelines

Die Hälfte des Linux-Betriebs besteht aus **Logs lesen**. Verkette grep, awk und sed mit Pipes, und du ziehst in Sekunden Antworten aus Hunderttausenden Logzeilen.

In der Lab-Umgebung liegt ein Webserver-Access-Log mit 2.000 Zeilen bereit. Sieh dir zuerst seine Form an.

Die ersten 5 Zeilen ansehen:

```
head -5 /var/log/lab/access.log
```

- `head -5 <Datei>` — gibt nur die ersten 5 Zeilen aus (wie `-n 5`).

Gesamtzahl der Zeilen zählen:

```
wc -l /var/log/lab/access.log
```

- `wc -l <Datei>` — zählt Zeilen (word count, Zeilenmodus); `-w` zählt Wörter, `-c` Bytes.

Der Aufbau einer Zeile (Feldnummern, an Leerraum getrennt):

| Feld | Inhalt | Beispiel |
|---|---|---|
| $1 | Client-IP | `192.168.14.23` |
| $6~$8 | Anfrage (`"METHOD path HTTP/1.1"`) | `"GET /api/users HTTP/1.1"` |
| $9 | Statuscode | `200` |
| $10 | Antwort-Bytes | `1532` |

## Fehler mit grep finden

grep ist ein Werkzeug, das **Zeilen herausfiltert**, die zu einem Muster passen. Suchen wir Serverfehler (5xx). Ein naives `grep 500` trifft auch Zeilen mit 500 Bytes — du musst **nur die Position des Statuscodes** treffen.

```
grep -E '" 5[0-9]{2} ' /var/log/lab/access.log | head
```

- `grep -E` — erweiterte Regex; `5[0-9]{2}` ist eine dreistellige Zahl, die mit 5 beginnt.
- `'" 5[0-9]{2} '` — das umgebende Anführungszeichen und die Leerzeichen verankern den Treffer an der Statuscode-Position. Das ganze Muster steht in einfachen Anführungszeichen, damit die Shell es nicht anfasst.

Entscheidend ist der Kontext um den Treffer, sodass nur ein 5xx nach `"` und einem Leerzeichen zählt. `-c` gibt nur die Anzahl passender Zeilen aus.

Aufgabe: Speichere die Anzahl der 5xx-Fehlerzeilen in `~/work/err5xx.count`.

Anzahl der 5xx-Zeilen speichern:

```
grep -Ec '" 5[0-9]{2} ' /var/log/lab/access.log > ~/work/err5xx.count
```

- `-c` — gibt die **Anzahl** passender Zeilen statt der Zeilen aus; zusammen mit `-E` als `-Ec`.
- `> ~/work/err5xx.count` — speichert diese Zahl in einer Datei.

Gespeicherten Wert prüfen:

```
cat ~/work/err5xx.count
```

- `cat` — gibt die Datei aus, um die gespeicherte Zahl zu bestätigen.

Wenn gespeichert, **[Prüfen]** drücken.

## Felder extrahieren und aggregieren mit awk

awk arbeitet mit **in Felder zerlegten** Zeilen. `$1` ist das erste Feld (die IP).

```
awk '{print $1}' /var/log/lab/access.log | head
```

- `awk '{print $1}'` — zerlegt jede Zeile in durch Leerraum getrennte Felder und gibt das erste (die IP) aus. Die Aktion in `{ }` läuft für jede Zeile.

Hänge die klassische Aggregations-Pipeline `sort | uniq -c | sort -rn` an, und du erhältst eine Häufigkeitstabelle.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn
```

- `sort` — gruppiert gleiche IPs; `uniq -c` — fasst aufeinanderfolgende Duplikate zusammen und stellt die Anzahl voran.
- `sort -rn` — numerisch (`-n`) absteigend (`-r`) sortieren → die aktivste IP oben.

> `uniq -c` zählt nur **benachbarte** Duplikate, daher muss `sort` zuerst kommen.

Aufgabe: Speichere **nur die eine IP** mit den meisten Anfragen (nur die IP, ohne Anzahl) in `~/work/top-ip.txt`. Nimm mit `head -1` die erste Zeile und extrahiere dann mit awk erneut nur das IP-Feld.

```
awk '{print $1}' /var/log/lab/access.log | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > ~/work/top-ip.txt
```

- `head -1` — behält die oberste Zeile (`  123 1.2.3.4`).
- `awk '{print $2}'` — nimmt ihr zweites Feld (die IP) und speichert es mit `>`.

Wenn gespeichert, **[Prüfen]** drücken.

## Stream-Bearbeitung mit sed

Dieses Log soll extern geteilt werden, aber Client-IPs sind personenbezogene Daten und müssen **maskiert** werden. Die Ersetzung von sed (`s/Muster/Ersatz/`) löst das.

Fange mit einer Regex die IPv4 am Anfang jeder Zeile ab. Mit `-E` (erweiterte Regex) kannst du den Quantor `{1,3}` direkt verwenden.

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log | head -3
```

- `sed -E 's/Muster/Ersatz/'` — ersetzt den ersten Treffer jeder Zeile und gibt das Ergebnis aus (die Datei selbst bleibt unverändert).
- `^` — Zeilenanfang, `[0-9]{1,3}` — 1–3 Ziffern, `\.` — ein wörtlicher Punkt; zusammen die IPv4-Adresse am Zeilenanfang.

Aufgabe: Speichere eine Kopie des gesamten Logs, in der die IPs durch `REDACTED` ersetzt sind, als `~/work/access-redacted.log`. Die Zeilenzahl muss dem Original entsprechen (Ersetzen, nicht Löschen).

Maskierte Kopie speichern:

```
sed -E 's/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/REDACTED/' /var/log/lab/access.log > ~/work/access-redacted.log
```

- Wendet dieselbe Ersetzung auf die ganze Datei an und speichert eine neue Kopie. `-i` würde das Original direkt bearbeiten, hier behalten wir es.

Maskierte Zeilen zählen:

```
grep -c REDACTED ~/work/access-redacted.log
```

- Zählt Zeilen mit `REDACTED`; das sollte der ursprünglichen Zeilenzahl aus `wc -l` entsprechen.

Wenn gespeichert, **[Prüfen]** drücken.

## Die Pipeline zusammensetzen

Zum Schluss eine Frage aus der Praxis: **„Wie viele Bytes wurden insgesamt von erfolgreichen (200) Antworten auf Anfragen unter dem Pfad /api übertragen?"**

Ein einziges awk kann gleichzeitig filtern und aggregieren — eine Bedingung wählt Zeilen aus, eine Variable summiert, und der `END`-Block gibt aus.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log
```

- `$7 ~ /Regex/` — passt Feld 7 zur Regex? Ein `/` innerhalb der Regex wird als `\/` maskiert.
- Die Variable `s` beginnt ohne Deklaration bei 0; der `END`-Block läuft einmal, nachdem alle Zeilen gelesen sind.

Aufgeschlüsselt:

| Teil | Bedeutung |
|---|---|
| `$7 ~ /^\/api\//` | das Pfadfeld beginnt mit `/api` |
| `&& $9 == 200` | und der Status ist 200 |
| `{s += $10}` | das Byte-Feld in s aufsummieren |
| `END {print s}` | nach dem Lesen aller Zeilen die Summe ausgeben |

Aufgabe: Speichere diese Summe in `~/work/api-bytes.txt` und drücke **[Prüfen]**.

```
awk '$7 ~ /^\/api\// && $9 == 200 {s += $10} END {print s}' /var/log/lab/access.log > ~/work/api-bytes.txt
```

- Derselbe Befehl wie oben, die Ausgabe wird mit `>` in eine Datei gespeichert.
