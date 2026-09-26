# Dateirechte und Spezialbits

Der erste Schritt der Linux-Sicherheit sind **Dateirechte**. Dieses Modul behandelt Grundrechte (rwx) und umask, Spezialbits wie setgid und Sticky, feingranulare Zugriffskontrolle mit ACLs und schließlich ein praktisches Audit: gefährliche Rechte auf einem echten System finden und beheben.

Prüfen wir den aktuellen Benutzer. `learner` ist ein normaler Benutzer mit sudo-Zugriff.

```
id
```

- `id` — UID des aktuellen Benutzers, seine primäre Gruppe (`gid`) und alle Gruppen, denen er angehört (`groups`).

Du solltest zwischen beiden Rechte-Schreibweisen wechseln können.

| Schreibweise | Beispiel | Bedeutung |
|---|---|---|
| Symbolisch | `rwxr-x---` | Eigentümer rwx / Gruppe r-x / andere nichts |
| Oktal | `750` | Summe aus r=4, w=2, x=1 |

## Grundrechte und umask

Beim Anlegen einer Datei bestimmt die **umask** die Standardrechte.

Aktuelle umask prüfen:

```
umask
```

- `umask` — Rechte-Bits, die neuen Dateien/Verzeichnissen **entzogen** werden. Das übliche `0022` entzieht Gruppe/anderen das Schreibrecht → Dateien 644, Verzeichnisse 755.

Eine Datei anlegen und sehen, welche Rechte sie tatsächlich bekommt:

```
touch /tmp/t1 && stat -c %a /tmp/t1
```

- `touch` — legt eine leere Datei an (oder aktualisiert nur den Zeitstempel). `&&` — den nächsten Befehl nur ausführen, wenn dieser erfolgreich war.
- `stat -c %a` — eigenes Format (`-c`), das nur die oktalen Rechte (`%a`) ausgibt.

Lege jetzt einen Arbeitsbereich an, auf den nur du zugreifen kannst. Anforderungen:

- Verzeichnis `~/work` — Modus **700** (rwx nur für den Eigentümer)
- Datei `~/work/secret.txt` — beliebiger Inhalt, Modus **600** (rw nur für den Eigentümer)

Arbeitsverzeichnis mit Modus 700 anlegen:

```
mkdir -p ~/work && chmod 700 ~/work
```

- `mkdir -p` — legt fehlende übergeordnete Verzeichnisse an, kein Fehler, wenn es existiert.
- `chmod 700` — oktaler Modus: Eigentümer rwx (7), Gruppe/andere nichts (0).

Geheime Datei anlegen:

```
echo "top secret" > ~/work/secret.txt
```

- `echo "…" > Datei` — schreibt den String in die Datei (wird angelegt, falls sie fehlt, sonst überschrieben). Die Rechte neuer Dateien folgen der umask.

Modus der Datei auf 600 setzen:

```
chmod 600 ~/work/secret.txt
```

- `600` — Eigentümer rw (6 = 4+2), nichts für Gruppe/andere. Symbolisch: `chmod u=rw,go= <Datei>`.

Mit `stat` bestätigen und **[Prüfen]** drücken.

```
stat -c '%a %n' ~/work ~/work/secret.txt
```

- `%a` oktale Rechte, `%n` Dateiname; eine Zeile pro angegebener Datei.

> Das `x`-Bit eines Verzeichnisses bedeutet „Durchgangsrecht (Betreten)". Selbst mit `r` auf einem Verzeichnis erreichst du die Dateien darin ohne `x` nicht — das begegnet uns im ACL-Schritt wieder.

## setgid und das Sticky-Bit

Zwei Spezialbits, die du für Team-Verzeichnisse oft brauchst:

| Bit | Oktal | Wirkung auf ein Verzeichnis |
|---|---|---|
| setgid | 2000 | darin angelegte Dateien **erben die Gruppe des Verzeichnisses** |
| sticky | 1000 | nur der **Eigentümer** darf eine Datei löschen (wie bei `/tmp`) |

Lege das gemeinsame Verzeichnis `/srv/share` für die Gruppe `share` an. Anforderungen:

- Gruppe anlegen: `share`
- Verzeichnis `/srv/share`, Eigentümergruppe `share`
- Modus **3775** = setgid(2000) + sticky(1000) + 775

Gruppe anlegen:

```
sudo groupadd -f share
```

- `groupadd` — legt eine Gruppe an; `-f` endet still erfolgreich, wenn sie schon existiert.

Gemeinsames Verzeichnis anlegen:

```
sudo mkdir -p /srv/share
```

- `/srv` gehört root, daher `sudo`.

Eigentümergruppe auf share setzen:

```
sudo chgrp share /srv/share
```

- `chgrp <Gruppe> <Pfad>` — ändert nur die Eigentümergruppe; mit `chown Benutzer:Gruppe` änderst du beides.

Modus 3775 mit den Spezialbits setzen:

```
sudo chmod 3775 /srv/share
```

