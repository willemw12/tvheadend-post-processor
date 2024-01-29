#!/usr/bin/env bash

# Transcode a recording file to a video file.
# The script is invoked from Tvheadend.
#
# This bash script depends on: awk, ffmpeg, getopt (util-linux), handbrake-cli.
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

# shellcheck disable=SC2174

usage() {
  printf 'USAGE:\n  %s [OPTION]... RECORDING_MESSAGE RECORDING_FILE\n' "${0##*/}"

  # shellcheck disable=SC2016
  printf '
OPTIONS:
  -c, --config CONFIG
          Use an absolute configuration path. Or use a relative path,
          relative to the default configuration file location (see section CONFIGURATION below):
  --delete-recordings-after-days DAYS
          Whenever this script is called, cleanup any recordings (*.ts files) that were kept
          after post-processing. See also option -k, --keep-recording.
          If DAYS is 1, 2, etc., then this option is enabled. If DAYS is 0, then this option is disabled.
          The number of days is compared against the file'\''s modification time
          (see "-mtime" command line option of "find"), not against the date in the filename.
  -f, --force-overwrite
  -h, --help
  -k, --keep-recording (default)
  -K, --no-keep-recording
  -o, --option HANDBRAKE_OPTION ...
          Override OPTIONS configuration values for HandBrake.
          Options --format, --input and --output are ignored.
          The leading "--" or "-" of HANDBRAKE_OPTION can be left out.
          Example: --option=deinterlace --option=crop=0:0:0:0 --option='\''preset=Very Fast 1080p30'\''
  -p, --show-progress (default)
  -q, --queue-transcoding
          Run transcodings sequentially instead of in parallel.
          If the script is queued, it will wait and exit after transcoding has finished.
  --skip-user-check
          Disable the user check. Enable running as an other user instead of user "hts" or "tvheadend".
          Setting this option is usually not recommended.
  -t, --type TYPE
          Video type. mkv (default) or mp4.
  -v, --video-path VIDEO_PATH
          Override the video files path. Absolute path or relative to TRANSCODING_PATH
  -w, --transcoding-path TRANSCODING_PATH
          The transcoding work folder during post-processing.

ARGUMENTS:
  RECORDING_MESSAGE
          "CLEANUP": cleanup old recordings (*.ts files) only. No other arguments.
                     See option --delete-recordings-after-days.
          "OK": perform post-processing.
  RECORDING_FILE
          A .ts file.

DESCRIPTION:
  This script, run by Tvheadend usually as user "hts" or "tvheadend", transcodes a recording file to a video file.
  The recording file, if kept, can be moved to a backup folder after successful transcoding.

CONFIGURATION:
  Setup example in Tvheadend'\''s web interface. Go to menu item "Configuration", then to menu item "Recording".
  Change "View level" to "Expert" or "Advanced". Set "Post-processor command", including at least
  the following two arguments:
          tvheadend-post-processor.sh "%%e" "%%f"

  Note: If an argument in the line above is quoted, then it has to be in double-quotes.

  Default configuration file:
          For user "tvheadend", if folder "/etc/tvheadend" exists:
              /etc/tvheadend/tvheadend-post-processor/tvheadend-post-processor.conf.
          Otherwise:
              $XDG_CONFIG_HOME/tvheadend-post-processor/tvheadend-post-processor.conf or else
              $HOME/.config/tvheadend-post-processor/tvheadend-post-processor.conf.
              (For user "hts": /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf.)

          To create the default configuration file manually (for user "hts"), run:
              sudo -u hts tvheadend-post-processor.sh

SCRIPTS:
  Executable pre-transcoding and post-transcoding scripts (*.sh files) can be placed in drop-in folders "pre-scripts.d"
  and "post-scripts.d", located next to the current configuration file. The folders are not created automatically.
  To make a script executable, run: chmod +x 10-pre-script.sh. These scripts are run in alphabetical order.
  Scripts in "post-scripts.d" are only run after successful transcoding. The transcoded video filename is passed in
  as the first argument.

  Similarly, scripts for monitoring failed recordings can be placed in the "error-scripts.d" folder.
  The error message is passed in as the first argument. Failed post-processing messages start with "Post-processor: ".
  Error messages from Tvheadend do not.\n'

  # shellcheck disable=SC2016
  printf '
MANUAL TRANSCODING:
  To manually start transcoding or redo transcoding, use tvheadend-post-processor-batch.sh (for more information,
  run that script with option --help), or run this script directly, for example (for user "hts"),
          sudo -u hts %s --keep-recording --show-progress --config="$(pwd)/my-tvheadend-post-processor.conf" OK '\''recording1.ts'\''
          sudo -u hts %s --keep-recording --show-progress --option=deinterlace --option=crop=0:0:0:0 --option='\''preset=Very Fast 1080p30'\'' OK '\''recording1.ts'\''\n' "${0##*/}" "${0##*/}"

  # shellcheck disable=SC2016
  printf '
ENVIRONMENT VARIABLES:
  IONICE_CLASS          Set the I/O priority. See --class in "man ionice". Default: 3.
  NICE_PRIO             Set the process priority. See --priority in "man renice". Default: +12.
  QUEUE_LOCKFILE        Full path and filename to the lock file used for sequential transcoding. Default: inside $TMPDIR.
  TMPDIR                Temporary folder (for temporary error log files). Default: /tmp.

  Note that any environment variable can also be set in the configuration file.

SEE ALSO:
  The generated configuration file.\n\n'
}

