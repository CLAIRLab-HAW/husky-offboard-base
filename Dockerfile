# Gemeinsames Basis-Image fuer husky-offboard und husky-offboard-lite (Jazzy).
#
# Enthaelt die Layer, die in beiden finalen Dockerfiles bisher byte-identisch
# (oder fast identisch) dupliziert waren:
#   - Clearpath apt-Repo + Keyring + rosdep-Liste
#   - GUI/noVNC-Stack: Xvfb + x11vnc + noVNC + websockify + fluxbox + Software-GL
#   - noVNC-Default 'resize=scale' (lokales Scaling im Browser)
#   - rg6_description (Greifer-Meshes) aus Source (onrobot-rg6)
#   - gemeinsamer noVNC-Desktop-Start (/usr/local/bin/start-desktop.sh)
#   - gemeinsame ENV-Defaults (RMW, DOMAIN_ID, Software-GL, DISPLAY, NS, noVNC-Geo)
#
# NICHT in der Base (final-spezifisch):
#   - clearpath-desktop / clearpath-manipulators  (offboard)
#   - rviz2 + moveit-ros-visualization + *-description  (lite)
#   - clearpath_generator_robot-Source-Build, plan-bridge/robot-contract  (offboard)
#   - rg6_control (Treiber)  -> offboard baut es inkrementell auf diesem Clone
#   - robot.yaml/Generatoren-Logik im Entrypoint  (offboard)
#   - ENTRYPOINT  -> jeder Final bringt seinen eigenen entrypoint.sh
#
# Verteilung: CI pusht nach ghcr.io/clairlab-haw/husky-offboard-base:jazzy.
# Finals referenzieren via  ARG BASE_IMAGE=ghcr.io/clairlab-haw/husky-offboard-base:jazzy
# und koennen lokal mit  --build-arg BASE_IMAGE=husky-offboard-base:jazzy  eine
# selbstgebaute Base nutzen (Offline/Entwicklung ohne Registry-Pull).
FROM ros:jazzy-ros-base

SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG RG6_REPO_URL=https://github.com/CLAIRLab-HAW/onrobot-rg6.git

