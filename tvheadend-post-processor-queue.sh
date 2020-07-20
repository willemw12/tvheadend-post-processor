#!/usr/bin/env sh

# A Tvheadend post-processor script
#
# This script depends on: task-spooler.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

POSTPROSCRIPT=tvheadend-post-processor.sh

if [ $# -ge 1 ]; then
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    printf "Transcode a recording file. Transcodings are performed sequentially instead of in parallel.\n" >&2
    printf "Try 'tvheadend-post-processor.sh --help' for more information.\n" >&2
  fi
  exit 0
fi

USER="$(whoami)"
if [ "$USER" != "hts" ]; then
  printf "%s: must be 'hts' user to run this script\n" "${0##*/}" >&2
  exit 1
fi

##tsp -nf sh -c "$POSTPROSCRIPT $@"
#CMD="$POSTPROSCRIPT $@"
CMD="$POSTPROSCRIPT $*"
tsp -nf sh -c "$CMD"

