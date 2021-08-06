# Bug hunting (Tarantool replication)

## Too long RAFT election
Run bash script `./run.sh`.

Wait several seconds (5-10) when cluster will fully bootstrap and client will push messages;

Run in separate console `./get_leader_pid.sh` to make sure that cluster has been elected new Leader.
Run in separate console `./do_the_infinite_raft.sh` script to reproduce the issue (sometimes it takes more than once to do it).

You may read merged logs in `tarantool.log` file.