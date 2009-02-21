#!/bin/bash
# FIXME: hard-coded module list of doom.
instmods ${modules:-=ata =block =drm dm-crypt aes sha256 cbc}

# Grab modules for all filesystem types we currently have mounted
while read d mp t rest; do
    instmods "$t"
done </proc/mounts