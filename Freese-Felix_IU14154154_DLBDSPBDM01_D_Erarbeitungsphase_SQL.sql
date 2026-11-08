-- Buchtausch-App, Kurs DLBDSPBDM01_D, Phase 2: Erarbeitungsphase
-- Felix Freese, IU14154154
-- PostgreSQL 18, benötigt die Erweiterung btree_gist
-- Ausführung: psql -d <Datenbank> -f <Datei>
-- Das Schema buchtausch wird gelöscht und neu angelegt

-- 1. Setup
-- definiere psql: bei einem Fehler abbrechen
\set ON_ERROR_STOP on
-- definiere psql: Befehlsbestätigungen ausblenden
\set QUIET on
-- Hinweismeldungen ausblenden
SET client_min_messages TO warning;
-- Schema neu anlegen
DROP SCHEMA IF EXISTS buchtausch CASCADE;
-- Schema anlegen
CREATE SCHEMA buchtausch;
-- Folgende Objekte im Schema buchtausch anlegen
SET search_path TO buchtausch;
-- Erweiterung für die EXCLUDE-Constraints
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- Uhrzeiten definieren
CREATE TYPE timerange AS RANGE (subtype = time);


-- 2. Tabellen
-- "Nutzer" sind die Stammdaten der Teilnehmer
CREATE TABLE Nutzer (
    NutzerID      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Name          VARCHAR(100) NOT NULL,
    Vorname       VARCHAR(100) NOT NULL,
    EMail         VARCHAR(255) NOT NULL UNIQUE,
    Telefonnummer VARCHAR(30)
);

-- "Standort" als Adresse mit Koordinaten (für Umkreissuche benötigt)
CREATE TABLE Standort (
    StandortID    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    NutzerID      INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    Straße        VARCHAR(100) NOT NULL,
    Hausnummer    VARCHAR(10)  NOT NULL,
    Postleitzahl  VARCHAR(10)  NOT NULL,
    Ort           VARCHAR(100) NOT NULL,
    Land          VARCHAR(100) NOT NULL,
    Breitengrad   NUMERIC(8,6) NOT NULL CHECK (Breitengrad BETWEEN -90 AND 90),
    Längengrad    NUMERIC(9,6) NOT NULL CHECK (Längengrad BETWEEN -180 AND 180),
    UNIQUE (NutzerID, StandortID)
);

-- Verlage der Buchtitel
CREATE TABLE Verlag (
    VerlagID INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Name     VARCHAR(150) NOT NULL UNIQUE,
    Ort      VARCHAR(100),
    Land     VARCHAR(100)
);

-- Genres
CREATE TABLE Genre (
    GenreID     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Bezeichnung VARCHAR(50) NOT NULL UNIQUE
);

-- Sprachen
CREATE TABLE Sprache (
    SpracheID   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Bezeichnung VARCHAR(50) NOT NULL UNIQUE
);

-- Autoren der Buchtitel
CREATE TABLE Autor (
    AutorID INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Name    VARCHAR(100) NOT NULL,
    Vorname VARCHAR(100)
);

-- Buchtitel also bibliografische Angaben
CREATE TABLE Buchtitel (
    BuchtitelID      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    VerlagID         INTEGER REFERENCES Verlag (VerlagID) ON DELETE RESTRICT,
    GenreID          INTEGER NOT NULL REFERENCES Genre (GenreID) ON DELETE RESTRICT,
    SpracheID        INTEGER NOT NULL REFERENCES Sprache (SpracheID) ON DELETE RESTRICT,
    ISBN             VARCHAR(17) UNIQUE,
    Titel            VARCHAR(255) NOT NULL,
    Erscheinungsjahr SMALLINT NOT NULL CHECK (Erscheinungsjahr BETWEEN 1450 AND 2100),
    Auflage          SMALLINT NOT NULL DEFAULT 1 CHECK (Auflage > 0)
);

-- Zuordnungstabelle von Buchtitel zu Autor
CREATE TABLE Buchtitel_Autor (
    BuchtitelID INTEGER NOT NULL REFERENCES Buchtitel (BuchtitelID) ON DELETE CASCADE,
    AutorID     INTEGER NOT NULL REFERENCES Autor (AutorID) ON DELETE RESTRICT,
    PRIMARY KEY (BuchtitelID, AutorID)
);

-- Exemplar, also ein physisches Buch eines Besitzers mit Abholort
CREATE TABLE Exemplar (
    ExemplarID          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BuchtitelID         INTEGER NOT NULL REFERENCES Buchtitel (BuchtitelID) ON DELETE RESTRICT,
    BesitzerNutzerID    INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    StandortID          INTEGER NOT NULL,
    Zustand             VARCHAR(20) NOT NULL CHECK (Zustand IN ('Neu', 'Gut', 'Gebraucht')),
    MaxAusleihDauerTage SMALLINT NOT NULL CHECK (MaxAusleihDauerTage > 0),
    VersandMöglich      BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (BesitzerNutzerID, StandortID)
        REFERENCES Standort (NutzerID, StandortID) ON DELETE RESTRICT
);

-- Zeitslot ist das Abholfenster eines Exemplars
CREATE TABLE Zeitslot (
    ZeitslotID  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ExemplarID  INTEGER NOT NULL REFERENCES Exemplar (ExemplarID) ON DELETE CASCADE,
    Tag_von     DATE NOT NULL,
    Tag_bis     DATE NOT NULL,
    Uhrzeit_von TIME NOT NULL,
    Uhrzeit_bis TIME NOT NULL,
    CHECK (Tag_bis >= Tag_von),
    CHECK (Uhrzeit_bis > Uhrzeit_von),
    UNIQUE (ExemplarID, ZeitslotID),
    EXCLUDE USING gist (
        ExemplarID WITH =,
        daterange(Tag_von, Tag_bis, '[]') WITH &&,
        timerange(Uhrzeit_von, Uhrzeit_bis) WITH &&
    )
);

-- Ausleihe verknüpft Exemplar, Zeitslot, Ausleiher und Verleiher
CREATE TABLE Ausleihe (
    AusleiheID         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ExemplarID         INTEGER NOT NULL REFERENCES Exemplar (ExemplarID) ON DELETE RESTRICT,
    ZeitslotID         INTEGER NOT NULL,
    AusleiherNutzerID  INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    VerleiherNutzerID  INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    Ausleihdatum       DATE NOT NULL DEFAULT CURRENT_DATE,
    RückgabeSpätestens DATE NOT NULL,
    Rückgabedatum      DATE,
    CHECK (VerleiherNutzerID <> AusleiherNutzerID),
    CHECK (RückgabeSpätestens > Ausleihdatum),
    CHECK (Rückgabedatum >= Ausleihdatum),
    FOREIGN KEY (ExemplarID, ZeitslotID)
        REFERENCES Zeitslot (ExemplarID, ZeitslotID) ON DELETE RESTRICT,
    EXCLUDE USING gist (
        ExemplarID WITH =,
        daterange(Ausleihdatum, RückgabeSpätestens, '[)') WITH &&
    )
);

