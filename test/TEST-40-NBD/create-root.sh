#!/bin/sh
# don't let udev and this script step on eachother's toes
for x in 63-luks.rules 64-lvm.rules 70-mdadm.rules 99-mount-rules; do
    > "/etc/udev/rules.d/$x"
done
udevadm control --reload-rules
echo -n test >keyfile
cryptsetup -q luksFormat /dev/sdb /keyfile
echo "The passphrase is test"
cryptsetup luksOpen /dev/sdb dracut_crypt_test </keyfile && \
lvm pvcreate -ff  -y /dev/mapper/dracut_crypt_test && \
lvm vgcreate dracut /dev/mapper/dracut_crypt_test && \
lvm lvcreate -l 100%FREE -n root dracut && \
lvm vgchange -ay && \
mke2fs -j /dev/dracut/root && \
mkdir -p /sysroot && \
mount /dev/dracut/root /sysroot && \
cp -a -t /sysroot /source/* && \
umount /sysroot && \
lvm lvchange -a n /dev/dracut/root && \
cryptsetup luksClose /dev/mapper/dracut_crypt_test && \
echo "dracut-root-block-created" >/dev/sda
poweroff -f
