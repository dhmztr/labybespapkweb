# unter-hs

Symulator ride-hailingu (klon Ubera) — backend w Haskellu (Servant,
PostgreSQL, Redis) i frontend w Elmie z mapą 3D Wrocławia. Kierowcy to
wątki (`forkIO`) poruszające się losowo po mieście, dopóki nie dostaną
zamówienia — wtedy jadą po klienta, a potem do celu.

## Co jest w środku

* **Logowanie/rejestracja** — argon2id, sesje w Redisie
* **Symulacja kierowców** — każdy kierowca to osobny wątek, losowy ruch
  wewnątrz granic miasta (ray casting, nie poza polygon), dopasowanie
  najbliższego wolnego kierowcy do zamówienia, trasa dwuetapowa (odbiór →
  cel)
* **Zamówienia** — zapisywane do Postgresa (`rides`), historia per user
  (`/mojeprzejazdy`), blokada drugiego zamówienia póki poprzednie trwa
* **Komentarze/opinie** o kierowcach — autoryzowane, sanityzowane (XSS),
  walidowane, data/autor ustalane po stronie serwera
* **Rate limiting** po IP (licznik w oknie czasowym, nie tylko cooldown)
* **Frontend 3D** — modele aut i mapa Wrocławia (Three.js + podkład z Esri),
  zapasowa płaska mapa 2D bez WebGL
* **Docker/k8s** — multistage, non-root obraz; manifesty k8s + Flux

## API

| metoda | ścieżka | nagłówki | odpowiedź |
|---|---|---|---|
| `GET` | `/` | | strona aplikacji (Elm) |
| `GET` | `/zdrowie` | | `200 "ok"` |
| `POST` | `/login` | `content-type: application/json` | `200 {"token":"<64 hex>"}` albo `401` |
| `POST` | `/rejestracja` | `content-type: application/json` | `200 {"token":"<64 hex>"}` (loguje od razu), `409` gdy email zajęty |
| `GET` | `/ja` | `Authorization: Bearer <token>` | `200 {"mojemail":"...","przejadz": null \| "<idKierowcy>"}` albo `401` |
| `POST` | `/wyloguj` | `Authorization: Bearer <token>` | `200` (usuwa token z Redisa) |
| `GET` | `/kierowcy` | | `200 [Kierowca]` — pozycje, `cel`, `celKoncowy`, wolne miejsca |
| `POST` | `/zamowienie` | `Authorization: Bearer <token>`, JSON | `200 Kierowca` (dopasowany, z ustawionym `cel`), `400`/`401`/`403`/`409` (już masz aktywny przejazd) |
| `GET` | `/mojeprzejazdy` | `Authorization: Bearer <token>` | `200 [Przejazd]` — historia z `rides` |
| `POST` | `/komentarze` | `Authorization: Bearer <token>`, `{"reqidkier":"..."}` | `200 [Komentarz]` dla danego kierowcy |
| `POST` | `/wystawkomentarz` | `Authorization: Bearer <token>`, JSON | `200 "OK"`, `406` gdy walidacja nie przeszła |
| `GET` | `/swagger-ui` | | interaktywna dokumentacja API |

Ciało `/login`/`/rejestracja`: `{"email":"...","haslo":"..."}`.
Ciało `/zamowienie`: `{"lat_startowy","lon_startowy","lat_koncowy","lon_koncowy","miejsca"}`.
`Authorization` wymaga prefiksu `Bearer ` wszędzie — goły token dostaje `401`.

## Wymagania

* GHC 9.10 z pakietami w `shell.nix`: `servant-server`, `warp`, `aeson`,
  `password`, `text`, `crypton`, `bytestring`, `containers`,
  `postgresql-simple`, `resource-pool`, `hedis`, `servant-swagger`,
  `servant-swagger-ui`, `swagger2`, `random`, `xss-sanitize`
* Elm 0.19.1 (tylko do zbudowania frontendu)
* PostgreSQL 15+ i Redis (schemat w `migrations/`, patrz niżej)