####

main() {
  # NOTE: Sets global variables
  init_global

  set_trap

  parse_command_line "$@"

  check_user
  check_dependencies
  check_create_default_config_file

  # NOTE: Sets global variables
  load_config_file
  handle_default_options
  handle_arguments
  override_config_with_arguments
  check_paths

  cleanup_recordings

  setup_transcoding
  run_prerun_scripts
  #( flock 9
  transcode_recording
  verify_video_file
  #) 9>"$QUEUE_LOCKFILE"
  move_or_delete_recording_file
  run_postrun_scripts

  #exit
}

####

# NOTE: Sets global variables
init_global() {
  TMPDIR="${TMPDIR:-/tmp}"

  [ -v QUEUE_LOCKFILE ] || QUEUE_LOCKFILE="$TMPDIR/${0##*/}.lock"

  # NOTE: USER may not always be defined
  [ -v USER ] || USER="$(whoami)"
  #export USER
  if [ -z "$USER" ]; then
    # shellcheck disable=SC2016
    printf '%s: ERROR: cannot determine the current user (from $USER or "whoami" command)\n' "${0##*/}" >&2
    exit 1
  fi
}

####

set_trap() {
  #unset trap_msg_printed
  trap_msg_printed=

  #USER="${USER:-Unknown"
  ##trap "printf \"%s: ERROR: while running as user '%s'\n\" \"${0##*/}\" \"$USER\" >&2" ERR
  #trap 'printf "%s: ERROR: while running as user \"%s\"\n" "${0##*/}" "$USER" >&2' ERR

  trap 'print_trap_msg' EXIT
}

reset_trap() {
  trap - ERR
}

print_trap_msg() {
  # shellcheck disable=SC2181
  if (($? != 0)) && [ -n "$trap_msg_printed" ]; then
    printf '%s: ERROR: while running as user "%s"\n' "${0##*/}" "$USER" >&2
    trap_msg_printed=
  fi
}

####

