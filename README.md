# Replication stopped with Transaction id must be equal to LSN of the first row in the transaction.

## Archive description

Archive provides 3 scripts to ease your setup:

- `run.sh` - starts 3 tarantools instance_00{1,2,3} in all-rw setup (full-mesh)
- `stop.sh` - SIGTERMs all 3 tarantools
- `clear.sh` - removes all files in `data/` directory
- `check.sh` - connects via iproto to every instance and counts upstreams and downstreams in status "follow".

Directory structure:

```bash
.
├── README.md
├── check.sh
├── clear.sh
├── data
│   ├── instance_001
│   │   ├── 00000000000000000010.snap
│   │   └── 00000000000000000010.xlog
│   ├── instance_002
│   │   ├── 00000000000000000000.snap
│   │   └── 00000000000000000000.xlog
│   └── instance_003
│       ├── 00000000000000000009.snap
│       └── 00000000000000000009.xlog
├── init.lua
├── instance_001.lua -> init.lua
├── instance_002.lua -> init.lua
├── instance_003.lua -> init.lua
├── logs
│   ├── instance_001.lua.log
│   ├── instance_002.lua.log
│   └── instance_003.lua.log
├── run.sh
└── stop.sh
```

## Steps to reproduce

Execute `run.sh`

```bash
$ bash run.sh
```

Wait until all tarantools are ok (just spam check.sh)

```bash
❯ ./check.sh
127.0.0.1:3301 not follows everyone (follows: 3, should be 4)
127.0.0.1:3302 - OK
127.0.0.1:3303 not follows everyone (follows: 3, should be 4)
❯ ./check.sh
127.0.0.1:3301 - OK
127.0.0.1:3302 - OK
127.0.0.1:3303 - OK
```

Run reproducer

```bash
tarantoolctl connect 127.0.0.1:3301 <<< "_G.sendmsg()"
```

And run checker `check.sh`

```bash
❯ ./check.sh
127.0.0.1:3301 not follows everyone (follows: 3, should be 4)
127.0.0.1:3302 not follows everyone (follows: 2, should be 4)
127.0.0.1:3303 not follows everyone (follows: 3, should be 4)
```

In logs you can find following messages:

```plain
==> logs/instance_001.lua.log <==
2023-08-07 12:15:53.146 [46530] main/122/main/instance_001 I> msg [1, 2, 1691399753.1458, {'text': 'ping'}] has been sent
2023-08-07 12:15:53.151 [46530] main/120/inbox/instance_001/instance_001 I> received message from 2: [1691399753.1484, 2, {'type': 'response', 'text': 'pong'}]
2023-08-07 12:15:53.151 [46530] main/120/inbox/instance_001/instance_001 I> [1] received response [1691399753.1484, 2, {'type': 'response', 'text': 'pong'}]
2023-08-07 12:15:53.158 [46530] relay/127.0.0.1:54445/101/main coio.c:349 E> SocketError: unexpected EOF when reading from socket, called on fd 21, aka 127.0.0.1:3301, peer of 127.0.0.1:54445: Broken pipe
2023-08-07 12:15:53.158 [46530] relay/127.0.0.1:54445/101/main I> exiting the relay loop

==> logs/instance_002.lua.log <==
2023-08-07 12:15:53.148 [46529] relay/127.0.0.1:54453/101/main I> recover from `data/instance_002/00000000000000000010.xlog'
2023-08-07 12:15:53.149 [46529] main/112/applier/127.0.0.1:3303 I> can't read row
2023-08-07 12:15:53.149 [46529] main/112/applier/127.0.0.1:3303 applier.cc:1146 E> ER_PROTOCOL: Transaction id must be equal to LSN of the first row in the transaction.
2023-08-07 12:15:53.152 [46529] main/110/applier/127.0.0.1:3301 I> can't read row
2023-08-07 12:15:53.152 [46529] main/110/applier/127.0.0.1:3301 applier.cc:1146 E> ER_PROTOCOL: Transaction id must be equal to LSN of the first row in the transaction.

==> logs/instance_003.lua.log <==
2023-08-07 12:15:53.148 [46531] main/124/inbox/instance_003/instance_003 I> received message from 1: [1691399753.1458, 1, {'text': 'ping'}]
2023-08-07 12:15:53.148 [46531] main/124/inbox/instance_003/instance_003 I> [2] received message from 1: [1691399753.1458, 1, {'text': 'ping'}]
2023-08-07 12:15:53.149 [46531] main/124/inbox/instance_003/instance_003 I> response to [1691399753.1458, 1, {'text': 'ping'}] has been sent
2023-08-07 12:15:53.153 [46531] relay/127.0.0.1:54454/101/main coio.c:349 E> SocketError: unexpected EOF when reading from socket, called on fd 30, aka 127.0.0.1:3303, peer of 127.0.0.1:54454: Broken pipe
2023-08-07 12:15:53.153 [46531] relay/127.0.0.1:54454/101/main I> exiting the relay loop
```

In this case instance_001 was sending message to instance_003. And instance_003 was responding to instance_001.

But replication from instance_003 to instance_002 and instance_001 to instance_002 became stopped due to

```bash
2023-08-07 12:15:53.149 [46529] main/112/applier/127.0.0.1:3303 applier.cc:1146 E> ER_PROTOCOL: Transaction id must be equal to LSN of the first row in the transaction.
```
