-- Tabela komentarzy/opinii dla kierowców
CREATE TABLE IF NOT EXISTS komentarze (
    id SERIAL PRIMARY KEY,
    idKier TEXT NOT NULL CHECK (char_length(trim(idKier)) > 0),
    data TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP::TEXT) CHECK (char_length(trim(data)) > 0),
    ocena DOUBLE PRECISION NOT NULL CHECK (ocena >= 1.0 AND ocena <= 5.0),
    wystawiajacy TEXT NOT NULL CHECK (char_length(trim(wystawiajacy)) > 0 AND char_length(wystawiajacy) <= 100),
    tresc TEXT NOT NULL CHECK (char_length(trim(tresc)) >= 1 AND char_length(tresc) <= 1000)
);

-- Indeks przyspieszający pobieranie komentarzy dla konkretnego kierowcy (WHERE idKier = ?)
CREATE INDEX IF NOT EXISTS idx_komentarze_idkier ON komentarze(idKier);

-- Przykładowy komentarz testowy
INSERT INTO komentarze (idKier, data, ocena, wystawiajacy, tresc)
VALUES (
    'kierowca1',
    '2026-11-02 15:30:00',
    5.0,
    'test@mail.pl',
    'Super przejazd, szybko i bezpiecznie!'
);
