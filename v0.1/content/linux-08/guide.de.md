# Abschluss – einen toten Dienst wiederbeleben

2 Uhr nachts, der Pager schlägt an: **„lab-app startet nicht."** Dieses Modul ist ein Abschlussszenario, in dem du einen echten Vorfall von Anfang bis Ende bearbeitest — mit allem, was du bisher gelernt hast (systemd, journald, Signal- und Port-Verfolgung, Dateirechte).

Diesmal bekommst du nicht jeden Befehl vorgegeben — die **Reihenfolge der Diagnose** ist das Lernziel. Wenn du feststeckst, erinnere dich an die Werkzeuge aus den früheren Modulen: `systemctl status/cat`, `journalctl -u`, `sudo ss -ltnp`, `ls -l`, `sudo -u <Benutzer>`.

Verschaffe dir zuerst ein Bild der Lage.

```
systemctl status lab-app --no-pager
```

- Suche den ersten Hinweis in der Zeile `Active:` und in den letzten Logzeilen. `--no-pager` gibt ohne less aus.

## Startfehler diagnostizieren — 203/EXEC

Reicht status nicht, kennt das Journal die Antwort.

```
journalctl -u lab-app --no-pager | tail -20
```

- `journalctl -u <Unit>` — nur die Logs dieser Unit; `| tail -20` konzentriert sich auf die neuesten 20 Zeilen.

`status=203/EXEC` — der Code, den du in linux-06 kennengelernt hast. Finde heraus, **was die Unit auszuführen versuchte**, als sie scheiterte.

```
systemctl cat lab-app
```

- Zeigt die Unit-Datei unverändert. Achte auf `ExecStart=` (was läuft) und `User=` (wer es ausführt).

Vergleiche den Interpreterpfad in ExecStart mit dem, was auf diesem System tatsächlich existiert (`ls /usr/bin/python3*`). Er wird auf eine Version zeigen, die es nicht gibt — ein häufiger Unfall, wenn ein Deploy-Skript für einen anderen Server geschrieben wurde.

Aufgabe: Korrigiere ExecStart auf einen existierenden Interpreter und führe `daemon-reload` aus. Wenn behoben, **[Prüfen]** drücken.

> start wird noch nicht klappen — Vorfälle haben selten nur eine Ebene. Weiter zum nächsten Schritt.

## Einen Portkonflikt auflösen

Jetzt erzeugt der Start einen anderen Fehler.

Dienst zu starten versuchen:

```
sudo systemctl start lab-app
```

- Nach der Reparatur erneut starten; schlägt es fehl, nennt das nächste Log die neue Ursache.

Fehlerlog prüfen:

```
journalctl -u lab-app --no-pager | tail -5
```

- Nur das Log dieses letzten Versuchs zählt, also die letzten 5 Zeilen.

`Address already in use` — **etwas anderes hat** den Port 8080 belegt, den lab-app braucht. Finde den Schuldigen mit der Port-Verfolgung aus linux-02 und linux-07.

```
sudo ss -ltnp | grep 8080
```

- Findet den auf 8080 lauschenden Socket und seinen Prozess (`users:(("Name",pid=…))`). Merke dir die PID.

Um von einer PID auf ihre Unit zurückzuschließen, ist `systemctl status <PID>` praktisch. Der Schuldige ist eine Legacy-Unit, die stillgelegt werden soll. Stoppen reicht nicht — nach einem Neustart käme sie zurück, daher musst du sie **auch deaktivieren**.

Aufgabe: Nimm den Besetzer mit `disable --now` vom Netz und starte lab-app. Ist lab-app active, **[Prüfen]** drücken.

## Ein Berechtigungsproblem lösen

Der Dienst läuft … aber wir sind noch nicht fertig.

```
curl -i http://127.0.0.1:8080/index.html
```

- `curl -i` — gibt vor dem Body auch die Statuszeile (`HTTP/1.0 404 …`) und die Header aus.

**404** — dabei existiert die Datei eindeutig (`ls -l /srv/lab-app/`). Warum?

Zwei Hinweise. ① Die Unit hat `User=labapp` — der Dienst läuft als labapp, nicht als root. ② index.html ist `root:root 600` — **labapp kann sie nicht lesen.** Dieser Server (http.server) liefert 404, wenn er eine Datei nicht öffnen kann. Ein Lehrbuchfall von „Datei existiert, aber 404".

Gewöhne dir an, Verdachtsmomente zu überprüfen — lies die Datei als dieser Benutzer.

```
sudo -u labapp cat /srv/lab-app/index.html
```

- `sudo -u <Benutzer> <Befehl>` — führt den Befehl als dieser Benutzer aus: Du liest die Datei mit genau den Rechten, die der Dienst hat.

Aufgabe: Korrigiere Eigentümer oder Rechte, sodass labapp die Datei lesen kann (mit der Denkweise aus linux-01 — nicht weiter öffnen als nötig). Liefert curl `LAB APP OK`, **[Prüfen]** drücken.

## Wiederholung verhindern und abschließen

Wiederherstellung besteht aus zwei Teilen: „jetzt zum Laufen bringen" + **„auch beim nächsten Mal überleben lassen".** Die Checkliste:

1. Ist lab-app **aktiviert (enable)**? (eine Wiederherstellung, die nach einem Neustart wieder stirbt, ist keine)
2. Die endgültige Antwort als Beleg sichern — in `~/work/final.txt` speichern

Start beim Booten aktivieren:

```
sudo systemctl enable lab-app
```

- `enable` — registriert den automatischen Start beim Booten (legt den Symlink an); der laufende Dienst bleibt unberührt. Prüfen mit `systemctl is-enabled lab-app`.

Endgültige Antwort speichern:

```
curl -s http://127.0.0.1:8080/index.html > ~/work/final.txt
```

- Speichert den von `curl -s` gelieferten Body mit `>` in einer Datei.

Gespeicherten Inhalt prüfen:

```
cat ~/work/final.txt
```

- Prüfe, dass die gespeicherte Antwort `LAB APP OK` lautet.

Drücke **[Prüfen]**, und du hast den Linux-Track abgeschlossen. Merke dir: Der dreifache Fehler, den du heute gelöst hast (falscher Pfad → Portkonflikt → Rechte), ist die häufigste Kombination in echten Vorfallsberichten — und alle drei **wussten journal, ss und ls -l zuerst**.
