#!/bin/bash
set -eu

function is_leader () {
	tarantoolctl connect "$1" <<< "box.info.ro == false" 2> /dev/null | tail -3 | head -1 | sed -e 's/[- ]//g';
}

for port in {3301..3303}; do
	addr="127.0.0.1:$port";
	rw=$(is_leader "$addr");
	if [ "$rw" == "true" ]; then
		# echo "Leader is $addr";
		lsof -Pi ":$port" | grep "\*:$port" | awk '{ print $2 }';
	fi;
done;