- Bei einem vierstelligen Oktalmodus enthält die erste Ziffer die Spezialbits: `3` = setgid (2) + sticky (1). Der Rest `775` ist rwx für Eigentümer/Gruppe, r-x für andere.

Prüfe das Ergebnis. In symbolischer Schreibweise erscheint setgid als `s` an der Gruppenposition und Sticky als `t` an der letzten Position (`drwxrwsr-t`).

Modus und Eigentümergruppe prüfen:

```
stat -c '%a %G %n' /srv/share
```

- `%G` — der Name der Eigentümergruppe.

Symbolische Schreibweise ansehen:

```
ls -ld /srv/share
```

- `ls -ld` — das Verzeichnis **selbst** (`-d`), nicht sein Inhalt, in symbolischer Form (`drwxrwsr-t`).

Wenn alles stimmt, **[Prüfen]** drücken.

## Feingranularer Zugriff mit ACLs

`rwx` hat nur drei Plätze: Eigentümer/Gruppe/andere. „Genau **einem bestimmten Benutzer** das Lesen dieser Datei erlauben" löst man mit einer **ACL** (Access Control List).

Auf dem System gibt es bereits ein Audit-Konto namens `audit`. Gib `audit` die Datei `~/work/secret.txt` aus Schritt 1 **nur zum Lesen** frei.

audit ein Lese-ACL geben:

```
setfacl -m u:audit:r ~/work/secret.txt
```

- `setfacl -m` — fügt einen ACL-Eintrag hinzu bzw. ändert ihn (modify), Format `u:<Benutzer>:<Rechte>` (`g:` für Gruppen).

ACL-Einträge prüfen:

```
getfacl ~/work/secret.txt
```

- `getfacl` — zeigt Eigentümer, Gruppe, alle ACL-Einträge und die `mask` (die maximalen ACL-Rechte).

Das allein reicht aber nicht — damit `audit` die Datei tatsächlich **erreicht**, muss es die Verzeichnisse auf dem Pfad (`~` und `~/work`) durchqueren können. Ein 700-Verzeichnis sperrt audit aus.

Nur das Durchgangsrecht (x) per ACL freigeben:

```
setfacl -m u:audit:x ~ ~/work
```

- Nur `x` auf einem Verzeichnis erlaubt das **Durchqueren**, ohne es auflisten zu dürfen (r). Wird auf beide Pfade (`~`, `~/work`) gleichzeitig angewendet.

Prüfe es aus Sicht von audit.

Lesen — sollte klappen:

```
sudo -u audit cat ~/work/secret.txt
```

- `sudo -u <Benutzer> <Befehl>` — führt den Befehl als anderer Benutzer aus, um die tatsächlichen Rechte zu prüfen.

Schreiben — sollte scheitern:

```
sudo -u audit sh -c 'echo x >> ~learner/work/secret.txt'
```

- `sh -c '…'` — startet eine ganze Shell als audit, damit auch die Umleitung (`>>`) mit den Rechten von audit läuft.
- `~learner` — das Home-Verzeichnis von learner (für audit wäre `~` sein eigenes Home).

Dateien mit ACL zeigen in `ls -l` ein `+` hinter den Rechte-Bits. Bestätige das und drücke **[Prüfen]**.

## Rechte-Audit und Reparatur

Zum Schluss eine Aufgabe aus der Praxis. Programme mit dem **SUID**-Bit (4000) laufen mit den Rechten des Eigentümers (meist root) und haben daher bei jedem Audit höchste Priorität.

Alle SUID-Dateien im System finden und die Liste speichern:

```
sudo find / -xdev -perm -4000 -type f > ~/work/suid.txt
```

- `find /` — rekursive Suche ab der Wurzel. `-xdev` — nicht in andere Dateisysteme (/proc, …) wechseln.
- `-perm -4000` — Dateien, die das SUID-Bit **enthalten** (`-` = „hat alle diese Bits"). `-type f` — nur reguläre Dateien.
- `> ~/work/suid.txt` — speichert die Liste in einer Datei.

Liste ansehen:

```
cat ~/work/suid.txt
```

- `cat` — gibt die gespeicherte Liste der SUID-Dateien aus.

Überlege, warum `passwd` SUID ist — ein normaler Benutzer muss die root gehörende `/etc/shadow` aktualisieren können.

Zweite Aufgabe: `/opt/lab/perm/danger.conf` ist eine Konfigurationsdatei mit einem DB-Passwort, wurde aber mit Modus **666** ausgeliefert (für alle les- und schreibbar!).

Aktuelle Rechte prüfen:

```
ls -l /opt/lab/perm/
```

- `ls -l` — prüft Rechte (`-rw-rw-rw-` = 666), Eigentümer und Gruppe.

Auf 640 reparieren:

```
sudo chmod 640 /opt/lab/perm/danger.conf
```

- `640` — Eigentümer rw, Gruppe r, andere nichts: Die Anwendung kann über ihre Gruppe weiter lesen, alle anderen sind ausgesperrt.

Drücke nach der Reparatur **[Prüfen]**, um das Modul abzuschließen.
