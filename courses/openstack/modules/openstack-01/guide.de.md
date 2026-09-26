# Die erste Instanz starten

Dieses Lab läuft auf **deinem eigenen All-in-one-OpenStack** (Caracal) im Pod. keystone,
glance, neutron und nova laufen alle hier, und im Terminal sind bereits Admin-Zugangsdaten
eingerichtet — nutze direkt die `openstack`-CLI (es gibt auch den Alias `os`).

> Hinweis: nova läuft in diesem Lab mit dem **Fake-Treiber** — Instanzen „booten" als reine
> Zustandsautomaten ohne echte VM dahinter, starten daher sofort und kosten fast nichts.
> Konsolenzugriff und SSH funktionieren nicht, aber der API-/CLI-Ablauf ist identisch mit einem echten
> OpenStack.

### Den Servicekatalog lesen

OpenStack ist nicht ein Programm, sondern **eine Sammlung von Diensten mit unterschiedlichen Aufgaben**. Jeder hat
seine eigene REST-API, und sie finden einander über den **Servicekatalog**, den keystone führt.
`openstack service list` zeigt, was in diesem Katalog registriert ist.

Diese Dienste begegnen dir in diesem Lab:

| Dienst | Typ | Aufgabe |
|---|---|---|
| keystone | identity | Authentifizierung und Autorisierung. Stellt das Token aus, das alle anderen Dienste prüfen |
| glance | image | Speichert und liefert die Disk-Images, aus denen Instanzen erstellt werden |
| neutron | network | Virtuelles Netzwerk — Netze, Subnetze, Ports |
| nova | compute | Lebenszyklus der Instanzen: anlegen, booten, stoppen, löschen |
| placement | placement | Verfolgt, welcher Host noch Kapazität (vCPU, RAM, Disk) hat, damit nova Instanzen platzieren kann |

Servicekatalog prüfen:

```bash
openstack service list
```

- `openstack <Objekt> <Aktion>` — die Grundform der OpenStack-CLI; hier ist das Objekt `service`, die Aktion `list`.
- Listet die im keystone-Servicekatalog registrierten Dienste auf. Für die Endpunkt-URLs `openstack endpoint list` verwenden.

`Name` ist der Name des Dienstes, `Type` der Standardbezeichner seiner Rolle. Die CLI findet Endpunkte
über den **Typ**: `openstack image list` sucht den Typ `image` und ruft glance auf. Anders gesagt entspricht
das erste Wort eines Befehls (`image`, `network`, `server`, …) einem Typ in dieser Tabelle.

### Die Compute-Dienstliste lesen

nova selbst ist **in mehrere Prozesse aufgeteilt**. `openstack compute service list` zeigt, welche davon
auf welchem Host laufen.

| Komponente | Aufgabe |
|---|---|
| nova-scheduler | Wählt aus, **auf welchem Compute-Host** eine neue Instanz landet; placement grenzt die Kandidaten ein |
| nova-conductor | Übernimmt Datenbankzugriffe und lang laufende Aufgaben, damit Compute-Knoten nie direkt auf die DB zugreifen |
| nova-compute | Steuert den Hypervisor, um Instanzen zu starten und zu stoppen. Läuft auf jedem Compute-Host einmal |

Compute-Host prüfen:

```bash
openstack compute service list
```

- Zeigt die Hintergrundprozesse von nova (scheduler, conductor, compute) mit Host, `Status` (enabled/disabled) und `State` (up/down).

`State` ist `up`, wenn der Prozess lebt; `Status` zeigt, ob ihn ein Betreiber deaktiviert hat.
Das ist die erste Tabelle, die man ansieht, wenn Instanzen sich nicht einplanen lassen — nichts erreicht einen
Host, dessen nova-compute `down` ist.

**nova-api steht nicht in dieser Liste.** API-Dienste laufen als Webserver und erscheinen stattdessen als
Endpunkte im Servicekatalog; hier siehst du die Hintergrundprozesse. Dieses Lab ist All-in-one,
daher melden alle drei Komponenten denselben Hostnamen.

