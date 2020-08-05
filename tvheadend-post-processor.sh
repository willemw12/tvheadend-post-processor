#!/usr/bin/env bash

# Transcode a recording file to a video file.
# The script is invoked from Tvheadend.
#
# This script depends on: ffmpeg, getopt (util-linux), handbrake-cli.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

# shellcheck disable=SC2174

usage() {
  printf "USAGE:\n  %s [OPTION]... RECORDING_MESSAGE RECORDING_FILE\n\n" "${0##*/}" >&2

  printf "OPTIONS:
  -c, --config CONFIG
          Use an absolute configuration path
          or a path relative to \$XDG_CONFIG_HOME/tvheadend-post-processor (for user 'hts')
          or relative to /home/hts/.config/tvheadend-post-processor.
  -d, --transcoding-path TRANSCODING_PATH
          The transcoding work folder during post-processing.
  --delete-recordings-after-days DAYS
          Whenever this script is called, cleanup recordings (*.ts files) that were kept after post-processing.
          See option -k, --keep-recording.
          DAYS is 1, 2, etc.: enables this option. DAYS is 0: disables this option.
          The number of days is compared against the file's modification time (find -mtime),
          not against the date in the filename.
  -f, --force-overwrite
  -h, --help
  -k, --keep-recording
  -o, --option \"HANDBRAKE_OPTION1\" ...
          Options --format, --input and --output are ignored.
          For example, --option=\"--deinterlace\" --option=\"crop=0:0:0:0\" --option=\"preset=Very Fast 1080p30\"
  -p, --show-progress
  -t, --type VIDEO_TYPE (mkv or mp4)

ARGUMENTS:
  RECORDING_MESSAGE
          \"CLEANUP\": cleanup old recordings (*.ts files) only. See option --delete-recordings-after-days.
          \"OK\": perform post-processing.
  RECORDING_FILE
          .ts file

DESCRIPTION:
  This script, run by Tvheadend as user 'hts', transcodes a recording file to a video file.
  The recording file, if kept, can be moved to a backup folder after successful transcoding.

CONFIGURATION:
  Setup example in Tvheadend's web interface menu \"Configuration\" --> \"Recording\":
          Post-processor command = tvheadend-post-processor.sh --keep-recording \"%%e\" \"%%f\"

  Default configuration file location:
          \$XDG_CONFIG_HOME/tvheadend-post-processor/tvheadend-post-processor.conf (for user 'hts')
          or else /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf.

  To create the default configuration file manually, run:
          sudo -u hts tvheadend-post-processor.sh

  Executable pre-transcoding and post-transcoding scripts (*.sh files) can be placed in folders \"pre-scripts.d\" and
  \"post-scripts.d\", located in the configuration folder or else in one of the default configuration folders.
  These scripts are run in alphabetical order. Scripts in \"post-scripts.d\" are only run after successful transcoding
  and the transcoded video filename is passed as the first argument.

  File ownership is by default: user 'hts', group 'video'. Note: the user or group may be different.
  Set the file ownership of folders (configuration options BACKUP_PATH, ERROR_PATH and VIDEO_PATH), if necessary:
          sudo chown hts:video ...
  Optionally, to allow a user to move or delete files created by user 'hts', add the user name to group 'video' and
  relogin:
          sudo usermod -aG video user1
  and allow group write permission on folders:
          sudo chmod g+w ...\n\n" >&2

  printf "MANUAL TRANSCODING:
  To manually start transcoding or redo transcoding, use tvheadend-post-processor-batch.sh (see option --help),
  or run this post-processor script directly, for example:
          sudo -u hts %s --keep-recording --show-progress --config=\"\$(pwd)/my-tvheadend-post-processor.conf\" \"OK\" recording1.ts
          sudo -u hts %s --keep-recording --show-progress --option=\"deinterlace\" --option=\"crop=0:0:0:0\" --option=\"preset=Very Fast 1080p30\" \"OK\" recording1.ts\n\n" "${0##*/}" "${0##*/}" >&2
}

help() {
  printf "Try '%s --help' for more information.\n" "${0##*/}" >&2
}

is_true() {
  # Convert to lowercase
  BOOL="${1,,}"

  [ "$BOOL" = "false" ] || [ "$BOOL" = "no" ] || [ "$BOOL" = "0" ] || [ "$BOOL" = "" ] || return 0    # Return true
  return 1    # Return false
}

