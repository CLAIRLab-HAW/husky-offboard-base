# Shared base image for every container in deploy/ (Jazzy).
#
# The rule this file follows: it carries what ALL of them need, and nothing else.  Anything narrower belongs to the
# stage whose consumers actually want it -- every byte here is paid for by every deploy image.
#
#   - rmw_zenoh_cpp, the middleware the robot speaks -- and the only one anything here speaks
#   - python3-rich, the renderer behind libs/clearlog's Python handler
#   - the shared shell helpers: clearlog, zenoh-connect
#   - the shared ENV defaults (RMW, DOMAIN_ID, namespace, rcutils line format)
#
# Everything else lives in the `viewer` stage of deploy/husky-offboard/Dockerfile, where lite, offboard and
# mock-robot all inherit it -- still one place to change, one level further down:
#
#   noVNC desktop     Xvfb, x11vnc, novnc, websockify, fluxbox, xterm, Mesa, start-desktop.  446 MB with its
#                     X11/Mesa closure (measured 2026-08-25 with `docker history`), and spact-logic is an action
#                     client with no display.
#   Clearpath apt     repo, keyring, rosdep list -- plus wget/gnupg/lsb-release and xacro, which exist here only
#                     to set it up and to build against it.  Measured 2026-08-26: the logic image has ZERO
#                     clearpath packages installed.
#   rg6_description   the gripper meshes.  Only the images that resolve package:// URIs out of the robot URDF want
#                     them, which is the same four stages as the desktop.
#
# git, curl and colcon (including python3-colcon-common-extensions, so `colcon build` works) come with
# ros:jazzy-ros-base -- measured 2026-08-26 in that image; naming them again would suggest they are ours.
#
# Distribution: CI pushes to ghcr.io/clairlab-haw/husky-offboard-base:jazzy.  The finals reference it via
# ARG BASE_IMAGE and can point at a locally built base with --build-arg BASE_IMAGE=husky-offboard-base:jazzy
# (offline/development without a registry pull).
FROM ros:jazzy-ros-base

SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
# Set by BuildKit. The apt cache mounts below are keyed on it: CI builds linux/amd64 AND linux/arm64, and .debs of
# two architectures in one cache directory would be a corrupt cache, not a fast one.
ARG TARGETARCH

# --- No package changelogs or examples, in this image and in every image built on it ---
# dpkg reads /etc/dpkg/dpkg.cfg.d/ on EVERY install, so one file here covers the derived stages as well.
#
# Be honest about the size of this: it is SMALL. /usr/share/doc is 172 MB in clearpath-offboard, and measured
# 2026-08-26, 159 MB of that are `copyright` files -- which the path-include below keeps on purpose, because this
# image is pushed to GHCR and shipping a binary without its licence text is not a size decision. Of the remaining
# 7 MB, most are changelogs from packages that ros:jazzy-ros-base installed before this config existed. What the
# exclusion actually buys is roughly a megabyte today, plus a cap on the next package that ships 50 MB of
# examples.
#
# man, info, locale and lintian are deliberately NOT excluded: 1-2 MB each, measured, and `man` in a debugging
# shell is worth more than that.
#
# Where the weight really sits, also measured 2026-08-26 and NOT removable: 57 `-dev` packages, 169 MB, in a
# runtime image -- libvtk9-dev, libomp-18-dev, libhdf5-dev, libpcl-dev and the boost dev chain. ROS debs declare
# them as hard runtime Depends (`libpcl-dev` <- `ros-jazzy-velodyne-pointcloud`), so apt would take the depending
# package with them. That is upstream packaging, not something to fix here.
RUN mkdir -p /etc/dpkg/dpkg.cfg.d \
    && printf 'path-exclude=/usr/share/doc/*\npath-include=/usr/share/doc/*/copyright\n' \
        > /etc/dpkg/dpkg.cfg.d/01_nodoc

