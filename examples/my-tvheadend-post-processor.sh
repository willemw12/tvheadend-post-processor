#!/usr/bin/env bash

# An example post-processor wrapper script that can:
#
#   - skip post-processing of specific programmes and/or channels
#   - set specific post-processing options per channel or a set of channels
#   - ...
#
# https://github.com/willemw12/tvheadend-post-processor, GPLv3

####

# Example: manage channel specific post-processing options:
#
#   Configuration:
#
#     - Record in 720p by default, except when the channel name ends on ' HD'.
#     - Crop away white dashes at the top the recording for one specific channel.
#
#   Setup for that configuration:
#
#     - In Tvheadend's web interface menu "Configuration" --> "Recording":
#         Post-processor command = my-tvheadend-post-processor.sh "%e" "%f" "%c"
#
#       Note the additional "channel name" format string "%c" at the end.
#
#     - Define default post-processing options:
#         File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf:
#             ...
#             options=(--deinterlace --crop=0:0:0:0 --preset='Very Fast 720p30')
#
#     - Either define specific post-processing options in separate config files:
#         File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor-1080p.conf:
#             ...
#             options=(--deinterlace --crop=0:0:0:0 --preset='Very Fast 1080p30')
#
#         File /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor-crop.conf:
#             ...
#             options=(--deinterlace --crop=1:0:0:0 --preset='Very Fast 720p30')
#
#         Pass the specific config file as command line argument in the case-statement as shown below (commented out).
#
#     - or pass the specific options directly as command line arguments in the case-statement as shown below.

####

# Here are some pattern matching examples containing space characters and wildcard characters (* and ?):
#
#     hd_channel_names='BBC * HD'
#
#     case "$channel_name" in
#       $hd_channel_names)
#         ...
#         ;;
#       'BBC '*' HD')
#         ...
#         ;;
#       BBC\ ?\ HD)
#         ...
#         ;;

script=tvheadend-post-processor.sh

main() {
  if (($# < 3)); then
    printf '%s: argument(s) missing\n' "${0##*/}" >&2
    error_help
    exit 1
  fi

  args=("$@")

  # Get last argument
  channel_name="${args[-1]}"

  # Get second last argument
  recording_fullname="${args[-2]}"

  recording_name="${recording_fullname##*/}"

  ####

  # Skip post-processing of specific programmes
  case "$recording_name" in
    # Skip a programme
    'BBC News at One-'*'.ts')
      skip_postpro "$recording_fullname"
      ;;

    # Skip programmes on specific channels
    'BBC News'*'-'*'.ts')
      if [[ "$channel_name" == 'BBC '*' HD' ]]; then
        skip_postpro "$recording_fullname"
      fi
      ;;
  esac

  # Skip post-processing of specific channels
  case "$channel_name" in
    # Skip a channel
    'BBC One')
      skip_postpro "$recording_fullname"
      ;;

    # Skip channels
    'BBC '*' HD' | 'BBC Two')
      skip_postpro "$recording_fullname"
      ;;
  esac

  ####

  # Set default options
  options=()

  # Add or set specific post-processing options for programmes
  #case "$recording_name" in
  #  ...
  #esac

  # Add or set specific post-processing options for channels
  case "$channel_name" in
    'BBC One' | 'BBC Two')
      #options+=(--config=tvheadend-post-processor-crop.conf)
      options+=(--option=crop=1:0:0:0)
      ;;

    *' HD')
      #options+=(--config=tvheadend-post-processor-1080p.conf)
      options+=(--option='preset=Very Fast 1080p30')
      ;;

    -h | --help)
      error_help
      exit 0
      ;;

    *)
      #options=()
      ;;
  esac

  # Run script
  $script "${options[@]}" "$@"
}

####

error_help() {
  printf 'See setup comments in this script.\n' >&2
}

skip_postpro() {
  printf "Skip post-processing file '%s'\n" "$1"
  exit 0
}

####

main "$@"
