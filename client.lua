local pool = require 'pool'(
	{ "127.0.0.1:3301", "127.0.0.1:3302", "127.0.0.1:3303" },
	{ timeout = 10 }
)

local log = require('log')
local json = require('json')
local fiber = require('fiber')

local function loop()
	local info = pool:callrw('dostring', [[
		box.schema.space.create('test', { if_not_exists = true })
		box.space.test:create_index('pri', { if_not_exists = true })
		return box.info
	]])
	log.info("DDL complete on %s/%s", info.id, json.encode(info.vclock), json.encode(info.election))
	log.info(pool:callrw('box.info'))

	for i = 1, 1e6 do
		pool:callrw('dostring', [[
			box.space.test:insert{
				box.space.test:len(),
				box.info.vclock,
				box.info.election,
				require 'fiber'.time(),
			}
		]])
		if i % 1e3 == 0 then
			log.info("Completed %s", i)
		end
		fiber.sleep(0.03)
	end
end

fiber.create(function()
	while true do
		local ok, err = pcall(loop)
		if not ok then
			log.error(err)
		else
			break
		end
	end
end)