is_false() {
  is_true "$1" && return 1    # Return false
  return 0    # Return true
}

unset TRAP_MSG_PRINTED

print_trap_msg() {
  if [ $? -ne 0 ] && [ ! -v TRAP_MSG_PRINTED ]; then
    printf "%s: error, while running as user '%s'\n" "${0##*/}" "$(whoami)"
    TRAP_MSG_PRINTED=""
  fi
}

set_trap() {
  #USER="$(whoami)"
  ##trap "printf \"%s: error, while running as user '%s'\n\" \"${0##*/}\" \"$USER\"" ERR
  #trap 'printf "%s: error, while running as user \"%s\"\n" "${0##*/}" "$USER"' ERR

  trap 'print_trap_msg' EXIT
}

set_trap

TMPDIR="${TMPDIR:-/tmp}"

####

# Handle command line and configuration options

# Check getopt dependency
command -v getopt >/dev/null || printf "%s: executable getopt not found. Install, for example, util-linux\n" "${0##*/}" >&2

CONFIG_DIR_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/tvheadend-post-processor"
CONFIG_DEFAULT="$CONFIG_DIR_DEFAULT/$(basename "${0%.*}").conf"
CONFIG="$CONFIG_DEFAULT"
unset DELETE_RECORDINGS_AFTER_DAYS_OVERRIDE
unset FORCE_OVERWRITE_OVERRIDE
unset KEEP_RECORDING_OVERRIDE
unset OPTIONS_OVERRIDE
unset TRANSCODING_PATH_OVERRIDE
unset SHOW_PROGRESS_OVERRIDE
#unset SKIP_VIDEO_FILE_VERIFICATION
unset TYPE_OVERRIDE
# Parse command line options
#backup-path,error-path,video-path
if ! GETOPT_CMD="$(getopt --options c:d:fhko:pt: --longoptions delete-recordings-after-days:,config:,force-overwrite,help,keep-recording,option:,transcoding-path:,show-progress,type: --name "${0##*/}" -- "$@")"; then
  #printf "%s: getopt internal error\n" "${0##*/}" >&2
  help
  exit 1
fi
eval set -- "$GETOPT_CMD"
while true; do
  case "$1" in
    -c|--config)
      if [ "${2:0:1}" = "/" ]; then
        # Absolute path
        CONFIG="$2"
      else
        # Relative path
        CONFIG="$CONFIG_DIR_DEFAULT/$2"
      fi
      shift 2;;
    -d|--transcoding-path)
      TRANSCODING_PATH_OVERRIDE="$2"; shift 2;;
    --delete-recordings-after-days)
      DELETE_RECORDINGS_AFTER_DAYS_OVERRIDE="$2"; shift 2;;
    -f|--force-overwrite)
      FORCE_OVERWRITE_OVERRIDE="true"; shift;;
    -h|--help)
      usage; exit 0;;
    -k|--keep-recording)
      KEEP_RECORDING_OVERRIDE="true"; shift;;
    -o|--option)
      #declare -a OPTIONS_OVERRIDE
      if [ "${2:0:1}" = "-" ]; then
        OPTIONS_OVERRIDE+=("$2")
      else
        # Add - or -- before option
        if [ "${2:1:1}" = " " ]; then
          OPTIONS_OVERRIDE+=("-$2")
        else
          OPTIONS_OVERRIDE+=("--$2")
        fi
      fi
      shift 2;;
    -p|--show-progress)
      SHOW_PROGRESS_OVERRIDE="true"; shift;;
    -t|--type)
      TYPE_OVERRIDE="$2"; shift 2;;
    --)
      shift; break;;
    *)
      printf "%s: getopt internal error\n" "${0##*/}" >&2; help; exit 1
  esac
done

# Check user
USER="$(whoami)"
if [ "$USER" != "hts" ]; then
  printf "%s: must be user 'hts' to run this script\n" "${0##*/}" >&2
  help
  exit 1
fi

# Check dependencies
if ! command -v HandBrakeCLI >/dev/null; then
  printf "%s: executable HandBrakeCLI not found. Install, for example, handbrake-cli\n" "${0##*/}" >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null; then
  printf "%s: executable ffmpeg not found\n" "${0##*/}" >&2
  exit 1
