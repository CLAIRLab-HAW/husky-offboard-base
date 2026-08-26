# Changelog — husky-offboard-base

What changed when. The current state is described in the [README](README.md).

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
the versioning [Semantic Versioning](https://semver.org/).

## 2026-08-26 (a push to main started no run at all, and the gate skipped itself)

- **The `paths:` filter is gone from the trigger.** A workflow-level filter that does not match produces NO RUN
  AT ALL, and the Actions tab then looks the same whether the filter did its job or the push never reached
  Actions. Measured 2026-08-26: a push touching `Dockerfile`, `scripts/ros-env`, `scripts/clearlog` and this
  workflow started nothing here, while `husky-offboard`, whose workflow carries no filter, ran on the very same
  push. Every push to `main` now starts a visible run.
- **The saving moved to the expensive job.** A `scope` step compares the push through `gh api` and names the
  changed files in the log; `build-and-push` runs only when `Dockerfile`, `scripts/` or this workflow is among
  them. Anything that is not a plain push rebuilds, and so does a compare list that hits the API's 300-file cap
  -- a missed rebuild is the failure this step exists to prevent.
- **The neighbour is checked out with `CLAIRLAB_READ_TOKEN`**, the org secret `robot-contract`, `perception`,
  `plan-bridge`, `skill-tree` and `husky-sdk` already use for their private siblings. `GITHUB_TOKEN` is scoped
  to the repository the workflow runs in, so against another private repo of the same org the API answers "Not
  Found" rather than 403 -- measured here as three attempts, ~35 s of backoff, then `Error: Not Found`.
- **The checkout is required, not optional.** It was briefly written with `continue-on-error` and skip
  conditions, which meant the behavioural half of the gate silently did not run. A gate that skips itself is not
  a gate; no other repo in the org writes it that way either.

## 2026-08-26 (clearlog's own comments were still German)

- **`scripts/clearlog` reads English.** Its header block and the four comments inside it explained the printf
  template rule, the `set -e`/`set -u` constraints, the POSIX-sh requirement and the deliberate difference from
  `handler.py:shorten()` -- in German, with transliterated umlauts. It is the file every entrypoint and helper
  sources, so it is read more often than most.
- **Prose only.** `libs/clearlog/tests/test_shell_parity.py` reads exactly this file and ties it to the Python
  handler; 100 tests pass unchanged.

## 2026-08-26 (the push had no gate in front of it)

- **`build-and-push` now `needs: test`.** Until today a push to `main` built this image and published it to GHCR
  with nothing checked first, while the suite that checks its scripts sat in `husky-offboard`, which had no
  workflow at all. The two halves were the wrong way round.
- **The floor always runs**: `bash -n` over every file in `scripts/`. The behavioural checks live in the
  neighbouring repo on purpose -- they compare a script against the Dockerfiles that copy it -- so the job checks
  that repo out beside this one and runs its suite against this working tree. If the checkout fails (a private
  repo needs a PAT rather than `GITHUB_TOKEN`), the job says so as a warning and the syntax floor still gates the
  build, rather than a token problem turning into a red build.
- **`README.md` gained the `Running Tests` section** the workspace README skeleton asks for, saying where the
  tests actually are and why they are not here.

## 2026-08-26 (ros-env moved here, so every image can have the same one)

- **`ros-env` — THE one ROS source chain — now lives in this repo and this image**, next to `zenoh-connect`,
  `ready-banner` and `clearlog`, and for the same reason: every image that runs a ROS tool needs it. It lands on
  `/usr/local/bin/ros-env`, so the four husky-offboard images inherit it instead of copying it, and
  `deploy/app-runner` can take it through the build context the way it already takes `zenoh-connect`.
- **The file is unchanged.** Its up to three overlay stages are each guarded with `[ -f … ]`, which is exactly
  what makes one file correct in an image that has only `/opt/ros/jazzy/setup.bash` and in one that also has
  `clearpath_ws` and the rg6 overlay.
- **Order matters for whoever builds next**: this image has to be rebuilt and pushed before husky-offboard is
  built against it, because husky-offboard no longer copies `ros-env` from its own `scripts/`.

## 2026-08-26 (.DS_Store was not ignored)

- **`.gitignore` listed only `.env`.** macOS writes a `.DS_Store` into any directory a Finder window has
  visited, and this repo is developed on one. Added, matching the workspace base list (CLAUDE.md). The
  remaining six entries of that list stay out: this repo carries no Python at all.

## 2026-08-26 (the downloaded .debs survive in a build cache)

- **`docker-clean` is removed and `Keep-Downloaded-Packages` set**, so the apt cache mounts in this image and in
  every derived stage actually hold something. Without it apt deletes each `.deb` right after installing it.
- **The apt step mounts a BuildKit cache** for `/var/cache/apt` and `/var/lib/apt/lists`, keyed on `TARGETARCH`:
  CI builds linux/amd64 AND linux/arm64, and `.deb`s of two architectures in one cache directory would be a
  corrupt cache, not a fast one.
- **Why:** measured 2026-08-26 against the real stack, rebuilding one invalidated apt layer spent 368 s of 577 s
  downloading and 168 s unpacking. In an isolated counter-test the same layer took 62 s cold and 23 s warm. The
  cache is a BUILD cache: nothing of it reaches a layer, `/var/lib/apt/lists` stays out of the images entirely,
  and on a machine that has never built this the first build costs exactly what it did before.

## 2026-08-26 (no package changelogs or examples -- and an honest measurement of what that is worth)

- **`/etc/dpkg/dpkg.cfg.d/01_nodoc` excludes `/usr/share/doc/*` and keeps `*/copyright`.** dpkg reads that
  directory on every install, so one file here covers every derived stage.
- **The size claim that motivated it was wrong, and the file now says so.** `/usr/share/doc` is 172 MB in
  `clearpath-offboard`, but measured 2026-08-26, **159 MB of that are `copyright` files** -- kept on purpose,
  because this image is pushed to GHCR and shipping a binary without its licence text is not a size decision. Of
  the remaining 7 MB most are changelogs installed by `ros:jazzy-ros-base` before this config existed. The
  exclusion buys about a megabyte today; what it is really for is capping the next package that ships 50 MB of
  examples.
- **Where the weight actually sits, checked and left alone:** 57 `-dev` packages, 169 MB, in a runtime image --
  `libvtk9-dev`, `libomp-18-dev`, `libhdf5-dev`, `libpcl-dev`, the boost dev chain. ROS debs declare them as hard
  runtime `Depends` (`libpcl-dev` <- `ros-jazzy-velodyne-pointcloud`), so apt would take the depending package
  with them. Upstream packaging, not something to fix here -- written down so nobody re-derives it.

## 2026-08-26 (clearlog.sh is clearlog, and the last dead fallback is gone)

- **`clearlog.sh` is `clearlog`.** The suffix was kept one round longer on the argument that it distinguishes the
  shell half from the Python package `libs/clearlog` -- overruled: nothing on `/usr/local/bin` carries an
  extension, the two halves never appear in the same place, and `libs/clearlog/tests/test_shell_parity.py`
  reaches for the file by path anyway. Checked before renaming: `libs/clearlog` declares no `[project.scripts]`,
  so there is no command of that name to collide with.
- **`zenoh-connect` sources clearlog strictly**, like every other script. Its eleven-line fallback could not fire:
  clearlog ships in this image beside it.

## 2026-08-26 (a derived ready banner for every entrypoint)

- **New `scripts/ready-banner`.** It prints the tools a container actually carries -- every plain file directly on
  `/usr/local/bin` that starts with a shebang, minus the cross-cutting pieces that are sourced or invoked by the
  entrypoint rather than by a user (`ros-env`, `guard`, `clearlog.sh`, `zenoh-connect`, `start-desktop`, itself).
  It belongs here because ALL four entrypoints print that line; keeping the list per entrypoint is how one of them
  ended up advertising `foxglove` long after that bridge had moved to another image. `deploy/app-runner` copies it
  through the same build context it already uses for `zenoh-connect`.

## 2026-08-26 (a command on PATH does not carry a file extension)

- **`zenoh-connect.sh` is `zenoh-connect`.** Of the fourteen files on `/usr/local/bin` in the mock-robot image,
  ten carry no extension -- `view-moveit`, `teach-pose`, `ros-env`, `guard`, `mock`, `moveit`, `nav`, `rviz`,
  `view-nav`, `foxglove` -- and everything husky-offboard added itself went without one. The three `.sh` files
  all came from this repo, which made the suffix look like a convention when it was a leftover. It did not even
  mark "sourced" consistently: `ros-env` and `guard` are sourced too and have none.
- **`clearlog.sh` keeps its suffix, and now says why.** `clearlog` is the name of a Python package in this
  workspace (`libs/clearlog`) and this file is its shell half; the suffix says which one you are looking at. It
  is also the one file there that is sourced and deliberately not executable.

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
