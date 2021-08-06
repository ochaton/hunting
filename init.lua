require('strict').on()

local fiber = require 'fiber'
local log = require 'log'
local fio = require 'fio'

local instance_name = fio.basename(fio.dirname(fio.abspath(debug.getinfo(1, "S").source:match("^@(.+)$"))))
log.info("MY HOSTNAME: %s", instance_name)

local uuids = {
	tnt1 = "aaaaaaaa-0001-0000-0000-000000000001",
	tnt2 = "aaaaaaaa-0002-0000-0000-000000000001",
	tnt3 = "aaaaaaaa-0003-0000-0000-000000000001",
}

box.cfg{
	instance_uuid = assert(uuids[instance_name], "failed to get instance_uuid"),
	replicaset_uuid = 'f4ad5d13-28a2-48ed-a4a6-3d6b93b8d9c8',
	listen = 3300+instance_name:match("%d+"),
	custom_proc_title = instance_name,
	memtx_dir = '.tnt/'..instance_name,
	wal_dir = '.tnt/'..instance_name,
	replication = { "127.0.0.1:3301", "127.0.0.1:3302", "127.0.0.1:3303" },
	election_mode = 'candidate',
	replication_synchro_quorum = 2,
	replication_connect_quorum = 2,
	replication_connect_timeout = 5,
	replication_timeout = 0.5,
	election_timeout = 0.5,
}

pcall(box.ctl.wait_rw, 3)
box.schema.user.grant('guest', 'super', nil, nil, { if_not_exists = true })

local json = require 'json'

fiber.create(function ()
	fiber.name("rwbell")
	local last_ro, last_rw
	if box.info.ro then
		last_ro = fiber.time()
	end
	while true do
		box.ctl.wait_rw()
		last_rw = fiber.time()
		log.info("RW vclock:%s election:%s (was ro:%.2fs)",
			json.encode(box.info.vclock),
			json.encode(box.info.election),
			fiber.time()-(last_ro or fiber.time()-box.info.uptime)
		)
		box.ctl.wait_ro()
		last_ro = fiber.time()
		log.info("RO vclock:%s election:%s (was rw:%.2fs",
			json.encode(box.info.vclock),
			json.encode(box.info.election),
			fiber.time()-(last_rw or fiber.time()-box.info.uptime)
		)
	end
end)