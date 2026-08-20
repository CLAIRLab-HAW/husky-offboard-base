# husky-offboard-base

Shared base image (ROS 2 Jazzy) for [`husky-offboard`](https://github.com/CLAIRLab-HAW/husky-offboard)
and [`husky-offboard-lite`](https://github.com/hannesvoss/offboard-lite). Contains
the layers both final Dockerfiles share, and is
distributed via GHCR so both finals can cache it (one base build,
reused everywhere).

## Features

- **One base build, reused everywhere**: the layers `husky-offboard` and
  `husky-offboard-lite` share, distributed via GHCR so both finals cache
  against it.
- **The one Zenoh router logic** (`zenoh-connect.sh`) instead of a copy per
  final.
- **GUI over noVNC** (Xvfb + x11vnc + fluxbox) — no XQuartz, no X11 forwarding.
- **arm64 native**, no emulation.

## Tech Stack

ROS 2 Jazzy desktop, Zenoh (`rmw_zenoh_cpp`), noVNC/x11vnc/fluxbox, clearlog.

## Installation

Pull the published base, or build it locally (see *Rebuild* below):

```bash
docker pull ghcr.io/clairlab-haw/husky-offboard-base:jazzy
```

## Usage

This image is not run directly — the finals build `FROM` it. See
*Building the finals against the base*.

### What's inside
- Clearpath apt repo + keyring + rosdep list (`packages.clearpathrobotics.com`)
- `colcon` (for the rg6 build and the finals)
- noVNC desktop stack: `Xvfb` + `x11vnc` + `noVNC` + `websockify` + `fluxbox`
  + Mesa llvmpipe (software GL)
- noVNC default `resize=scale` (local scaling in the browser)
- `rg6_description` (gripper meshes) from source (`onrobot-rg6`) into `/opt/onrobot-rg6`
- `/usr/local/bin/start-desktop.sh` — shared desktop startup that both final
  entrypoints invoke. Reads `DISPLAY`, `NOVNC_WIDTH`, `NOVNC_HEIGHT` and
  `VNC_PASSWORD` from the environment.

  **`VNC_PASSWORD` decides whether a native VNC client can get in at all.**
  Unset (the default), `x11vnc` runs `-nopw` and offers exactly one security
  type: `None`. Apple's Screen Sharing refuses that type and answers with a
  message about the *remote machine* — "make sure Screen Sharing is enabled" —
  when what actually failed is the handshake. On the robot (`network_mode:
  host`) the passwordless server also binds `127.0.0.1` instead of `0.0.0.0`,
  so port 5900 answers *Connection refused* from anywhere else. Measured on
  a200-0553 on 2026-08-20: 6080 open, 5900 loopback-only.

  Set it, and `x11vnc` offers `VNC Auth` and listens on `0.0.0.0`. The
  protocol caps VNC passwords at 8 characters. noVNC on 6080 is unaffected
  either way — `websockify` reaches 5900 over the container's own loopback.
- `/usr/local/bin/zenoh-connect.sh` — **THE one Zenoh router logic** shared by all
  containers (RMW check, `ZENOH_LOCAL=1` on the robot,
  `ZENOH_STANDALONE=1` isolated local router for the zenoh mock demo,
  `ROBOT_ZENOH_ENDPOINT` offboard). offboard + lite invoke it in their entrypoint;
  the [app-runner](../app-runner/README.md) copies it via the build context.
  Changing Zenoh behavior = change only this file (rebuild + push the base).
- ENV defaults: `RMW_IMPLEMENTATION=rmw_zenoh_cpp`, `ROS_DOMAIN_ID=0`,
  `LIBGL_ALWAYS_SOFTWARE=1`, `DISPLAY=:1`, `CLEARPATH_NS=a200_0553`,
  `NOVNC_WIDTH=1600`, `NOVNC_HEIGHT=900`; `EXPOSE 6080`; `CMD sleep infinity`
  (`VNC_PASSWORD` has no ENV default — unset means "no password", see above)

### What is NOT included (final-specific)
- `clearpath-desktop` / `clearpath-manipulators`, `foxglove-bridge`,
  `ur-robot-driver`, `clearpath_generator_robot` (offboard)
- `rviz2` + `moveit-ros-visualization` + `*-description` mesh packages (lite)
- `rg6_control` (driver) — offboard builds it incrementally on the base clone
- `robot.yaml`/generator logic + `ENTRYPOINT` — each final ships its own
  `entrypoint.sh`

### Image / tags
CI (`.github/workflows/build.yml`) pushes on push to `main`:
- `ghcr.io/clairlab-haw/husky-offboard-base:jazzy` — rolling
- `ghcr.io/clairlab-haw/husky-offboard-base:<YYYYMMDD>-<sha>` — pinnable

The layer cache lives at `ghcr.io/clairlab-haw/husky-offboard-base:buildcache`.

### Rebuild + push the base (manual / local)
```bash
docker buildx build \
  --push \
  -t ghcr.io/clairlab-haw/husky-offboard-base:jazzy \
  -t ghcr.io/clairlab-haw/husky-offboard-base:local \
  .
```
Without push (local only, e.g. to test the finals without a registry pull):
```bash
docker build -t husky-offboard-base:jazzy .
```

### Building the finals against the base
Both final Dockerfiles use:
```dockerfile
ARG BASE_IMAGE=ghcr.io/clairlab-haw/husky-offboard-base:jazzy
FROM ${BASE_IMAGE}
```
The default is the GHCR image. For a local build (without a registry pull), build
the base yourself first (see above) and override `BASE_IMAGE`:
```bash
# in the respective final repo:
docker compose -f docker-compose.<profile>.yml build --build-arg BASE_IMAGE=husky-offboard-base:jazzy
```
or set `BASE_IMAGE=husky-offboard-base:jazzy` in your shell, provided the
compose file declares `build.args.BASE_IMAGE` with a default (see the final
READMEs).

### Pinning
For reproducible final builds, pin the base digest:
```bash
docker buildx imagetools inspect ghcr.io/clairlab-haw/husky-offboard-base:jazzy
# ->  FROM ghcr.io/clairlab-haw/husky-offboard-base:jazzy@sha256:...
```

## Related

- [husky-offboard](../husky-offboard/README.md) — the full offboard container
- [husky-offboard-lite](../husky-offboard-lite/README.md) — the slim RViz+MoveIt
  client

## Versioning

[Semantic Versioning](https://semver.org/) via the `VERSION` file and
[CHANGELOG.md](CHANGELOG.md). The image tag (`jazzy`) tracks the ROS
distribution and is independent of it.

## License

See workspace root.
