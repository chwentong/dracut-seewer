#!/bin/bash
TEST_DESCRIPTION="root filesystem over iSCSI"

KVERSION=${KVERSION-$(uname -r)}

#DEBUGFAIL="rdinitdebug rdnetdebug rdudevinfo"

run_server() {
    # Start server first
    echo "iSCSI TEST SETUP: Starting DHCP/iSCSI server"

    $testdir/run-qemu -hda server.ext2 -hdb root.ext2 -m 128M -nographic \
	-net nic,macaddr=52:54:00:12:34:56,model=e1000 \
	-net socket,mcast=230.0.0.1:1234 \
	-serial udp:127.0.0.1:9999 \
	-kernel /boot/vmlinuz-$KVERSION \
	-append "root=/dev/sda rw quiet console=ttyS0,115200n81" \
	-initrd initramfs.server -pidfile server.pid -daemonize || return 1
    sudo chmod 644 server.pid || return 1

    # Cleanup the terminal if we have one
    tty -s && stty sane

    echo Sleeping 10 seconds to give the server a head start
    sleep 10
}

run_client() {

    # Need this so kvm-qemu will boot (needs non-/dev/zero local disk)
    if ! dd if=/dev/zero of=client.img bs=1M count=1; then
	echo "Unable to make client sda image" 1>&2
	return 1
    fi

    $testdir/run-qemu -hda client.img -m 128M -nographic \
  	-net nic,macaddr=52:54:00:12:34:00,model=e1000 \
  	-net socket,mcast=230.0.0.1:1234 \
  	-kernel /boot/vmlinuz-$KVERSION \
	-append "root=dhcp rw quiet console=ttyS0,115200n81 $DEBUGFAIL" \
  	-initrd initramfs.testing
    grep -m 1 -q iscsi-OK client.img || return 1
}

test_run() {
    if ! run_server; then
	echo "Failed to start server" 1>&2
	return 1
    fi
    run_client
    if [[ -s server.pid ]]; then
	sudo kill -TERM $(cat server.pid)
	rm -f server.pid
    fi
}

test_setup() {
    if [ ! -x /usr/sbin/iscsi-target ]; then
	echo "Need iscsi-target from netbsd-iscsi"
	return 1
    fi

    # Create the blank file to use as a root filesystem
    dd if=/dev/zero of=root.ext2 bs=1M count=20

    kernel=$KVERSION
    # Create what will eventually be our root filesystem onto an overlay
    (
	initdir=overlay/source
	. $basedir/dracut-functions
	dracut_install sh shutdown poweroff stty cat ps ln ip \
        	/lib/terminfo/l/linux mount dmesg mkdir \
		cp ping grep
	inst ./client-init /sbin/init
	(cd "$initdir"; mkdir -p dev sys proc etc var/run tmp )
	ldconfig -n -r "$initdir" /lib* /usr/lib*
    )
 
    # second, install the files needed to make the root filesystem
    (
	initdir=overlay
	. $basedir/dracut-functions
	dracut_install sfdisk mke2fs poweroff cp umount 
	inst_simple ./create-root.sh /pre-mount/01create-root.sh
    )
 
    # create an initramfs that will create the target root filesystem.
    # We do it this way so that we do not risk trashing the host mdraid
    # devices, volume groups, encrypted partitions, etc.
    $basedir/dracut -l -i overlay / \
	-m "dash crypt lvm mdraid udev-rules base rootfs-block" \
	-d "ata_piix ext2 sd_mod" \
	-f initramfs.makeroot $KVERSION || return 1
    rm -rf overlay


    # Need this so kvm-qemu will boot (needs non-/dev/zero local disk)
    if ! dd if=/dev/zero of=client.img bs=1M count=1; then
	echo "Unable to make client sdb image" 1>&2
	return 1
    fi
    # Invoke KVM and/or QEMU to actually create the target filesystem.
    $testdir/run-qemu -hda root.ext2 -hdb client.img -m 128M -nographic -net none \
	-kernel "/boot/vmlinuz-$kernel" \
	-append "root=/dev/dracut/root rw rootfstype=ext2 quiet console=ttyS0,115200n81" \
	-initrd initramfs.makeroot  || return 1
    grep -m 1 -q dracut-root-block-created client.img || return 1
    rm client.img
    (
	initdir=overlay
	. $basedir/dracut-functions
	dracut_install poweroff shutdown
	inst_simple ./hard-off.sh /emergency/01hard-off.sh
#	inst ./cryptroot-ask /sbin/cryptroot-ask
    )
#	-m "debug dash crypt lvm mdraid udev-rules base rootfs-block iscsi" \
    sudo $basedir/dracut -l -i overlay / \
	-m "debug dash udev-rules base rootfs-block iscsi" \
	-d "ata_piix ext2 sd_mod" \
	-f initramfs.testing $KVERSION || return 1

    # Make server root
    dd if=/dev/zero of=server.ext2 bs=1M count=60
    mke2fs -F server.ext2
    mkdir mnt
    sudo mount -o loop server.ext2 mnt

    kernel=$KVERSION
    (
    	initdir=mnt
	. $basedir/dracut-functions
	(
	    cd "$initdir";
	    mkdir -p dev sys proc etc var/run tmp var/lib/dhcpd /etc/iscsi
	)
	inst /etc/passwd /etc/passwd
	dracut_install sh ls shutdown poweroff stty cat ps ln ip \
	    /lib/terminfo/l/linux dmesg mkdir cp ping \
	    modprobe tcpdump \
	    /etc/services sleep mount chmod
	dracut_install /usr/sbin/iscsi-target
	instmods iscsi_tcp crc32c ipv6
        inst ./targets /etc/iscsi/targets
#	inst ./root.ext2 /
	[ -f /etc/netconfig ] && dracut_install /etc/netconfig 
	which dhcpd >/dev/null 2>&1 && dracut_install dhcpd
	[ -x /usr/sbin/dhcpd3 ] && inst /usr/sbin/dhcpd3 /usr/sbin/dhcpd
	inst ./server-init /sbin/init
	inst ./hosts /etc/hosts
	inst ./dhcpd.conf /etc/dhcpd.conf
	dracut_install /etc/nsswitch.conf /etc/rpc /etc/protocols
	inst /etc/group /etc/group

	/sbin/depmod -a -b "$initdir" $kernel
	ldconfig -n -r "$initdir" /lib* /usr/lib*
    )

    sudo umount mnt
    rm -fr mnt


    # Make server's dracut image
    $basedir/dracut -l -i overlay / \
	-m "dash udev-rules base rootfs-block debug" \
	-d "ata_piix ext2 sd_mod e1000" \
	-f initramfs.server $KVERSION || return 1

}

test_cleanup() {
    if [[ -s server.pid ]]; then
	sudo kill -TERM $(cat server.pid)
	rm -f server.pid
    fi
    rm -rf mnt overlay
    rm -f client.ext2 server.ext2 client.img initramfs.server initramfs.testing
    rm -f initramfs.makeroot root.ext2
}

. $testdir/test-functions
