# tor-hidden-service

Tor, packaged as a container that runs a single v3 onion service. Built for the homelab
because every off-the-shelf "tor hidden service" image on Docker Hub is years stale
(`zeta0/alpine-tor` 2017, `goldy/tor-hidden-service` 2023) and an onion service is exactly
the kind of internet-facing, key-holding workload that should not run an abandoned Tor.

The image is `FROM scratch`: only the tor binary, its three shared libraries, geoip tables and
a `tor` passwd entry. No shell, no package manager, no curl.

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

# the image is FROM scratch (no shell, no curl). Wait for "Bootstrapped 100%", then read the
# address from the mounted directory:
docker logs onion | grep Bootstrapped
cat hs-state/hostname
# end-to-end check: run a curl container in the same network namespace
docker run --rm --network container:onion curlimages/curl -sS --socks5-hostname 127.0.0.1:9050 http://<address>.onion/
```

`docker run` applies none of the hardening described under *Security notes* on its own. For a
plain-Docker deployment use the bundled `docker-compose.yml` (read-only rootfs, `cap_drop: ALL`,
`no-new-privileges`, pid/memory limits, an unprivileged nginx sharing tor's network namespace
so the backend is only ever `127.0.0.1:8080`). Put your site in `./site` and run
`docker compose up -d` (it pulls the published image). It uses named volumes so Docker seeds the `0700` tor-owned
directories; bind mounts must be `chown 100:101` / `chmod 700` by hand.

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

## Security notes

What this image does, and what was checked against the shipped `0.4.9.14` binary rather than
copied from a hardening checklist:

- **No inbound listener.** With no `ORPort` the process only dials out, so a hidden service
  needs no port forward and a firewall egress-only policy is enough. (Tor itself warns if you
  configure `ORPort` *and* a hidden service in one process - do not do that; relay and service
  belong in separate processes.)
- **Runs as uid 100 with nothing setuid, no port under 1024, no chown.** Safe to deploy with
  `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`,
  `allowPrivilegeEscalation: false` and `seccompProfile: RuntimeDefault`, which is how the
  homelab runs it.
- **`Sandbox 1` does not work in a container - do not add it.** It parses, then tor exits at
  startup with `install_syscall_filter(): Bug: (Sandbox) failed to load: -125 (Operation
  canceled)`: a process already inside a seccomp filter cannot install its own. Take the
  runtime's profile instead. Verified with Docker's default profile, which is the same family
  as `RuntimeDefault` in containerd.
- **The hidden service directory must be 0700 and owned by tor's uid** or tor refuses to start
  (`Permissions on directory ... are too permissive`). On CIFS/NFS you control this with mount
  options (`uid=`, `dir_mode=`), and there is no `HiddenServiceIgnoreOwner` /
  `HiddenServiceIgnoreFSPermissions` escape hatch in 0.4.9 - both are unknown options.
- **`MaxMemInQueues` is set in the default config**, because tor sizes it from total system
  memory and in a pod that means the node's memory, not the container limit.
- **`SocksPort` stays on loopback.** It exists so a deployment can fetch its own onion and
  prove the descriptor published. It is not reachable outside the pod, and do not try to
  restrict it with `SocksPolicy` - 0.4.9 rejects `accept *.onion` as a malformed address
  pattern, and `reject *` blocks the very fetch the port is there for.
- **Base pinned by tag *and* digest, packages not pinned** - see the Dockerfile header for why
  that is the safer combination here.

## Refreshing Tor

```sh
docker buildx imagetools inspect alpine:3.24 --format '{{json .Manifest}}'   # newest digest
# bump FROM alpine:<new>@sha256:<digest> in the Dockerfile (or merge the Dependabot PR)
git commit -am "alpine 3.24.x" && git push && git tag 1.0.x && git push --tags
```
CI pushes `:<semver>`, `:latest` and `:sha-<shortsha>`. The homelab pins the semver tag.
