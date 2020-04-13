#!/bin/sh
# This script will monitor scan folder for files
# if the size doesn't change of a file in 5 seconds
# the file will be copied to a backup location
# and the mayan watch folder.
while true; do
  file=`find /volume1/Scans -type f ! -iname *.size`
  for f in $file; do
    size=`ls -al "$f"|cut -d " " -f 5`
    if [ -f "$f.size" ]; then
      psize=`cat "$f.size"`
      if [ "$size" == "$psize" ]; then
        echo copy
        d=`echo $f | cut -d "/" -f 3-`
        dir=`dirname -- "/$d"`
        mkdir -p "/volume1/Backup$dir"
        mkdir -p "/volume1/docker/mayan-edms$dir"
        cp -R "$f" "/volume1/Backup/$d"
        cp -R "$f" "/volume1/docker/mayan-edms/$d"
        chmod 0777 "/volume1/docker/mayan-edms/$d"
        rm "$f"
        rm "$f.size"
      else
        echo "$size" > "$f.size"
      fi
    else
      echo "$size" > "$f.size"
    fi
  done
  sleep 15
done