-- Bewertung einer Ausleihe durch alle Beteiligten
CREATE TABLE Bewertung (
    BewertungID         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    AusleiheID          INTEGER NOT NULL REFERENCES Ausleihe (AusleiheID) ON DELETE RESTRICT,
    BewertenderNutzerID INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    BewerteterNutzerID  INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    Sterne              SMALLINT NOT NULL CHECK (Sterne BETWEEN 1 AND 5),
    Kommentar           TEXT,
    Datum               DATE NOT NULL DEFAULT CURRENT_DATE,
    CHECK (BewerteterNutzerID <> BewertenderNutzerID),
    UNIQUE (AusleiheID, BewertenderNutzerID)
);

-- Bewertung eines Buchtitels durch einen Nutzer
CREATE TABLE Buchbewertung (
    BuchbewertungID INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BuchtitelID     INTEGER NOT NULL REFERENCES Buchtitel (BuchtitelID) ON DELETE RESTRICT,
    NutzerID        INTEGER NOT NULL REFERENCES Nutzer (NutzerID) ON DELETE RESTRICT,
    Sterne          SMALLINT NOT NULL CHECK (Sterne BETWEEN 1 AND 5),
    Kommentar       TEXT,
    Datum           DATE NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE (BuchtitelID, NutzerID)
);


-- 3. Regeln die über Constraints hinausgehen
-- Ausleihe: Verleiher ist der Besitzer, RückgabeSpätestens aus der Ausleihdauer
CREATE FUNCTION Ausleihe_Regeln() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_besitzer INTEGER;
    v_max      SMALLINT;
BEGIN
    SELECT BesitzerNutzerID, MaxAusleihDauerTage INTO v_besitzer, v_max
      FROM Exemplar WHERE ExemplarID = NEW.ExemplarID;

    IF TG_OP = 'INSERT'
       OR (NEW.ExemplarID, NEW.VerleiherNutzerID)
          IS DISTINCT FROM (OLD.ExemplarID, OLD.VerleiherNutzerID) THEN
        IF NEW.VerleiherNutzerID <> v_besitzer THEN
            RAISE EXCEPTION 'Verleiher % ist nicht der Besitzer % des Exemplars %',
                NEW.VerleiherNutzerID, v_besitzer, NEW.ExemplarID
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF TG_OP = 'INSERT'
       OR (NEW.ExemplarID, NEW.Ausleihdatum, NEW.RückgabeSpätestens)
          IS DISTINCT FROM (OLD.ExemplarID, OLD.Ausleihdatum, OLD.RückgabeSpätestens) THEN
        IF NEW.RückgabeSpätestens IS NULL THEN
            NEW.RückgabeSpätestens := NEW.Ausleihdatum + v_max;
        ELSIF NEW.RückgabeSpätestens <> NEW.Ausleihdatum + v_max THEN
            RAISE EXCEPTION 'RückgabeSpätestens muss % sein (Ausleihdatum + % Tage)',
                NEW.Ausleihdatum + v_max, v_max
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Ruft die Ausleihe_Regeln vor INSERT und UPDATE auf
CREATE TRIGGER Ausleihe_Regeln_Trigger
    BEFORE INSERT OR UPDATE OF ExemplarID, VerleiherNutzerID, Ausleihdatum, RückgabeSpätestens
    ON Ausleihe
    FOR EACH ROW EXECUTE FUNCTION Ausleihe_Regeln();

-- Bewertender und Bewerteter sind Ausleiher und Verleiher
CREATE FUNCTION Bewertung_Regeln() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_ausleiher INTEGER;
    v_verleiher INTEGER;
BEGIN
    SELECT AusleiherNutzerID, VerleiherNutzerID INTO v_ausleiher, v_verleiher
      FROM Ausleihe WHERE AusleiheID = NEW.AusleiheID;

    IF NOT (NEW.BewertenderNutzerID IN (v_ausleiher, v_verleiher)
        AND NEW.BewerteterNutzerID  IN (v_ausleiher, v_verleiher)) THEN
        RAISE EXCEPTION 'Bewertender % und Bewerteter % müssen Ausleiher % und Verleiher % der Ausleihe % sein',
            NEW.BewertenderNutzerID, NEW.BewerteterNutzerID, v_ausleiher, v_verleiher, NEW.AusleiheID
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

-- Ruft Bewertung_Regeln vor INSERT und UPDATE auf
CREATE TRIGGER Bewertung_Regeln_Trigger
    BEFORE INSERT OR UPDATE OF AusleiheID, BewertenderNutzerID, BewerteterNutzerID
    ON Bewertung
    FOR EACH ROW EXECUTE FUNCTION Bewertung_Regeln();


-- 4. Indizes
-- Join von Exemplar zu Buchtitel
CREATE INDEX idx_exemplar_buchtitel      ON Exemplar (BuchtitelID);
-- Join von Ausleihe zu Exemplar und Zeitslot
CREATE INDEX idx_ausleihe_exemplar_slot  ON Ausleihe (ExemplarID, ZeitslotID);
-- Join von Ausleihe zum Ausleiher
CREATE INDEX idx_ausleihe_ausleiher      ON Ausleihe (AusleiherNutzerID);
-- Join von Bewertung zum bewerteten Nutzer
CREATE INDEX idx_bewertung_bewerteter    ON Bewertung (BewerteterNutzerID);
-- Vorauswahl der Umkreissuche
CREATE INDEX idx_standort_koordinaten    ON Standort (Breitengrad, Längengrad);


-- 5. Beispiel Daten initialisieren
-- Beispiel Daten für Nutzer
INSERT INTO Nutzer (Name, Vorname, EMail, Telefonnummer) VALUES
    ('Musterfrau', 'Anna',  'anna.musterfrau@example.org', '+49 30 23125001'),
    ('Mustermann', 'Ben',   'ben.mustermann@example.org',  '+49 30 23125002'),
    ('Beispiel',   'Clara', 'clara.beispiel@example.org',  NULL),
    ('Testmann',   'David', 'david.testmann@example.org',  '+49 30 23125004'),
    ('Probe',      'Elisa', 'elisa.probe@example.org',     '+49 89 99998005'),
    ('Demo',       'Fabian','fabian.demo@example.org',     '+49 89 99998006'),
    ('Dummy',      'Greta', 'greta.dummy@example.org',     NULL),
    ('Platzhalter','Hans',  'hans.platzhalter@example.org','+49 89 99998008'),
    ('Vorlage',    'Ida',   'ida.vorlage@example.org',     '+49 40 66969009'),
    ('Stichprobe', 'Jonas', 'jonas.stichprobe@example.org','+49 40 66969010'),
    ('Attrappe',   'Kira',  'kira.attrappe@example.org',   NULL),
    ('Exempel',    'Leon',  'leon.exempel@example.org',    '+49 40 66969012');

