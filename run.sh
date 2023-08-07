#!/bin/bash

mkdir -p logs/;

start() {
	name="$1";
	if [ ! -f "$name" ]; then
		>&2 echo "file $name not found";
		exit 1;
	fi;

	log_file="logs/$(basename "$name").log"

	dat=$(date "+%Y-%m-%d at %H:%M:%S")
	echo "======= Starting $name at $dat =======" >> "$log_file"
	tarantool "$name" 2>> "$log_file" >> "$log_file";
}

start "instance_001.lua" &
start "instance_002.lua" &
start "instance_003.lua" &