parse_command_line() {
  # Check getopt dependency
  if ! command -v getopt >/dev/null; then
    printf '%s: ERROR: executable getopt not found. Install, for example, util-linux\n' "${0##*/}" >&2
    exit 1
  fi

  local _basename
  #_basename="${0%.*}"; _basename="${_basename##*/}"
  _basename="$(basename "${0%.*}")"
  if [ "$USER" = tvheadend ] && [ -d /etc/tvheadend/ ]; then
    # In case configuration is kept outside the home folder
    config_dir_default="/etc/tvheadend/$_basename"
  else
    config_dir_default="${XDG_CONFIG_HOME:-$HOME/.config}/$_basename"
  fi
  config_default="$config_dir_default/$_basename.conf"
  readonly config_default

  config="$config_default"

  #unset skip_video_file_verification
  unset skip_user_check

  unset delete_recordings_after_days_override
  unset force_overwrite_override
  unset handbrake_options_override
  unset keep_recording_override
  unset queue_transcoding_override
  unset show_progress_override
  unset transcoding_path_override
  unset type_override
  unset video_path_override

  # Parse command line options
  local _options
  #backup-path,error-path,video-path
  if ! _options="$(getopt --options c:fhKko:pqt:v:w: --longoptions config:,delete-recordings-after-days:,force-overwrite,help,keep-recording,no-keep-recording,option:,queue-transcoding,show-progress,skip-user-check,transcoding-path:,type:,video-path: --name "${0##*/}" -- "$@")"; then
    #printf '%s: ERROR: getopt internal error\n' "${0##*/}" >&2
    error_help
    exit 1
  fi
  eval set -- "$_options"
  while true; do
    case "$1" in
      -c | --config)
        if [ "${2:0:1}" = '/' ]; then
          # Absolute path
          config="$2"
        else
          # Relative path
          config="$config_dir_default/$2"
        fi
        shift 2
        ;;
      --delete-recordings-after-days)
        delete_recordings_after_days_override="$2"
        shift 2
        ;;
      -f | --force-overwrite)
        force_overwrite_override=true
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -k | --keep-recording)
        keep_recording_override=true
        shift
        ;;
      -K | --no-keep-recording)
        keep_recording_override=false
        shift
        ;;
      -o | --option)
        if [ "${2:0:1}" = '-' ]; then
          handbrake_options_override+=("$2")
        else
          # Add missing - or -- before option value
          if [ "${2:1:1}" = '' ]; then
            handbrake_options_override+=("-$2")
          else
            handbrake_options_override+=("--$2")
          fi
        fi
        shift 2
        ;;
      -p | --show-progress)
        show_progress_override=true
        shift
        ;;
      -q | --queue-transcoding)
        queue_transcoding_override=true
        shift
        ;;
      --skip-user-check)
        skip_user_check=true
        shift
        ;;
      -t | --type)
        type_override="$2"
        shift 2
        ;;
      -v | --video-path)
        video_path_override="$2"
        shift 2
        ;;
      -w | --transcoding-path)
        transcoding_path_override="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        printf '%s: ERROR: getopt internal error\n' "${0##*/}" >&2
        error_help
        exit 1
        ;;
    esac
  done

  readonly config

  #readonly skip_video_file_verification
  readonly skip_user_check

  readonly delete_recordings_after_days_override
  readonly force_overwrite_override
  readonly handbrake_options_override
  readonly keep_recording_override
  readonly queue_transcoding_override
  readonly show_progress_override
  readonly transcoding_path_override
  readonly type_override
  readonly video_path_override

  ####

  # NOTE: Sets new global variable
  args=("$@")
  readonly args
}

####

check_user() {
  if is_false "$skip_user_check" && [ "$USER" != hts ] && [ "$USER" != tvheadend ]; then
    printf '%s: ERROR: must be user "hts" or "tvheadend" to run this script. Or add option "--skip-user-check"\n' "${0##*/}" >&2
    run_error_scripts_postpro 'validation failed'
    error_help
    exit 1
  fi
}

check_dependencies() {
  if ! command -v HandBrakeCLI >/dev/null; then
    printf '%s: ERROR: executable HandBrakeCLI not found. Install, for example, handbrake-cli\n' "${0##*/}" >&2
    run_error_scripts_postpro 'validation failed'
    exit 1
  fi

  if ! command -v ffmpeg >/dev/null; then
    printf '%s: ERROR: executable ffmpeg not found\n' "${0##*/}" >&2
    run_error_scripts_postpro 'validation failed'
    exit 1
  fi

  ##if ! command -v flock >/dev/null && [ is_true "$queue_transcoding" ]; then
  #if ! command -v flock >/dev/null; then
  #  printf '%s: WARNING: transcoding queue is disabled. Executable flock not found. Install, for example, util-linux\n' "${0##*/}" >&2
  #fi

}

