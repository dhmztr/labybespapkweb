-- Dodanie przykładowych kierowców
INSERT INTO users (email, password_hash, role) VALUES
    ('kierowca1@unter.pl', 'tajne', 'driver'),
    ('kierowca2@unter.pl', 'tajne', 'driver'),
    ('kierowca3@unter.pl', 'tajne', 'driver'),
    ('kierowca4@unter.pl', 'tajne', 'driver'),
    ('kierowca5@unter.pl', 'tajne', 'driver'),
    ('kierowca6@unter.pl', 'tajne', 'driver'),
    ('kierowca7@unter.pl', 'tajne', 'driver'),
    ('kierowca8@unter.pl', 'tajne', 'driver'),
    ('kierowca9@unter.pl', 'tajne', 'driver'),
    ('kierowca10@unter.pl', 'tajne', 'driver')
ON CONFLICT (email) DO NOTHING;

-- Dodanie losowych aut
INSERT INTO vehicles (driver_id, registration_number, model, status) VALUES
    ((SELECT id FROM users WHERE email = 'kierowca1@unter.pl'), 'DW 1001A', 'Toyota Corolla', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca2@unter.pl'), 'DW 2002B', 'Skoda Octavia', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca3@unter.pl'), 'DW 3003C', 'Hyundai i30', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca4@unter.pl'), 'DW 4004D', 'Volkswagen Passat', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca5@unter.pl'), 'DW 5005E', 'Ford Focus', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca6@unter.pl'), 'DW 6006F', 'Kia Ceed', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca7@unter.pl'), 'DW 7007G', 'Toyota Camry', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca8@unter.pl'), 'DW 8008H', 'Mazda 6', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca9@unter.pl'), 'DW 9009J', 'Opel Astra', 'available'),
    ((SELECT id FROM users WHERE email = 'kierowca10@unter.pl'), 'DW 1010K', 'Renault Megane', 'available')
ON CONFLICT (registration_number) DO NOTHING;
