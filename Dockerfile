FROM ubuntu:20.04 as base

RUN apt update
RUN apt install -y ca-certificates

RUN apt install -y sudo
RUN apt install -y ssh
RUN apt install -y netplan.io

# resizerootfs f s
RUN apt install -y udev
RUN apt install -y parted

# ifconfig
RUN apt install -y net-tools

# needed by knod-static-nodes to create a list of static device nodes
RUN apt install -y kmod

# Install our resizerootfs service
COPY root/etc/systemd/ /etc/systemd

RUN systemctl enable resizerootfs
RUN systemctl enable ssh
RUN systemctl enable systemd-networkd
RUN systemctl enable setup-resolve

RUN mkdir -p /opt/nvidia/l4t-packages
RUN touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall

COPY root/etc/apt/ /etc/apt
COPY root/usr/share/keyrings /usr/share/keyrings
RUN apt update

# nv-l4t-usb-device-mode
RUN apt install -y bridge-utils

# L4T packages
RUN apt install -y -o Dpkg::Options::="--force-overwrite" \
    nvidia-l4t-core \
    nvidia-l4t-init \
    nvidia-l4t-bootloader \
    nvidia-l4t-camera \
    nvidia-l4t-initrd \
    nvidia-l4t-xusb-firmware \
    nvidia-l4t-kernel \
    nvidia-l4t-kernel-dtbs \
    nvidia-l4t-kernel-headers \
    nvidia-l4t-cuda \
    jetson-gpio-common \
    python3-jetson-gpio

RUN rm -rf /opt/nvidia/l4t-packages

COPY root/ /

# Usuario
RUN useradd -ms /bin/bash jetson
RUN echo 'jetson:jetson' | chpasswd
RUN usermod -a -G sudo jetson

# =========================
# CUSTOM: UI + ES + locale
# =========================
ENV DEBIAN_FRONTEND=noninteractive

# Paquetes mínimos para escritorio ligero + audio + herramientas build
RUN apt update && apt install -y \
    xorg \
    openbox \
    lightdm \
    lxterminal \
    xinit \
    x11-xserver-utils \
    dbus-x11 \
    alsa-utils \
    pulseaudio \
    locales \
    tzdata \
    git \
    build-essential \
    cmake \
    libsdl2-dev \
    libfreeimage-dev \
    libfreetype6-dev \
    libcurl4-openssl-dev \
    libasound2-dev \
    libgl1-mesa-dev \
    libudev-dev \
    fonts-dejavu \
    fonts-noto \
    pcmanfm \
    && rm -rf /var/lib/apt/lists/*

# Locale Español (Chile) + TZ Santiago
RUN sed -i 's/^# *es_CL.UTF-8 UTF-8/es_CL.UTF-8 UTF-8/' /etc/locale.gen || true
RUN locale-gen es_CL.UTF-8
RUN update-locale LANG=es_CL.UTF-8 LANGUAGE=es_CL:es LC_ALL=es_CL.UTF-8
RUN ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime

# Auto-login LightDM para Openbox
RUN mkdir -p /etc/lightdm/lightdm.conf.d
RUN printf '%s\\n' \
  '[Seat:*]' \
  'autologin-user=jetson' \
  'autologin-user-timeout=0' \
  'user-session=openbox' \
  > /etc/lightdm/lightdm.conf.d/12-autologin.conf

# =========================
# CUSTOM: EmulationStation (RetroPie fork)
# =========================
RUN apt update && apt install -y \
    libboost-system-dev libboost-filesystem-dev libboost-date-time-dev libboost-locale-dev libboost-thread-dev \
    libeigen3-dev libsm-dev libssl-dev \
    libx11-dev libxext-dev libxrandr-dev libxinerama-dev libxi-dev \
    libgl1-mesa-dev libegl1-mesa-dev \
    libvlc-dev libvlccore-dev vlc-plugin-base rapidjson-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --recursive https://github.com/RetroPie/EmulationStation.git /tmp/EmulationStation \
    && cd /tmp/EmulationStation \
    && cmake -DFREETYPE_INCLUDE_DIRS=/usr/include/freetype2/ . \
    && make -j"$(nproc)" \
    && install -m 0755 emulationstation /usr/local/bin/emulationstation \
    && rm -rf /tmp/EmulationStation

# Openbox autostart: lanzar EmulationStation
# Openbox ejecuta ~/.config/openbox/autostart al iniciar sesión. 
RUN mkdir -p /home/jetson/.config/openbox /home/jetson/bin
RUN printf '%s\\n' \
  '#!/bin/bash' \
  'xset -dpms' \
  'xset s off' \
  'xset s noblank' \
  '/home/jetson/bin/emulationstation.sh &' \
  > /home/jetson/.config/openbox/autostart
RUN chmod +x /home/jetson/.config/openbox/autostart

# Wrapper (por si luego quieres cambiar flags o lanzar primero algún script)
RUN printf '%s\\n' \
  '#!/bin/bash' \
  'exec /usr/local/bin/emulationstation' \
  > /home/jetson/bin/emulationstation.sh
RUN chmod +x /home/jetson/bin/emulationstation.sh

# Carpeta ROMs (simple: copias ROMs a /roms en la microSD)
RUN mkdir -p /roms && chown -R jetson:jetson /roms
RUN ln -sf /roms /home/jetson/roms

# Permisos del home
RUN chown -R jetson:jetson /home/jetson

# Habilitar LightDM para que arranque el entorno gráfico
RUN systemctl enable lightdm
