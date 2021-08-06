#!/bin/bash
set -eux

exec &> >(tee tarantool.log);

rm -rvf .tnt;
mkdir -p .tnt/tnt{1,2,3};

tarantool client.lua &
tarantool tnt1/init.lua &
tarantool tnt2/init.lua &
tarantool tnt3/init.lua &

wait;
wait;
wait;
wait;