-- Beispiel Daten für Standort
INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad) VALUES
    (1,  'Musterstraße',       '1',  '10115', 'Berlin',  'Deutschland', 52.520000,  13.405000),
    (2,  'Beispielweg',        '2',  '10117', 'Berlin',  'Deutschland', 52.496000,  13.343000),
    (3,  'Testallee',          '3',  '10119', 'Berlin',  'Deutschland', 52.541000,  13.416000),
    (4,  'Probegasse',         '4',  '10178', 'Berlin',  'Deutschland', 52.480000,  13.435000),
    (5,  'Demoplatz',          '5',  '80331', 'München', 'Deutschland', 48.137400,  11.575500),
    (6,  'Dummyring',          '6',  '80333', 'München', 'Deutschland', 48.162000,  11.587000),
    (7,  'Platzhalterstraße',  '7',  '80335', 'München', 'Deutschland', 48.120000,  11.547000),
    (8,  'Vorlagenweg',        '8',  '80336', 'München', 'Deutschland', 48.153000,  11.534000),
    (9,  'Stichprobenallee',   '9',  '20095', 'Hamburg', 'Deutschland', 53.551100,   9.993700),
    (10, 'Attrappenstraße',    '10', '20144', 'Hamburg', 'Deutschland', 53.575000,   9.960000),
    (11, 'Exempelufer',        '11', '20249', 'Hamburg', 'Deutschland', 53.563000,  10.030000),
    (12, 'Datenstraße',        '12', '20457', 'Hamburg', 'Deutschland', 53.540000,   9.985000),
    (1,  'Zweitwohnungsweg',   '13', '80331', 'München', 'Deutschland', 48.145000,  11.560000),
    (2,  'Nebenstandortgasse', '14', '20095', 'Hamburg', 'Deutschland', 53.556000,  10.000000);

-- Beispiel Daten für Verlag
INSERT INTO Verlag (Name, Ort, Land) VALUES
    ('Musterverlag',        'Berlin',  'Deutschland'),
    ('Beispielverlag',      'München', 'Deutschland'),
    ('Testverlag',          'Hamburg', 'Deutschland'),
    ('Demoverlag',          'Berlin',  'Deutschland'),
    ('Probeverlag',         'München', 'Deutschland'),
    ('Platzhalter Press',   'Hamburg', 'Deutschland'),
    ('Dummy Books',         'Berlin',  'Deutschland'),
    ('Stichproben-Verlag',  'München', 'Deutschland'),
    ('Vorlage & Söhne',     NULL,      NULL),
    ('Exempel-Verlag',      'Hamburg', 'Deutschland'),
    ('Datenverlag',         NULL,      NULL);

-- Beispiel Daten für Genre
INSERT INTO Genre (Bezeichnung) VALUES
    ('Roman'), ('Krimi'), ('Drama'), ('Fantasy'), ('Science-Fiction'),
    ('Kinderbuch'), ('Sachbuch'), ('Fachbuch'), ('Biografie'), ('Lyrik');

-- Beispiel Daten für Sprache
INSERT INTO Sprache (Bezeichnung) VALUES
    ('Deutsch'), ('Englisch'), ('Französisch'), ('Spanisch'), ('Italienisch'),
    ('Niederländisch'), ('Polnisch'), ('Schwedisch'), ('Türkisch'), ('Portugiesisch');

-- Beispiel Daten für Autor
INSERT INTO Autor (Name, Vorname) VALUES
    ('Mustermann',  'Max'),
    ('Musterfrau',  'Erika'),
    ('Beispiel',    'Bernd'),
    ('Testfeld',    'Tina'),
    ('Probe',       'Paul'),
    ('Demo',        'Doris'),
    ('Dummy',       'Dieter'),
    ('Platzhalter', 'Petra'),
    ('Vorlage',     'Viktor'),
    ('Stichprobe',  'Sabine');

-- Beispiel Daten für Buchtitel
INSERT INTO Buchtitel (VerlagID, GenreID, SpracheID, ISBN, Titel, Erscheinungsjahr, Auflage)
SELECT v.VerlagID, g.GenreID, s.SpracheID, d.ISBN, d.Titel, d.Jahr, d.Auflage
  FROM (VALUES
        (1,  'Musterverlag',       'Roman',           'Deutsch',  '978-3-99999-001-9', 'Das Testroman-Experiment',          2018, 1),
        (2,  'Beispielverlag',     'Drama',           'Deutsch',  '978-3-99999-002-6', 'Beispiel-Drama in drei Akten',      1998, 2),
        (3,  'Testverlag',         'Krimi',           'Deutsch',  '978-3-99999-003-3', 'Der Fall Mustermann',               2012, 1),
        (4,  'Demoverlag',         'Roman',           'Deutsch',  '978-3-99999-004-0', 'Die Reise ins Datenland',           2005, 3),
        (5,  'Probeverlag',        'Roman',           'Deutsch',  '978-3-99999-005-7', 'Zwischen Tabelle und Zeile',        2021, 1),
        (6,  'Platzhalter Press',  'Fantasy',         'Deutsch',  '978-3-99999-006-4', 'Drache Dummy und der Probestein',   2009, 4),
        (7,  'Dummy Books',        'Kinderbuch',      'Deutsch',  '978-3-99999-007-1', 'Das Kinderbuch der Beispiele',      2015, 2),
        (8,  'Stichproben-Verlag', 'Sachbuch',        'Deutsch',  '978-3-99999-008-8', 'Kurze Geschichte der Testdaten',    2019, 1),
        (9,  'Vorlage & Söhne',    'Science-Fiction', 'Englisch', '978-3-99999-009-5', 'Planet Placeholder',                2003, 1),
        (10, 'Exempel-Verlag',     'Fachbuch',        'Deutsch',  '978-3-99999-010-1', 'Handbuch der Beispieldatenbank',    2022, 5),
        (11, NULL,                 'Lyrik',           'Deutsch',  NULL,                'Gedichte aus dem Testlabor',        2024, 1)
       ) AS d (Nr, Verlag, Genre, Sprache, ISBN, Titel, Jahr, Auflage)
  LEFT JOIN Verlag v ON v.Name = d.Verlag
  JOIN Genre   g ON g.Bezeichnung = d.Genre
  JOIN Sprache s ON s.Bezeichnung = d.Sprache
 ORDER BY d.Nr;

-- Beispiel Daten für Buchtitel_Autor
INSERT INTO Buchtitel_Autor (BuchtitelID, AutorID)
SELECT d.BuchtitelID, a.AutorID
  FROM (VALUES
        (1,  'Mustermann'),
        (2,  'Musterfrau'),
        (3,  'Beispiel'),
        (3,  'Testfeld'),
        (4,  'Probe'),
        (5,  'Demo'),
        (6,  'Dummy'),
        (7,  'Platzhalter'),
        (8,  'Vorlage'),
        (9,  'Stichprobe'),
        (10, 'Mustermann'),
        (11, 'Musterfrau')
       ) AS d (BuchtitelID, Autor)
  JOIN Autor a ON a.Name = d.Autor;

