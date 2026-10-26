# Tor as a v3 hidden-service endpoint.
#
# The base tag is pinned to an exact Alpine patch release on purpose: tor, libevent and
# openssl all come from Alpine's signed repository, so `apk add` at build time is the patch
# story. Rebuilding this image against a current base IS the security update; there is
# nothing vendored here to maintain.
FROM alpine:3.24.3

RUN apk add --no-cache tor curl

RUN install -d -o tor -g tor -m 0700 /var/lib/tor /var/lib/tor/data /var/lib/tor/hidden_service

COPY rootfs/etc/tor/torrc /etc/tor/torrc

# uid/gid of the tor user the Alpine package creates.
USER 100:101

EXPOSE 9050

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]