check_create_default_config_file() {
  #if [ "$config" = "$config_default" ] && [ ! -f "$config_default" ]; then
  if [ ! -f "$config_default" ]; then
    set -eE
    mkdir -p "${config_default%/*}"
    set +eE
    printf 'Creating default configuration file "%s"\n' "$config_default"
    cat <<EOF >"$config_default"
# Configuration file for script tvheadend-post-processor.sh
#
# A value is false if: false, no, 0 or <empty>

# Default: no
#force_overwrite=yes

# Default: yes
#keep_recording=no

# Default: yes
#show_progress=no

# Default: no
#queue_transcoding=yes

# Whenever the post-processor script is called, cleanup recording files in folder backup_path=
# Default: disabled. To enable, set to 1 or higher
#delete_recordings_after_days=30

# For recording file permissions (*.ts files), see "File permissions" in Tvheadend's web interface menu "Configuration" --> "Recording"
# Default: 664
#file_permissions=664
# Default: 775
#folder_permissions=775



# HandBrake settings

# Default: mkv
#type=mp4

# HandBrake options. Options --format, --input and --output are ignored
# Autocrop is disabled (--crop): display subtitles on the lower black bar
# Optionally, specify the framerate (--rate)
#options=(--deinterlace --crop=0:0:0:0    --preset-import-file /home/hts/.config/tvheadend-post-processor/Fast-1080p30-modified.json --preset='Fast 1080p30 modified')
#options=(--deinterlace --crop=0:0:0:0    --preset='Normal' --quality=24 --rate=25    --native-language=eng)
options=(--deinterlace --crop=0:0:0:0    --preset='Very Fast 1080p30'    --all-subtitles --subtitle-burned=none --subtitle-default=none)



# FFmpeg settings

# Default: yes
#verify_fast=no



# Path settings

# Transcoding work folder
# Default: "\$HOME"
#transcoding_path=/home/hts

# Folder for in progress and successfully transcoded video files
# Default: 'archive'. Absolute path or relative to transcoding_path=
#video_path=archive

# Backup folder for recording files after successful post-processing
# Default: ''. Absolute path or relative to transcoding_path=
# It is recommended not to change the default.
# By default, the recording file is not moved to another folder. This allows Tvheadend
# to handle recording filename conflicts (by renaming the new recording file)
#backup_path=

# Folder for failed transcoded recording and video files
# Default: 'failed'. Absolute path or relative to transcoding_path=
#error_path=failed

EOF
  fi
}

# NOTE: Warning: don't expand and execute variables, for example 'if "$VARIABLE"; then ...'.

# NOTE: Sets global variables
load_config_file() {
  if [ ! -f "$config" ]; then
    printf '%s: ERROR: config file \"%s\" does not exist, is not a file or is not accessible to user "%s"\n' "${0##*/}" "$config" "$USER" >&2
    run_error_scripts_postpro 'configuration error'
    exit 1
  fi

  . "$config"

}

# NOTE: Sets global variables
handle_default_options() {
  #[ -v backup_path ] || backup_path=orig
  [ -v backup_path ] || backup_path=
  [ -v error_path ] || error_path=failed
  # HandBrake default options
  [ -v options ] || options=(--deinterlace --crop='0:0:0:0' --preset='Very Fast 1080p30' --all-subtitles --subtitle-burned=none --subtitle-default=none)
  [ -v video_path ] || video_path=archive

  delete_recordings_after_days="${delete_recordings_after_days//[^0-9]/}"
  delete_recordings_after_days="${delete_recordings_after_days:-}"
  file_permissions="${file_permissions:-664}"
  folder_permissions="${folder_permissions:-775}"
  force_overwrite="${force_overwrite:-no}"
  keep_recording="${keep_recording:-yes}"
  queue_transcoding="${queue_transcoding:-no}"
  show_progress="${show_progress:-yes}"
  transcoding_path="${transcoding_path:-$HOME}"
  type="${type:-mkv}"
  verify_fast="${verify_fast:-yes}"
}

####

# NOTE: Sets global variables
handle_arguments() {
  if (("${#args[@]}" > 1)) && [ "${args[0]}" = CLEANUP ]; then
    printf '%s: ERROR: too many argument(s)\n' "${0##*/}" >&2
    run_error_scripts_postpro "validation failed"
    error_help
    exit 1
  fi

  if (("${#args[@]}" == 0 || "${#args[@]}" == 1)) && [ "${args[0]}" != CLEANUP ]; then
    printf '%s: ERROR: argument(s) missing\n' "${0##*/}" >&2
    run_error_scripts_postpro 'validation failed'
    error_help
    exit 1
  fi

  message="${args[0]}"
  recording_file="${args[1]}"
  #channel="${args[2]}"

  readonly message recording_file # channel

  #if [ -n "$ABORT_MESSAGE" ] && [ "$message" = "$ABORT_MESSAGE" ]; then
  #  printf '%s: WARNING: Tvheadend abort message: %s\n' "${0##*/}" "$message" # >&2
  #  #exit 1
  #  exit 0
  #fi

  if [ "$message" != OK ]; then
    printf '%s: ERROR: Tvheadend error message: %s\n' "${0##*/}" "$message" >&2
    run_error_scripts "$message" # "$recording_file"
    exit 1
  fi
}

