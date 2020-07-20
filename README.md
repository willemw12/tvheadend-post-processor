Tvheadend post-processor/post-processing scripts
================================================

Automatically transcode [Tvheadend](https://tvheadend.org/projects/tvheadend) recording files to smaller video files using HandBrake.


Features
--------

- Transcode recording files to MKV or MP4 video files
- Keep or delete recording files after successful transcoding
- Delete kept recording files older than a specified number of days
- Verify transcoded video files using ffmpeg
- Configure HandBrake settings (crop, deinterlace, preset, ...)
- Run pre-transcoding and post-transcoding scripts


Main scripts
------------

- tvheadend-post-processor.sh

  Transcode a recording file to a video file.
  The script is invoked from Tvheadend.

- tvheadend-post-processor-batch.sh

  Start or redo transcodings manually from outside Tvheadend.
  This is not a post-processor script for Tvheadend.


Additional scripts
------------------

- tvheadend-post-processor-queue.sh

  A variant of the main tvheadend-post-processor.sh script, which uses task-spooler to run transcodings sequentially instead of in parallel.
  The script is invoked from Tvheadend.

  Use of the main tvheadend-post-processor.sh script instead is recommended. The main script already runs with low process priority and I/O priority.

- examples/my-tvheadend-post-processor.sh

  An example script that shows how to set specific transcoding options per channel or a set of channels.


Dependencies
------------

Common dependencies:

- bash, ffmpeg, getopt (util-linux), handbrake-cli

For tvheadend-post-processor-batch.sh also:

- sudo

For tvheadend-post-processor-queue.sh also:

- task-spooler


Installation
------------

Download the scripts:

    git clone https://github.com/willemw12/tvheadend-post-processor.git
    cd tvheadend-post-processor

Copy the scripts to a location accessible to Tvheadend's 'hts' user. For example, in one of its $PATH paths:

    sudo cp tvheadend-post-processor*.sh /usr/local/bin/


Configuration
-------------

Configure the Tvheadend's web interface to use one of the scripts. From the main page, go to
"Configuration" and then to "Recording". Set "Post-processor command" to, for example:

    tvheadend-post-processor.sh --keep-recording "%e" "%f"

To change the default configuration, edit the configuration file, which is located at /home/hts/.config/tvheadend-post-processor/tvheadend-post-processor.conf.

To create the default configuration file manually, run:

    sudo -u hts tvheadend-post-processor.sh


Help
----

For more information, run:

    ./tvheadend-post-processor.sh --help


License
-------

These scripts are released under GPLv3. See included COPYING file.


Links
-----

The scripts are on [GitHub](https://github.com/willemw12/tvheadend-post-processor).

