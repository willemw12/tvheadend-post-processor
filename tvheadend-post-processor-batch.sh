#!/usr/bin/env sh

# Start or redo transcodings manually from outside Tvheadend.
# This is not a post-processor script for Tvheadend.
#
# This script depends on: getopt (util-linux), sudo.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

usage() {
  printf "Usage: %s [-c, --config CONFIG] [-d, --recording-path PATH] [-f, --force-overwrite] [-p, --post-processor SCRIPT] RECORDING_FILES\n\n" "${0##*/}" >&2
  printf "Transcode RECORDING_FILES from outside Tvheadend.\n\n"
  printf "Recording files are not deleted after transcoding.\n" >&2
  printf "The post-processor scripts are run by user 'hts'.\n"
}

help() {
  printf "Try '%s --help' for more information.\n" "${0##*/}" >&2
}

unset CONFIG_OPT
unset FORCE_OVERWRITE_OPT
#unset RECORDINGDIR
unset RECORDINGDIR_OPT
POSTPROSCRIPT=tvheadend-post-processor.sh
if ! GETOPT_CMD="$(getopt --options c:d:fhp: --longoptions config:,force-overwrite,help,post-processor:,recording-path: --name "${0##*/}" -- "$@")"; then
  #printf "%s: getopt internal error\n" "${0##*/}>&2
  help
  exit 1
fi
eval set -- "$GETOPT_CMD"
while true; do
  case "$1" in
    -c|--config)
      CONFIG_OPT="--config=$2"; shift 2;;
    -d|--recording-path)
      #RECORDINGDIR_OPT="--recording-path=$2"; RECORDINGDIR="$2"; shift 2;;
      RECORDINGDIR_OPT="--recording-path=$2"; shift 2;;
    -f|--force-overwrite)
      FORCE_OVERWRITE_OPT="--force-overwrite"; shift;;
    -h|--help)
      usage; exit 0;;
    -p|--post-processor)
      POSTPROSCRIPT="$(command -v "$2")"; shift 2;;
    --)
      shift; break;;
    *)
      printf "%s: getopt internal error\n" "${0##*/}" >&2; help; exit 1
  esac
done

# Avoid sudo timeout when run as non-root user
if [ "$(id -ru)" -ne 0 ]; then
  printf "%s: must be 'root' user to run this script\n" "${0##*/}" >&2
  help
  exit 1
fi

if [ $# -lt 1 ]; then
  printf "%s: argument(s) missing\n" "${0##*/}" >&2
  help
  exit 1
fi

#if [ -v RECORDINGDIR ]; then
#  for DIR in "$RECORDINGDIR/"{,"$VIDEO_PATH","$BACKUP_PATH"}; do
#    mkdir -p "$DIR"
#    chmod g+w "$DIR"
#    chown hts:video "$DIR"
#  done
#fi

# Stop the script when pressing Ctrl-c to cancel
trap "exit" INT

while [ -n "$1" ]; do
  # shellcheck disable=SC2086
  # Do not delete any recording file (keep current recording file and disable cleanup of old recording files)
  sudo --user=hts "$POSTPROSCRIPT" --keep-recording --delete-recordings-after-days=0 --show-progress $CONFIG_OPT $FORCE_OVERWRITE_OPT $RECORDINGDIR_OPT OK "$1"    # || exit
  shift
done