####

# Override options from the config file with corresponding options from the command line

# TODO: Maybe don't set variables readonly here (but after run_prerun_scripts()).
#       And allow pre-transcoding scripts to alter configuration variables
# NOTE: Sets global variables
override_config_with_arguments() {
  delete_recordings_after_days="$(print_value_or_default "$delete_recordings_after_days_override" "$delete_recordings_after_days")"
  readonly delete_recordings_after_days

  force_overwrite="$(print_value_or_default "$force_overwrite_override" "$force_overwrite")"
  readonly force_overwrite

  keep_recording="$(print_value_or_default "$keep_recording_override" "$keep_recording")"
  readonly keep_recording

  queue_transcoding="$(print_value_or_default "$queue_transcoding_override" "$queue_transcoding")"
  readonly queue_transcoding

  # Append options from the command line, which will override the corresponding options in the config file.
  # When there are duplicate options in the list, HandBrake accepts the last option.
  #
  # NOTE: Or use an associative array instead to override options (and reject options "format", "input" and "output").
  # NOTE: options= is an array in order to handle spaces in the preset name when specified in the config file.
  # NOTE: When looping over options= (from the config file), prepend missing -- before each option (there are only long options in the config file).
  [ -v handbrake_options_override ] && options=("${options[@]}" "${handbrake_options_override[@]}")
  readonly options

  show_progress="$(print_value_or_default "$show_progress_override" "$show_progress")"
  # When running inside a service
  #[ "$TERM" = dumb ] && show_progress=0
  [ -t 1 ] || show_progress=0
  readonly show_progress

  [ -v type_override ] && type="$type_override"
  # Convert to lowercase
  type="${type,,}"
  readonly type

  transcoding_path="$(print_value_or_default "$transcoding_path_override" "$transcoding_path")"
  readonly transcoding_path

  video_path="$(print_value_or_default "$video_path_override" "$video_path")"
  readonly video_path
}

print_value_or_default() {
  local _default="$1" _value="$2"

  echo -n "${_value:-$_default}"
}

####

# NOTE: Sets global variables
check_paths() {
  if [ ! -f "$recording_file" ]; then
    printf '%s: ERROR: recording file "%s" does not exist or is not a file\n' "${0##*/}" "$recording_file" >&2
    run_error_scripts_postpro "validation failed"
    exit 1
  fi

  if [ ! -r "$recording_file" ]; then
    printf '%s: ERROR: recording file "%s" is not readable by user "%s"\n' "${0##*/}" "$recording_file" "$USER" >&2
    run_error_scripts_postpro "validation failed"
    exit 1
  fi

  backup_dir="$(print_full_path "$backup_path" "$transcoding_path")"
  readonly backup_dir
  check_folder_permissions "$folder_permissions" "$backup_dir"

  error_dir="$(print_full_path "$error_path" "$transcoding_path")"
  readonly error_dir
  check_folder_permissions "$folder_permissions" "$error_dir"

  video_dir="$(print_full_path "$video_path" "$transcoding_path")"
  readonly video_dir
  check_video_folder
  check_folder_permissions "$folder_permissions" "$video_dir"

  ####

  # NOTE: Sets new global variable
  video_file="$video_dir/$(basename "${recording_file%.*}").$type"
  readonly video_file
}

# Print "dir" if absolute path, else print "dir" relative to "parentdir" (i.e. "parentdir/dir")
print_full_path() {
  local _dir="$1" _parentdir="$2"

  local _fulldir
  _dir="$(echo -n "$_dir")"
  if [ -z "$_dir" ]; then
    _fulldir="$_parentdir"
  elif [ "${_dir:0:1}" = '/' ]; then
    _fulldir="$_dir"
  else
    _fulldir="$_parentdir/$_dir"
  fi

  echo -n "$_fulldir"
}

check_folder_permissions() {
  local _permissions="$1" _dir="$2"

  #set -eE
  mkdir -p -m "$_permissions" "$_dir"
  set +eE
  #chmod g+w "$_dir"
  #chown ... "$_dir"
}

