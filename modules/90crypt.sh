#!/bin/bash
inst cryptsetup
inst_rules "$dsrc/rules.d/63-luks.rules"
inst_hook pre-mount 50 "$dsrc/hooks/cryptroot.sh"