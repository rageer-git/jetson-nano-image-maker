FROM ubuntu:20.04 as base

ENV DEBIAN_FRONTEND=noninteractive

# Fix CRÍTICO 1: Repos NVIDIA L4T PRIMERO (evita "Unable to locate package nvidia-l4t-*")
RUN apt-get update && apt-get install -y ca-certificates wget gnupg \
    && echo "deb https://repo.download.nvidia.com/jetson/common r32 main" > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && echo "deb https://repo.download.nvidia.com/jetson/t210 r32 main" >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list \
    && apt-key adv --fetch-keys https://repo.download.nvidia.com/jetson/gpgkey \
    && apt-get update

RUN mkdir -p /opt/nvidia/l4t-packages && touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall

COPY root/etc/apt/ /etc/apt
COPY root/usr/share/keyrings /usr/share/keyrings

# Core tools + L4T base (agrupado)
RUN apt-get install -y sudo ssh netplan.io udev parted net-tools kmod bridge-utils \
    && apt-get install -y -o Dpkg::Options::="--force-overwrite" \
    nvidia-l4t-core nvidia-l4t-init nvidia-l4t-bootloader nvidia-l4t-camera \
    nvidia-l4t-initrd nvidia-l4t-xusb-firmware nvidia-l4t-kernel \
    nvidia-l4t-kernel-dtbs nvidia-l4t-kernel-headers nvidia-l4t-cuda \
    jetson-gpio-common python3-jetson-gpio \
    && rm -rf /opt/nvidia/l4t-packages /var/lib/apt/lists/*

COPY root/etc/systemd/ /etc/systemd
COPY root/ /

RUN systemctl enable resizerootfs ssh systemd-networkd setup-resolve

# Fix CRÍTICO 2: Graphics/Vulkan + DIAG (Tegra GPU real!)
RUN apt-get update && apt-get install -y -o Dpkg::Options::="--force-overwrite" \
    nvidia-l4t-x11 nvidia-l4t-graphics-demos nvidia-l4t-libvulkan \
    nvidia-l4t-wayland nvidia-l4t-weston vulkan-tools mesa-utils \
    tegrastats nvpmodel locales tzdata \
    && rm -rf /opt/nvidia/l4t-packages /var/lib/apt/lists/*

# Fix 3: nvpmodel.conf (¡no más "Failed to read"!)
RUN cat > /etc/nvpmodel.conf << 'EOF'
[nvpmodels]
0=MAXN - (1260-1260 760-760 384-384)
1=MAXP - (1035-1035 668-668 384-384)
EOF

# Fix 4: Vulkan ICD NVIDIA Tegra (¡vulkaninfo → Tegra, no llvmpipe!)
RUN echo '{"file_format_version": "1.0.0", "ICD": {"library_path": "/usr/lib/aarch64-linux-gnu/libvulkan.so.1", "api_version": "1.3.261"}}' > /usr/share/vulkan/icd.d/nvidia_tegra_icd.json

# Usuario + home
RUN useradd -ms /bin/bash jetson && echo 'jetson:jetson' | chpasswd \
    && usermod -a -G sudo jetson \
    && chown -R jetson:jetson /home/jetson

# Desktop LIGERO Openbox + LightDM + audio (2GB OK)
RUN apt-get update && apt-get install -y \
    xorg openbox lightdm lxterminal xinit x11-xserver-utils dbus-x11 \
    alsa-utils pulseaudio pcmanfm fonts-dejavu fonts-noto git build-essential \
    libgl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

# Locale/TZ Chile
RUN sed -i 's/^# *es_CL.UTF-8 UTF-8/es_CL.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen es_CL.UTF-8 \
    && update-locale LANG=es_CL.UTF-8 LC_ALL=es_CL.UTF-8 \
    && ln -sf /usr/share/zoneinfo/America/Santiago /etc/localtime

# LightDM auto-login Openbox
RUN mkdir -p /etc/lightdm/lightdm.conf.d \
    && printf '%s\n' '[Seat:*]' 'autologin-user=jetson' 'autologin-user-timeout=0' 'user-session=openbox' \
    > /etc/lightdm/lightdm.conf.d/12-autologin.conf

RUN systemctl enable lightdm
