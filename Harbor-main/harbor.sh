#!/bin/sh

#############################
# Ubuntu Base Installation  #
#############################

# Define the root directory to /home/container.
# We can only write in /home/container and /tmp in the container.
ROOTFS_DIR=/home/container

# Define the Ubuntu Base release we are going to be using.
UBUNTU_SERIES="24.04"
UBUNTU_BASE_VERSION="24.04.4"
PROOT_VERSION="5.3.0" # Some releases do not have static builds attached.
DEFAULT_PACKAGES="ca-certificates curl nano sudo neofetch nginx git wget unzip zip less procps iproute2 net-tools locales tzdata bash-completion"

# Detect the machine architecture.
ARCH=$(uname -m)

# Check machine architecture to make sure it is supported.
# If not, we exit with a non-zero status code.
if [ "$ARCH" = "x86_64" ]; then
  ARCH_ALT=amd64
elif [ "$ARCH" = "aarch64" ]; then
  ARCH_ALT=arm64
else
  printf "Unsupported CPU architecture: ${ARCH}"
  exit 1
fi

# Download & decompress the Ubuntu Base root file system if not already installed.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    mkdir -p $ROOTFS_DIR $ROOTFS_DIR/usr/local/bin
    # Download Ubuntu Base root file system.
    curl -Lo /tmp/rootfs.tar.gz \
    "https://cdimage.ubuntu.com/ubuntu-base/releases/${UBUNTU_SERIES}/release/ubuntu-base-${UBUNTU_BASE_VERSION}-base-${ARCH_ALT}.tar.gz"
    # Extract the Ubuntu Base root file system.
    tar -xzf /tmp/rootfs.tar.gz -C $ROOTFS_DIR
fi

################################
# Package Installation & Setup #
################################

# Download extra tools used by Harbor.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Download the packages from their sources.
    curl -Lo /tmp/gotty.tar.gz "https://github.com/sorenisanerd/gotty/releases/download/v1.5.0/gotty_v1.5.0_linux_${ARCH_ALT}.tar.gz"
    curl -Lo $ROOTFS_DIR/usr/local/bin/proot "https://github.com/proot-me/proot/releases/download/v${PROOT_VERSION}/proot-v${PROOT_VERSION}-${ARCH}-static"
    # Extract everything that needs to be extracted.
    tar -xzf /tmp/gotty.tar.gz -C $ROOTFS_DIR/usr/local/bin
    # Make PRoot and GoTTY executable.
    chmod 755 $ROOTFS_DIR/usr/local/bin/proot $ROOTFS_DIR/usr/local/bin/gotty
fi

# Clean-up after installation complete & finish up.
if [ ! -e $ROOTFS_DIR/.installed ]; then
    # Add DNS Resolver nameservers to resolv.conf.
    printf "nameserver 1.1.1.1\nnameserver 1.0.0.1" > ${ROOTFS_DIR}/etc/resolv.conf
    # Wipe the files we downloaded into /tmp previously.
    rm -rf /tmp/rootfs.tar.gz /tmp/gotty.tar.gz
    # Create .installed to later check whether Ubuntu Base is installed.
    touch $ROOTFS_DIR/.installed
fi

# Ensure basic runtime paths exist for TUI apps/configs.
mkdir -p ${ROOTFS_DIR}/root/.config

