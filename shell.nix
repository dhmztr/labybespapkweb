{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  buildInputs = [
    pkgs.postgresql
    (pkgs.haskellPackages.ghcWithPackages (
      p: with p; [
        servant-server
        warp
        aeson
        password
        text
        crypton
        bytestring
        containers
        postgresql-simple
        servant-swagger
        servant-swagger-ui
        swagger2
      ]
    ))
  ];

  # baza w katalogu projektu, bez zmian w systemie
  shellHook = ''
    export PGDATA="$PWD/.pgdata"
    export PGHOST="$PWD/.pgsock"
    export PGDATABASE=unter_dev
    export PGUSER="$(whoami)"
  '';
}