check_video_folder() {
  # NOTE: HandBrake continues to transcode, even if the video folder is an unwritable folder or file
  if [ -e "$video_dir" ]; then
    if [ ! -d "$video_dir" ]; then
      if [ "${video_path:0:1}" = "/" ]; then
        printf '%s: ERROR: HandBrake video folder video_path="%s" is not a folder\n' "${0##*/}" "$video_dir" >&2
      else
        printf '%s: ERROR: HandBrake video folder transcoding_path/video_path="%s" is not a folder\n' "${0##*/}" "$video_dir" >&2
      fi
      run_error_scripts_postpro 'validation failed'
      exit 1
    fi
    if [ ! -w "$video_dir" ]; then
      if [ "${video_path:0:1}" = "/" ]; then
        printf '%s: ERROR: HandBrake video folder video_path="%s" is not writable by user "%s"\n' "${0##*/}" "$video_dir" "$USER" >&2
      else
        printf '%s: ERROR: HandBrake video folder ranscoding_path/video_path="%s" is not writable by user "%s"\n' "${0##*/}" "$video_dir" "$USER" >&2
      fi
      run_error_scripts_postpro 'validation failed'
      exit 1
    fi
  fi
}

####

cleanup_recordings() {
  #if (( delete_recordings_after_days >= 1 )); then
  if ((delete_recordings_after_days >= 1)) && [ -d "$backup_dir" ]; then
    # To remove on the last day as well: -mtime +"$((delete_recordings_after_days - 1))"
    local _recording
    #find "$backup_dir" -maxdepth 1 -type f -name \*.ts -daystart -mtime +"$delete_recordings_after_days" -printf 'Cleaning up old recording %p\n' -delete
    find "$backup_dir" -maxdepth 1 -type f -name \*.ts -daystart -mtime +"$delete_recordings_after_days" | sort | while read -r _recording; do
      local _video_found _type
      _video_found=0
      for _type in mp4 mkv; do
        local _video
        _video="$video_dir/$(basename "${_recording%.*}").$_type.part"
        if [ -f "$_video" ]; then
          _video_found=1
          break
        fi
      done
      if ((_video_found)); then
        printf 'WARNING: Skip cleaning up old recording file "%s". Found partial video file "%s"\n' "$_recording" "$_video" # >&2
        continue
      fi

      printf 'Cleaning up old recording file "%s"\n' "$_recording"
      rm -r "$_recording"
    done
  fi

  rmdir "$error_dir" 2>/dev/null

  # Exit after cleanup
  [ "$message" = CLEANUP ] && exit 0
}

####

setup_transcoding() {
  # Stop the script when pressing Ctrl-c to cancel
  # For example, when HandBrake is interrupted, don't rename the .part file
  trap 'exit' INT

  # Run this process with low priority
  ionice --class="${IONICE_CLASS:-3}" --pid=$$
  renice --priority "${NICE_PRIO:-+12}" --pid $$ >/dev/null
}

####

# NOTE: run this after reading in the configuration file as these scripts may contain global settings
run_prerun_scripts() {
  local _pre_scripts_dir _script

  _pre_scripts_dir="${config%/*}/pre-scripts.d"
  [ -d "$_pre_scripts_dir" ] || _pre_scripts_dir="$config_dir_default/pre-scripts.d"
  if [ -d "$_pre_scripts_dir" ]; then
    for _script in "$_pre_scripts_dir/"?*.sh; do
      [ -x "$_script" ] && . "$_script"
    done
  fi

  ####

  readonly QUEUE_LOCKFILE TMPDIR USER

  # Abort on an unbound/unset variable
  #set -o nounset
}

####

