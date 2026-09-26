# Benutzer, Gruppen und sudo mit minimalen Rechten

Kommt ein neues Teammitglied auf einen Server, legst du sein Konto an, fügst es der Teamgruppe hinzu und gibst **nur so viel** sudo frei wie nötig. Geht es, sperrst du das Konto. Dieses Modul behandelt diesen gesamten Lebenszyklus.

Zuerst: Wo Kontoinformationen liegen.

| Datei | Inhalt |
|---|---|
| `/etc/passwd` | Benutzerliste (Name:x:UID:GID:Kommentar:Home:Shell) |
| `/etc/shadow` | Passwort-Hashes + Ablaufrichtlinie (nur für root lesbar) |
| `/etc/group` | Gruppen und ihre Mitglieder |
| `/etc/sudoers`, `/etc/sudoers.d/` | sudo-Berechtigungsregeln |

Das Konto learner nachschlagen:

```
getent passwd learner
```

- `getent <Datenbank> <Schlüssel>` — schlägt einen Eintrag über NSS nach; gibt die Zeile von `learner` aus der Datenbank `passwd` aus.

Einen Blick auf den Anfang von shadow werfen:

```
sudo head -3 /etc/shadow
```

- `/etc/shadow` ist nur für root lesbar, daher `sudo`. Das zweite Feld ist der Passwort-Hash (`*` oder `!` bedeutet: keine Anmeldung per Passwort).

> `getent` fragt über NSS ab (einschließlich externer Quellen wie LDAP), statt Dateien direkt zu öffnen — eine genauere Gewohnheit als `cat /etc/passwd`.

## Benutzer anlegen

Lege das Deployment-Konto `deploy` an. Anforderungen:

- ein Home-Verzeichnis anlegen (`-m` — ohne entsteht ein Konto ohne Home)
- Login-Shell `/bin/bash` (`-s` — viele Distributionen nutzen standardmäßig sh)

Benutzer deploy anlegen:

```
sudo useradd -m -s /bin/bash deploy
```

- `useradd` — legt einen Benutzer an: `-m` legt das Home-Verzeichnis an (kopiert `/etc/skel`), `-s /bin/bash` setzt die Login-Shell, das letzte Argument ist der Benutzername.
- Das Passwort wird separat mit `passwd deploy` gesetzt (in diesem Lab nicht nötig).

passwd-Eintrag prüfen:

```
getent passwd deploy
```

- Von den durch Doppelpunkte getrennten Feldern sind die letzten beiden Home-Verzeichnis und Shell — prüfe auf `/home/deploy` und `/bin/bash`.

Home-Verzeichnis prüfen:

```
ls -ld /home/deploy
```

- `ls -ld` — zeigt das Verzeichnis **selbst** (`-d`), nicht seinen Inhalt: Rechte und Eigentümer. Der Eigentümer sollte `deploy` sein.

`useradd` ist ein Low-Level-Werkzeug und **fragt nichts nach**. Lässt du eine Option weg, legt es das Konto einfach so an, daher ist die Kontrolle danach Pflicht. Wenn geprüft, **[Prüfen]** drücken.

## Gruppen einrichten

Lege die Betriebsgruppe `ops` an und füge deploy hinzu. Hier lauert eine klassische Falle —

| Befehl | Ergebnis |
|---|---|
| `usermod -aG ops deploy` | **fügt** ops als Zusatzgruppe hinzu ✔ |
| `usermod -G ops deploy` | **ersetzt** alle Zusatzgruppen durch nur ops (alles andere fällt weg!) |
| `usermod -g ops deploy` | **ersetzt die primäre Gruppe** (ändert die Standardgruppe neuer Dateien) |

`-G` ohne `-a` (append) ist eine Abkürzung zum Vorfall. Füge die Gruppe als Zusatzgruppe hinzu.

Gruppe ops anlegen:

```
sudo groupadd ops
```

- `groupadd <Gruppe>` — legt eine neue Gruppe an; in `/etc/group` kommt eine Zeile hinzu.

Als Zusatzgruppe hinzufügen:

```
sudo usermod -aG ops deploy
```

- `usermod` — ändert einen bestehenden Benutzer. `-G ops` setzt Zusatzgruppen, `-a` **hängt** sie an die vorhandenen an.
- Bereits angemeldete Sitzungen sehen die neue Gruppe erst nach erneuter Anmeldung.

Gruppen prüfen:

```
id deploy
```

- `id <Benutzer>` — UID, primäre Gruppe (`gid=`) und alle Gruppen (`groups=`) in einer Zeile.

