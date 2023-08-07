#!/usr/bin/env tarantool

local log = require 'log'
local fio = require 'fio'
local fiber = require 'fiber'
local name = fio.basename(arg[0], "%.lua")

local listen_cfg = {
	instance_001 = '127.0.0.1:3301',
	instance_002 = '127.0.0.1:3302',
	instance_003 = '127.0.0.1:3303',
}

local iproto_listen = listen_cfg[name]
if not iproto_listen then
	error(("No iproto_listen configured for %q. Did you execute symlink?")
		:format(name), 0)
end

local data_dir = fio.pathjoin("data/", name)
assert(fio.mktree(data_dir))
log.info("created dir %s", data_dir)

local inbox_notify = fiber.cond()

box.cfg{
	read_only = false,
	listen = iproto_listen,
	replication = { '127.0.0.1:3301', '127.0.0.1:3302', '127.0.0.1:3303' },
	wal_dir = data_dir,
	memtx_dir = data_dir,
	vinyl_dir = data_dir,
}

-- grant everything
box.schema.user.grant('guest', 'super', nil, nil, { if_not_exists = true })

-- wait for 1s to become rw
box.ctl.wait_rw(1)
assert(not box.info.ro, "must become rw")

-- create DDL
box.schema.space.create('bus', {
	if_not_exists = true,
	format = {
		{ name = 'src',     type = 'unsigned' },
		{ name = 'dst',     type = 'unsigned' },
		{ name = 'time',    type = 'number'   }, -- creation time
		{ name = 'message', type = 'any'      }, -- just payload
	},
})

box.space.bus:create_index('primary', {
	if_not_exists = true,
	parts = { 'src', 'time' },
})

box.space.bus:create_index('inbox', {
	if_not_exists = true,
	parts = { 'dst', 'time', 'src' },
})

box.schema.space.create('inbox', {
	if_not_exists = true,
	is_local = true, -- inbox is local space
	format = {
		{ name = 'time',    type = 'number' }, -- arrival time
		{ name = 'src',     type = 'unsigned' }, -- sender
		{ name = 'message', type = 'any' },
	},
})

box.space.inbox:create_index('primary', {
	if_not_exists = true,
	parts = { 'time' }, -- time is unique
})

-- now goes trigger
box.space.bus:on_replace(function (old_tuple, new_tuple)
	if box.session.type() ~= "applier" then
		return
	end

	-- this code executes only inside applier
	if old_tuple or not new_tuple then
		-- update or delete of existing data => we do nothing
		return
	end

	if new_tuple.dst ~= box.info.id then
		-- not our message, just skip
		return
	end

	-- our message
	-- insert into local space (extend transaction)
	box.space.inbox:insert{
		new_tuple.time,
		new_tuple.src,
		new_tuple.message,
	}

	box.on_commit(function()
		-- notify listenner (broadcast never yields)
		-- we do it inside on_commit to ensure data has been written to wal
		-- and we already exiting from transaction
		inbox_notify:broadcast()
	end)
end)

fiber.new(function()
	fiber.name("inbox/"..name)
	log.info("inbox listenner has been started")

	while true do
		while box.space.inbox:len() > 0 do

			local letter = box.space.inbox:pairs():nth(1)
			log.info("received message from %s: %s", letter.src, letter)

			if letter.message.type == 'response' then
				log.info("[%s] received response %s", box.info.id, letter)

				box.begin()
					box.space.inbox:delete({ letter.time }) -- just remove response
					if box.space.bus:get({ letter.src, letter.time }) then
						box.space.bus:delete({ letter.src, letter.time }) -- remove message from bus
					end
				box.commit()
			else
				log.info("[%s] received message from %s: %s", box.info.id, letter.src, letter)
				-- we have message inside local inbox, remove it from common bus
				if box.space.bus:get({ letter.src, letter.time }) then
					box.space.bus:delete({ letter.src, letter.time })
				end

				-- now prepare response
				-- in general preparing response can be very hard
				box.begin()
					box.space.bus:insert{
						box.info.id,  -- source
						letter.src,   -- destination
						fiber.time(), -- local time
						{ type = 'response', text = 'pong' },
					}
					-- and clear local inbox
					box.space.inbox:delete({ letter.time })
				box.commit()
				log.info("response to %s has been sent", letter)
			end
		end

		inbox_notify:wait(1)
	end
end)

function _G.sendmsg()
	local dst
	if box.info.id ~= 1 then
		dst = 1
	else
		dst = 2
	end
	local msg = box.space.bus:insert{
		box.info.id, -- source
		dst, -- destination
		fiber.time(), -- local time
		{ text = 'ping' }, -- message
	}

	log.info("msg %s has been sent", msg)
end