fi

# Create default config file
#if [ "$CONFIG" = "$CONFIG_DEFAULT" ] && [ ! -f "$CONFIG_DEFAULT" ]; then
if [ ! -f "$CONFIG_DEFAULT" ]; then
  set -eE
  mkdir -p "$(dirname "$CONFIG_DEFAULT")"
  set +eE
  printf "Creating default configuration file '%s'\n" "$CONFIG_DEFAULT" >&2
  cat <<EOF >"$CONFIG_DEFAULT"
# Configuration file for script tvheadend-post-processor.sh
#
# A value is false if: false, no, 0 or <empty>

# Default: no
#FORCE_OVERWRITE=yes

# Default: yes
#KEEP_RECORDING=no

# Default: yes
#SHOW_PROGRESS=no

# Whenever the post-processor script is called, cleanup recording files in folder BACKUP_PATH
# Default: disabled. To enable: 1 or more days
#DELETE_RECORDINGS_AFTER_DAYS=30

# For recording file permissions (*.ts files), see "File permissions" in Tvheadend's web interface menu "Configuration" --> "Recording"
# Default: 664
#FILE_PERMISSIONS=664
# Default: 775
#FOLDER_PERMISSIONS=775



# HandBrake settings

# Mandatory
#TYPE=mkv
TYPE=mp4

# HandBrake options. Options --format, --input and --output are ignored
# Autocrop is disabled (--crop): display subtitles on the lower black bar
# Optionally, specify the recording's framerate (--rate)
#OPTIONS=(--deinterlace --crop=0:0:0:0    --preset-import-file /home/hts/.config/tvheadend-post-processor/Fast-1080p30-modified.json --preset="Fast 1080p30 modified")
#OPTIONS=(--deinterlace --crop=0:0:0:0    --preset="Normal" --quality=24 --rate=25 --native-language=eng)
OPTIONS=(--deinterlace --crop=0:0:0:0    --preset="Very Fast 1080p30")



# Path settings

# Transcoding work folder
# Default: "/home/hts"
#TRANSCODING_PATH=/home/hts

# Folder for successfully transcoded video files
# Default: "archive". Absolute path or relative to TRANSCODING_PATH
#VIDEO_PATH=archive

# Backup folder for recording files after successful post-processing
# Default: "". Absolute path or relative to TRANSCODING_PATH
# If the recording file is not moved to another folder (the default),
# then Tvheadend can handle recording filename conflicts (by renaming the new recording file)
#BACKUP_PATH=

# Folder for failed transcoded recording and video files
# Default: "failed". Absolute path or relative to TRANSCODING_PATH
#ERROR_PATH=failed

EOF
fi

if [ ! -f "$CONFIG" ]; then
  printf "%s: config file '%s' does not exist, is not a file or is not accessible to user '%s'\n" "${0##*/}" "$CONFIG" "$USER" >&2
  exit 1
fi

#declare -a OPTIONS

# Note: Warning: don't expand and execute variables, for example 'if "$VARIABLE"; then ...'.
#       The variable (with possible malicious code) may have been defined in the config file

. "$CONFIG"

# Handle default options
#BACKUP_PATH="${BACKUP_PATH:-orig}"
[ -v ERROR_PATH ] || ERROR_PATH="${ERROR_PATH:-failed}"
[ -v VIDEO_PATH ] || VIDEO_PATH="${VIDEO_PATH:-archive}"
DELETE_RECORDINGS_AFTER_DAYS="${DELETE_RECORDINGS_AFTER_DAYS:-}"
FILE_PERMISSIONS="${FILE_PERMISSIONS:-664}"
FOLDER_PERMISSIONS="${FOLDER_PERMISSIONS:-775}"
FORCE_OVERWRITE="${FORCE_OVERWRITE:-no}"
KEEP_RECORDING="${KEEP_RECORDING:-yes}"
SHOW_PROGRESS="${SHOW_PROGRESS:-yes}"
TRANSCODING_PATH="${TRANSCODING_PATH:-/home/hts}"
TYPE="${TYPE:-mp4}"

