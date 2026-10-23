FROM nixos/nix:latest

WORKDIR /unter-hs

COPY . .

RUN cd frontend && \
    nix-shell -p elmPackages.elm --run "elm make src/Main.elm --output=public/elm.js"

RUN nix-shell shell.nix --run "ghc -O2 -threaded Main.hs -o unter-server"

EXPOSE 8080

CMD ["./unter-server"]
