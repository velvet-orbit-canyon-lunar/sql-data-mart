# Buchtausch-App: relationale Datenbank in PostgreSQL

Datenbank für eine Buchtausch-App, über die Nachbarn private Bücher anbieten und ausleihen können. Das Projekt entstand im Kurs *Data-Mart-Erstellung in SQL* (DLBDSPBDM01_D) der IU Internationale Hochschule GmbH und umfasst die drei Phasen: Konzeption, Erarbeitung und Finalisierung.

## Inhalt der Datenbank

Das Schema `buchtausch` besteht aus 13 Tabellen (12 Entitäten und eine Zuordnungstabelle) mit ausschließlich Dummy-Einträgen. Alle Namen, Titel und Adressen sind frei erfunden.

| Bereich | Tabellen |
|---|---|
| Nutzer und Orte | `Nutzer`, `Standort` |
| Bibliografie | `Buchtitel`, `Autor`, `Buchtitel_Autor`, `Verlag`, `Genre`, `Sprache` |
| Bestand und Verfügbarkeit | `Exemplar`, `Zeitslot` |
| Vorgänge | `Ausleihe`, `Bewertung`, `Buchbewertung` |

Die Regeln des Verleihs sind, insofern möglich, als Bedingungen der Datenbank umgesetzt:

| Mechanismus | Anzahl |
|---|---|
| Primärschlüssel | 13 |
| Fremdschlüssel (davon 2 zusammengesetzt) | 19 |
| `UNIQUE` | 9 |
| `CHECK` | 14 |
| `EXCLUDE` (keine überlappenden Zeitslots und Verleihzeiträume je Exemplar) | 2 |
| Trigger | 2 |
| zusätzliche Indizes | 5 |

Die Datei enthält außerdem 95 Testfälle (51 negativ, 44 positiv) und sechs Beispielabfagen, darunter beispielsweise eine Umkreissuche über die Geokoordinaten der Standorte mit Mittelpunkt und Radius als Parameter. Letztlich gibt Abschnitt 8 die Größe der Datenbank und der Tabellen sowie den Plan der Vorauswahl der Umkreissuche aus.

## Voraussetzungen

- PostgreSQL 18 und der Kommandozeilenclient `psql`
- die Erweiterung `btree_gist`, ein zusätzliches Modul der PostgreSQL-Distribution. Die Datei legt sie mit `CREATE EXTENSION IF NOT EXISTS` an der ausführende Benutzer muss aber dazu berechtigt sein.
- eine Datenbank, in der das Schema angelegt werden darf

## Installation und Ausführung

In einem Schritt:

```bash
createdb buchtausch
psql -d buchtausch -f Freese-Felix_IU14154154_DLBDSPBDM01_D_Abschlussphase_SQL.sql
```

In einer `psql`-Sitzung, um das Testprotokoll danach abzufragen. Es ist eine temporäre Tabelle und nur in der Sitzung vorhanden, die die Datei ausführt:

```bash
psql -d buchtausch
```

```sql
\i Freese-Felix_IU14154154_DLBDSPBDM01_D_Abschlussphase_SQL.sql
SELECT Nr, Regel, Art, Erwartet, Ergebnis, Status
  FROM Testprotokoll WHERE Tabelle = 'Nutzer' ORDER BY Nr;
```

Das erwartete Ergebnis der Testauswertung: zwei Zeilen, `negativ` und `positiv`, jeweils mit Status `OK`, Anzahl 51 und 44. Keine Zeile hat den Status `FEHLER`.

## Einige Hinweise

- Die Datei löscht das Schema `buchtausch` mit `DROP SCHEMA IF EXISTS buchtausch CASCADE` und legt es dann neu an. Sie ist daher beliebig oft ausführbar, alle Daten im Schema gehen dabei jedoch verloren.
- Bei einem Fehler bricht `psql` die Ausführung ab (`ON_ERROR_STOP`).
- Die Tests erwarten für `RESTRICT` den SQLSTATE 23001, den PostgreSQL ab Version 18 meldet. Unter älteren Versionen ist u.U. mit abweichenden Ergebnissen dieser Tests zu rechnen.
- Die Umkreissuche (Abfrage 1) sucht standardmäßig im Umkreis von 300km um Standort 3. Beide Werte lassen sich beim Aufruf überschreiben, beispielsweise `psql -d buchtausch -v standort=5 -v radius_km=600 -f …`.
- Gegenüber der Erarbeitungsphase erzwingt die Datenbank zusätzlich, dass eine Bewertung erst nach der Rückgabe erfolgt und das Ausleihdatum im gewählten Zeitslot ist. Der Verleihzeitraum endet mit der tatsächlichen Rückgabe, ein vorzeitig zurückgegebenes Exemplar ist also sofort wieder verleihbar. Die Änderungen sind in der SQL-Datei mit „Phase 3“ markiert.

## Beiliegende Dateien

| Datei | Inhalt |
|---|---|
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Abschlussphase_SQL.sql` | Phase 3: Schema, Dummy-Daten, Testfälle, Abfragen sowie Metadaten und Abfrageplan |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Erarbeitungsphase_SQL.sql` | Phase 2: Stand der Erarbeitungsphase |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Konzeptionsphase_AB.pdf` | Phase 1: Anforderungsspezifikation, Lösungsansatz, ER-Modell und Datenwörterbuch |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Erarbeitungsphase_PR.pdf` | Phase 2: Präsentation mit SQL-Dokumentation, Testfällen und Screenshots |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Erarbeitungsphase_KZ.pdf` | Phase 2: Zusammenfassung der Implementierung |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Abschlussphase_BE.pdf` | Phase 3: Funktionsumfang und Metadaten der Datenbank |
| `Freese-Felix_IU14154154_DLBDSPBDM01_D_Abschlussphase_AB.pdf` | Phase 3: Abstract |