-- Beispiel Daten für Exemplar
INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage, VersandMöglich) VALUES
    (1,  1,  1,  'Gut',       14, FALSE),
    (2,  2,  2,  'Neu',       21, TRUE),
    (3,  3,  3,  'Gebraucht', 14, FALSE),
    (4,  4,  4,  'Gut',       28, TRUE),
    (5,  5,  5,  'Neu',       14, FALSE),
    (6,  6,  6,  'Gebraucht', 21, TRUE),
    (7,  7,  7,  'Gut',       14, FALSE),
    (8,  8,  8,  'Gut',       28, FALSE),
    (9,  9,  9,  'Gebraucht', 14, TRUE),
    (10, 10, 10, 'Gut',       21, FALSE),
    (1,  11, 11, 'Gut',       14, FALSE),
    (3,  12, 12, 'Neu',       14, TRUE),
    (2,  1,  13, 'Gut',       21, FALSE),
    (5,  2,  14, 'Gebraucht', 14, TRUE);

-- Beispiel Daten für Zeitslot
INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis) VALUES
    (1,  '2026-01-01', '2026-12-31', '17:00', '19:00'),
    (2,  '2026-01-01', '2026-12-31', '16:00', '18:00'),
    (3,  '2026-02-01', '2026-06-30', '18:00', '20:00'),
    (4,  '2026-01-01', '2026-12-31', '09:00', '11:00'),
    (5,  '2026-03-01', '2026-12-31', '17:00', '19:00'),
    (6,  '2026-01-01', '2026-12-31', '10:00', '12:00'),
    (7,  '2026-01-01', '2026-12-31', '15:00', '17:00'),
    (8,  '2026-04-01', '2026-12-31', '18:00', '20:00'),
    (9,  '2026-01-01', '2026-12-31', '12:00', '14:00'),
    (10, '2026-01-01', '2026-12-31', '17:30', '19:30'),
    (11, '2026-01-01', '2026-12-31', '17:00', '19:00'),
    (12, '2026-01-01', '2026-12-31', '14:00', '16:00'),
    (13, '2026-01-01', '2026-12-31', '17:00', '19:00'),
    (14, '2026-01-01', '2026-12-31', '08:00', '10:00'),
    (1,  '2026-01-01', '2026-12-31', '19:00', '21:00');

-- Beispiel Daten für Ausleihe
INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum, Rückgabedatum) VALUES
    (1,  1,  5,  1,  '2026-02-03', '2026-02-15'),
    (1,  1,  9,  1,  '2026-03-02', '2026-03-14'),
    (2,  2,  3,  2,  '2026-02-10', '2026-03-01'),
    (3,  3,  6,  3,  '2026-03-05', '2026-03-19'),
    (4,  4,  8,  4,  '2026-04-01', '2026-04-20'),
    (5,  5,  10, 5,  '2026-05-04', '2026-05-17'),
    (6,  6,  11, 6,  '2026-06-01', '2026-06-20'),
    (7,  7,  12, 7,  '2026-07-06', '2026-07-18'),
    (8,  8,  1,  8,  '2026-08-03', '2026-08-25'),
    (9,  9,  2,  9,  '2026-09-07', '2026-09-20'),
    (10, 10, 4,  10, '2026-10-05', NULL),
    (11, 11, 7,  11, '2026-10-12', NULL),
    (1,  15, 3,  1,  '2026-04-06', '2026-04-18'),
    (13, 13, 6,  1,  '2026-05-11', '2026-05-30'),
    (14, 14, 9,  2,  '2026-06-08', '2026-06-20');

-- Beispiel Daten für Bewertung
INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne, Kommentar, Datum) VALUES
    (1,  5,  1,  5, 'Pünktliche Übergabe, freundlich',          '2026-02-15'),
    (1,  1,  5,  4, 'Buch unversehrt zurückgegeben',            '2026-02-15'),
    (2,  9,  1,  5, NULL,                                       '2026-03-14'),
    (2,  1,  9,  3, 'Zustand in Ordnung',                       '2026-03-14'),
    (3,  3,  2,  4, 'Gute Absprache zum Abohlfenster',          '2026-03-01'),
    (3,  2,  3,  5, NULL,                                       '2026-03-01'),
    (4,  6,  3,  5, 'Alles wie beschrieben',                    '2026-03-19'),
    (4,  3,  6,  4, NULL,                                       '2026-03-19'),
    (5,  8,  4,  3, 'Übergabe etwas verspätet',                 '2026-04-20'),
    (5,  4,  8,  5, 'Sehr zuverlässig',                         '2026-04-20'),
    (6,  10, 5,  5, NULL,                                       '2026-05-17'),
    (6,  5,  10, 5, 'Gerne wieder',                             '2026-05-17'),
    (7,  11, 6,  4, 'Versand hat gut funktioniert',             '2026-06-20'),
    (8,  12, 7,  5, NULL,                                       '2026-07-18'),
    (10, 2,  9,  4, 'Kurzfristig erreichbar',                   '2026-09-20'),
    (9,  1,  8,  4, NULL,                                       '2026-08-25');

-- Beispiel Daten für Buchbewertung
INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne, Kommentar, Datum) VALUES
    (1, 5,  5, 'Spannend bis zum Schluss',    '2026-02-20'),
    (1, 9,  4, NULL,                          '2026-03-20'),
    (1, 3,  3, 'Etwas langatmig',             '2026-04-25'),
    (2, 3,  3, NULL,                          '2026-03-05'),
    (2, 6,  4, 'Gute Dialoge',                '2026-06-05'),
    (3, 6,  5, NULL,                          '2026-03-25'),
    (4, 8,  4, 'Lesenswert',                  '2026-04-25'),
    (5, 10, 5, NULL,                          '2026-05-20'),
    (5, 9,  4, 'Kurzwelig',                  '2026-06-25'),
    (6, 11, 4, NULL,                          '2026-06-25'),
    (7, 12, 5, 'Auch für Erwachsene geeignet','2026-07-22'),
    (8, 1,  3, NULL,                          '2026-08-30'),
    (9, 2,  4, 'Interessante Idee',           '2026-09-25');

-- 6. Tests
-- Testprotokoll und Prüfverfahren - nur in dieser Sitzung vorhanden
DROP TABLE IF EXISTS pg_temp.Testprotokoll;
CREATE TEMP TABLE Testprotokoll (
    Nr       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Tabelle  TEXT NOT NULL,
    Regel    TEXT NOT NULL,
    Art      TEXT NOT NULL CHECK (Art IN ('positiv', 'negativ')),
    Erwartet TEXT NOT NULL,
    Ergebnis TEXT NOT NULL,
    Status   TEXT NOT NULL
);

