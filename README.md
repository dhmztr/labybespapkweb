# unter-hs

Backend logowania w Haskellu (Servant + argon2id + PostgreSQL).

## API

| metoda | ścieżka | nagłówki | odpowiedź |
|---|---|---|---|
| `GET` | `/zdrowie` | — | `200` liczba aktywnych sesji |
| `POST` | `/login` | `content-type: application/json` | `200 {"token":"<64 hex>"}` albo `401` |
| `GET` | `/ja` | `Authorization: <token>` | `200 "<email>"` albo `401` |
| `GET` | `/swagger-ui` | — | interaktywna dokumentacja |

Ciało `/login`: `{"email":"...","haslo":"..."}`

## Wymagania

- **GHC 9.10** + pakiety: `servant-server`, `warp`, `aeson`, `password`,
  `text`, `crypton`, `bytestring`, `containers`, `postgresql-simple`,
  `servant-swagger`, `servant-swagger-ui`, `swagger2`
- **PostgreSQL 15+**

Wszystko to jest w `shell.nix` uzycie nixa jest zalecane
Wymaga bazy PSQL dane do bazy sa w `shell.nix`

## Linux (nix) — droga zalecana

```bash
nix-shell          # ściąga GHC, pakiety i Postgresa
runghc Main.hs     # serwer na http://localhost:8080
```



Szybki test:

```bash
curl -s -X POST localhost:8080/login -H 'content-type: application/json' \
  -d '{"email":"a@b.pl","haslo":"tajne"}'
```

## Windows

`nix-shell` nie działa na Windowsie natywnie. Dwie opcje:

### WSL2 (prościej)

```powershell
wsl --install -d Ubuntu
```

Potem w Ubuntu zainstaluj nixa i dalej **dokładnie jak w sekcji Linux**:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### Natywnie, bez nixa

1. [GHCup](https://www.haskell.org/ghcup/) → GHC 9.10 + cabal
2. [PostgreSQL dla Windows](https://www.postgresql.org/download/windows/)
3. `cabal install --lib` z listą pakietów z sekcji Wymagania
4. Baza: utwórz `unter_dev` w pgAdmin, wykonaj `schema.sql`
5. Ustaw zmienne `PGHOST`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
6. `runghc Main.hs`


## Konfiguracja bazy

`connectPostgreSQL ""` czyta standardowe zmienne `PG*` ze środowiska.
Żadnych haseł w kodzie. Pod nixem `shell.nix` ustawia je automatycznie.

## Bezpieczeństwo

- hasła hashowane **argon2id** (`m=65536, t=2, p=1`), nigdy nie przechowywane jawnie
- kolumna `password_hash` musi być `text` — hash ma ~97 znaków, `varchar(60)`
  uciąłby go bez błędu
- tokeny: 32 bajty z systemowego CSPRNG (256 bitów entropii)
- weryfikacja hasła wykonuje tę samą pracę dla istniejących i nieistniejących
  adresów, brak kanału czasowego ujawniającego, które konta istnieją

### Czego narazie brakuje

- wygasania tokenów (mapa sesji rośnie do restartu)
- wylogowania
- rate limitingu na `/login` — weryfikacja hasła to ~260 ms i 64 MB RAM,
  wywoływalna anonimowo
- prefiksu `Bearer` w nagłówku `Authorization`
