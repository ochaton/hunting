# Bug hunting (Tarantool replication)

## Bootstrap 2 clusters even if quorums are satisfied
Run `docker compose up` until all instances left running.
Then enter each instance using `docker compose exec tnt1 tarantoolctl connect 3301` and see what happens.

## Too long RAFT election
[Look here](https://github.com/ochaton/hunting/tree/infinite-raft)