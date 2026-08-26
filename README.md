# husky-offboard-base

Shared base image (ROS 2 Jazzy) for every container under
[`deploy/`](../README.md) — the four stages of
[`husky-offboard`](https://github.com/CLAIRLab-HAW/husky-offboard) and
[`app-runner`](../app-runner/README.md). It carries the layers all of them
share and nothing else, and is distributed via GHCR so one base build is
reused everywhere.

## Features

- **One base build, reused everywhere**: the layers every deploy image shares,
  distributed via GHCR so the finals cache against it.
- **The one Zenoh router logic** (`zenoh-connect`) instead of a copy per
  final.
- **The one ROS source chain** (`ros-env`) instead of a copy per helper: each
  of its up to three overlays is guarded, so the same file is right in an
  image that has only `/opt/ros/jazzy` and in one that has all three.
- **`rmw_zenoh_cpp` — the middleware the robot speaks, and the only one we
  speak.** The image ships the package its own `RMW_IMPLEMENTATION` default
  names, so a bare `docker run` of this image works.
- **arm64 and amd64**, both built natively-tagged by CI; no emulation on
  either host.

## Tech Stack

ROS 2 Jazzy (`ros-base`), Zenoh (`rmw_zenoh_cpp`), clearlog.

## Installation

Pull the published base, or build it locally (see *Rebuild* below):

```bash
docker pull ghcr.io/clairlab-haw/husky-offboard-base:jazzy
```

## Usage

This image is not run directly — the finals build `FROM` it. See
*Building the finals against the base*.

### What's inside
Four things, and that is the whole list — everything with a narrower audience
belongs to a stage, not here.

- `rmw_zenoh_cpp` — the middleware every image speaks; the ENV default below
  names it, so it has to be here
- `python3-rich` — the renderer behind [`clearlog`](../../libs/clearlog/README.md)'s
  Python handler; needed by every container that logs, display or not
- `/usr/local/bin/zenoh-connect` — **THE one Zenoh router logic** shared by all
  containers (`ZENOH_LOCAL=1` on the robot, `ZENOH_STANDALONE=1` for the
  isolated mock graph, `ROBOT_ZENOH_ENDPOINT` for a remote one). Every entrypoint invokes it; the
  [app-runner](../app-runner/README.md) copies it via the build context.
  Changing Zenoh behavior = change only this file (rebuild + push the base).
- `/usr/local/bin/clearlog` — the shell half of `clearlog`, sourced (not
  executed) by every entrypoint and helper so container lines and Python lines
  share one format
- `/usr/local/bin/ros-env` — **THE one ROS source chain**, sourced by every
  helper and entrypoint that needs ROS. A fresh `docker exec` shell has none
  sourced, and a helper that skips the chain fails *silently* — it prints
  nothing rather than an error. Each overlay stage is guarded with `[ -f … ]`,
  so this one file is correct in an image carrying only `/opt/ros/jazzy` and in
  one carrying `clearpath_ws` and the rg6 overlay as well. The
  [app-runner](../app-runner/README.md) copies it via the build context, like
  `zenoh-connect`.
- ENV defaults: `RMW_IMPLEMENTATION=rmw_zenoh_cpp`, `ROS_DOMAIN_ID=0`,
  `CLEARPATH_NS=a200_0553`, `RCUTILS_CONSOLE_OUTPUT_FORMAT`;
  `CMD sleep infinity`

### What is NOT included
- **The noVNC desktop** — `Xvfb`, `x11vnc`, `noVNC`, `websockify`, `fluxbox`,
  `xterm`, Mesa, the `resize=scale` patch and `start-desktop` all live in
  the `viewer` stage of
  [`husky-offboard`](../husky-offboard/README.md#image-structure), which is
  still one place to change them: `lite`, `offboard` and `mock-robot` all
  inherit from `viewer`. Anything in this image is paid for by every deploy
  image, and that apt layer with its X11/Mesa closure is 446 MB (measured
  2026-08-25 with `docker history`) — which `spact-logic`, an action client
  with no display, has no use for.
- **The Clearpath apt repo, keyring and rosdep list**, plus the
  `wget`/`gnupg`/`lsb-release` that exist only to set them up, and
  `ros-jazzy-xacro` — also in `viewer`. Measured 2026-08-26: the `spact-logic`
  image has ZERO clearpath packages installed, and
  [`app-runner`](../app-runner/README.md) does not build on this base at all.
- **`rg6_description`** (the gripper meshes, from the `onrobot-rg6` source) —
  also in `viewer`, together with the `RG6_REF` checkout. Only images that
  resolve `package://` mesh URIs out of the robot URDF need them, which is the
  same four stages as the desktop. `rg6_control` (the driver) is narrower
  still: `mock-robot` builds it, because only that stage runs
  `rg6_moveit_patch`.
- `git`, `curl` and `colcon` — they ship with `ros:jazzy-ros-base`
  (`python3-colcon-common-extensions` included, so `colcon build` works;
  measured 2026-08-26). Naming them here would suggest they are ours.
- `clearpath-desktop` / `clearpath-manipulators`, `clearpath_generator_robot`,
  `foxglove-bridge`, the Nav2/UR packages, `rviz2` +
  `moveit-ros-visualization` + the `*-description` mesh packages — all
  stage-specific
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
Every final Dockerfile uses:
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

- [husky-offboard](../husky-offboard/README.md) — the four stages built on this
  base: `viewer`, `lite`, `offboard`, `mock-robot`, plus the `logic` image
- [app-runner](../app-runner/README.md) — the one image for the thin SDK apps
- [clearlog](../../libs/clearlog/README.md) — the log format `clearlog`
  implements for the shell side

## Versioning

[Semantic Versioning](https://semver.org/) via the `VERSION` file and
[CHANGELOG.md](CHANGELOG.md). The image tag (`jazzy`) tracks the ROS
distribution and is independent of it.

## License

See workspace root.