CREATE OR REPLACE PROCEDURE pg_temp.pruefe(p_tabelle TEXT, p_regel TEXT, p_art TEXT, p_erwartet TEXT, p_sql TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_ergebnis TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        v_ergebnis := 'akzeptiert';
        RAISE EXCEPTION 'Test zurückgenommen' USING ERRCODE = 'RB000';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE <> 'RB000' THEN
            v_ergebnis := SQLSTATE;
        END IF;
    END;
    INSERT INTO Testprotokoll (Tabelle, Regel, Art, Erwartet, Ergebnis, Status)
    VALUES (p_tabelle, p_regel, p_art, p_erwartet, v_ergebnis,
            CASE WHEN v_ergebnis = p_erwartet THEN 'OK' ELSE 'FEHLER' END);
END;
$$;

-- Test 1, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Nutzer', 'EMail eindeutig', 'negativ', '23505',
    $t$INSERT INTO Nutzer (Name, Vorname, EMail) VALUES ('Test', 'Neu', 'anna.musterfrau@example.org')$t$);
-- Test 2, positiv: wird angenommen
CALL pg_temp.pruefe('Nutzer', 'EMail eindeutig', 'positiv', 'akzeptiert',
    $t$INSERT INTO Nutzer (Name, Vorname, EMail) VALUES ('Test', 'Neu', 'neu.test@example.org')$t$);
-- Test 3, negativ: abgelehnt mit 23502 (NOT NULL)
CALL pg_temp.pruefe('Nutzer', 'Name ist Pflichtfeld', 'negativ', '23502',
    $t$INSERT INTO Nutzer (Name, Vorname, EMail) VALUES (NULL, 'Neu', 'neu.test@example.org')$t$);
-- Test 4, positiv: wird angenommen
CALL pg_temp.pruefe('Nutzer', 'Telefonnummer ist optional', 'positiv', 'akzeptiert',
    $t$INSERT INTO Nutzer (Name, Vorname, EMail) VALUES ('Test', 'Neu', 'neu.test@example.org')$t$);
-- Test 5, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Nutzer', 'Nutzer mit Bezügen nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Nutzer WHERE NutzerID = 5$t$);
-- Test 6, positiv: wird angenommen
CALL pg_temp.pruefe('Nutzer', 'Nutzer ohne Bezüge löschbar', 'positiv', 'akzeptiert',
    $t$INSERT INTO Nutzer (Name, Vorname, EMail) VALUES ('Test', 'Löschen', 'loeschen@example.org');
       DELETE FROM Nutzer WHERE EMail = 'loeschen@example.org'$t$);
-- Test 7, positiv: wird angenommen
CALL pg_temp.pruefe('Nutzer', 'Anonymisierung statt Löschen', 'positiv', 'akzeptiert',
    $t$UPDATE Nutzer SET Name = 'anonym', Vorname = 'anonym', EMail = 'anonym-5@example.invalid',
              Telefonnummer = NULL WHERE NutzerID = 5$t$);

-- Test 8, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Standort', 'Breitengrad höchstens 90', 'negativ', '23514',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (1, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 90.500000, 13.400000)$t$);
-- Test 9, positiv: wird angenommen
CALL pg_temp.pruefe('Standort', 'Breitengrad höchstens 90', 'positiv', 'akzeptiert',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (1, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 90.000000, 13.400000)$t$);
-- Test 10, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Standort', 'Längengrad mindestens -180', 'negativ', '23514',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (1, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 52.500000, -180.500000)$t$);
-- Test 11, positiv: wird angenommen
CALL pg_temp.pruefe('Standort', 'Längengrad mindestens -180', 'positiv', 'akzeptiert',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (1, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 52.500000, -180.000000)$t$);
-- Test 12, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Standort', 'Nutzer muss existieren', 'negativ', '23503',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (999, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 52.500000, 13.400000)$t$);
-- Test 13, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Standort', 'Standort mit Exemplar nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Standort WHERE StandortID = 1$t$);
-- Test 14, positiv: wird angenommen
CALL pg_temp.pruefe('Standort', 'Standort ohne Exemplar löschbar', 'positiv', 'akzeptiert',
    $t$INSERT INTO Standort (NutzerID, Straße, Hausnummer, Postleitzahl, Ort, Land, Breitengrad, Längengrad)
       VALUES (1, 'Testweg', '1', '10115', 'Berlin', 'Deutschland', 52.500000, 13.400000);
       DELETE FROM Standort WHERE Straße = 'Testweg'$t$);

-- Test 15, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Verlag', 'Name eindeutig', 'negativ', '23505',
    $t$INSERT INTO Verlag (Name) VALUES ('Musterverlag')$t$);
-- Test 16, positiv: wird angenommen
CALL pg_temp.pruefe('Verlag', 'Name eindeutig', 'positiv', 'akzeptiert',
    $t$INSERT INTO Verlag (Name) VALUES ('Neuer Testverlag')$t$);
-- Test 17, positiv: wird angenommen
CALL pg_temp.pruefe('Verlag', 'Ort und Land sind optional', 'positiv', 'akzeptiert',
    $t$INSERT INTO Verlag (Name, Ort, Land) VALUES ('Neuer Testverlag', NULL, NULL)$t$);
-- Test 18, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Verlag', 'Verlag mit Titeln nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Verlag WHERE Name = 'Musterverlag'$t$);
-- Test 19, positiv: wird angenommen
CALL pg_temp.pruefe('Verlag', 'Verlag ohne Titel löschbar', 'positiv', 'akzeptiert',
    $t$DELETE FROM Verlag WHERE Name = 'Datenverlag'$t$);

-- Test 20, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Genre', 'Bezeichnung eindeutig', 'negativ', '23505',
    $t$INSERT INTO Genre (Bezeichnung) VALUES ('Roman')$t$);
-- Test 21, positiv: wird angenommen
CALL pg_temp.pruefe('Genre', 'Bezeichnung eindeutig', 'positiv', 'akzeptiert',
    $t$INSERT INTO Genre (Bezeichnung) VALUES ('Märchen')$t$);
-- Test 22, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Genre', 'Genre in Verwendung nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Genre WHERE Bezeichnung = 'Roman'$t$);
-- Test 23, positiv: wird angenommen
CALL pg_temp.pruefe('Genre', 'Ungenutztes Genre löschbar', 'positiv', 'akzeptiert',
    $t$DELETE FROM Genre WHERE Bezeichnung = 'Biografie'$t$);

-- Test 24, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Sprache', 'Bezeichnung eindeutig', 'negativ', '23505',
    $t$INSERT INTO Sprache (Bezeichnung) VALUES ('Deutsch')$t$);
-- Test 25, positiv: wird angenommen
CALL pg_temp.pruefe('Sprache', 'Bezeichnung eindeutig', 'positiv', 'akzeptiert',
    $t$INSERT INTO Sprache (Bezeichnung) VALUES ('Dänisch')$t$);
