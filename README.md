# husky-offboard-base

Gemeinsames Basis-Image (ROS 2 Jazzy) fuer [`husky-offboard`](https://github.com/CLAIRLab-HAW/husky-offboard)
und [`husky-offboard-lite`](https://github.com/hannesvoss/offboard-lite). Enthaelt
die Layer, die in beiden finalen Dockerfiles bisher dupliziert waren, und wird
via GHCR verteilt, sodass beide Finals es cachen koennen (ein Base-Build,
ueberall reused).

## Was drin ist
- Clearpath apt-Repo + Keyring + rosdep-Liste (`packages.clearpathrobotics.com`)
- `colcon` (fuer den rg6-Build und die Finals)
- noVNC-Desktop-Stack: `Xvfb` + `x11vnc` + `noVNC` + `websockify` + `fluxbox`
  + Mesa llvmpipe (Software-GL)
- noVNC-Default `resize=scale` (lokales Scaling im Browser)
- `rg6_description` (Greifer-Meshes) aus Source (`onrobot-rg6`) nach `/opt/onrobot-rg6`
- `/usr/local/bin/start-desktop.sh` — gemeinsamer noVNC-Desktop-Start, den beide
  finalen Entrypoints aufrufen
- `/usr/local/bin/zenoh-connect.sh` — **DIE eine Zenoh-Router-Logik** aller
  Container (RMW-Check, `ZENOH_LOCAL=1` auf dem Roboter,
  `ROBOT_ZENOH_ENDPOINT` offboard). offboard + lite rufen sie im Entrypoint
  auf; der [app-runner](../app-runner/README.md) kopiert sie per Build-Kontext.
  Zenoh-Verhalten ändern = nur diese Datei ändern (Base neu bauen + pushen).
- ENV-Defaults: `RMW_IMPLEMENTATION=rmw_zenoh_cpp`, `ROS_DOMAIN_ID=0`,
  `LIBGL_ALWAYS_SOFTWARE=1`, `DISPLAY=:1`, `CLEARPATH_NS=a200_0553`,
  `NOVNC_WIDTH=1600`, `NOVNC_HEIGHT=900`; `EXPOSE 6080`; `CMD sleep infinity`

## Was NICHT drin ist (final-spezifisch)
- `clearpath-desktop` / `clearpath-manipulators`, `foxglove-bridge`,
  `ur-robot-driver`, `clearpath_generator_robot` (offboard)
- `rviz2` + `moveit-ros-visualization` + `*-description`-Mesh-Pakete (lite)
- `rg6_control` (Treiber) — offboard baut ihn inkrementell auf dem Base-Clone
- `robot.yaml`/Generatoren-Logik + `ENTRYPOINT` — jeder Final bringt seinen
  eigenen `entrypoint.sh`

## Image / Tags
CI (`.github/workflows/build.yml`) pusht bei Push auf `main`:
- `ghcr.io/clairlab-haw/husky-offboard-base:jazzy` — rolling
- `ghcr.io/clairlab-haw/husky-offboard-base:<YYYYMMDD>-<sha>` — pinbar

Layer-Cache liegt unter `ghcr.io/clairlab-haw/husky-offboard-base:buildcache`.

## Base neu bauen + pushen (manuell / lokal)
```bash
docker buildx build \
  --push \
  -t ghcr.io/clairlab-haw/husky-offboard-base:jazzy \
  -t ghcr.io/clairlab-haw/husky-offboard-base:local \
  .
```
Ohne Push (nur lokal, z.B. zum Testen der Finals ohne Registry-Pull):
```bash
docker build -t husky-offboard-base:jazzy .
```

## Finals gegen die Base bauen
Beide finalen Dockerfiles nutzen:
```dockerfile
ARG BASE_IMAGE=ghcr.io/clairlab-haw/husky-offboard-base:jazzy
FROM ${BASE_IMAGE}
```
Default ist das GHCR-Image. Fuer einen lokalen Build (ohne Registry-Pull) die
Base vorher selbst bauen (s.o.) und `BASE_IMAGE` ueberschreiben:
```bash
# im jeweiligen finalen Repo:
docker compose -f docker-compose.<profil>.yml build --build-arg BASE_IMAGE=husky-offboard-base:jazzy
```
oder in der Shell `BASE_IMAGE=husky-offboard-base:jazzy` setzen, sofern das
Compose-File `build.args.BASE_IMAGE` mit Default deklariert (siehe finale
READMEs).

## Pinnen
Fuer reproduzierbare Final-Builds den Base-Digest pinnen:
```bash
docker buildx imagetools inspect ghcr.io/clairlab-haw/husky-offboard-base:jazzy
# ->  FROM ghcr.io/clairlab-haw/husky-offboard-base:jazzy@sha256:...
```