> Referenz: [OpenStack-CLI-Dokumentation](https://docs.openstack.org/python-openstackclient/latest/) ·
> [Compute service overview](https://docs.openstack.org/nova/latest/admin/architecture.html)

## 1. Ein Netz und ein Subnetz anlegen

Beginne mit einem Projektnetz, an das die Instanz angeschlossen wird.

Netz `net1` anlegen:

```bash
openstack network create net1
```

- Legt in neutron das virtuelle L2-Netz `net1` an. Es hat noch keinen IP-Bereich, Instanzen bekämen also keine Adresse — das Subnetz im nächsten Befehl liefert sie.

Subnetz `subnet1` in `net1` mit dem Bereich `192.168.100.0/24` anlegen:

```bash
openstack subnet create --network net1 --subnet-range 192.168.100.0/24 subnet1
```

- `--network net1` — das Netz, zu dem das Subnetz gehört.
- `--subnet-range 192.168.100.0/24` — der CIDR-Bereich; Gateway (standardmäßig `.1`) und DHCP-Pool werden automatisch abgeleitet.
- Das letzte Argument `subnet1` ist der Name des Subnetzes.

Netze zur Kontrolle auflisten:

```bash
openstack network list
```

- Zeigt die Spalte `Subnets` die ID des neuen Subnetzes, ist das Netz bereit.

## 2. Eine Instanz booten (ACTIVE)

Boote die Instanz `vm1` aus dem vorab geladenen Image `cirros` mit dem Flavor `m1.tiny`.

Verfügbare Images auflisten:

```bash
openstack image list
```

- In glance registrierte Images. Nur Images mit `Status` `active` können zum Anlegen von Instanzen verwendet werden.

Flavors auflisten:

```bash
openstack flavor list
```

- Ein Flavor ist eine Größenvorlage für die Hardware (vCPU, RAM, Disk) einer Instanz; `m1.tiny` ist der kleinste.

Instanz booten:

```bash
openstack server create --flavor m1.tiny --image cirros --network net1 vm1
```

- `--flavor m1.tiny` — Hardwaregröße, `--image cirros` — zu bootendes Disk-Image, `--network net1` — Netz, in dem ein Port angelegt und angeschlossen wird.
- Das letzte Argument `vm1` ist der Instanzname. Der Befehl reicht die Anfrage nur ein und kehrt zurück (`BUILD`), prüfe den Status daher separat.

Beobachten, bis der Status `ACTIVE` ist (kann einige Sekunden dauern):

```bash
openstack server show vm1 -c status -c addresses
```

- `openstack server show <Name>` — Details einer Instanz.
- `-c <Spalte>` — zeigt nur die gewählten Spalten (Felder); wiederholbar. `addresses` zeigt die zugewiesene IP, z. B. `net1=192.168.100.x`.

## 3. Instanzen aller Projekte auflisten

Das bisher verwendete `openstack server list` zeigt nur **Instanzen deines eigenen Projekts**.

Ein **Projekt** ist die Einheit, der in OpenStack Ressourcen gehören (früher hieß es Tenant).
Netze, Instanzen, Volumes und Images gehören alle zu einem Projekt, und Quotas gelten pro
Projekt. Benutzer erhalten über eine **Rolle** Zugang zu einem Projekt, und Tokens werden „als" ein Projekt ausgestellt —
deshalb sieht dieselbe Person je nach Projekt, mit dem sie sich angemeldet hat, unterschiedliche Ressourcen.

Prüfen, zu welchem Projekt dein aktuelles Token gehört:

```bash
openstack token issue -c project_id -f value
```

- `openstack token issue` — holt mit deinen aktuellen Zugangsdaten ein keystone-Token und zeigt seine Details.
- `-c project_id -f value` — nur die Spalte `project_id`, als nackter Wert (`-f value`) ohne Tabellenrahmen ausgegeben — praktisch in Skripten.

In diesem Lab gibt es bereits Projekte wie `admin`, `service` und `demo`. Liste sie auf:

```bash
openstack project list
```

- Projekte (ID und Name) in keystone; ordne hier die `project_id` aus dem vorherigen Befehl einem Namen zu.

`--all-projects` fordert **die Ressourcen aller Projekte auf einmal** an. Es ist eine Betreiberoption, um
die gesamte Cloud zu sehen, und benötigt daher die Admin-Rolle; ein normaler Benutzer erhält einen Berechtigungsfehler.

Die Standardspalten enthalten das Projekt nicht. Da es hier darum geht, wem was gehört, wähle
diese Spalte ausdrücklich mit `-c 'Project ID'`. (`--long` ist eine eigene Option, die betriebliche Details
wie Task-Status und Host hinzufügt.)

Mit Projekt-ID auflisten:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID'
```

- `--all-projects` — listet Instanzen aller Projekte auf (benötigt die Admin-Rolle).
- `-c <Spalte>` — zeigt nur die gewählten Spalten (Felder); wiederholbar. Spaltennamen mit Leerzeichen in Anführungszeichen setzen (`'Project ID'`).

Ergebnis für die Bewertung in einer Datei speichern:

```bash
openstack server list --all-projects -c ID -c Name -c Status -c 'Project ID' -f value > ~/all-servers.txt
```

- `-f value` — gibt durch Leerzeichen getrennte Werte statt einer Tabelle aus.
- `> ~/all-servers.txt` — speichert (überschreibt) diese Ausgabe in einer Datei; das Prüfskript liest sie.

> Referenz: [Manage projects, users, and roles](https://docs.openstack.org/keystone/latest/admin/manage-projects-users-and-roles.html)

## 4. Die Instanz stoppen (SHUTOFF)

Schließe den Lebenszyklus ab, indem du die Instanz stoppst.

Instanz stoppen:

```bash
openstack server stop vm1
```

- Fährt die Instanz herunter (schaltet sie aus). Disk, IP und andere Ressourcen bleiben erhalten, und `openstack server start vm1` schaltet sie wieder ein. Zum vollständigen Entfernen `openstack server delete` verwenden.

Prüfen, ob der Status `SHUTOFF` ist:

```bash
openstack server show vm1 -c status
```

- Prüfe, ob `status` auf `SHUTOFF` gewechselt ist; falls noch nicht, nach einigen Sekunden erneut ausführen.