-- Test 26, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Sprache', 'Sprache in Verwendung nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Sprache WHERE Bezeichnung = 'Deutsch'$t$);
-- Test 27, positiv: wird angenommen
CALL pg_temp.pruefe('Sprache', 'Ungenutzte Sprache löschbar', 'positiv', 'akzeptiert',
    $t$DELETE FROM Sprache WHERE Bezeichnung = 'Portugiesisch'$t$);

-- Test 28, negativ: abgelehnt mit 23502 (NOT NULL)
CALL pg_temp.pruefe('Autor', 'Name ist Pflichtfeld', 'negativ', '23502',
    $t$INSERT INTO Autor (Name, Vorname) VALUES (NULL, 'Test')$t$);
-- Test 29, positiv: wird angenommen
CALL pg_temp.pruefe('Autor', 'Vorname ist optional', 'positiv', 'akzeptiert',
    $t$INSERT INTO Autor (Name, Vorname) VALUES ('Pseudonym', NULL)$t$);
-- Test 30, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Autor', 'Autor mit Titel nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Autor WHERE Name = 'Mustermann'$t$);
-- Test 31, positiv: wird angenommen
CALL pg_temp.pruefe('Autor', 'Autor ohne Titel löschbar', 'positiv', 'akzeptiert',
    $t$INSERT INTO Autor (Name, Vorname) VALUES ('Pseudonym', NULL);
       DELETE FROM Autor WHERE Name = 'Pseudonym'$t$);

-- Test 32, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Buchtitel', 'ISBN eindeutig', 'negativ', '23505',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, ISBN, Titel, Erscheinungsjahr)
       VALUES (1, 1, '978-3-99999-001-9', 'Doppelte ISBN', 2020)$t$);
-- Test 33, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel', 'ISBN eindeutig', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, ISBN, Titel, Erscheinungsjahr)
       VALUES (1, 1, NULL, 'Titel ohne ISBN', 2020)$t$);
-- Test 34, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Buchtitel', 'Erscheinungsjahr mindestens 1450', 'negativ', '23514',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (1, 1, 'Zu alt', 1449)$t$);
-- Test 35, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel', 'Erscheinungsjahr mindestens 1450', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (1, 1, 'Frühdruck', 1450)$t$);
-- Test 36, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Buchtitel', 'Erscheinungsjahr höchstens 2100', 'negativ', '23514',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (1, 1, 'Zu neu', 2101)$t$);
-- Test 37, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Buchtitel', 'Auflage größer 0', 'negativ', '23514',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr, Auflage)
       VALUES (1, 1, 'Nullte Auflage', 2020, 0)$t$);
-- Test 38, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel', 'Auflage größer 0', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (1, 1, 'Standardauflage', 2020)$t$);
-- Test 39, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel', 'Verlag ist optional', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchtitel (VerlagID, GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (NULL, 1, 1, 'Titel ohne Verlag', 2020)$t$);
-- Test 40, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Buchtitel', 'Genre muss existieren', 'negativ', '23503',
    $t$INSERT INTO Buchtitel (GenreID, SpracheID, Titel, Erscheinungsjahr)
       VALUES (999, 1, 'Unbekanntes Genre', 2020)$t$);
-- Test 41, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Buchtitel', 'Titel mit Exemplar nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Buchtitel WHERE BuchtitelID = 1$t$);
-- Test 42, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel', 'Löschen entfernt Autorenzuordnung', 'positiv', 'akzeptiert',
    $t$DO $$ BEGIN
           DELETE FROM Buchtitel WHERE BuchtitelID = 11;
           IF EXISTS (SELECT 1 FROM Buchtitel_Autor WHERE BuchtitelID = 11) THEN
               RAISE EXCEPTION 'Zuordnung blieb bestehen';
           END IF;
       END $$$t$);

-- Test 43, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Buchtitel_Autor', 'Zuordnung nur einmal', 'negativ', '23505',
    $t$INSERT INTO Buchtitel_Autor (BuchtitelID, AutorID) VALUES (1, 1)$t$);
-- Test 44, positiv: wird angenommen
CALL pg_temp.pruefe('Buchtitel_Autor', 'Zweiter Autor je Titel möglich', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchtitel_Autor (BuchtitelID, AutorID) VALUES (1, 2)$t$);

-- Test 45, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Exemplar', 'Zustand Neu, Gut oder Gebraucht', 'negativ', '23514',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 1, 'Defekt', 14)$t$);
-- Test 46, positiv: wird angenommen
CALL pg_temp.pruefe('Exemplar', 'Zustand Neu, Gut oder Gebraucht', 'positiv', 'akzeptiert',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 1, 'Neu', 14)$t$);
-- Test 47, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Exemplar', 'Maximale Ausleihdauer größer 0', 'negativ', '23514',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 1, 'Gut', 0)$t$);
-- Test 48, positiv: wird angenommen
CALL pg_temp.pruefe('Exemplar', 'Maximale Ausleihdauer größer 0', 'positiv', 'akzeptiert',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 1, 'Gut', 1)$t$);
-- Test 49, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Exemplar', 'Abholort gehört dem Besitzer', 'negativ', '23503',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 2, 'Gut', 14)$t$);
-- Test 50, positiv: wird angenommen
CALL pg_temp.pruefe('Exemplar', 'Abholort gehört dem Besitzer', 'positiv', 'akzeptiert',
    $t$INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
       VALUES (1, 1, 13, 'Gut', 14)$t$);
-- Test 51, positiv: wird angenommen
CALL pg_temp.pruefe('Exemplar', 'Versand standardmäßig nicht möglich', 'positiv', 'akzeptiert',
    $t$DO $$ DECLARE v BOOLEAN; BEGIN
           INSERT INTO Exemplar (BuchtitelID, BesitzerNutzerID, StandortID, Zustand, MaxAusleihDauerTage)
           VALUES (1, 1, 1, 'Gut', 14) RETURNING VersandMöglich INTO v;
           IF v IS DISTINCT FROM FALSE THEN RAISE EXCEPTION 'Standardwert ist nicht FALSE'; END IF;
       END $$$t$);