# Handle HandBrake default options
[ ! -v OPTIONS ] && OPTIONS=(--deinterlace "--crop=0:0:0:0"    "--preset=\"Very Fast 1080p30\"")

####

# Handle arguments

if [ $# -gt 1 ] && [ "$1" = "CLEANUP" ]; then
  printf "%s: too many argument(s)\n" "${0##*/}" >&2
  help
  exit 1
fi

if [ $# -eq 0 ] || [ $# -eq 1 ] && [ "$1" != "CLEANUP" ]; then
  printf "%s: argument(s) missing\n" "${0##*/}" >&2
  help
  exit 1
fi

MSG="$1"
RECORDING_FILE="$2"
#CHANNEL="$3"

if [ "$MSG" != "OK" ]; then
  printf "%s: Tvheadend error - %s\n" "${0##*/}" "$MSG" >&2
  exit 1
fi

####

# Override options from the config file with corresponding options from the command line

[ -v DELETE_RECORDINGS_AFTER_DAYS_OVERRIDE ] && DELETE_RECORDINGS_AFTER_DAYS="$DELETE_RECORDINGS_AFTER_DAYS_OVERRIDE"
[ -v FORCE_OVERWRITE_OVERRIDE ] && FORCE_OVERWRITE="$FORCE_OVERWRITE_OVERRIDE"
is_false "$FORCE_OVERWRITE" && unset FORCE_OVERWRITE

[ -v KEEP_RECORDING_OVERRIDE ] && KEEP_RECORDING="$KEEP_RECORDING_OVERRIDE"
is_false "$KEEP_RECORDING" && unset KEEP_RECORDING

# Append options from the command line, which will override the corresponding options in the config file.
# When there are duplicate options in the list, HandBrake accepts the last option.
#
# Note: Or use an associative array instead to override options (and reject options "format", "input" and "output").
# Note: OPTIONS is an array in order to handle spaces in the preset name when specified in the config file.
# Note: When looping over OPTIONS (from the config file), prepend missing -- before each option (there are only long options in the config file).
[ -v OPTIONS_OVERRIDE ] && OPTIONS=("${OPTIONS[@]}" "${OPTIONS_OVERRIDE[@]}")

[ -v SHOW_PROGRESS_OVERRIDE ] && SHOW_PROGRESS="$SHOW_PROGRESS_OVERRIDE"
is_false "$SHOW_PROGRESS" && unset SHOW_PROGRESS
# When running inside a service
[ "$TERM" = "dumb" ] && unset SHOW_PROGRESS

[ -v TYPE_OVERRIDE ] && TYPE="$TYPE_OVERRIDE"
# Convert to lowercase
TYPE="${TYPE,,}"

[ -v TRANSCODING_PATH_OVERRIDE ] && TRANSCODING_PATH="$TRANSCODING_PATH_OVERRIDE"
set -eE
mkdir -p -m "$FOLDER_PERMISSIONS" "$TRANSCODING_PATH"
set +eE
#chmod g+w "$TRANSCODING_PATH"
#chown hts:video "$TRANSCODING_PATH"

####

# Check paths

if [ ! -f "$RECORDING_FILE" ]; then
  printf "%s: recording file '%s' does not exist or is not a file\n" "${0##*/}" "$RECORDING_FILE" >&2
  exit 1
fi

if [ ! -r "$RECORDING_FILE" ]; then
  printf "%s: recording file '%s' is not readable by user '%s'\n" "${0##*/}" "$RECORDING_FILE" "$USER" >&2
  exit 1
fi

#[ -v BACKUP_PATH_OVERRIDE ] && BACKUP_PATH="$BACKUP_PATH_OVERRIDE"
#if [ "${BACKUP_PATH:0:1}" = "/" ]; then
#  printf "%s: BACKUP_PATH '%s' (in TRANSCODING_PATH/BACKUP_PATH) must be a relative path and not start with /\n" "${0##*/}" "$BACKUP_PATH" >&2
#  exit 1
#fi
#BACKUP_DIR="$TRANSCODING_PATH/$BACKUP_PATH"
#
BACKUP_PATH="$(echo -n "$BACKUP_PATH")"
if [ -z "$BACKUP_PATH" ]; then
  BACKUP_DIR="$TRANSCODING_PATH"
elif [ "${BACKUP_PATH:0:1}" = "/" ]; then
  BACKUP_DIR="$BACKUP_PATH"
else
  BACKUP_DIR="$TRANSCODING_PATH/$BACKUP_PATH"
fi

ERROR_PATH="$(echo -n "$ERROR_PATH")"
if [ -z "$ERROR_PATH" ]; then
  ERROR_DIR="$TRANSCODING_PATH"
elif [ "${ERROR_PATH:0:1}" = "/" ]; then
  ERROR_DIR="$ERROR_PATH"
else
  ERROR_DIR="$TRANSCODING_PATH/$ERROR_PATH"
fi

VIDEO_PATH="$(echo -n "$VIDEO_PATH")"
if [ -z "$VIDEO_PATH" ]; then
  VIDEO_DIR="$TRANSCODING_PATH"
elif [ "${VIDEO_PATH:0:1}" = "/" ]; then
  VIDEO_DIR="$VIDEO_PATH"
else
  VIDEO_DIR="$TRANSCODING_PATH/$VIDEO_PATH"
fi

# Check video folder
# Note: HandBrake continues to transcode, even if the video folder is an unwritable folder or file
if [ -e "$VIDEO_DIR" ]; then
  if [ ! -d "$VIDEO_DIR" ]; then
    if [ "${VIDEO_PATH:0:1}" = "/" ]; then
      printf "%s: Handbrake video folder VIDEO_PATH '%s' is not a folder\n" "${0##*/}" "$VIDEO_DIR" >&2
    else
      printf "%s: Handbrake video folder TRANSCODING_PATH/VIDEO_PATH '%s' is not a folder\n" "${0##*/}" "$VIDEO_DIR" >&2
    fi
    exit 1
  fi
  if [ ! -w "$VIDEO_DIR" ]; then
    if [ "${VIDEO_PATH:0:1}" = "/" ]; then
      printf "%s: Handbrake video folder VIDEO_PATH '%s' is not writable by user '%s'\n" "${0##*/}" "$VIDEO_DIR" "$USER" >&2
    else
      printf "%s: Handbrake video folder TRANSCODING_PATH/VIDEO_PATH '%s' is not writable by user '%s'\n" "${0##*/}" "$VIDEO_DIR" "$USER" >&2
    fi
    exit 1
  fi
fi
set -eE
mkdir -p -m "$FOLDER_PERMISSIONS" "$VIDEO_DIR"
set +eE
#chmod g+w "$VIDEO_DIR"
#chown hts:video "$VIDEO_DIR"

####

# Cleanup recordings

#if [[ "$DELETE_RECORDINGS_AFTER_DAYS" -ge 1 ]]; then
if [ "$((DELETE_RECORDINGS_AFTER_DAYS + 0))" -ge 1 ] && [ -d "$BACKUP_DIR" ]; then
  # To remove on the last day as well: -mtime +"$((DELETE_RECORDINGS_AFTER_DAYS - 1))"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name \*.ts -daystart -mtime +"$DELETE_RECORDINGS_AFTER_DAYS" -printf "Cleaning up old recording %p\n" -delete
fi

rmdir "$ERROR_DIR" 2> /dev/null

# Exit after cleanup
#[ $# -eq 1 ] && [ "$1" = "CLEANUP" ] && exit 0
[ "$1" = "CLEANUP" ] && exit 0

####

# Setup transcoding

# Stop the script when pressing Ctrl-c to cancel
# For example, when HandBrake is interrupted, don't rename the .part file
trap "exit" INT

# Run this process with low priority
ionice -c 3 -p $$
renice +12 -p $$ > /dev/null

####

# Run pre-run scripts

PRE_SCRIPTS_DIR="$(dirname "$CONFIG")/pre-scripts.d"
[ -d "$PRE_SCRIPTS_DIR" ] || PRE_SCRIPTS_DIR="$CONFIG_DIR_DEFAULT/pre-scripts.d"
if [ -d "$PRE_SCRIPTS_DIR" ]; then
  for SCRIPT in "$PRE_SCRIPTS_DIR/"?*.sh; do
    [ -x "$SCRIPT" ] && . "$SCRIPT"
  done
fi

####

# Perform transcoding

VIDEO_FILE="$VIDEO_DIR/$(basename "${RECORDING_FILE%.*}").$TYPE"
#if [ ! -v FORCE_OVERWRITE ] && [ -f "$VIDEO_FILE" ]; then
if [ ! -v FORCE_OVERWRITE ]; then
  for FILE in "$VIDEO_FILE.part" "$VIDEO_FILE"; do
    if [ -f "$FILE" ]; then
      printf "%s: video file '%s' already exists. Remove the file or use -f/--force-overwrite to overwrite\n" "${0##*/}" "$FILE" >&2

      # Save recording file. It may get overwritten by another recording
      mkdir -p -m "$FOLDER_PERMISSIONS" "$ERROR_DIR"
      ERROR_FILE="$(mktemp "$ERROR_DIR/$(basename "${RECORDING_FILE%.*}")-video-file-exists-error.XXXXXX.${RECORDING_FILE##*.}")"
      printf "%s: moving '%s' to '%s'\n" "${0##*/}" "$RECORDING_FILE" "$ERROR_FILE" >&2
      mv "$RECORDING_FILE" "$ERROR_FILE"
      exit 1
    fi
  done
fi

# Transcode recording file
ERROR_FILE="$(mktemp "$TMPDIR/$(basename "${0%.*}")-$(basename "${RECORDING_FILE%.*}")-handbrake-error.log.XXXXXX")"
if [ -v SHOW_PROGRESS ]; then
  # Note: returns 0, in case of "unknown option"
  #--deinterlace
  #HandBrakeCLI "${OPTIONS[@]}" --format="av_$TYPE" --input="$RECORDING_FILE" --output="$VIDEO_FILE.part" 2>(tee "$ERROR_FILE")
  HandBrakeCLI "${OPTIONS[@]}" --format="av_$TYPE" --input="$RECORDING_FILE" --output="$VIDEO_FILE.part" 2>&1 | tee "$ERROR_FILE"
else
  #HandBrakeCLI "${OPTIONS[@]}" --format="av_$TYPE" --input="$RECORDING_FILE" --output="$VIDEO_FILE.part" 2>(tee "$ERROR_FILE") > /dev/null
  HandBrakeCLI "${OPTIONS[@]}" --format="av_$TYPE" --input="$RECORDING_FILE" --output="$VIDEO_FILE.part" > "$ERROR_FILE" 2>&1
fi
RET=$?

chmod "$FILE_PERMISSIONS" "$VIDEO_FILE.part"
chmod "$FILE_PERMISSIONS" "$ERROR_FILE"
#if [ $RET -ne 0 ] || [ -s "$ERROR_FILE" ]; then
# If stdout was also redirected to ERROR_FILE
[ $RET -eq 0 ] && grep -Eq "^ERROR: |^FATAL: " "$ERROR_FILE" && RET=1
if [ $RET -ne 0 ]; then
  # Transcoding failed. Move files to the error folder
  mkdir -p -m "$FOLDER_PERMISSIONS" "$ERROR_DIR"

  RECORDING_FILE_SAVED="$(mktemp "$ERROR_DIR/$(basename "${RECORDING_FILE%.*}")-handbrake-error.XXXXXX.${RECORDING_FILE##*.}")"
  TEMP_ID="$(echo -n "$RECORDING_FILE_SAVED" | awk -F'.' '{print $(NF-1)}')"
  mv "$RECORDING_FILE" "$RECORDING_FILE_SAVED"

  mv "$VIDEO_FILE.part" "$ERROR_DIR/$(basename "${VIDEO_FILE%.*}")-handbrake-error.$TEMP_ID.${VIDEO_FILE##*.}.part"

  ERROR_FILE_SAVED="$ERROR_DIR/$(basename "${RECORDING_FILE%.*}-handbrake-error.$TEMP_ID.log")"
  mv "$ERROR_FILE" "$ERROR_FILE_SAVED"

  if [ -s "$ERROR_FILE_SAVED" ]; then
    printf "%s: \"HandBrakeCli '%s'\" returned with exit code %d.\nSee file %s\n" "${0##*/}" "$RECORDING_FILE" "$RET" "$ERROR_FILE_SAVED" >&2
    #cat "$ERROR_FILE_SAVED" >&2
  else
    printf "%s: \"HandBrakeCli '%s'\" returned with exit code %d\n" "${0##*/}" "$RECORDING_FILE" "$RET" >&2
    rm -f "$ERROR_FILE_SAVED"
  fi
  exit $RET
else
  # Transcoding succeeded
  rm -f "$ERROR_FILE"
fi
mv -f "$VIDEO_FILE.part" "$VIDEO_FILE"

####

# Verify video file

#if [ ! -v SKIP_VERIFY_VIDEO_FILE ]; then

##reset_trap
trap - ERR

ERROR_FILE="$(mktemp "$TMPDIR/$(basename "${0%.*}")-$(basename "${RECORDING_FILE%.*}")-ffmpeg-error.log.XXXXXX")"
#
# Check the whole file
#ffmpeg -nostdin -v error -i "$VIDEO_FILE" -f null - 2>"$ERROR_FILE"
#
# Check only the end part (faster)
#ffmpeg -nostdin -v error -sseof -60 -i "$VIDEO_FILE" -f null - 2> "$ERROR_FILE"
#RET=$?
#if [ $RET -ne 0 ] || [ -s "$ERROR_FILE" ]; then
#
# Check only the end part (faster)
# grep -v: ignore subtitle "error" (https://trac.ffmpeg.org/ticket/2212)
ffmpeg -nostdin -v error -sseof -60 -i "$VIDEO_FILE" -f null - 2>&1 | \
        grep -v "Application provided invalid, non monotonically increasing dts to muxer in stream" > "$ERROR_FILE"

set_trap

chmod "$FILE_PERMISSIONS" "$ERROR_FILE"
if [ -s "$ERROR_FILE" ]; then
  # Error in video file. Move files to the error folder
  mkdir -p -m "$FOLDER_PERMISSIONS" "$ERROR_DIR"

  RECORDING_FILE_SAVED="$(mktemp "$ERROR_DIR/$(basename "${RECORDING_FILE%.*}")-ffmpeg-error.XXXXXX.${RECORDING_FILE##*.}")"
  TEMP_ID="$(echo -n "$RECORDING_FILE_SAVED" | awk -F'.' '{print $(NF-1)}')"
  mv "$RECORDING_FILE" "$RECORDING_FILE_SAVED"

  mv "$VIDEO_FILE" "$ERROR_DIR/$(basename "${VIDEO_FILE%.*}")-ffmpeg-error.$TEMP_ID.${VIDEO_FILE##*.}"

  ERROR_FILE_SAVED="$ERROR_DIR/$(basename "${RECORDING_FILE%.*}-ffmpeg-error.$TEMP_ID.log")"
  mv "$ERROR_FILE" "$ERROR_FILE_SAVED"

  printf "%s: ffmpeg error. See file %s\n" "${0##*/}" "$ERROR_FILE_SAVED" >&2
  #cat "$ERROR_FILE_SAVED" >&2
  exit $RET
else
  # No error in video file
  rm -f "$ERROR_FILE"
fi

####

# Move or delete recording file

if [ -v KEEP_RECORDING ]; then
  #set -eE
  mkdir -p -m "$FOLDER_PERMISSIONS" "$BACKUP_DIR"
  #set +eE
  #chmod g+w "$BACKUP_DIR"
  #chown hts:video "$BACKUP_DIR"

  if [ -v FORCE_OVERWRITE ]; then
    [ "$(realpath "$RECORDING_FILE")" != "$(realpath "$BACKUP_DIR/$(basename "$RECORDING_FILE")")" ] && mv "$RECORDING_FILE" "$BACKUP_DIR/"
  else
    mv --no-clobber "$RECORDING_FILE" "$BACKUP_DIR/"
  fi
else
  rm "$RECORDING_FILE"
fi

####

# Run post-run scripts

POST_SCRIPTS_DIR="$(dirname "$CONFIG")/post-scripts.d"
[ -d "$POST_SCRIPTS_DIR" ] || POST_SCRIPTS_DIR="$CONFIG_DIR_DEFAULT/post-scripts.d"
if [ -d "$POST_SCRIPTS_DIR" ]; then
  for SCRIPT in "$POST_SCRIPTS_DIR/"?*.sh; do
    [ -x "$SCRIPT" ] && . "$SCRIPT" "$VIDEO_FILE"
  done
fi

