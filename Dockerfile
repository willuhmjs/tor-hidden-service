# Tor as a v3 hidden-service endpoint.
#
# The base is pinned to an exact patch release AND its digest, so a rebuild is a deliberate
# act rather than whatever upstream happened to publish. Dependabot opens the bump PR.
#
# apk packages are deliberately NOT version-pinned (unlike some similar images): tor, libevent
# and openssl come from Alpine's signed v3.24 repository, and a rebuild is supposed to pull
# their newest patched builds. Freezing `tor=0.4.9.14-r0` is how an image ends up as stale as
# the ones this repo exists to avoid - and it breaks the build outright once Alpine rolls the
# revision, which turns "rebuild for the security fix" into a failed CI run.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache tor curl

# 0700 owned by the tor user: tor refuses to start if the hidden service directory is
# group/world-accessible ("Permissions on directory ... are too permissive"), and the key
# inside it should not be readable by anything else in the container.
RUN install -d -o tor -g tor -m 0700 /var/lib/tor /var/lib/tor/data /var/lib/tor/hidden_service

COPY rootfs/etc/tor/torrc /etc/tor/torrc

# uid/gid of the tor user the Alpine package creates. Nothing in this image needs to be root
# at runtime: no setuid, no bind under 1024, no chown - so it can run with
# readOnlyRootFilesystem + capability-drop + seccompProfile: RuntimeDefault as-is.
USER 100:101

EXPOSE 9050

ENTRYPOINT ["tor", "-f", "/etc/tor/torrc"]