Przy nixie nie instalujesz niczego ręcznie, `shell.nix` ma wszystko poza
Redisem — tego lokalnie (bez Dockera) nie masz, patrz sekcja Docker Compose.

## Baza danych

Schemat w repo: `migrations/001_init.sql` (`users`, `vehicles`, `rides`,
`password_reset_tokens`) i `migrations/002_comments.sql` (`komentarze`,
z `CHECK` constraintami pilnującymi tego samego co walidacja po stronie
Haskella — długości, zakres oceny). Docker Compose odpala oba automatycznie
przy pierwszym starcie kontenera postgresa; lokalnie trzeba ręcznie:

```bash
./baza.sh psql -d "$PGDATABASE" -f migrations/001_init.sql
./baza.sh psql -d "$PGDATABASE" -f migrations/002_comments.sql
```

`vehicles` nie jest seedowane migracją — backend wczytuje z niej same `id`
przy starcie i generuje każdemu kierowcy losową pozycję/liczbę miejsc w
pamięci (nie w bazie). Żeby `/kierowcy` cokolwiek zwróciło, potrzebujesz
chociaż kilku wierszy:

```bash
./baza.sh psql -c "INSERT INTO vehicles (registration_number, model) VALUES ('WR12345','Toyota');"
```

Kolumna na którą backend jest szczególnie wyczulony: `password_hash` musi
być `text`, nie `varchar(60)` — hash argon2id ma ~97 znaków, `varchar(60)`
uciąłby go bez błędu i logowanie przestałoby działać w sposób trudny do
zdiagnozowania.

Połączenie do Postgresa idzie przez pulę (`Data.Pool`, max 10 połączeń,
60s idle timeout) — handlery nie dzielą jednego gołego `Connection`
między wątkami. Zmienne środowiskowe standardowe: `PGHOST`, `PGDATABASE`,
`PGUSER`, `PGPASSWORD`.

## Sesje (Redis)

Tokeny żyją w Redisie (`token -> email`), nie w pamięci procesu — restart
appki nie wylogowuje wszystkich. Jeden email może mieć wiele aktywnych
tokenów naraz (różne urządzenia); `/wyloguj` kasuje tylko ten jeden token
z requestu. `R.Connection` z `hedis` to w środku pula połączeń, bezpieczna
do współdzielenia między wątkami bez dodatkowego locka.

## Linux (nix)

```bash
nix-shell
./baza.sh start

# frontend: BEZ tego kroku strona jest biała
cd frontend && nix-shell -p elmPackages.elm \
  --run 'elm make src/Main.elm --output=public/elm.js' && cd ..

runghc Main.hs       # http://localhost:8080
```

Dwie rzeczy, które łatwo przegapić:

1. Serwer musi być odpalany z katalogu `unter-hs/`, bo ścieżka do plików
   statycznych (`frontend/public`) jest relatywna.
2. `elm.js` nie odbudowuje się sam. Po każdej zmianie w `src/Main.elm`
   powtórz `elm make`.

Lokalnie (bez Dockera) **nie ma Redisa pod ręką** — `runghc Main.hs` padnie
przy starcie próbując połączyć się z hostem `redis`, którego nie ma poza
siecią `podman-compose`. Do testowania backendu z sesjami używaj Docker
Compose (niżej); `baza.sh` zarządza tylko lokalnym Postgresem.

Grafika 3D (modele aut i mapa Wrocławia) siedzi w `frontend/public/unter3d.js`
jako dwa custom elementy, `<unter-auto>` i `<unter-miasto>`, które Elm
renderuje jak zwykłe tagi. Three.js (0.160.0) ładuje się z jsdelivr, a podkład
mapy z serwerów Esri, więc przeglądarka potrzebuje internetu. Bez WebGL
strona pokazuje zapasową płaską mapę 2D z Elma. Frontend ma cztery widoki:
mapa z autami, zamówienie przejazdu, historia przejazdów, komentarze.