Lerne, in der Ausgabe von `id` zwischen `gid=` (primär) und `groups=` (alle) zu unterscheiden. Wenn geprüft, **[Prüfen]** drücken.

## sudoers nach Least Privilege

deploy soll den Dienststatus abfragen dürfen, aber **nichts weiter**. Konvention ist, `/etc/sudoers` nicht direkt zu bearbeiten, sondern Drop-ins unter `/etc/sudoers.d/` anzulegen.

Syntax: `wer wo=(als-wer) [NOPASSWD:] Befehle`

Drop-in-Regel schreiben:

```
echo 'deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *' | sudo tee /etc/sudoers.d/deploy
```

- `echo 'Regel' | sudo tee <Datei>` — bei `sudo echo … > Datei` erledigt deine eigene Shell die Umleitung und scheitert an den Rechten, daher schreibt `tee`, das als root läuft, die Datei.
- Die Regel: `deploy` darf auf jedem Host (`ALL`), als beliebiger Benutzer (`(ALL)`), ohne Passwort (`NOPASSWD:`) nur `systemctl status *` ausführen.

Modus 440 setzen:

```
sudo chmod 440 /etc/sudoers.d/deploy
```

- `440` — nur lesbar für Eigentümer (root) und Gruppe. sudo verweigert sudoers-Dateien, die für andere beschreibbar sind.

**Die Syntaxprüfung ist Pflicht.** Ein kaputtes sudoers legt sudo selbst lahm, was die Wiederherstellung mühsam macht. `visudo -cf` ist das Sicherheitsnetz.

```
sudo visudo -cf /etc/sudoers.d/deploy
```

- `visudo -c` — nur Syntaxprüfung, `-f <Datei>` — die zu prüfende Datei; es sollte `parsed OK` ausgeben.
- Üblicherweise bearbeitet man sudoers mit `sudo visudo`, das vor dem Speichern prüft.

Prüfe, was deploy tatsächlich darf.

sudo-Rechte von deploy auflisten:

```
sudo -l -U deploy
```

- `sudo -l` — erlaubte sudo-Befehle auflisten; `-U deploy` — für einen anderen Benutzer (benötigt root).

Erlaubter Befehl — sollte klappen:

```
sudo -u deploy sudo -n systemctl status cron --no-pager | head -3   # erlaubt
```

- `sudo -u deploy <Befehl>` — führt den Befehl als deploy aus; darin wird erneut `sudo` aufgerufen, um die sudo-Rechte von deploy zu testen.
- `sudo -n` — nie nach einem Passwort fragen (nicht interaktiv); scheitert sofort, wenn eines nötig wäre.
- `--no-pager` — direkt ausgeben statt über less.

Verbotener Befehl — sollte abgelehnt werden:

```
sudo -u deploy sudo -n systemctl restart cron 2>&1 | tail -1        # abgelehnt
```

- `restart` steht nicht in der Regel und wird daher abgelehnt. `2>&1` schickt auch den Fehler in die Pipe, `tail -1` zeigt die letzte Zeile.

Verhalten sich Erlauben/Ablehnen wie gewünscht, **[Prüfen]** drücken.

## Konten sperren und Passwortrichtlinie

`olduser` gehört jemandem, der gegangen ist. Löschen (`userdel`) wirft Probleme beim Aufräumen der Dateieigentümerschaft auf, daher ist der übliche erste Schritt das **Sperren**.

Konto sperren:

```
sudo usermod -L olduser
```

- `usermod -L` — sperrt das Konto, indem dem shadow-Hash ein `!` vorangestellt wird; das blockiert Anmeldungen per Passwort. Entsperren mit `-U`.

Sperrstatus prüfen:

```
sudo passwd -S olduser
```

- `passwd -S <Benutzer>` — Zusammenfassung des Passwortstatus; zweites Feld `L` gesperrt, `P` nutzbar, `NP` kein Passwort.

Ist das zweite Feld von `passwd -S` `L` (locked), hat es geklappt. Das Sperren stellt dem Hash in shadow nur ein `!` voran und lässt sich daher jederzeit mit `-U` rückgängig machen.

Wende als Nächstes auf deploy ein **maximales Passwortalter von 90 Tagen** an.

90-Tage-Maximum anwenden:

```
sudo chage -M 90 deploy
```

- `chage` — ändert die Richtlinie zur Passwortalterung; `-M 90` — maximales Alter von 90 Tagen.

Richtlinie prüfen:

```
sudo chage -l deploy
```

- `chage -l` — listet die aktuelle Richtlinie auf: letzte Änderung, Ablauf, minimale/maximale Tage, …

Sind beide bestätigt, **[Prüfen]** drücken — Modul abgeschlossen.
