#!/bin/bash

stop() {
	process_name="$1"
	pid=$(pgrep "$process_name");
	if [ "$pid" != "" ]; then
		echo "kill (-15) $process_name pid $pid";
		kill -15 "$pid";
	else
		echo "process with title $process_name not found";
	fi;
}

stop "instance_001.lua"
stop "instance_002.lua"
stop "instance_003.lua"