# --- Let the downloaded .debs survive in a BuildKit cache mount --------------
# Every apt step in this image and in the derived stages mounts a cache at /var/cache/apt (see the RUNs below and
# in deploy/husky-offboard/Dockerfile). That only pays off if apt stops deleting what it downloaded, which the
# `docker-clean` hook shipped in Debian/Ubuntu images does after every install.
#
# Why bother: measured 2026-08-26 against the real stack, a rebuild of one invalidated apt layer spent 368 s of
# 577 s downloading and 168 s unpacking. In an isolated counter-test the same layer took 62 s cold and 23 s with
# the cache warm.
#
# The cache is a BUILD cache, not part of the image: nothing here ends up in a layer, and /var/lib/apt/lists stays
# out of the images entirely, which is why the apt steps no longer clean it themselves. On a machine that has
# never built this (a fresh CI runner) the cache is empty and the first build costs exactly what it did before.
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# --- The two runtime dependencies every image shares ------------------------
# rmw_zenoh_cpp: the ENV block below names it as the default RMW, so it has to BE here.  Measured 2026-08-25 in
# this image without it, `ros2 topic list` aborted with "RMW implementation not installed (expected identifier of
# 'rmw_zenoh_cpp') ... librmw_zenoh_cpp.so: cannot open shared object file".  An image whose own default is
# unusable is a trap for the next person who runs a bare `docker run husky-offboard-base:jazzy`.
#
# python3-rich: libs/clearlog renders its Python handler through it (rich.console/rule/table/text).  Every
# container logs, display or not.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=aptlists-${TARGETARCH} \
    apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-rmw-zenoh-cpp \
        python3-rich

# --- shared shell helpers ---------------------------------------------------
# zenoh-connect is THE one router logic for every container (ZENOH_LOCAL on the robot, ZENOH_STANDALONE for
# the isolated graph, ROBOT_ZENOH_ENDPOINT for a remote one).  deploy/app-runner copies the same file through a
# build context rather than keeping a second version of it.
#
# ready-banner derives an entrypoint's "ready. Tools: ..." line from what is actually on /usr/local/bin. It is
# here rather than in a final because ALL four entrypoints print that line, and a hand-kept list per entrypoint
# is how one of them ended up advertising a tool that had moved to another image.
#
# ros-env is THE one ROS source chain, for the same reason: every image that runs a ROS tool needs it, and each
# of its up to three overlays is guarded with `[ -f ... ]`, so the same file is correct where only the first
# stage exists (this image, spact-logic, deploy/app-runner) and where all three do (clearpath-offboard,
# clearpath-mock-robot).  A fresh `docker exec` shell has no ROS sourced, and a helper that skips the chain
# fails silently rather than loudly -- which is why it may not have a second version anywhere.
COPY scripts/zenoh-connect /usr/local/bin/zenoh-connect
COPY scripts/ready-banner /usr/local/bin/ready-banner
COPY scripts/clearlog /usr/local/bin/clearlog
COPY scripts/ros-env /usr/local/bin/ros-env
RUN chmod +x /usr/local/bin/zenoh-connect /usr/local/bin/ready-banner /usr/local/bin/ros-env
# clearlog is sourced, not executed -> deliberately no chmod +x, so nobody gets the idea to run it.
#
# It is also the ONE file on /usr/local/bin that keeps a suffix, and that is a decision rather than an oversight:
# `clearlog` is the name of a Python package in this workspace (libs/clearlog), and this is its shell half. The
# suffix says which one you are looking at. Everything else there is a command a human types -- view-moveit,
# teach-pose, zenoh-connect -- and commands do not carry file extensions.

# --- shared ENV defaults ----------------------------------------------------
# CLEARPATH_NS is the Husky namespace.  CLEARPATH_SETUP belongs to the roles that generate it and stays in the
# offboard stage; DISPLAY/LIBGL/NOVNC_* belong to `viewer`, with the packages they configure.
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp \
    ROS_DOMAIN_ID=0 \
    CLEARPATH_NS=a200_0553

# Brings the rcutils output of the ROS nodes onto the same column order as clearlog: time, level as a word, name,
# text.  Two limits remain -- {time} is epoch seconds (rcutils has no strftime) and the level is unpadded (no
# width specifiers).  Compose can override this.  RCUTILS_COLORIZED_OUTPUT is deliberately NOT set: left unset,
# rcutils detects the terminal itself, exactly like clearlog.
ENV RCUTILS_CONSOLE_OUTPUT_FORMAT="{time}  {severity}  {name}  {message}"

# No ENTRYPOINT here -> every final brings its own.
CMD ["sleep", "infinity"]
