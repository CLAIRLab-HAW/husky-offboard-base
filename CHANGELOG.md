# Changelog — husky-offboard-base

What changed when. The current state is described in the [README](README.md).

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung [Semantic Versioning](https://semver.org/lang/de/).

## [Unreleased]

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
