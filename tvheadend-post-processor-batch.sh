#!/usr/bin/env bash

# Start or redo transcodings manually from outside Tvheadend.
# This is not a post-processor script for Tvheadend.
#
# This bash script depends on: getopt (util-linux) and tvheadend-post-processor.sh dependencies.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

# shellcheck disable=SC2016
usage() {
  printf 'USAGE:
  %s [OPTIONS]... RECORDING_FILE...

OPTIONS:
      --channel CHANNEL
  -c, --config CONFIG
  -f, --force-overwrite
  -o, --option HANDBRAKE_OPTION ...
  -q, --queue-transcoding
  -p, --post-processor SCRIPT
      --skip-user-check
  -w, --transcoding-path PATH

  For more details, run: tvheadend-post-processor.sh --help.

DESCRIPTION:
  Transcode recording files from outside Tvheadend.
  Recording files are not deleted after transcoding.
  The user that runs this script should be the same as the Tvheadend'\''s user, usually "hts" or "tvheadend".

EXAMPLES:
  sudo -u hts tvheadend-post-processor-batch.sh --config="$(pwd)/my-tvheadend-post-processor.conf" '\''recording1.ts'\''
  sudo -u hts tvheadend-post-processor-batch.sh --option=deinterlace --option=crop=0:0:0:0 --option='\''preset=Very Fast 1080p30'\'' '\''recording1.ts'\''
  sudo -u hts tvheadend-post-processor-batch.sh --user=tvheadend --force-overwrite /path/to/*.ts\n\n' "${0##*/}"
}

error_help() {
  printf "Try '%s --help' for more information.\n" "${0##*/}" >&2
}

# This script does not delete any recording file (keeps current recording file and disables cleanup of old recording files).
# Leave the cleanup of recording files up to the regular script: tvheadend-post-processor.sh [CLEANUP]
options=(--delete-recordings-after-days=0 --keep-recording --show-progress)

unset channel_name
unset handbrake_options
unset skip_user_check

postproscript=tvheadend-post-processor.sh

# Reuse the main post-processing script's queue
# Assumption: TMPDIR is the same value as in main post-processing script
TMPDIR="${TMPDIR:-/tmp}"
[ -v QUEUE_LOCKFILE ] || QUEUE_LOCKFILE="$TMPDIR/${postproscript##*/}.lock"
export QUEUE_LOCKFILE

if ! getopt_cmd="$(getopt --options c:fho:p:qu:w: --longoptions channel:,config:,force-overwrite,help,option:,post-processor:,queue-transcoding,skip-user-check,transcoding-path:,user: --name "${0##*/}" -- "$@")"; then
  #printf '%s: getopt internal error\n' "${0##*/}>&2
  error_help
  exit 1
fi
eval set -- "$getopt_cmd"
while true; do
  case "$1" in
    -f | --force-overwrite | -q | --queue-transcoding)
      options+=("$1")
      shift
      ;;
    -c | --config | -w | --transcoding-path)
      options+=("$1=$2")
      shift 2
      ;;
    --channel)
      channel_name="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -o | --option)
      if [ "${2:0:1}" = '-' ]; then
        handbrake_options+=("$2")
      else
        # Add missing - or -- before option value
        if [ "${2:1:1}" = '' ]; then
          handbrake_options+=("-$2")
        else
          handbrake_options+=("--$2")
        fi
      fi
      shift 2
      ;;
    -p | --post-processor)
      postproscript="$(command -v "$2")"
      shift 2
      ;;
    --skip-user-check)
      skip_user_check=1
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      printf '%s: getopt internal error\n' "${0##*/}" >&2
      error_help
      exit 1
      ;;
  esac
done
((skip_user_check)) && options+=(--skip-user-check)

# Check user here only once, instead of possibly multiple times inside the loop below
USER="$(whoami)"
if ((!skip_user_check)) && [ "$USER" != hts ] && [ "$USER" != tvheadend ]; then
  printf '%s: must be "hts" or "tvheadend" user to run this script\n' "${0##*/}" >&2
  error_help
  exit 1
fi

if (($# < 1)); then
  printf '%s: argument(s) missing\n' "${0##*/}" >&2
  error_help
  exit 1
fi

# Stop the script when pressing Ctrl-c to cancel
trap 'exit' INT

while [ -n "$1" ]; do
  "$postproscript" "${options[@]}" "${handbrake_options[@]}" OK "$1" "$channel_name" # || exit
  shift
done
