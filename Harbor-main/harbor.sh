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