# --- Clearpath apt-Repo + rosdep-Liste -------------------------------------
# Repo-Setup wie in husky-offboard/husky-offboard-lite. curl zusaetzlich (offboard
# zieht robot.yaml + Calib per curl; lite braucht es nicht, aber es ist klein
# und vereinheitlicht die Base).
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget curl gnupg lsb-release ca-certificates git \
        python3-colcon-common-extensions \
        ros-jazzy-xacro \
    && mkdir -p /etc/apt/keyrings \
    && wget -qO - https://packages.clearpathrobotics.com/public.key \
        | gpg --dearmor -o /etc/apt/keyrings/clearpath.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/clearpath.gpg] https://packages.clearpathrobotics.com/stable/ubuntu $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/clearpath-latest.list \
    && wget -q https://raw.githubusercontent.com/clearpathrobotics/public-rosdistro/master/rosdep/50-clearpath.list \
        -O /etc/ros/rosdep/sources.list.d/50-clearpath.list \
    && rm -rf /var/lib/apt/lists/*

# colcon ist in ros:jazzy-ros-base NICHT enthalten, der rg6-Build unten braucht
# es aber -> hier mitinstallieren (beide Finals ziehen es ohnehin; in der Base
# gezogen, damit der rg6_description-Build zuverlaessig laeuft).

# --- GUI: virtuelles X + VNC + noVNC + WM + Software-GL ---------------------
# Identisch zu den beiden finalen Dockerfiles. RViz/MoveIt laufen im Browser
# (http://localhost:6080/vnc.html) ueber Xvfb -> x11vnc -> websockify/noVNC,
# fluxbox als WM, Mesa llvmpipe als Software-GL (LIBGL_ALWAYS_SOFTWARE=1).
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb x11vnc novnc websockify fluxbox xterm \
        mesa-utils libgl1-mesa-dri \
        python3-rich \
    && rm -rf /var/lib/apt/lists/*

# --- noVNC per Default mit lokalem Scaling ---------------------------------
# noVNC defaultet ohne URL-Parameter ?resize= auf 'off' -> der Framebuffer wird
# 1:1 im Browser gezeigt und bei kleinerem Viewport beschnitten. Wir setzen den
# Default in app/ui.js ('off' -> 'scale'), sodass der Framebuffer lokal an die
# Browser-Fenstergroesse skaliert wird. URL (?resize=off|remote) und der
# Cookie-Override (Settings-Panel) haben weiter Vorrang. Byte-identisch zu
# beiden finalen Dockerfiles.
RUN sed -i "s/UI\.initSetting('resize', 'off')/UI.initSetting('resize', 'scale')/" \
        /usr/share/novnc/app/ui.js \
    && grep -q "UI.initSetting('resize', 'scale')" /usr/share/novnc/app/ui.js \
    && echo "[novnc] resize-Default -> scale (lokales Scaling)"

# --- rg6_description (Greifer-Meshes) aus Source ---------------------------
# Kein apt-Paket. Beide Finals brauchen rg6_description (package://-Aufloesung
# der Greifer-Meshes im URDF). Nur rg6_description bauen, NICHT rg6_control
# (Treiber) -> lite braucht ihn nicht, offboard baut ihn im Finalimage
# inkrementell auf diesem Clone weiter (--packages-up-to rg6_control zieht
# rg6_msgs als Dep mit; rg6_description explizit, da keine Dep von rg6_control).
# Die Selbstheilung in husky-offboard/entrypoint.sh bleibt als Sicherheitsnetz.
RUN git clone "$RG6_REPO_URL" /opt/onrobot-rg6 \
    && source /opt/ros/jazzy/setup.bash \
    && cd /opt/onrobot-rg6 \
    && colcon build --packages-select rg6_description \
    || echo "WARN: rg6_description-Build fehlgeschlagen -> Greifer bleibt ohne Mesh."

# --- gemeinsame Entrypoint-Bausteine (ausgelagert) --------------------------
# /usr/local/bin/start-desktop.sh startet Xvfb/fluxbox/x11vnc/websockify aus den
# ENV-Variablen (DISPLAY, NOVNC_WIDTH, NOVNC_HEIGHT). Beide finalen Entrypoints
# rufen es auf (start-desktop.sh offboard | start-desktop.sh lite), statt den
# Block zu duplizieren.
# /usr/local/bin/zenoh-connect.sh ist DIE eine Zenoh-Router-Logik aller
# Container (offboard, lite; app-runner kopiert sie per Build-Kontext) —
# RMW-Check, ZENOH_LOCAL=1 (auf dem Roboter), ROBOT_ZENOH_ENDPOINT.
COPY scripts/start-desktop.sh /usr/local/bin/start-desktop.sh
COPY scripts/zenoh-connect.sh /usr/local/bin/zenoh-connect.sh
COPY scripts/clearlog.sh /usr/local/bin/clearlog.sh
RUN chmod +x /usr/local/bin/start-desktop.sh /usr/local/bin/zenoh-connect.sh
# clearlog.sh wird gesourct, nicht ausgefuehrt -> bewusst kein chmod +x,
# damit niemand auf die Idee kommt, es zu starten.

# --- gemeinsame ENV-Defaults -----------------------------------------------
# RMW/DOMAIN_ID sind Defaults; Compose kann sie ueberschreiben (mock -> fastrtps).
# CLEARPATH_NS ist der Husky-Namespace; CLEARPATH_SETUP ist offboard-spezifisch
# und bleibt im offboard-Final. NOVNC_WIDTH/NOVNC_HEIGHT sind die einzige Quelle
# fuer die Desktop-Aufloesung (start-desktop.sh + RViz-Window-Geometry).
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp \
    ROS_DOMAIN_ID=0 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    DISPLAY=:1 \
    CLEARPATH_NS=a200_0553 \
    NOVNC_WIDTH=1600 \
    NOVNC_HEIGHT=900

# Bringt die rcutils-Ausgabe der ROS-Nodes auf dieselbe Spaltenfolge wie
# clearlog: Zeit, Level als Wort, Name, Text.  Zwei Grenzen bleiben --
# {time} sind Epoch-Sekunden (rcutils kennt kein strftime), und das Level
# ist ungepolstert (keine Breitenangaben).  Compose kann das ueberschreiben.
# RCUTILS_COLORIZED_OUTPUT wird bewusst NICHT gesetzt: unbelegt erkennt
# rcutils das Terminal selbst, genau wie clearlog.
ENV RCUTILS_CONSOLE_OUTPUT_FORMAT="{time}  {severity}  {name}  {message}"

EXPOSE 6080

# Kein ENTRYPOINT hier -> jeder Final bringt seinen eigenen entrypoint.sh
# (offboard generiert Clearpath-Setup aus robot.yaml, lite nicht).
CMD ["sleep", "infinity"]