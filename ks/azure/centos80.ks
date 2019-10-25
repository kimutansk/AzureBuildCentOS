# Kickstart for provisioning a CentOS 8.0 Azure VM

# System authorization information
auth --enableshadow --passalgo=sha512

# Use graphical install
text

# Do not run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp

# Use network installation
url --url="http://olcentgbl.trafficmanager.net/centos/8.0.1905/BaseOS/x86_64/os/"
repo --name "BaseOS" --baseurl="http://olcentgbl.trafficmanager.net/centos/8.0.1905/BaseOS/x86_64/os/" --cost=100
repo --name="AppStream" --baseurl="http://olcentgbl.trafficmanager.net/centos/8.0.1905/AppStream/x86_64/os/" --cost=100

# Root password
rootpw --plaintext "to_be_disabled"

# System services
services --enabled="sshd,waagent,NetworkManager,systemd-resolved"

# System timezone
timezone Etc/UTC --isUtc

# Firewall configuration
firewall --disabled

# Enable SELinux
selinux --enforcing

# Don't configure X
skipx

# Power down the machine after install
poweroff

# Partitioning and bootloader configuration
# Note: biosboot and efi partitions are pre-created %pre to work around blivet issue
zerombr
bootloader --location=mbr --timeout=1
# part biosboot --onpart=sda14 --size=4
part /boot/efi --onpart=sda15 --fstype=vfat --size=500
part /boot --fstype="xfs" --size=500
part / --fstype="xfs" --size=1 --grow --asprimary

%pre --log=/var/log/anaconda/pre-install.log --erroronfail
#!/bin/bash

# Pre-create the biosboot and EFI partitions
sgdisk --clear /dev/sda
sgdisk --new=14:2048:10239 /dev/sda
sgdisk --new=15:10240:500M /dev/sda
sgdisk --typecode=14:EF02 /dev/sda
sgdisk --typecode=15:EF00 /dev/sda

%end


# Disable kdump
%addon com_redhat_kdump --disable
%end

%packages
WALinuxAgent
@base
@core
#@container-tools
chrony
sudo
parted
-dracut-config-rescue
-postfix
-NetworkManager-config-server
grub2-pc
grub2-pc-modules 
openssh-server
kernel
dnf-utils
rng-tools
cracklib
cracklib-dicts
centos-release

# pull firmware packages out
-aic94xx-firmware
-alsa-firmware
-alsa-lib
-alsa-tools-firmware
-ivtv-firmware
-iwl1000-firmware
-iwl100-firmware
-iwl105-firmware
-iwl135-firmware
-iwl2000-firmware
-iwl2030-firmware
-iwl3160-firmware
-iwl3945-firmware
-iwl4965-firmware
-iwl5000-firmware
-iwl5150-firmware
-iwl6000-firmware
-iwl6000g2a-firmware
-iwl6000g2b-firmware
-iwl6050-firmware
-iwl7260-firmware
-libertas-sd8686-firmware
-libertas-sd8787-firmware
-libertas-usb8388-firmware

# Some things from @core we can do without in a minimal install
-biosdevname
-plymouth
-iprutils

# enable rootfs resize on boot
cloud-utils-growpart
gdisk

%end


%post --log=/var/log/anaconda/post-install.log --erroronfail

#!/bin/bash

# Disable the root account
usermod root -p '!!'

# Set Base and AppStream repos to the Azure mirrors
sed -i 's/mirror.centos.org/olcentgbl.trafficmanager.net/'  /etc/yum.repos.d/CentOS-AppStream.repo
sed -i 's/^mirrorlist/#mirrorlist/'                         /etc/yum.repos.d/CentOS-AppStream.repo
sed -i 's/^#baseurl/baseurl/'                               /etc/yum.repos.d/CentOS-AppStream.repo

sed -i 's/mirror.centos.org/olcentgbl.trafficmanager.net/'  /etc/yum.repos.d/CentOS-Base.repo
sed -i 's/^mirrorlist/#mirrorlist/'                         /etc/yum.repos.d/CentOS-Base.repo
sed -i 's/^#baseurl/baseurl/'                               /etc/yum.repos.d/CentOS-Base.repo

# Import CentOS public key
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

# Set the kernel cmdline
sed -i 's/^\(GRUB_CMDLINE_LINUX\)=".*"$/\1="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0 scsi_mod.use_blk_mq=y"/g' /etc/default/grub

# Enable grub serial console
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub
sed -i 's/^GRUB_TERMINAL_OUTPUT=".*"$/GRUB_TERMINAL="serial console"/g' /etc/default/grub

# Enable BIOS bootloader
rm -f /boot/grub2/grubenv
cp /boot/efi/EFI/centos/grubenv /boot/grub2/grubenv
grub2-install --target=i386-pc --directory=/usr/lib/grub/i386-pc/ /dev/sda
grub2-mkconfig --output=/boot/grub2/grub.cfg

 # Fix grub.cfg to remove EFI entries, otherwise "boot=" is not set correctly and blscfg fails
 EFI_ID=`blkid --match-tag UUID --output value /dev/sda15`
 BOOT_ID=`blkid --match-tag UUID --output value /dev/sda1`
 sed -i 's/gpt15/gpt1/' /boot/grub2/grub.cfg
 sed -i "s/${EFI_ID}/${BOOT_ID}/" /boot/grub2/grub.cfg

# Blacklist the nouveau driver
cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

# Ensure Hyper-V drivers are built into initramfs
echo '# Ensure Hyper-V drivers are built into initramfs'	>> /etc/dracut.conf.d/azure.conf
echo -e "\nadd_drivers+=\"hv_vmbus hv_netvsc hv_storvsc\""	>> /etc/dracut.conf.d/azure.conf
kversion=$( rpm -q kernel | sed 's/kernel\-//' )
dracut -v -f "/boot/initramfs-${kversion}.img" "$kversion"

# Enable SSH keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=yes
PERSISTENT_DHCLIENT=yes
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
EOF

# Disable NetworkManager handling of the SRIOV interfaces
cat <<EOF > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules

# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"

EOF

# Enable PTP with chrony for accurate time sync
echo -e "\nrefclock PHC /dev/ptp0 poll 3 dpoll -2 offset 0\n" >> /etc/chrony.conf

# Enable DNS cache
sed -i 's/hosts:\s*files dns myhostname/hosts:      files resolve dns myhostname/' /etc/nsswitch.conf

# Update dnf configuration
echo "http_caching=packages" >> /etc/dnf/dnf.conf
dnf clean all

# Set tuned profile
echo "virtual-guest" > /etc/tuned/active_profile

# Deprovision and prepare for Azure
/usr/sbin/waagent -force -deprovision

%end
