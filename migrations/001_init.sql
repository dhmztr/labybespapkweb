-- Tabela użytkowników
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'client',  -- 'client', 'driver', 'admin'
    is_2fa_enabled BOOLEAN DEFAULT FALSE,
    two_factor_secret TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabela aut/kierowców
CREATE TABLE IF NOT EXISTS vehicles (
    id SERIAL PRIMARY KEY,
    driver_id INT REFERENCES users(id) ON DELETE SET NULL,
    registration_number TEXT UNIQUE NOT NULL,
    model TEXT NOT NULL,
    status TEXT DEFAULT 'offline' -- 'offline', 'available', 'busy'
);

-- Tabela przejazdów

CREATE TABLE IF NOT EXISTS rides (
    id SERIAL PRIMARY KEY,
    client_id INT REFERENCES users(id),
    vehicle_id INT REFERENCES vehicles(id),
    pickup_lat DOUBLE PRECISION NOT NULL,
    pickup_lng DOUBLE PRECISION NOT NULL,
    dropoff_lat DOUBLE PRECISION NOT NULL,
    dropoff_lng DOUBLE PRECISION NOT NULL,
    status TEXT DEFAULT 'requested',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


--Tabela pod reset hasła

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used BOOLEAN DEFAULT FALSE
);

--testowy uzytkownik (email test@mail.pl, haslo 'tajne')

INSERT INTO users (email, password_hash, role)
VALUES (
    'test@mail.pl',
    '$argon2id$v=19$m=65536,t=2,p=1$bW9qYXNvbDEyMzQ1Njc4OQ$EqabBC3aUTPQzQHiNNeb5Dv4ZDj5Z8W4j0QUjN2ksQ8',
    'client'
) ON CONFLICT (email) DO NOTHING;
