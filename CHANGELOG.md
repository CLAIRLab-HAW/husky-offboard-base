# Changelog — husky-offboard-base

What changed when. The current state is described in the [README](README.md).

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung [Semantic Versioning](https://semver.org/lang/de/).

## 2026-08-26 (the base carries only what every image needs)

- **The image named an RMW it did not ship.** `ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp` had been the default since
  the base existed, but `ros-jazzy-rmw-zenoh-cpp` was never installed here -- measured 2026-08-25, `ros2 topic
  list` in a bare `docker run` of this image aborted with *"RMW implementation not installed (expected identifier
  of 'rmw_zenoh_cpp') ... librmw_zenoh_cpp.so: cannot open shared object file"*. It stayed invisible because all
  four finals installed the package again themselves (three times in `husky-offboard/Dockerfile`, once in
  `Dockerfile.logic`). The package is here now and those four re-installs are gone;
  `husky-offboard/tests/test_logic_image.py` fails if one comes back.
- **The noVNC desktop moved to the `viewer` stage of `husky-offboard`** -- `xvfb`, `x11vnc`, `novnc`,
  `websockify`, `fluxbox`, `xterm`, `mesa-utils`, `libgl1-mesa-dri`, the `resize=scale` patch, the
  `DISPLAY`/`LIBGL_ALWAYS_SOFTWARE`/`NOVNC_WIDTH`/`NOVNC_HEIGHT` defaults, `EXPOSE 6080`, and `start-desktop.sh`
  with them. Measured 2026-08-25 with `docker history`: that apt layer plus its X11/Mesa closure is 446 MB, and
  `spact-logic` -- an action client whose entrypoint never calls `start-desktop.sh` -- inherited every byte.
  `lite`, `offboard` and `mock-robot` all descend from `viewer`, so there is still exactly one place to change it.
- **The Clearpath apt repo, keyring and rosdep list moved there too**, along with `wget`/`gnupg`/`lsb-release`
  (which existed only to set it up) and `ros-jazzy-xacro`. Measured 2026-08-26: the `spact-logic` image has ZERO
  clearpath packages installed, and `deploy/app-runner` does not build on this base at all.
- **`rg6_description` moved there as well.** The clone was built here and then thrown away again: the `viewer`
  stage did a `git fetch --prune` + `reset --hard FETCH_HEAD` + rebuild on top of it on every build. It is a
  single clone in `viewer` now, and the images that resolve `package://` mesh URIs -- the same four stages -- are
  the only ones carrying it.
- **`python3-rich` stayed, and moved out of the desktop apt block into its own.** It is the renderer behind
  `libs/clearlog`'s Python handler, which every container uses, display or not.
- **`git`, `curl` and `colcon` are no longer installed here.** Measured 2026-08-26 in `ros:jazzy-ros-base`: all
  three are present, `python3-colcon-common-extensions` included, so `colcon build` works. The comment claiming
  the opposite ("colcon ist in ros:jazzy-ros-base NICHT enthalten") was wrong.
- **The image is 1.9 GB -> ~1.4 GB**, and the Dockerfile, the README and the CI workflow are English.

## 2026-08-26 (one middleware: zenoh, in every profile)

- **`zenoh-connect.sh` no longer decides WHETHER there is a router, only which graph it joins.** The
  `RMW != rmw_zenoh_cpp -> no router` branch existed for the FastRTPS mock; it is now a loud warning about a
  configuration nobody supports rather than a supported mode.
- **Both router configs state `scouting: { multicast: { enabled: false } }` explicitly.** It is the upstream
  default (`DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5`, "ROS setting: disable multicast discovery by default"), but
  the mock's isolation from the robot now rests on it, and a default a safety property depends on gets written
  down rather than inherited. `husky-offboard/tests/test_zenoh_isolation.py` fails if either config loses it.
- **The fixed `sleep 3` after starting `rmw_zenohd` became a readiness check** on `127.0.0.1:7447`
  (`ZENOH_ROUTER_WAIT_S`, default 20 s). A fixed sleep is either too short -- nodes start, find no router, log
  "Proceeding with initialization" and never discover anything -- or wasted time.

## 2026-08-25 (the shared scripts log under the calling container's name)

- **`start-desktop.sh` and `zenoh-connect.sh` put the same identity on the line twice** -- once as the logger
  name (`base.desktop` / `base.zenoh`), once as a `[offboard]` prefix in front of every message. Removing that
  prefix "everywhere, it now lives in the name column" was the stated intent of the clearlog rollout
  (`docs/superpowers/plans/2026-07-30-docker-logging.md`, step 3); the two shared scripts kept it because the
  name column could not say *which* container was speaking. It can now: the caller passes its role, so the name
  is `offboard.desktop` / `mock-robot.zenoh` / `lite.desktop` and the messages carry no prefix. A caller that
  passes nothing still gets `base.*`.
