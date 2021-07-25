# Bug hunting (Tarantool replication)

## Bootstrap 2 clusters even if quorums are satisfied
Run `docker compose up` until all instances left running.
Then enter each instance using `docker compose exec tnt1 tarantoolctl connect 3301` and see what happens.

## Too long RAFT election
Got it!

Run compose up `docker compose up`.
Then do (check that tnt1 is the leader):
`docker compose pause tnt1; sleep 2; docker compose unpause tnt1`

Moreover we catch replication conflicts:
```
tnt1_1    | 2021-07-25 08:38:45.958 [1] main/112/applier/tnt3:3301 applier.cc:298 E> error applying row: {type: 'INSERT', replica_id: 3, lsn: 2, space_id: 512, index_id: 0, tuple: [712, {0: 5, 1: 719, 3: 1}, {"state": "leader", "vote": 3, "leader": 3, "term": 6}, 1.6272e+09]}
tnt1_1    | 2021-07-25 08:38:45.958 [1] main/112/applier/tnt3:3301 I> can't read row
tnt1_1    | 2021-07-25 08:38:45.958 [1] main/112/applier/tnt3:3301 memtx_tree.cc:863 E> ER_TUPLE_FOUND: Duplicate key exists in unique index "pri" in space "test" with old tuple - [712, {0: 2, 1: 719}, {"state": "leader", "vote": 1, "leader": 1, "term": 2}, 1.6272e+09] and new tuple - [712, {0: 5, 1: 719, 3: 1}, {"state": "leader", "vote": 3, "leader": 3, "term": 6}, 1.6272e+09]
```
