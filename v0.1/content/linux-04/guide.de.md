# Bash-Skripting

Wenn sich ein Einzeiler zu wiederholen beginnt, ist es Zeit für ein Skript. In diesem Modul lernst du, **keine Skripte zu schreiben, die nie sterben, sondern Skripte, die sofort sterben, wenn etwas schiefgeht (fail-fast)** — denn ein Skript, das still falsche Ergebnisse liefert, ist das gefährlichste.

Alles kommt nach `~/work/`. Nimm vim oder nano, wie du magst, oder lege Dateien mit einem Heredoc `cat > Datei <<'EOF'` an.

## Ein sicheres Skript-Grundgerüst

Die ersten beiden Zeilen jedes Skripts stehen praktisch fest.

```
#!/bin/bash
set -euo pipefail
```

| Option | Wirkung |
|---|---|
| `-e` | sofort beenden, wenn ein Befehl fehlschlägt |
| `-u` | Fehler beim Verwenden undefinierter Variablen (fängt Tippfehler ab) |
| `-o pipefail` | ein Fehler mitten in einer Pipe zählt als Fehler |

Aufgabe: Schreibe `~/work/sysinfo.sh`. Anforderungen:

- bash-Shebang + `set -euo pipefail`
- eine Zeile `host=<Hostname>` und eine Zeile `uptime=<Sekunden>` ausgeben
- Ausführungsrecht

Skript schreiben:

```
cat > ~/work/sysinfo.sh <<'EOF'
#!/bin/bash
set -euo pipefail
echo "host=$(uname -n)"
echo "uptime=$(awk '{print $1}' /proc/uptime)"
EOF
```

- `cat > Datei <<'EOF'` … `EOF` — ein Heredoc: Die Zeilen zwischen den beiden `EOF` gehen an `cat` und werden mit `>` in der Datei gespeichert. Das Quoting von `'EOF'` verhindert, dass `$(...)` jetzt ausgeführt wird; es wird wörtlich gespeichert.
- `#!/bin/bash` — der Shebang; sagt dem Kernel, welcher Interpreter die Datei ausführt.
- `$(uname -n)` — Hostname; `awk '{print $1}' /proc/uptime` — Sekunden seit dem Booten (erstes Feld).

Ausführbar machen:

```
chmod +x ~/work/sysinfo.sh
```

- `chmod +x` — fügt das Ausführungsrecht (x) hinzu; ohne es scheitert `./skript` mit `Permission denied`.

Ausführen:

```
~/work/sysinfo.sh
```

- Beim Aufruf über den Pfad führt das `/bin/bash` aus dem Shebang es aus (`bash Datei` funktioniert auch ohne Ausführungsbit).

Prüfe, dass es funktioniert, und drücke **[Prüfen]**.

## Argumente und Exit-Codes

Skriptargumente kommen als `$1 $2 …` an, ihre Anzahl als `$#`. Die Konvention bei falschem Aufruf: **Usage auf stderr ausgeben und mit einem Code ungleich null beenden** — Aufrufer (andere Skripte, CI) müssen den Fehler erkennen können.

Aufgabe: Schreibe `~/work/logcut.sh <Logdatei> <Status>`.

- gibt die Anzahl der Zeilen mit dem angegebenen Statuscode im Format von `/opt/lab/data/app.log` aus (`… status=200 msg=…`)
- bei nicht genau 2 Argumenten: Usage ausgeben + Exit-Code 2

Skript schreiben:

```
cat > ~/work/logcut.sh <<'EOF'
#!/bin/bash
set -euo pipefail
usage() { echo "usage: $0 <logfile> <status>" >&2; exit 2; }
[ $# -eq 2 ] || usage
grep -c "status=$2 " "$1" || true
EOF
```

- `usage() { …; }` — eine Funktion. `>&2` schickt die Meldung nach stderr, `exit 2` beendet mit Exit-Code 2.
- `[ $# -eq 2 ] || usage` — ist die Anzahl der Argumente (`$#`) nicht 2, wird usage aufgerufen (`||`). `[ ]` ist der Bedingungsbefehl (`test`).
- `grep -c "status=$2 " "$1"` — zählt Zeilen mit dem Statuscode aus Argument 2. Variablen stehen in doppelten Anführungszeichen, damit Pfade mit Leerzeichen sicher bleiben.

Ausführbar machen:

```
chmod +x ~/work/logcut.sh
```

- Jedes neue Skript braucht das Ausführungsbit.

> `grep -c` endet bei null Treffern mit **Code 1**. Unter `set -e` beendet das das Skript, daher stellt `|| true` ausdrücklich klar: „null Treffer ist in Ordnung" — fail-fast bleibt an, aber was kein Fehler ist, wird nicht als Fehler behandelt.

Teste es und drücke **[Prüfen]**.

Normaler Aufruf — die 500er-Zeilen zählen:

```
~/work/logcut.sh /opt/lab/data/app.log 500
```

- Das erste Argument wird zu `$1` (Logdatei), das zweite zu `$2` (Statuscode).

Aufruf ohne Argumente — Exit-Code 2 erwartet:

```
~/work/logcut.sh; echo "exit=$?"
```