- **`start-desktop.sh`'s closing "desktop ready" line was a bare `echo`** -- stdout, no stamp, no level, no
  name, while every other line of the script goes formatted to stderr. In a container log there is no second
  channel for a note to the human, so it is `log_info` now, like the `ready. Tools:` line of the offboard
  entrypoint next to it.
- **`zenoh-connect.sh`'s five log lines are English.** They lost their prefix anyway, so they came along.

## 2026-08-25 (the VNC log line no longer claims the browser needs no password)

- **`start-desktop.sh` announced "VNC without password ... set VNC_PASSWORD for a native viewer", and the
  README and both composes said noVNC on 6080 was "unaffected either way".** All of them rested on the same
  false premise -- that `websockify` reaching 5900 over the container's own loopback somehow skips
  authentication. It does not: `x11vnc` negotiates the security type per RFB connection, so with
  `VNC_PASSWORD` set the browser is prompted exactly like a native viewer. Measured by reading the handshake
  inside the two running containers: `offboard` (`VNC_PASSWORD=husky`) offers only type 2 `VNC Auth` on
  `localhost:5900`, `mock-robot` (no password) only type 1 `None`. Both log lines now say what the setting
  means for **both** doors.
- **The "desktop ready" banner promised `http://localhost:6080/vnc.html` from every container that runs the
  script.** Only the container whose compose service publishes 6080 is reachable there -- in the
  husky-offboard stack that is `offboard` alone, so `mock-robot` was pointing the reader at a *different*
  container's desktop. It now names the container port and says the host URL holds where compose publishes it.
- **The script's log lines are English** ("what you touch, you bring along"). The German comment blocks it did
  not otherwise touch are unchanged.

## [Unreleased]

### Behoben
- **Nach `docker start` blieb der Desktop tot.** `start-desktop.sh` startete
  `Xvfb` ohne das Lock des vorigen Laufs zu entfernen. Ein neu *angelegter*
  Container hat ein leeres `/tmp`, ein wieder*gestarteter* nicht — dort lag
  `/tmp/.X1-lock` noch, `Xvfb` brach mit *"Server is already active for display
  1"* ab, `fluxbox` und `x11vnc` fanden kein Display und starben mit.
  `websockify` lauschte weiter auf `6080`, weshalb es von außen wie ein
  gesunder Container aussah: `6080` offen, `5900` keine Antwort, noVNC meldete
  *"Failed to connect to server"*. Am 2026-08-20 an a200-0553 reproduziert —
  Stop + Start über die Cockpit-Seite, während `up -d --force-recreate`
  unauffällig war.

  Aufgeräumt wird nur ein **verwaistes** Lock: die Datei enthält die PID ihres
  `Xvfb`, und solange `/proc/<pid>` existiert, bleibt sie liegen.

### Hinzugefügt
- **`VNC_PASSWORD` in `start-desktop.sh` — ohne Passwort kommt kein nativer
  VNC-Client herein.** `x11vnc` lief mit `-nopw` und bot damit genau einen
  Security-Typ an: `None`. Zwei Folgen, die beide wie ein Netzwerkfehler
  aussehen und keiner sind:

  - Apples Bildschirmfreigabe akzeptiert `None` nicht und meldet stattdessen
    etwas über den *entfernten Rechner* ("Vergewissere dich, dass die
    Bildschirmfreigabe … aktiviert ist"), obwohl der Handshake scheiterte.
  - Ohne Passwort bindet `x11vnc` auf dem Roboter (`network_mode: host`) an
    `127.0.0.1` statt `0.0.0.0`. Am 2026-08-20 an a200-0553 gemessen: `6080`
    offen, `5900` nur auf loopback, von außen "Connection refused".

  Mit gesetztem `VNC_PASSWORD` bietet `x11vnc` `VNC Auth` an und lauscht per
  `-listen 0.0.0.0` explizit auf allen Interfaces. Ohne bleibt alles wie
  bisher; noVNC auf `6080` ist in beiden Fällen unberührt, weil `websockify`
  containerintern auf `localhost:5900` geht. VNC-Passwörter sind
  protokollbedingt auf 8 Zeichen begrenzt.

## [0.2.0] - 2026-08-19

- Repository and image created: the layers that had been duplicated in the
  `husky-offboard` and `husky-offboard-lite` Dockerfiles were pulled out into
  this shared ROS 2 Jazzy base, distributed via GHCR so both finals cache
  against one base build. The Zenoh layer moved in here from `husky-offboard`
  in the same window.
- **SemVer eingeführt.** Version auf `0.2.0`, dieses Changelog folgt
  [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Tag `v0.2.0`.
  Ältere Abschnitte behalten ihre Datumsüberschrift — ihnen nachträglich
  Versionsnummern zu geben, würde eine Release-Historie erfinden.
- **README nach dem Workspace-Schema** (readme.so): Features · Tech Stack ·
  Installation · Usage · Running Tests · Related · Versioning · License. Die
  vorhandene Prosa ist erhalten und unter den passenden Abschnitt gewandert.
