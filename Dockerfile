# ---- etap budowania: pelny toolchain Nixa, zrodla ----
FROM nixos/nix:latest AS builder

WORKDIR /unter-hs

COPY . .

RUN cd frontend && \
    nix-shell -p elmPackages.elm --run "elm make src/Main.elm --output=public/elm.js"

RUN nix-shell shell.nix --run "ghc -O2 -threaded Main.hs -o unter-server"

# zamkniecie bibliotek dynamicznych binarki (z nix store) do skopiowania osobno
# ldd nie ma w golej powloce obrazu bazowego, stad nix-shell -p glibc
RUN nix-shell -p glibc --run "ldd ./unter-server" | grep -oE '/nix/store/[^ )]+' | sort -u \
      | xargs -I{} nix-store --query --requisites {} \
      | sort -u > /closure.txt && \
    mkdir -p /out/unter-hs/frontend && \
    while read -r p; do \
      mkdir -p "/out$(dirname "$p")"; \
      cp -a "$p" "/out$p"; \
    done < /closure.txt && \
    cp unter-server /out/unter-server && \
    cp -r frontend/public /out/unter-hs/frontend/public && \
    mkdir -p /out/etc && \
    printf 'appuser:x:65532:65532::/unter-hs:/noshell\n' > /out/etc/passwd && \
    printf 'appuser:x:65532:\n' > /out/etc/group && \
    printf 'passwd: files\ngroup: files\nhosts: files dns\n' > /out/etc/nsswitch.conf

# ---- etap finalny: bez toolchaina, bez zrodel, bez roota ----
FROM scratch

COPY --from=builder /out /

WORKDIR /unter-hs

EXPOSE 8080

USER 65532:65532

CMD ["/unter-server"]
