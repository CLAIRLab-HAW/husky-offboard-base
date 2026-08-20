# Changelog — husky-offboard-base

What changed when. The current state is described in the [README](README.md).

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung [Semantic Versioning](https://semver.org/lang/de/).

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
