# Rocky Linux 9 Kickstart for SIAB
# Automated installation configuration

# Use network installation
url --url="http://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/"

# System language
lang en_US.UTF-8

# Keyboard layout
keyboard us

# Network configuration
network --bootproto=dhcp --device=link --activate --onboot=on --hostname=siab-node

# Root password (will be changed by cloud-init)
rootpw --iscrypted $6$rounds=4096$saltysalt$YhslZniqKCLsMbJ9FqF.W3XPGkwR9G7d7cDqGqZRfLQxYLnKxKxJJ5JUPt5r1qyeOGkLMR7NmZS0vMKHmODdP/

# Timezone
timezone UTC --utc

# Use text mode installation
text

# Run the Setup Agent on first boot
firstboot --enable

# SELinux configuration
selinux --enforcing

# Firewall configuration
firewall --enabled --service=ssh

# Partition clearing
clearpart --all --initlabel

# Disk partitioning
# Using LVM for flexibility
part /boot --fstype=xfs --size=1024 --ondisk=sda
part /boot/efi --fstype=efi --size=600 --ondisk=sda --fsoptions="umask=0077,shortname=winnt"
part pv.01 --fstype=lvmpv --size=1 --grow --ondisk=sda

volgroup vg_system pv.01

logvol / --fstype=xfs --name=lv_root --vgname=vg_system --size=50000
logvol /var --fstype=xfs --name=lv_var --vgname=vg_system --size=30000
logvol /var/lib/rancher --fstype=xfs --name=lv_rancher --vgname=vg_system --size=100000 --grow
logvol swap --name=lv_swap --vgname=vg_system --size=8192

# Bootloader configuration
bootloader --location=mbr --boot-drive=sda --timeout=5

# Package selection
%packages --ignoremissing
@^minimal-environment
@core
curl
wget
git
tar
openssl
net-tools
bind-utils
policycoreutils-python-utils
container-selinux
iptables
chrony
audit
firewalld
yum-utils
device-mapper-persistent-data
lvm2
rsync
vim
tmux
htop
-NetworkManager-wifi
-NetworkManager-wwan
-aic94xx-firmware
-alsa-firmware
-ivtv-firmware
-iwl*firmware
%end

# Post-installation script
%post --log=/root/kickstart-post.log

# Update system
dnf update -y

# Configure chronyd for time sync
systemctl enable --now chronyd

# Enable audit
systemctl enable --now auditd

# Configure firewall
systemctl enable --now firewalld

# Set up SSH key directory
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Create SIAB directories
mkdir -p /opt/siab
mkdir -p /etc/siab
mkdir -p /var/log/siab

# Download SIAB installer
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh -o /opt/siab/install.sh
chmod +x /opt/siab/install.sh

# Create systemd service for SIAB auto-install
cat > /etc/systemd/system/siab-autoinstall.service <<'SIABEOF'
[Unit]
Description=SIAB Auto Installer
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/siab/install.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SIABEOF

# Enable SIAB auto-install (will run on first boot after network is up)
systemctl enable siab-autoinstall.service

# Create flag file for post-install detection
cat > /etc/siab/provisioned <<'FLAGEOF'
PROVISIONING_METHOD=kickstart
PROVISIONED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ROCKY_VERSION=$(cat /etc/rocky-release)
FLAGEOF

# Disable initial setup
systemctl disable initial-setup.service
systemctl disable initial-setup-graphical.service

# Clean up
dnf clean all

echo "Kickstart post-installation complete"

%end

# Reboot after installation
reboot --eject
