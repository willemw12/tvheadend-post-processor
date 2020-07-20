#!/usr/bin/env bash

# A simple wrapper example script for dealing with channel specific transcoding options.
# It uses the Tvheadend's post-processor format string "%c" to achieve this.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3
#
#
# For example:
#    - Record in 720p by default, except when the channel name ends on " HD" and
#    - Crop away white dashes at the top the recording for one specific channel
#
# Setup:
#   - In Tvheadend's web interface menu "Configuration" --> "Recording":
#       Post-processor command = my-tvheadend-post-processor.sh --keep-recording "%e" "%f" "%c"
#
#   - Define default transcoding options:
#       File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf:
#           ...
#           OPTIONS=(--deinterlace --crop=0:0:0:0 --preset="Very Fast 720p30")
#
#   - Either define channel specific transcoding options in separate config files:
#       File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor-1080p.conf:
#           ...
#           OPTIONS=(--deinterlace --crop=0:0:0:0 --preset="Very Fast 1080p30")
#
#       File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor-crop.conf:
#           ...
#           OPTIONS=(--deinterlace --crop=1:0:0:0 --preset="Very Fast 720p30")
#
#       Pass the channel specific config file as command line argument in the case-statement below (commented out).
#
#   - or pass the channel specific options directly as command line arguments in the case-statement below.

#CMD=tvheadend-post-processor-queue.sh
CMD=tvheadend-post-processor.sh

####

help() {
  printf "See setup comments in this script\n" >&2
}

if [ $# -lt 3 ]; then
  printf "%s: argument(s) missing\n" "$(basename "$0")" >&2
  help
  exit 1
fi

USER="$(whoami)"
if [ "$USER" != "hts" ]; then
  printf "%s: must be user 'hts' to run this script\n" "$(basename "$0")" >&2
  help
  exit 1
fi

POSPARAMS=("$@")
# Last parameter
CHANNEL_NAME="${POSPARAMS[${#POSPARAMS[@]}-1]}"

#HD_CHANNEL_NAMES="BBC * HD"

case "$CHANNEL_NAME" in
  # Examples containing space and wildcard characters (* and ?):
  #     BBC\ ?\ HD)
  #     "BBC "*" HD")
  #     $HD_CHANNEL_NAMES)

  *\ HD)
    #$CMD --keep-recording --config=tvheadend-post-processor-1080p.conf "$@"
    $CMD --keep-recording --option="preset=Very Fast 1080p30" "$@"
    ;;
  Example\ channel\ name)
    #$CMD --keep-recording --config=tvheadend-post-processor-crop.conf "$@"
    $CMD --keep-recording --option="crop=1:0:0:0" "$@"
    ;;
  -h|--help)
    help
    ;;
  *)
    # Default
    $CMD "$@"
    #;;
esac

