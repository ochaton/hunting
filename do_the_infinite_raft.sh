#!/bin/bash
set -eux
RWPID=$(./get_leader_pid.sh);
echo "RWPID is discovered: $RWPID";
echo "Executing ps aux";
ps aux | grep "$RWPID";

echo "Executing lsof";
lsof -p "$RWPID";

echo "sending SIGSTOP to $RWPID";
kill -STOP "$RWPID";

echo "sleeping for 2 seconds";
sleep 2;

echo "sending CONT to $RWPID";
kill -CONT "$RWPID";

echo "sleeping for 2 seconds";
sleep 2;

echo "New RW: $(./get_leader_pid.sh)";
