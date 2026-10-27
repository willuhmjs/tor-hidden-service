# Tor as a v3 hidden-service endpoint, shipped as a shell-less image.
#
# Stage 1 installs tor from Alpine's signed repository and collects exactly the files it needs.
# Stage 2 is FROM scratch: no shell, no busybox, no apk, no curl, no package database. An
# attacker who gets code execution inside tor has no interpreter and no tooling to work with,
# and a scanner has no OS packages to flag except the ones tor itself links against.
#
# The builder base is pinned to an exact patch release AND its digest, so a rebuild is a
# deliberate act. Dependabot opens the bump PR. apk packages are deliberately NOT
# version-pinned: a rebuild is supposed to pull the newest patched tor/libevent/openssl, and
# freezing "tor=0.4.9.14-r0" breaks the build the day Alpine rolls the revision.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS build

RUN apk add --no-cache tor

# Everything tor needs at runtime: the binary, every shared object ldd resolves (including the
# musl loader), and its geoip tables. Copied with their absolute paths preserved.
RUN set -eu; \
    mkdir -p /out; \
    { echo /usr/bin/tor; \
      ldd /usr/bin/tor | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }'; \
    } | sort -u | while read -r f; do cp --parents -L "$f" /out; done; \
    cp --parents /usr/share/tor/geoip /usr/share/tor/geoip6 /out; \
    install -d -m 0755 /out/etc /out/tmp; \
    echo 'tor:x:100:101:tor:/var/lib/tor:/sbin/nologin' > /out/etc/passwd; \
    echo 'tor:x:101:' > /out/etc/group; \
    install -d -o 100 -g 101 -m 0700 /out/var/lib/tor /out/var/lib/tor/data /out/var/lib/tor/hidden_service; \
    chmod 1777 /out/tmp

FROM scratch

COPY --from=build /out/ /
COPY rootfs/etc/tor/torrc /etc/tor/torrc

LABEL org.opencontainers.image.source="https://github.com/willuhmjs/tor-hidden-service" \
      org.opencontainers.image.description="Tor v3 hidden-service endpoint, shell-less scratch image" \
      org.opencontainers.image.licenses="MIT"

# uid/gid of the tor user. Nothing here needs root at runtime: no setuid, no bind under 1024,
# no chown - so it runs with readOnlyRootFilesystem + capability-drop + seccomp RuntimeDefault.
USER 100:101

EXPOSE 9050

ENTRYPOINT ["/usr/bin/tor", "-f", "/etc/tor/torrc"]
