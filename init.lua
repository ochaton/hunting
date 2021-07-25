require('strict').on()

local ips = {}

local function mydockername()
	for _, name in ipairs{"tnt1", "tnt2", "tnt3", "$HOSTNAME"} do
		ips[name] = io.popen("ping -c 1 "..name.." | head -1 | awk '{ print $3 }' | grep -oE '((\\d|\\.)+)'")
			:read("*all"):gsub("\n", "")
	end
	local myip = ips["$HOSTNAME"]
	for hostname, ip in pairs(ips) do
		if ip == myip then
			return hostname
		end
	end
end

local fiber = require 'fiber'
local log = require 'log'

local docker_name = assert(mydockername(), "my hostname wasn't discovered")
log.info("MY HOSTNAME: %s", docker_name)

os.execute("sleep 5")

local uuids = {
	tnt1 = "4c159958-a66c-41e4-9aa8-a197a672dcb8",
	tnt3 = "94355c39-2eb2-4e01-8c8b-ea407bb76f47",
	tnt2 = "a6fb5ff2-7e84-4ecf-b311-0ae70f37fb8e",
}

io.popen("tc qdisc add dev eth0 root netem delay 50ms"):read("*all")

-- DROP tnt1 -> tnt3 and tnt3 -> tnt1 packages
-- if docker_name == "tnt1" then
-- 	io.popen("iptables -I INPUT -s "..ips["tnt3"].." -j DROP"):read("*all")
-- elseif docker_name == "tnt3" then
-- 	io.popen("iptables -I INPUT -s "..ips["tnt1"].." -j DROP"):read("*all")
-- end

box.cfg{
	instance_uuid = assert(uuids[docker_name], "failed to get instance_uuid"),
	replicaset_uuid = 'f4ad5d13-28a2-48ed-a4a6-3d6b93b8d9c8',
	listen = '0.0.0.0:3301',
	replication = { "tnt1:3301", "tnt2:3301", "tnt3:3301" },
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