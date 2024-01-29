#!/bin/sh

# NOTE: USER may not always be defined
USER="$(whoami)"
#export USER

####

# Global settings
#
# This script is called just before post-processing begins. So setting environment variable values here
# overrides the values set anywhere else (in the configuration file, for example)
#
# To have a fallback value instead of overriding a value, do:
#     VAR1="${VAR1:-default_value1}"
#     export VAR1

# Share the queue lock file between tvheadend-post-processor.sh and tvheadend-post-processor-batch.sh.
# Set the path somewhere outside /tmp (/tmp is the default), in case /tmp has been set to "private"
# in the tvheadend.service systemd unit file.
if [ "$USER" = tvheadend ] && [ -d /etc/tvheadend/ ]; then
  QUEUE_LOCKFILE=/etc/tvheadend/tvheadend-post-processor/.lock
else
  QUEUE_LOCKFILE="${XDG_CONFIG_HOME:-$HOME/.config}/tvheadend-post-processor/.lock"
fi
export QUEUE_LOCKFILE

####