-- Test 52, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Zeitslot', 'Tag_bis nicht vor Tag_von', 'negativ', '23514',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (3, '2026-08-10', '2026-08-01', '18:00', '20:00')$t$);
-- Test 53, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Tag_bis nicht vor Tag_von', 'positiv', 'akzeptiert',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (3, '2026-08-10', '2026-08-10', '18:00', '20:00')$t$);
-- Test 54, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Zeitslot', 'Uhrzeit_bis nach Uhrzeit_von', 'negativ', '23514',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (3, '2026-08-10', '2026-08-10', '20:00', '18:00')$t$);
-- Test 55, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Uhrzeit_bis nach Uhrzeit_von', 'positiv', 'akzeptiert',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (3, '2026-08-10', '2026-08-10', '18:00', '18:01')$t$);
-- Test 56, negativ: abgelehnt mit 23P01 (EXCLUDE)
CALL pg_temp.pruefe('Zeitslot', 'Keine Überlappung je Exemplar', 'negativ', '23P01',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (1, '2026-06-01', '2026-06-30', '18:00', '20:00')$t$);
-- Test 57, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Anschluss in der Uhrzeit erlaubt', 'positiv', 'akzeptiert',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (2, '2026-01-01', '2026-12-31', '18:00', '20:00')$t$);
-- Test 58, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Gleiche Uhrzeit in anderem Zeitraum', 'positiv', 'akzeptiert',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (3, '2026-07-01', '2026-07-31', '18:00', '20:00')$t$);
-- Test 59, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Zeitslot', 'Exemplar muss existieren', 'negativ', '23503',
    $t$INSERT INTO Zeitslot (ExemplarID, Tag_von, Tag_bis, Uhrzeit_von, Uhrzeit_bis)
       VALUES (999, '2026-01-01', '2026-01-31', '18:00', '20:00')$t$);
-- Test 60, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Zeitslot', 'Slot mit Ausleihe nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Zeitslot WHERE ZeitslotID = 1$t$);
-- Test 61, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Slot ohne Ausleihe löschbar', 'positiv', 'akzeptiert',
    $t$DELETE FROM Zeitslot WHERE ZeitslotID = 12$t$);
-- Test 62, positiv: wird angenommen
CALL pg_temp.pruefe('Zeitslot', 'Löschen des Exemplars entfernt Slots', 'positiv', 'akzeptiert',
    $t$DO $$ BEGIN
           DELETE FROM Exemplar WHERE ExemplarID = 12;
           IF EXISTS (SELECT 1 FROM Zeitslot WHERE ExemplarID = 12) THEN
               RAISE EXCEPTION 'Slots blieben bestehen';
           END IF;
       END $$$t$);
-- Test 63, negativ: abgelehnt mit 23001 (RESTRICT)
CALL pg_temp.pruefe('Exemplar', 'Exemplar mit Ausleihe nicht löschbar', 'negativ', '23001',
    $t$DELETE FROM Exemplar WHERE ExemplarID = 1$t$);

-- Test 64, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Ausleihe', 'Verleiher ungleich Ausleiher', 'negativ', '23514',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (1, 1, 1, 1, '2026-09-01')$t$);
-- Test 65, positiv: wird angenommen
CALL pg_temp.pruefe('Ausleihe', 'Verleiher ungleich Ausleiher', 'positiv', 'akzeptiert',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (2, 2, 4, 2, '2026-11-02')$t$);
-- Test 66, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Ausleihe', 'Verleiher ist Besitzer des Exemplars', 'negativ', '23514',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (3, 3, 5, 4, '2026-09-01')$t$);
-- Test 67, positiv: wird angenommen
CALL pg_temp.pruefe('Ausleihe', 'Besitzerwechsel lässt Ausleihen unberührt', 'positiv', 'akzeptiert',
    $t$UPDATE Exemplar SET BesitzerNutzerID = 2, StandortID = 2 WHERE ExemplarID = 1;
       UPDATE Ausleihe SET Rückgabedatum = '2026-02-16' WHERE AusleiheID = 1$t$);
-- Test 68, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Ausleihe', 'RückgabeSpätestens aus Ausleihdauer', 'negativ', '23514',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum, RückgabeSpätestens)
       VALUES (2, 2, 4, 2, '2026-11-02', '2026-11-30')$t$);
-- Test 69, positiv: wird angenommen
CALL pg_temp.pruefe('Ausleihe', 'RückgabeSpätestens aus Ausleihdauer', 'positiv', 'akzeptiert',
    $t$DO $$ DECLARE v DATE; BEGIN
           INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
           VALUES (2, 2, 4, 2, '2026-11-02') RETURNING RückgabeSpätestens INTO v;
           IF v <> DATE '2026-11-23' THEN RAISE EXCEPTION 'Falsche Frist %', v; END IF;
       END $$$t$);
-- Test 70, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Ausleihe', 'Rückgabe nicht vor Ausleihdatum', 'negativ', '23514',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum, Rückgabedatum)
       VALUES (2, 2, 4, 2, '2026-11-02', '2026-11-01')$t$);
-- Test 71, positiv: wird angenommen
CALL pg_temp.pruefe('Ausleihe', 'Rückgabe nicht vor Ausleihdatum', 'positiv', 'akzeptiert',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum, Rückgabedatum)
       VALUES (2, 2, 4, 2, '2026-11-02', '2026-11-02')$t$);
-- Test 72, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Ausleihe', 'Slot gehört zum Exemplar', 'negativ', '23503',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (2, 1, 4, 2, '2026-11-02')$t$);
-- Test 73, negativ: abgelehnt mit 23P01 (EXCLUDE)
CALL pg_temp.pruefe('Ausleihe', 'Keine überlappenden Ausleihen', 'negativ', '23P01',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (1, 1, 3, 1, '2026-03-10')$t$);
-- Test 74, positiv: wird angenommen
CALL pg_temp.pruefe('Ausleihe', 'Übergabe am Rückgabetag erlaubt', 'positiv', 'akzeptiert',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (1, 1, 3, 1, '2026-03-16')$t$);
-- Test 75, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Ausleihe', 'Ausleiher muss existieren', 'negativ', '23503',
    $t$INSERT INTO Ausleihe (ExemplarID, ZeitslotID, AusleiherNutzerID, VerleiherNutzerID, Ausleihdatum)
       VALUES (2, 2, 999, 2, '2026-11-02')$t$);

-- Test 76, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Bewertung', 'Sterne von 1 bis 5', 'negativ', '23514',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (7, 6, 11, 6)$t$);
-- Test 77, positiv: wird angenommen
CALL pg_temp.pruefe('Bewertung', 'Sterne von 1 bis 5', 'positiv', 'akzeptiert',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (7, 6, 11, 1)$t$);
-- Test 78, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Bewertung', 'Bewerteter ungleich Bewertender', 'negativ', '23514',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (7, 6, 6, 3)$t$);
-- Test 79, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Bewertung', 'Eine Bewertung je Bewertendem', 'negativ', '23505',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (1, 5, 1, 3)$t$);
-- Test 80, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Bewertung', 'Nur Beteiligte der Ausleihe', 'negativ', '23514',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (1, 3, 1, 4)$t$);
-- Test 81, positiv: wird angenommen
CALL pg_temp.pruefe('Bewertung', 'Nur Beteiligte der Ausleihe', 'positiv', 'akzeptiert',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (15, 2, 9, 5)$t$);
-- Test 82, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Bewertung', 'Ausleihe muss existieren', 'negativ', '23503',
    $t$INSERT INTO Bewertung (AusleiheID, BewertenderNutzerID, BewerteterNutzerID, Sterne)
       VALUES (999, 5, 1, 4)$t$);

