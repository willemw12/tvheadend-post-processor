Tvheadend post-processing scripts
=================================

Automatically transcode [Tvheadend](https://tvheadend.org/projects/tvheadend) recording files to smaller video files using the [HandBrake](https://handbrake.fr) command line tool.


Features
--------

- Transcode recording files to MKV or MP4 video files
- Keep or delete recording files after successful transcoding
- Delete kept recording files older than a specified number of days
- Verify transcoded video files using ffmpeg
- Configure HandBrake settings (crop, deinterlace, preset, ...)
- Run transcodings sequentially instead of in parallel
- Run pre-transcoding and post-transcoding scripts


Main scripts
------------

- tvheadend-post-processor.sh

  Transcode a recording file to a video file.
  This script is invoked from Tvheadend.

- tvheadend-post-processor-batch.sh

  Start or redo transcodings manually from outside Tvheadend.
  This is not a post-processor script for Tvheadend.


Additional scripts
------------------

- examples/my-tvheadend-post-processor.sh

  An example post-processor wrapper script that can:

    - skip post-processing of specific programmes and/or channels
    - set specific post-processing options per channel or a set of channels
    - ...

- examples/pre-scripts.d/10-pre-script.sh

  An example pre-transcoding script.


Dependencies
------------

Common dependencies:

- `awk`, `bash`, `ffmpeg`, `flock` and `getopt` (package `util-linux`), `handbrake-cli`


Installation
------------

Download the scripts:

    git clone https://github.com/willemw12/tvheadend-post-processor.git
    cd tvheadend-post-processor

The script(s) to be used by Tvheadend should be accessible to the Tvheadend user, usually "hts" or "tvheadend".

Optionally, copy the relevant scripts to another location, for example:

    sudo cp tvheadend-post-processor*.sh /usr/local/bin/


Configuration
-------------

### Set the post-processor command

From the main page of the Tvheadend's web interface, go to "Configuration" and then to "Recording".
Change "View level" to "Expert" or "Advanced". Set "Post-processor command", including at least
the following two arguments:

    tvheadend-post-processor.sh "%e" "%f"

An initial default configuration file is created by the script during the first post-processing.
To create the initial default configuration file manually, run, for example:

    sudo -u hts tvheadend-post-processor.sh

The default configuration file location for this user is /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf.

### Change the default configuration

Optionally, change some of the settings in the configuration file:

    KEEP_RECORDING=no
    TRANSCODING_PATH=/path/to/a/writable-folder
    # Uncomment to change or rename the video files folder
    #VIDEO_PATH=/path/to/a/writable-folder

and/or with command options:

    tvheadend-post-processor.sh --no-keep-recording --transcoding-path=/path/to/a/writable-folder "%e" "%f"


Help
----

For more detailed information, run:

    ./tvheadend-post-processor.sh --help

and see also the generated configuration file.


License
-------

These scripts are released under GPLv3. See included COPYING file.


Links
-----

The scripts are on [GitHub](https://github.com/willemw12/tvheadend-post-processor).

