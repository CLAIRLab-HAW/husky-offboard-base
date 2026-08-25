# Shared base image for every container in deploy/ (Jazzy).
#
# The rule this file follows: it carries what ALL of them need, and nothing else.  Anything narrower belongs to the
# stage whose consumers actually want it -- every byte here is paid for by every deploy image.
#
#   - rmw_zenoh_cpp, the middleware the robot speaks -- and the only one anything here speaks
#   - python3-rich, the renderer behind libs/clearlog's Python handler
#   - the shared shell helpers: clearlog.sh, zenoh-connect.sh
#   - the shared ENV defaults (RMW, DOMAIN_ID, namespace, rcutils line format)
#
# Everything else lives in the `viewer` stage of deploy/husky-offboard/Dockerfile, where lite, offboard and
# mock-robot all inherit it -- still one place to change, one level further down:
#
#   noVNC desktop     Xvfb, x11vnc, novnc, websockify, fluxbox, xterm, Mesa, start-desktop.sh.  446 MB with its
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

# --- The two runtime dependencies every image shares ------------------------
# rmw_zenoh_cpp: the ENV block below names it as the default RMW, so it has to BE here.  Measured 2026-08-25 in
# this image without it, `ros2 topic list` aborted with "RMW implementation not installed (expected identifier of
# 'rmw_zenoh_cpp') ... librmw_zenoh_cpp.so: cannot open shared object file".  An image whose own default is
# unusable is a trap for the next person who runs a bare `docker run husky-offboard-base:jazzy`.
#
# python3-rich: libs/clearlog renders its Python handler through it (rich.console/rule/table/text).  Every
# container logs, display or not.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-rmw-zenoh-cpp \
        python3-rich \
    && rm -rf /var/lib/apt/lists/*

# --- shared shell helpers ---------------------------------------------------
# zenoh-connect.sh is THE one router logic for every container (ZENOH_LOCAL on the robot, ZENOH_STANDALONE for
# the isolated graph, ROBOT_ZENOH_ENDPOINT for a remote one).  deploy/app-runner copies the same file through a
# build context rather than keeping a second version of it.
COPY scripts/zenoh-connect.sh /usr/local/bin/zenoh-connect.sh
COPY scripts/clearlog.sh /usr/local/bin/clearlog.sh
RUN chmod +x /usr/local/bin/zenoh-connect.sh
# clearlog.sh is sourced, not executed -> deliberately no chmod +x, so nobody gets the idea to run it.

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
