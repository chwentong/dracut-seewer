#!/bin/sh
#
# Format:
#	ip=[dhcp|on|any]
#
#	ip=<interface>:[dhcp|on|any]
#
#	ip=<client-IP-number>:<server-id>:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:[dhcp|on|any|none|off]
#
# When supplying more than only ip= line, <interface> is mandatory and
# bootdev= must contain the name of the primary interface to use for
# routing,dns,dhcp-options,etc.
#

# Sadly there's no easy way to split ':' separated lines into variables
ip_to_var() {
    local v=${1}:
    set --
    while [ -n "$v" ]; do
	set -- "$@" "${v%%:*}"
	v=${v#*:}
    done

    unset ip srv gw mask hostname dev autoconf
    case $# in
    0)	autoconf="error" ;;
    1)	autoconf=$1 ;;
    2)	dev=$1; autoconf=$2 ;;
    *)	ip=$1; srv=$2; gw=$3; mask=$4; hostname=$5; dev=$6; autoconf=$7 ;;
    esac
}

# Check if ip= lines should be used
if getarg ip= >/dev/null ; then
    if [ -z "$netroot" ] ; then
	echo "Warning: No netboot configured, ignoring ip= lines"
	return;
    fi
fi

# Don't mix BOOTIF=macaddr from pxelinux and ip= lines
getarg ip= >/dev/null && getarg BOOTIF= >/dev/null && \
    die "Mixing BOOTIF and ip= lines is dangerous"

# No more parsing stuff, BOOTIF says everything
[ -n "$(getarg BOOTIF)" ] && return

# Warn if defaulting to ip=dhcp
if [ -n "$netroot" ] && [ -z "$(getarg ip=)" ] ; then
    warn "No ip= argument(s) for netroot provided, defaulting to DHCP"
    return;
fi

# Count ip= lines to decide whether we need bootdev= or not
if [ -z "$NEEDBOOTDEV" ] ; then
    [ "$CMDLINE" ] || read CMDLINE < /proc/cmdline
    local count=0
    for p in $CMDLINE; do
	[ "${p%%=*}" = "ip" ] && count=$(( $count + 1 ))
    done
    [ $count -gt 1 ] && NEEDBOOTDEV=1
fi

# If needed, check if bootdev= contains anything usable
if [ -n "$NEEDBOOTDEV" ] ; then
    BOOTDEV=$(getarg bootdev=) || die "Please supply bootdev argument for multiple ip= lines"
    [ -z "$BOOTDEV" ] && die "Bootdev argument is empty"
fi

# Check ip= lines
# XXX Would be nice if we could errorcheck ip addresses here as well
[ "$CMDLINE" ] || read CMDLINE < /proc/cmdline
for p in $CMDLINE; do
    [ -n "${p%ip=*}" ] && continue

    ip_to_var ${p#ip=}

    # We need to have an ip= line for the specified bootdev
    [ -n "$NEEDBOOTDEV" ] && [ "$dev" = "$BOOTDEV" ] && BOOTDEVOK=1

    # Empty autoconf defaults to 'dhcp'
    if [ -z "$autoconf" ] ; then
	warn "Empty autoconf values default to dhcp"
	autoconf="dhcp"
    fi

    # Error checking for autoconf in combination with other values
    case $autoconf in
	error) die "Error parsing option '$p'";;
	bootp|rarp|both) die "Sorry, ip=$autoconf is currenty unsupported";;
	none|off) \
	    [ -z "$ip" ] && \
		die "For argument '$p'\nValue '$autoconf' without static configuration does not make sense"
	    [ -z "$mask" ] && \
		die "Sorry, automatic calculation of netmask is not yet supported"
	    ;;
	dhcp|on|any) \
	    [ -n "$NEEDBOOTDEV" ] && [ -z "$dev" ] && \
	        die "Sorry, '$p' does not make sense for multiple interface configurations"
	    [ -n "$ip" ] && \
		die "For argument '$p'\nSorry, setting client-ip does not make sense for '$autoconf'"
	    ;;
	*) die "For argument '$p'\nSorry, unknown value '$autoconf'";;
    esac

    if [ -n "$dev" ] ; then
        # We don't like duplicate device configs
	if [ -n "$IFACES" ] ; then
	    for i in $IFACES ; do
		[ "$dev" = "$i" ] && die "For argument '$p'\nDuplication configurations for '$dev'"
	    done
	fi
	# IFACES list for later use
	IFACES="$IFACES $dev"
    fi

    # Small optimization for udev rules
    [ -z "$NEEDBOOTDEV" ] && [ -n "$dev" ] && BOOTDEV=$dev

    # Do we need to check for specific options?
    if [ -n "$NEEDDHCP" ] || [ -n "$DHCPORSERVER" ] ; then
	# Correct device? (Empty is ok as well)
	[ "$dev" = "$BOOTDEV" ] || continue
	# Server-ip is there?
	[ -n "$DHCPORSERVER" ] && [ -n "$srv" ] && continue
	# dhcp? (It's simpler to check for a set ip. Checks above ensure that if
	# ip is there, we're static
	[ -z "$ip" ] && continue
	# Not good!
	die "Server-ip or dhcp for netboot needed, but current arguments say otherwise"
    fi

done

# This ensures that BOOTDEV is always first in IFACES
if [ -n "$BOOTDEV" ] && [ -n "$IFACES" ] ; then 
    IFACES="${IFACES%$BOOTDEV*} ${IFACES#*$BOOTDEV}"
    IFACES="$BOOTDEV $IFACES"
fi

# Store BOOTDEV and IFACES for later use
[ -n "$BOOTDEV" ] && echo $BOOTDEV > /tmp/net.bootdev
[ -n "$IFACES" ]  && echo $IFACES > /tmp/net.ifaces

# We need a ip= line for the configured bootdev= 
[ -n "$NEEDBOOTDEV" ] && [ -z "$BOOTDEVOK" ] && die "Bootdev Argument '$BOOTDEV' not found"