-- Test 83, negativ: abgelehnt mit 23514 (CHECK)
CALL pg_temp.pruefe('Buchbewertung', 'Sterne von 1 bis 5', 'negativ', '23514',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (4, 1, 0)$t$);
-- Test 84, positiv: wird angenommen
CALL pg_temp.pruefe('Buchbewertung', 'Sterne von 1 bis 5', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (4, 1, 5)$t$);
-- Test 85, negativ: abgelehnt mit 23505 (UNIQUE)
CALL pg_temp.pruefe('Buchbewertung', 'Eine Bewertung je Nutzer und Titel', 'negativ', '23505',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (1, 5, 4)$t$);
-- Test 86, positiv: wird angenommen
CALL pg_temp.pruefe('Buchbewertung', 'Eine Bewertung je Nutzer und Titel', 'positiv', 'akzeptiert',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (1, 7, 4)$t$);
-- Test 87, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Buchbewertung', 'Titel muss existieren', 'negativ', '23503',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (999, 1, 3)$t$);
-- Test 88, negativ: abgelehnt mit 23503 (Fremdschlüssel)
CALL pg_temp.pruefe('Buchbewertung', 'Nutzer muss existieren', 'negativ', '23503',
    $t$INSERT INTO Buchbewertung (BuchtitelID, NutzerID, Sterne) VALUES (1, 999, 3)$t$);


-- Ergebnis der Tests anzeigen
-- psql: Befehlsbestätigungen wieder einblenden
\set QUIET off
SELECT Art, Status, count(*) AS Anzahl
  FROM Testprotokoll
 GROUP BY Art, Status
 ORDER BY Art, Status;


-- 7. Beispiel Abfragen
-- Abfrage 1: Umkreissuche nach Veness
WITH Entfernung AS (
    SELECT e.ExemplarID, e.BuchtitelID, s.Ort,
           6371 * acos(sin(radians(m.Breitengrad)) * sin(radians(s.Breitengrad))
                + cos(radians(m.Breitengrad)) * cos(radians(s.Breitengrad))
                * cos(radians(s.Längengrad - m.Längengrad))) AS km
      FROM Standort m, Exemplar e
      JOIN Standort s ON s.NutzerID = e.BesitzerNutzerID AND s.StandortID = e.StandortID
     WHERE m.NutzerID = 3 AND m.StandortID = 3
       AND s.Breitengrad BETWEEN m.Breitengrad - 600 / 111.2 AND m.Breitengrad + 600 / 111.2
)
SELECT d.ExemplarID, b.Titel, d.Ort, round(d.km::numeric, 1) AS Entfernung_km
  FROM Entfernung d
  JOIN Buchtitel b ON b.BuchtitelID = d.BuchtitelID
 WHERE b.Titel = 'Zwischen Tabelle und Zeile'
   AND d.km <= 600
   AND NOT EXISTS (SELECT 1 FROM Ausleihe a
                    WHERE a.ExemplarID = d.ExemplarID AND a.Rückgabedatum IS NULL)
 ORDER BY d.km;

-- Abfrage 2: Exemplare mit Titel, Besitzer und Abholort
SELECT e.ExemplarID, b.Titel, n.Vorname || ' ' || n.Name AS Besitzer,
       s.Straße || ' ' || s.Hausnummer AS Abholort, s.Ort
  FROM Exemplar e
  JOIN Buchtitel b ON b.BuchtitelID = e.BuchtitelID
  JOIN Nutzer n    ON n.NutzerID    = e.BesitzerNutzerID
  JOIN Standort s  ON s.NutzerID    = e.BesitzerNutzerID AND s.StandortID = e.StandortID
 ORDER BY e.ExemplarID;

-- Abfrage 3: Ausleihen mit Beteiligten und Zeitslot
SELECT a.AusleiheID, b.Titel,
       ar.Vorname || ' ' || ar.Name AS Ausleiher,
       vr.Vorname || ' ' || vr.Name AS Verleiher,
       z.Uhrzeit_von, z.Uhrzeit_bis,
       a.Ausleihdatum, a.RückgabeSpätestens, a.Rückgabedatum
  FROM Ausleihe a
  JOIN Exemplar e  ON e.ExemplarID  = a.ExemplarID
  JOIN Buchtitel b ON b.BuchtitelID = e.BuchtitelID
  JOIN Zeitslot z  ON z.ExemplarID  = a.ExemplarID AND z.ZeitslotID = a.ZeitslotID
  JOIN Nutzer ar   ON ar.NutzerID   = a.AusleiherNutzerID
  JOIN Nutzer vr   ON vr.NutzerID   = a.VerleiherNutzerID
 ORDER BY a.AusleiheID;

-- Abfrage 4: Bewertungen mit Titel und Beteiligten
SELECT w.BewertungID, b.Titel,
       bd.Vorname || ' ' || bd.Name AS Bewertender,
       bt.Vorname || ' ' || bt.Name AS Bewerteter,
       w.Sterne, w.Kommentar
  FROM Bewertung w
  JOIN Ausleihe a  ON a.AusleiheID  = w.AusleiheID
  JOIN Exemplar e  ON e.ExemplarID  = a.ExemplarID
  JOIN Buchtitel b ON b.BuchtitelID = e.BuchtitelID
  JOIN Nutzer bd   ON bd.NutzerID   = w.BewertenderNutzerID
  JOIN Nutzer bt   ON bt.NutzerID   = w.BewerteterNutzerID
 ORDER BY w.BewertungID;

-- Abfrage 5: Durchschnittliche Bewertung je Nutzer
SELECT n.NutzerID, n.Vorname || ' ' || n.Name AS Nutzer,
       count(*) AS Bewertungen, round(avg(w.Sterne), 2) AS Durchschnitt
  FROM Bewertung w
  JOIN Nutzer n ON n.NutzerID = w.BewerteterNutzerID
 GROUP BY n.NutzerID, n.Vorname, n.Name
 ORDER BY Durchschnitt DESC, n.NutzerID;

-- Abfrage 6: Zeilenzahl je Tabelle
SELECT 'Nutzer' AS Tabelle, count(*) AS Zeilen FROM Nutzer
UNION ALL SELECT 'Standort', count(*) FROM Standort
UNION ALL SELECT 'Verlag', count(*) FROM Verlag
UNION ALL SELECT 'Genre', count(*) FROM Genre
UNION ALL SELECT 'Sprache', count(*) FROM Sprache
UNION ALL SELECT 'Autor', count(*) FROM Autor
UNION ALL SELECT 'Buchtitel', count(*) FROM Buchtitel
UNION ALL SELECT 'Buchtitel_Autor', count(*) FROM Buchtitel_Autor
UNION ALL SELECT 'Exemplar', count(*) FROM Exemplar
UNION ALL SELECT 'Zeitslot', count(*) FROM Zeitslot
UNION ALL SELECT 'Ausleihe', count(*) FROM Ausleihe
UNION ALL SELECT 'Bewertung', count(*) FROM Bewertung
UNION ALL SELECT 'Buchbewertung', count(*) FROM Buchbewertung;