- `$?` — Exit-Code des vorherigen Befehls; `;` führt dies direkt danach aus, um zu bestätigen, dass usage mit 2 beendet hat.

## Garantiertes Aufräumen mit trap

Ein Skript, das temporäre Dateien anlegt, hinterlässt Müll, wenn es mittendrin stirbt. `trap '…' EXIT` ist ein Aufräum-Hook, der immer läuft, wenn das Skript endet — **ob regulär oder mit Fehler**.

Aufgabe: Schreibe `~/work/withtmp.sh`.

- mit `mktemp -d` ein temporäres Verzeichnis anlegen und darin eine beliebige Datei erstellen
- das temporäre Verzeichnis beim Beenden per `trap` löschen
- den Pfad des temporären Verzeichnisses als **letzte Ausgabezeile** ausgeben (die Prüfung kontrolliert, dass dieser Pfad weg ist)

Skript schreiben:

```
cat > ~/work/withtmp.sh <<'EOF'
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
date > "$tmp/scratch.txt"
echo "$tmp"
EOF
```

- `mktemp -d` — legt ein temporäres Verzeichnis mit eindeutigem Namen an und gibt seinen Pfad aus.
- `trap 'Befehl' EXIT` — führt den Befehl unmittelbar vor dem Beenden des Skripts aus, egal aus welchem Grund — hier das Löschen des temporären Verzeichnisses.
- `rm -rf "$tmp"` — löscht das Verzeichnis samt Inhalt (`-r`) ohne Nachfrage (`-f`). Der trap-Rumpf steht in einfachen Anführungszeichen, daher wird `$tmp` erst beim Ausführen expandiert.

Ausführbar machen:

```
chmod +x ~/work/withtmp.sh
```

- Ausführungsbit hinzufügen.

Ausführen und das Löschen bestätigen:

```
d=$(~/work/withtmp.sh); ls -d "$d" 2>&1   # "No such file" heißt, es hat geklappt
```

- `d=$(Skript)` — speichert die Ausgabe des Skripts (den temporären Pfad) in `d`.
- `ls -d "$d"` — fragt das Verzeichnis selbst ab; `2>&1` zeigt auch die Fehlermeldung. Es sollte schon weg sein, also ist `No such file` zu erwarten.

Wenn bestätigt, **[Prüfen]** drücken.

## Ein kaputtes Skript reparieren

Zum Schluss das, was du in der Praxis am häufigsten tust — **das Skript eines anderen reparieren**. `/opt/lab/bin/backup.sh` sichert ein Verzeichnis nach /tmp, stirbt aber, wenn der Pfad **ein Leerzeichen enthält**.

Skript ansehen:

```
cat /opt/lab/bin/backup.sh
```

- Erst lesen, dann reparieren: Suche nach `$src` und `$dest` ohne Anführungszeichen.

Testverzeichnis mit Leerzeichen im Pfad vorbereiten:

```
mkdir -p "/tmp/my app"; echo hi > "/tmp/my app/f.txt"
```

- Der Pfad enthält ein Leerzeichen und steht daher in doppelten Anführungszeichen, damit er ein Argument bleibt; `;` legt darin anschließend eine Testdatei an.

Mit dem Leerzeichen-Pfad ausführen:

```
/opt/lab/bin/backup.sh "/tmp/my app"   # schlägt fehl!
```

- Du übergibst ein Argument in Anführungszeichen, aber sobald das Skript `$src` ohne Anführungszeichen verwendet, wird es wieder in zwei Wörter zerlegt (Word Splitting).

Die Ursache ist **Variablenexpansion ohne Anführungszeichen**. Ist `$src` gleich `/tmp/my app`, wird `cp -r $src/*` in zwei Argumente zerlegt: `/tmp/my` und `app/*`. Das ist der Klassiker unter den klassischen Shell-Skript-Fehlern.

Aufgabe: Kopiere es nach `~/work/backup-fixed.sh` und repariere es.

- jede Variablenexpansion mit `"…"` quoten (`"$dest"`, `"$src"/*` — der Glob `*` bleibt außerhalb der Anführungszeichen!)
- `set -euo pipefail` hinzufügen
- mit dem Leerzeichen-Pfad ausführen und den Erfolg bestätigen

Kopie anlegen:

```
cp /opt/lab/bin/backup.sh ~/work/backup-fixed.sh
```

- `cp <Quelle> <Ziel>` — lässt das Original unberührt und legt eine Kopie in deinem Arbeitsverzeichnis ab.

Im Editor reparieren:

```
vim ~/work/backup-fixed.sh
```

- vim: `i` für den Einfügemodus, dann `Esc` → `:wq` zum Speichern und Beenden. Wenn du magst, nimm `nano` (`Ctrl+O` speichern, `Ctrl+X` beenden).

Mit dem Leerzeichen-Pfad zur Bestätigung ausführen:

```
~/work/backup-fixed.sh "/tmp/my app" && echo OK
```

- `A && B` — führt B nur aus, wenn A erfolgreich war (Exit-Code 0); erscheint `OK`, funktioniert die Reparatur.

Bei Erfolg **[Prüfen]** drücken — Modul abgeschlossen.
