CREATE TABLE IF NOT EXISTS komentarze (
    id SERIAL PRIMARY KEY,
    idKier TEXT NOT NULL,
    data TEXT NOT NULL,
    ocena DOUBLE PRECISION NOT NULL,
    wystawiajacy TEXT NOT NULL,
    tresc TEXT NOT NULL
);
