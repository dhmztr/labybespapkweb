# unter-hs

Backend logowania w Haskellu (Servant, argon2id, PostgreSQL) z frontendem w Elmie.

## API

| metoda | ścieżka | nagłówki | odpowiedź |
|---|---|---|---|
| `GET` | `/` | | strona logowania (Elm) |
| `GET` | `/zdrowie` | | `200`, liczba aktywnych sesji |
| `POST` | `/login` | `content-type: application/json` | `200 {"token":"<64 hex>"}` albo `401` |
| `POST` | `/rejestracja` | `content-type: application/json` | `200 {"token":"<64 hex>"}` (loguje od razu), `409` gdy email zajęty |
| `GET` | `/ja` | `Authorization: Bearer <token>` | `200 "<email>"` albo `401` |
| `POST` | `/wyloguj` | `Authorization: Bearer <token>` | `200` (usuwa token z sesji, zawsze, nawet gdy już nieaktywny) |
| `POST` | `/zamowienie` | `Authorization: Bearer <token>`, `content-type: application/json` | `200 {"driver_id":"..."}`, `400`/`401` |
| `GET` | `/swagger-ui` | | interaktywna dokumentacja API |

Ciało `/login` i `/rejestracja`: `{"email":"...","haslo":"..."}`. Od tej wersji
nagłówek `Authorization` wymaga prefiksu `Bearer ` — gołego tokenu backend
już nie przyjmie (`401`).

## Wymagania

* GHC 9.10 z pakietami: `servant-server`, `warp`, `aeson`, `password`, `text`,
  `crypton`, `bytestring`, `containers`, `postgresql-simple`, `servant-swagger`,
  `servant-swagger-ui`, `swagger2`
* Elm 0.19.1 (tylko do zbudowania frontendu)
* PostgreSQL 15 lub nowszy, z gotowym schematem (patrz "Baza danych")

Przy nixie nie instalujesz niczego ręcznie, `shell.nix` ma wszystko.

## Baza danych

Schemat jest w repo: `migrations/001_init.sql` (tabele `users`, `vehicles`,
`rides`, `password_reset_tokens` + jeden testowy user). Docker Compose
odpala go automatycznie przy pierwszym starcie kontenera postgresa; przy
lokalnym `nix-shell` trzeba go wpuścić do bazy ręcznie:

```bash
./baza.sh psql -d "$PGDATABASE" -f migrations/001_init.sql
```

Kolumna, na której backend jest szczególnie wyczulony:

| kolumna | typ | uwaga |
|---|---|---|
| `email` | `text` | unikalny |
| `password_hash` | `text` | **musi być `text`**, nie `varchar(60)` |

Hash argon2id ma około 97 znaków. `varchar(60)`, czyli długość z czasów
bcrypta, uciąłby go bez żadnego błędu, a logowanie przestałoby działać
w sposób trudny do zdiagnozowania.

Zapytanie, którego używa backend:

```sql
SELECT password_hash FROM users WHERE email = ?
```

Połączenie konfigurujesz standardowymi zmiennymi środowiskowymi:
`PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`. `connectPostgreSQL ""` czyta
je sam, więc w kodzie nie ma żadnych haseł.

## Linux (nix)

```bash
nix-shell

# frontend: BEZ tego kroku strona jest biała
cd frontend && nix-shell -p elmPackages.elm \
  --run 'elm make src/Main.elm --output=public/elm.js' && cd ..

runghc Main.hs       # http://localhost:8080
```

Dwie rzeczy, które łatwo przegapić:

1. Serwer musi być odpalany z katalogu `unter-hs/`, bo ścieżka do plików
   statycznych (`frontend/public`) jest relatywna. Z innego katalogu API
   działa, ale strona jest biała.
2. `elm.js` nie odbudowuje się sam. Po każdej zmianie w `src/Main.elm`
   powtórz `elm make`.

Szybki test z konsoli:

```bash
curl -s -X POST localhost:8080/login -H 'content-type: application/json' \
  -d '{"email":"a@b.pl","haslo":"tajne"}'
# {"token":"<64 hex>"}

curl -s localhost:8080/ja -H 'Authorization: Bearer <64 hex>'
```

## Docker Compose

Alternatywa do `nix-shell` + `runghc` — stawia postgres, redis i appkę
w kontenerach jedną komendą:

```bash
cp .env.example .env   # ustawia POSTGRES_USER/PASSWORD/DB
docker compose up --build
# appka: http://localhost:8081, postgres na hoście: 5433 (nie 5432, patrz niżej)
```

Obraz appki buduje się z `Dockerfile` (multistage, finalny obraz bez
toolchaina Nixa i bez roota). Schemat bazy wchodzi automatycznie
z `migrations/001_init.sql` przy pierwszym starcie kontenera postgresa.

## Windows

`nix-shell` nie działa na Windowsie natywnie. Dwie drogi:

### WSL2 (prościej)

```powershell
wsl --install -d Ubuntu
```

W Ubuntu zainstaluj nixa i dalej postępuj dokładnie jak w sekcji Linux:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Natywnie, bez nixa

1. [GHCup](https://www.haskell.org/ghcup/), zainstaluj GHC 9.10 i cabal
2. [PostgreSQL dla Windows](https://www.postgresql.org/download/windows/)
3. `cabal install --lib` z listą pakietów z sekcji Wymagania
4. [Elm 0.19.1](https://github.com/elm/compiler/releases), potem
   `elm make src/Main.elm --output=public/elm.js` w katalogu `frontend`
5. Ustaw zmienne `PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
6. `runghc Main.hs` z katalogu `unter-hs`

## Bezpieczeństwo

* hasła hashowane **argon2id** (`m=65536, t=2, p=1`), nigdy nie przechowywane
  jawnie
* tokeny sesji: 32 bajty z systemowego CSPRNG, czyli 256 bitów entropii
* weryfikacja hasła wykonuje tę samą pracę dla adresów istniejących
  i nieistniejących, więc czas odpowiedzi nie ujawnia, które konta istnieją
  (zweryfikowane pomiarem: 0,28 s vs 0,31 s, nierozróżnialne)
* frontend **od tej wersji trzyma token w `localStorage`** (sesja przeżywa
  odświeżenie strony — przy starcie Elm sprawdza zapamiętany token przez
  `/ja` i albo wraca do widoku zalogowanego, albo czyści go gdy wygasł).
  To świadoma zmiana tradeoffu: wygoda logowania-raz-na-dłużej za cenę
  tego, że udany XSS może wykraść token z `localStorage` — poprzednia
  wersja (token tylko w pamięci) nie miała tego wektora
* `/wyloguj` usuwa token z mapy sesji po stronie serwera, nie tylko
  lokalnie w przeglądarce

### Czego świadomie brakuje

* wygasania tokenów, mapa sesji rośnie do restartu procesu
* rate limitingu na `/login`. Weryfikacja hasła to około 260 ms i 64 MB RAM,
  wywoływalna anonimowo, więc parametry argon2 i limit żądań to jedna decyzja