Szybki test z konsoli (lokalnie, bez Redisa to się nie uda — patrz wyżej):

```bash
curl -s -X POST localhost:8080/login -H 'content-type: application/json' \
  -d '{"email":"a@b.pl","haslo":"tajne"}'
curl -s localhost:8080/ja -H 'Authorization: Bearer <64 hex>'
```

## Docker Compose

Jedyny pełny sposób odpalenia całości (postgres + redis + appka) lokalnie:

```bash
cp .env.example .env   # ustawia POSTGRES_USER/PASSWORD/DB
docker compose up --build   # albo: podman-compose up --build
# appka: http://localhost:8081, postgres na hoście: 5433 (nie 5432)
```

`Dockerfile` jest multistage — finalny obraz bez toolchaina Nixa i bez
roota. Po `Ctrl+C` kontenery zostają zatrzymane, nie usunięte — przed
kolejnym `up` zrób `down`, inaczej dostaniesz "container already exists".
Appka czyta `vehicles` z bazy tylko raz, przy starcie — nowe wiersze
wstawione w locie wymagają restartu kontenera appki
(`podman restart unter_app`), nie całego stosu.

## Kubernetes / Flux

Manifesty w `k8s/` (namespace `unter`, sekrety zamiast plaintext haseł, PVC
dla Postgresa, hasło na Redisa, Flux `GitRepository`+`Kustomization`
śledzące ten branch). CI (`.github/workflows/ci.yml`) buduje i pushuje obraz
do GHCR z tagiem `github.sha` przy każdym pushu na `main`/`devops-test`.

## Windows

`nix-shell` nie działa na Windowsie natywnie. Dwie drogi:

### WSL2 (prościej)

```powershell
wsl --install -d Ubuntu
```

W Ubuntu zainstaluj nixa i dalej postępuj jak w sekcji Linux:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Natywnie, bez nixa

1. [GHCup](https://www.haskell.org/ghcup/), GHC 9.10 i cabal
2. [PostgreSQL](https://www.postgresql.org/download/windows/) i Redis dla Windows
3. `cabal install --lib` z listą pakietów z sekcji Wymagania
4. [Elm 0.19.1](https://github.com/elm/compiler/releases), potem
   `elm make src/Main.elm --output=public/elm.js` w katalogu `frontend`
5. Ustaw zmienne `PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
6. `runghc Main.hs` z katalogu `unter-hs`

## Bezpieczeństwo

* hasła hashowane **argon2id** (`m=65536, t=2, p=1`), nigdy nie
  przechowywane jawnie
* tokeny sesji: 32 bajty z systemowego CSPRNG, 256 bitów entropii, w Redisie
* weryfikacja hasła wykonuje tę samą pracę dla adresów istniejących
  i nieistniejących, więc czas odpowiedzi nie ujawnia które konta istnieją
  (zweryfikowane pomiarem: ~0,28s vs ~0,31s, nierozróżnialne)
* `/wystawkomentarz`: autoryzacja wymagana, treść sanityzowana
  (`xss-sanitize`), autor ustalany z sesji (nie z requestu — nie da się
  podszyć), data generowana po stronie serwera, walidacja długości i
  zakresu oceny (po stronie Haskella **i** w `CHECK` na bazie)
* rate limiting po IP: 5 żądań / 10s na `/login`, `/rejestracja`,
  `/zamowienie`, `/wystawkomentarz`
* frontend trzyma token w `localStorage` (sesja przeżywa odświeżenie —
  przy starcie Elm sprawdza token przez `/ja`). Świadomy tradeoff: udany
  XSS może wykraść token z `localStorage`
* `/wyloguj` usuwa token z Redisa po stronie serwera, nie tylko lokalnie

* tokeny w Redisie mają TTL (`SETEX`, 1h) — wygasają same, nie trzeba ich
  ręcznie czyścić

### Czego świadomie brakuje

* cache'owanie odczytów (`/komentarze`, `/mojeprzejazdy`) idzie zawsze do
  Postgresa, zero warstwy cache przed bazą