# Pterodactyl + PRoot can block dpkg's safe backup/link behavior.
# Force unsafe I/O mode to avoid status-old backup failures.
mkdir -p ${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d ${ROOTFS_DIR}/etc/apt/apt.conf.d
printf "force-unsafe-io\n" > ${ROOTFS_DIR}/etc/dpkg/dpkg.cfg.d/99harbor-unsafe-io
printf "DPkg::Options { \"--force-unsafe-io\"; };\n" > ${ROOTFS_DIR}/etc/apt/apt.conf.d/99harbor-unsafe-io

# Map host primary GID to silence "cannot find name for group ID ..." warnings.
HOST_GID=$(id -g 2>/dev/null || true)
if [ -n "${HOST_GID}" ] && ! grep -qE "^[^:]+:[^:]*:${HOST_GID}:" "${ROOTFS_DIR}/etc/group"; then
    printf "hostgid%s:x:%s:root\n" "${HOST_GID}" "${HOST_GID}" >> "${ROOTFS_DIR}/etc/group"
fi

# Install requested/default packages on first run.
if [ ! -e $ROOTFS_DIR/.packages_installed ]; then
    printf "\nInstalling default Ubuntu packages. This can take a few minutes...\n"

    PROOT_NO_SECCOMP=1 \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/root \
    USER=root \
    XDG_CONFIG_HOME=/root/.config \
    $ROOTFS_DIR/usr/local/bin/proot \
    --rootfs="${ROOTFS_DIR}" \
    --link2symlink \
    --kill-on-exit \
    --root-id \
    --cwd=/root \
    --bind=/proc \
    --bind=/dev \
    --bind=/sys \
    --bind=/tmp \
    /bin/sh -lc "
set -e
rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend

# Some Pterodactyl runtimes block hardlinks in /var/lib/dpkg.
if ! ln /var/lib/dpkg/status /var/lib/dpkg/.harbor-linktest 2>/dev/null; then
  mkdir -p /tmp/dpkg-work
  cp -a /var/lib/dpkg/. /tmp/dpkg-work/
  rm -rf /var/lib/dpkg
  ln -s /tmp/dpkg-work /var/lib/dpkg
else
  rm -f /var/lib/dpkg/.harbor-linktest
fi

dpkg --force-unsafe-io --configure -a || true
apt -o Dpkg::Options::=\"--force-unsafe-io\" -f install -y || true
apt update
apt -o Dpkg::Options::=\"--force-unsafe-io\" install -y --no-install-recommends ${DEFAULT_PACKAGES}

# Install Docker CLI/engine package if available.
apt -o Dpkg::Options::=\"--force-unsafe-io\" install -y --no-install-recommends docker.io || true

# Prefer PHP 8.2 if available; fallback to distro default PHP.
if apt-cache show php8.2 >/dev/null 2>&1; then
  apt -o Dpkg::Options::=\"--force-unsafe-io\" install -y --no-install-recommends php8.2 php8.2-cli php8.2-fpm
else
  apt -o Dpkg::Options::=\"--force-unsafe-io\" install -y --no-install-recommends php php-cli php-fpm
fi

apt clean
rm -rf /var/lib/apt/lists/*
"

    touch $ROOTFS_DIR/.packages_installed
fi

# Print some useful information to the terminal before entering PRoot.
# This is to introduce the user with the various Ubuntu commands.
SHELL_BIN="/bin/bash"
if [ ! -x "$ROOTFS_DIR/bin/bash" ]; then
    SHELL_BIN="/bin/sh"
fi

clear && cat << EOF

 ██╗  ██╗ █████╗ ██████╗ ██████╗  ██████╗ ██████╗ 
 ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔═══██╗██╔══██╗
 ███████║███████║██████╔╝██████╔╝██║   ██║██████╔╝
 ██╔══██║██╔══██║██╔══██╗██╔══██╗██║   ██║██╔══██╗
 ██║  ██║██║  ██║██║  ██║██████╔╝╚██████╔╝██║  ██║
 ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
 
 Welcome to Ubuntu Base rootfs!
 This is a lightweight Ubuntu userspace environment running through PRoot.
 Default tools and common packages are auto-installed on first run.
 
 Here are some useful commands to get you started:
 
    apt install [package] : install a package
    apt remove [package] : remove a package
    apt update : update package lists
    apt upgrade : upgrade installed packages
    apt search [keyword] : search for a package
    apt show [package] : show package information
    gotty -p [server-port] -w ${SHELL_BIN##*/} : share your terminal
 
 If you run into any issues make sure to report them on GitHub!
 https://github.com/RealTriassic/Harbor
 
EOF

###########################
# Start PRoot environment #
###########################

# This command starts PRoot and binds several important directories
# from the host file system to our special root file system.
# Pterodactyl often blocks/limits some syscalls; disable seccomp acceleration
# so link emulation (--link2symlink) is consistently applied for dpkg.
PROOT_NO_SECCOMP=1 \
DEBIAN_FRONTEND=noninteractive \
LANG=C.UTF-8 \
LC_ALL=C.UTF-8 \
HOME=/root \
USER=root \
XDG_CONFIG_HOME=/root/.config \
$ROOTFS_DIR/usr/local/bin/proot \
--rootfs="${ROOTFS_DIR}" \
--link2symlink \
--kill-on-exit \
--root-id \
--cwd=/root \
--bind=/proc \
--bind=/dev \
--bind=/sys \
--bind=/tmp \
$SHELL_BIN
