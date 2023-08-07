#!/bin/bash

check() {
	addr="$1";
	follow_n=$(tarantoolctl connect "$addr" <<< "box.info.replication" 2>/dev/null | grep -c follow)
	if [ "$follow_n" != 4 ]; then
		>&2 echo "$addr not follows everyone (follows: $follow_n, should be 4)";
	else
		echo "$addr - OK";
	fi;
}

check "127.0.0.1:3301"
check "127.0.0.1:3302"
check "127.0.0.1:3303"
