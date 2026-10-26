# tor-hidden-service

Tor, packaged as a container that runs a single v3 onion service. Built for the homelab
because every off-the-shelf "tor hidden service" image on Docker Hub is years stale
(`zeta0/alpine-tor` 2017, `goldy/tor-hidden-service` 2023) and an onion service is exactly
the kind of internet-facing, key-holding workload that should not run an abandoned Tor.

Everything here is a `Dockerfile` and four lines of `torrc`. The patch story is Alpine's:
`apk add tor` pulls Alpine's signed, security-maintained build, so **rebuilding the image is
the security update** — there is no vendored Tor to maintain.

Current contents (base `alpine:3.24.3`): Tor `0.4.9.14`, OpenSSL `3.5.9`, libevent `2.1.13`.

## Image

`ghcr.io/willuhmjs/tor-hidden-service` — public, `linux/amd64` only. Tags: `latest` (main),
`v1.0.0`-style semver from git tags, `sha-<shortsha>` per commit.

## Running it

Tor needs two things: a writable `DataDirectory` and a `HiddenServiceDir` that either is
empty (Tor generates a key and prints the new address in its log) or already holds
`hs_ed25519_secret_key` / `hs_ed25519_public_key` (the address you already own).

```sh
docker run --rm -d --name onion \
  -v "$PWD/hs-state:/var/lib/tor/hidden_service" \
  ghcr.io/willuhmjs/tor-hidden-service:latest

# then, from inside the same container (loopback SOCKS is on purpose, see below):
docker exec onion curl -sS --socks5-hostname 127.0.0.1:9050 http://<address>.onion/
```

The default `/etc/tor/torrc` forwards `80` on the onion to `127.0.0.1:8080`, so whatever
shares the pod/network namespace on port 8080 *is* the site. Mount your own torrc over
`/etc/tor/torrc` to change that.

`SocksPort` is bound to `127.0.0.1` only. That is deliberate: it lets a sidecar or
`kubectl exec` fetch the onion *through Tor itself*, which is the only way to prove the
service actually published, without exposing an open proxy.

## Deployment in this homelab

`apps/website` in the homelab repo runs this image next to `nginx:alpine`, and mounts the
existing onion key directory off the NAS SMB share as `HiddenServiceDir`, so the address is
stable across pod restarts and the private key lives on the (Longhorn-encrypted, backed-up)
share rather than in git or etcd.

## Refreshing Tor

```sh
docker pull alpine                    # find the newest patch release
# bump FROM alpine:<new> in the Dockerfile
git commit -am "alpine 3.24.x" && git push   # CI rebuilds and pushes :latest
```
