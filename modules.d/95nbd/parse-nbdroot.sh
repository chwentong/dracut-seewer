#!/bin/sh
#
# Preferred format:
#	root=nbd:srv:port[:fstype[:rootflags[:nbdopts]]]
#	[root=*] netroot=nbd:srv:port[:fstype[:rootflags[:nbdopts]]]
#
# Legacy formats:
#	[net]root=[nbd] nbdroot=srv,port
#	[net]root=[nbd] nbdroot=srv:port[:fstype[:rootflags[:nbdopts]]]
#
# nbdopts is a comma seperated list of options to give to nbd-client
#
# root= takes precedence over netroot= if root=nbd[...]
#

# Sadly there's no easy way to split ':' separated lines into variables
netroot_to_var() {
    local v=${1}:
    set --
    while [ -n "$v" ]; do
        set -- "$@" "${v%%:*}"
        v=${v#*:}
    done

    unset server port 
    server=$2; port=$3;
}

# Don't continue if root is ok
[ -n "$rootok" ] && return

# This script is sourced, so root should be set. But let's be paranoid
[ -z "$root" ] && root=$(getarg root=)
[ -z "$netroot" ] && netroot=$(getarg netroot=)
[ -z "$nbdroot" ] && nbdroot=$(getarg nbdroot=)

# Root takes precedence over netroot
if [ "${root%%:*}" = "nbd" ] ; then
    if [ -n "$netroot" ] ; then
	warn "root takes precedence over netroot. Ignoring netroot"

    fi
    netroot=$root
fi

# If it's not empty or nbd we don't continue
[ -z "$netroot" ] || [ "${netroot%%:*}" = "nbd" ] || return

if [ -n "$nbdroot" ] ; then
    [ -z "$netroot" ]  && netroot=$root

    # Debian legacy style contains no ':' Converting is easy
    [ "$nbdroot" = "${nbdroot##*:}" ] && nbdroot=${nbdroot%,*}:${nbdroot#*,}

    # @deprecated
    warn "Argument nbdroot is deprecated and might be removed in a future release. See http://apps.sourceforge.net/trac/dracut/wiki/commandline for more information."

    # Accept nbdroot argument?
    [ -z "$netroot" ] || [ "$netroot" = "nbd" ] || \
	die "Argument nbdroot only accepted for empty root= or [net]root=nbd"

    # Override netroot with nbdroot content?
    [ -z "$netroot" ] || [ "$netroot" = "nbd" ] && netroot=nbd:$nbdroot
fi

# If it's not nbd we don't continue
[ "${netroot%%:*}" = "nbd" ] || return

# Check required arguments
netroot_to_var $netroot
[ -z "$server" ] && die "Argument server for nbdroot is missing"
[ -z "$port" ] && die "Argument port for nbdroot is missing"

# NBD actually supported?
incol2 /proc/devices nbd || modprobe nbd || die "nbdroot requested but kernel/initrd does not support nbd"

# Done, all good!
rootok=1

# Shut up init error check
[ -z "$root" ] && root="nbd"
