#!/bin/bash
# Shorten a path: ~/long/path/to/project -> ~/l/p/to/project
echo "$1" | sed "s|^$HOME|~|" | awk -F/ 'BEGIN{ORS=""}{for(i=1;i<NF;i++) printf "%s/", substr($i,1,1); print $NF}'