transcode_recording() {
  local _error_file _file

  #if is_false "$force_overwrite" && [ -f "$video_file" ]; then
  if is_false "$force_overwrite"; then
    for _file in "$video_file.part" "$video_file"; do
      if [ -f "$_file" ]; then
        printf '%s: ERROR: video file "%s" already exists. Remove the file or use -f or --force-overwrite to overwrite\n' "${0##*/}" "$_file" >&2

        # Save recording file under a unique name, otherwise it may get overwritten by another recording with the same name
        mkdir -p -m "$folder_permissions" "$error_dir"
        _error_file="$(mktemp --dry-run "$error_dir/$(basename "${recording_file%.*}")-video-file-exists-error.XXXXXX.${recording_file##*.}")"
        printf '%s: ERROR: moving "%s" to "%s"\n' "${0##*/}" "$recording_file" "$_error_file" >&2
        mv "$recording_file" "$_error_file"
        run_error_scripts_postpro 'video file already exists error'
        exit 1
      fi
    done
  fi

  local _ret

  # Transcode recording file
  # NOTE: HandBrakeCLI returns 0 in case of "unknown option"
  _error_file="$(mktemp --dry-run "$TMPDIR/$(basename "${0%.*}")-$(basename "${recording_file%.*}")-handbrake-error.log.XXXXXX")"
  #set -o pipefail
  if is_true "$queue_transcoding"; then
    # Run transcodings sequentially
    (
      printf 'Adding video file "%s" to the queue (lock file "%s")\n' "$video_file" "$QUEUE_LOCKFILE"

      #sleep 4 &&
      rm -f "$video_file.part" &&
        touch "$video_file.part" &&
        flock 9 &&
        printf 'Taking video file "%s" from the queue\n' "$video_file" &&
        if is_true "$show_progress"; then
          #--deinterlace ...
          #HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>(tee "$_error_file")
          HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>&1 | tee "$_error_file"
        else
          #HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>(tee "$_error_file") > /dev/null
          HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" >"$_error_file" 2>&1
        fi
    ) 9>"$QUEUE_LOCKFILE"
  else
    # Run transcodings, as normal, in parallel
    if is_true "$show_progress"; then
      #HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>(tee "$_error_file")
      HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>&1 | tee "$_error_file"
    else
      #HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" 2>(tee "$_error_file") > /dev/null
      HandBrakeCLI "${options[@]}" --format="av_$type" --input="$recording_file" --output="$video_file.part" >"$_error_file" 2>&1
    fi
  fi
  # Save the transcoding exit status
  #_ret=$?
  #set +o pipefail
  # NOTE: Ignoring errors caused by writing to the error file
  _ret="${PIPESTATUS[0]}"

  chmod "$file_permissions" "$video_file.part"
  chmod "$file_permissions" "$_error_file"

  # When stdout was not redirected to _error_file
  #if (( $_ret != 0 )) || [ -s "$_error_file" ]; then

  # NOTE: Some errors are only warnings to HandBrake ("udfread ERROR: ECMA 167 Volume Recognition failed", ...)
  #(( _ret == 0 )) && grep -Eq '^ERROR: |^FATAL: ' "$_error_file" && _ret=1

  if (("$_ret" != 0)); then
    # Transcoding failed. Move files to the error folder
    mkdir -p -m "$folder_permissions" "$error_dir"

    local _recording_file_saved _temp_id
    _recording_file_saved="$(mktemp --dry-run "$error_dir/$(basename "${recording_file%.*}")-handbrake-error.XXXXXX.${recording_file##*.}")"
    _temp_id="$(echo -n "$_recording_file_saved" | awk -F'.' '{print $(NF-1)}')"
    mv "$recording_file" "$_recording_file_saved"
    #[ -s "$_recording_file_saved" ] || rm -f "$_recording_file_saved"

    mv "$video_file.part" "$error_dir/$(basename "${video_file%.*}")-handbrake-error.$_temp_id.${video_file##*.}.part"

    local _error_file_saved
    _error_file_saved="$error_dir/$(basename "${recording_file%.*}-handbrake-error.$_temp_id.log")"
    mv "$_error_file" "$_error_file_saved"

    if [ -s "$_error_file_saved" ]; then
      printf '%s: ERROR: \"HandBrakeCli "%s"" returned with exit code %d.\nSee file %s\n' "${0##*/}" "$recording_file" "$_ret" "$_error_file_saved" >&2
      #cat "$_error_file_saved" >&2
    else
      printf '%s: ERROR: "HandBrakeCli "%s"" returned with exit code %d\n' "${0##*/}" "$recording_file" "$_ret" >&2
      rm -f "$_error_file_saved"
    fi
    run_error_scripts_postpro 'HandBrake error'

    exit "$_ret"
  fi

  # Transcoding succeeded
  rm -f "$_error_file"

  #verify_video_file
  #mv -f "$video_file.part" "$video_file"
}

####

verify_video_file() {
  #if is_false "$skip_verify_video_file"; then

  reset_trap

  local _error_file

  _error_file="$(mktemp --dry-run "$TMPDIR/$(basename "${0%.*}")-$(basename "${recording_file%.*}")-ffmpeg-verify-error.log.XXXXXX")"

  if is_true "$verify_fast"; then
    # Check only the end part
    # "grep -v": ignore subtitle "error" (https://trac.ffmpeg.org/ticket/2212)
    ffmpeg -nostdin -v error -sseof -60 -i "$video_file.part" -f null - 2>&1 |
      grep -v 'Application provided invalid, non monotonically increasing dts to muxer in stream' >"$_error_file"
  else
    #(
    #  printf 'Added file "%s" for full verification to the queue (lock file "%s")\n' "$video_file" "$QUEUE_LOCKFILE"
    #
    #  #sleep 4
    #  flock 9

    # Check the whole file
    ffmpeg -nostdin -v error -i "$video_file.part" -f null - 2>"$_error_file"

    #) 9>"$QUEUE_LOCKFILE"
  fi

  set_trap

  chmod "$file_permissions" "$_error_file"
  if [ -s "$_error_file" ]; then
    # Error in video file. Move files to the error folder
    mkdir -p -m "$folder_permissions" "$error_dir"

    local _recording_file_saved _temp_id
    _recording_file_saved="$(mktemp --dry-run "$error_dir/$(basename "${recording_file%.*}")-ffmpeg-verify-error.XXXXXX.${recording_file##*.}")"
    _temp_id="$(echo -n "$_recording_file_saved" | awk -F'.' '{print $(NF-1)}')"
    mv "$recording_file" "$_recording_file_saved"

    mv "$video_file.part" "$error_dir/$(basename "${video_file%.*}")-ffmpeg-verify-error.$_temp_id.${video_file##*.}"

    local _error_file_saved
    _error_file_saved="$error_dir/$(basename "${recording_file%.*}-ffmpeg-verify-error.$_temp_id.log")"
    mv "$_error_file" "$_error_file_saved"

    printf '%s: ERROR: ffmpeg error. See file "%s"\n' "${0##*/}" "$_error_file_saved" >&2
    #cat "$_error_file_saved" >&2
    run_error_scripts_postpro 'ffmpeg validation failed'
    exit 1
  fi

  #fi

  # No errors found in video file
  rm -f "$_error_file"
  mv -f "$video_file.part" "$video_file"
}

####

move_or_delete_recording_file() {
  if is_true "$keep_recording"; then
    local _dest_recording_file
    _dest_recording_file="$(realpath "$backup_dir/$(basename "$recording_file")")"

    [ "$(realpath "$recording_file")" = "$_dest_recording_file" ] && return

    if is_false "$force_overwrite" && [ -e "$_dest_recording_file" ]; then
      # Save recording file under a unique name, otherwise it may get overwritten by another recording with the same name
      _dest_recording_file="$(mktemp --dry-run "${_dest_recording_file%.*}.XXXXXX.${_dest_recording_file##*.}")"
    fi
    mv "$recording_file" "$_dest_recording_file"
  else
    rm "$recording_file"
  fi
}

####

run_postrun_scripts() {
  local _post_scripts_dir _script

  _post_scripts_dir="${config%/*}/post-scripts.d"
  [ -d "$_post_scripts_dir" ] || _post_scripts_dir="$config_dir_default/post-scripts.d"
  if [ -d "$_post_scripts_dir" ]; then
    for _script in "$_post_scripts_dir/"?*.sh; do
      [ -x "$_script" ] && . "$_script" "$video_file"
    done
  fi

  ####

  #printf 'Successfully transcoded video file "%s"\n' "$video_file"
}

####

error_help() {
  printf "Try '%s --help' for more information.\n" "${0##*/}" >&2
}

run_error_scripts_postpro() {
  run_error_scripts "Post-processor: $1"
}

run_error_scripts() {
  local _msg="$1"

  [ "$_msg" = OK ] && return

  local _error_scripts_dir _script
  _error_scripts_dir="${config%/*}/error-scripts.d"
  [ -d "$_error_scripts_dir" ] || _error_scripts_dir="$config_dir_default/error-scripts.d"
  if [ -d "$_error_scripts_dir" ]; then
    for _script in "$_error_scripts_dir/"?*.sh; do
      [ -x "$_script" ] && . "$_script" "$_msg"
    done
  fi
}

####

is_true() {
  # Convert to lowercase
  local _bool="${1,,}"

  [ "$_bool" = false ] || [ "$_bool" = no ] || [ "$_bool" = 0 ] || [ "$_bool" = '' ] || return 0 # Return true

  #return 1
  false
}

is_false() {
  is_true "$1" && return 1 # Return false

  #return 0
  true
}

####

main "$@"
