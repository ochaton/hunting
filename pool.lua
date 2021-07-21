#!/usr/bin/env tarantool

local fiber = require 'fiber'
local netbox = require 'net.box'
local fun = require 'fun'
local log = require 'log'
local clock = require 'clock'


local function count(t)
	local c = 0
	for _ in pairs(t) do c = c + 1 end
	return c
end

local function pack(...)
	return { n = select('#', ...), ... }
end

return setmetatable({
	route = function(self, mode)
		local cnn
		local nodes = self[mode]

		local deadline = fiber.time() + self.timeout

		local discovered
		while fiber.time() < deadline do
			local _
			_, cnn = fun.iter(nodes):drop(math.random(count(nodes))-1):nth(1)
			if cnn then
				if discovered then
					log.warn("Master discovered: %s:%s (%s) in %.3fs",
						cnn.host, cnn.port, cnn.peer_uuid, clock.time()-deadline+self.timeout)
				end
				return cnn
			end

			log.info("Waiting for master for %.3fs", deadline-clock.time())
			if not self.wait[mode]:wait(deadline - clock.time()) then
				return box.error(box.error.TIMEOUT)
			end
			discovered = true
			fiber.testcancel()
		end
		return box.error(box.error.TIMEOUT)
	end,

	on_connect = function(self, addr, cnn)
		log.info("Connected to %s:%s (%s)", cnn.host, cnn.port, cnn.peer_uuid)
		cnn:wait_state{ active = true }

		if self.wrap_rw then
			cnn:eval [[
				function box.session.storage.rwcall(func, ...)
					if box.info.ro then
						return box.error(box.error.new{ code = 1, message = "Not a master" })
					end
					return box.internal.call_loadproc(func)(...)
				end
			]]
		end

		-- start ping
		while self.need[addr] do
			local ok, box_info = pcall(cnn.call, cnn, 'box.info')
			if ok then
				cnn.box_info = box_info

				if cnn.box_info.ro then
					self:register('ro', addr, cnn)
				else
					self:register('rw', addr, cnn)
				end
			else
				self:unregister(addr, cnn)
			end
			self.discovery:wait(self.pull_timeout)
		end

		cnn:close()
		return
	end,

	on_disconnect = function(self, addr, cnn)
		self:unregister(addr, cnn)
	end,

	__call = function(self, func, opts, ...)
		::again::
		if opts.deadline < fiber.time() then
			return box.error(box.error.TIMEOUT)
		end
		local mode = opts.mode or 'rw'
		local cnn = self:route(mode)
		if self.wrap_rw and mode == 'rw' then
			local r = pack(pcall(cnn.call, cnn, 'box.session.storage.rwcall', {func, ...}, {
				timeout = opts.deadline - fiber.time()
			}))
			if r[1] then
				return unpack(r, 2, r.n)
			end

			local err = r[2]
			if err:unpack().code == 1 then
				self.discovery:broadcast()
				fiber.yield()
				goto again
			end
			return box.error(err)
		else
			return cnn:call(func, {...}, { timeout = opts.deadline - fiber.time() })
		end
	end,

	call = function(self, func, mode, ...)
		return self:__call(func, { mode = mode, deadline = fiber.time()+self.timeout }, ...)
	end,

	callrw = function(self, func, ...)
		return self:call(func, 'rw', ...)
	end,

	callro = function(self, func, ...)
		return self:call(func, 'ro', ...)
	end,

	__connect_single = function (self, addr)
		local cnn = netbox.connect(addr, {
			connect_timeout = self.connect_timeout or self.timeout,
			reconnect_after = self.reconnect,
			wait_connected = false,
		})

		cnn:on_connect(function()
			fiber.create(function() self:on_connect(addr, cnn) end)
		end)

		cnn:on_disconnect(function()
			fiber.create(function() self:on_disconnect(addr, cnn) end)
		end)
	end,

	register = function(self, mode, addr, cnn)
		local b = assert(self[mode])
		local notmode = mode == 'ro' and 'rw' or 'ro'
		local notb = self[notmode]

		if b[addr] ~= cnn then
			b[addr] = cnn
			log.info("%s became %s", addr, mode)
		end

		self.wait[mode]:broadcast()

		if notb[addr] then
			log.info("%s not %s anymore", addr, notmode)
			notb[addr] = nil
		end
	end,

	unregister = function(self, addr, cnn)
		if self.ro[addr] == cnn then
			self.ro[addr] = nil
			log.info("%s lost was ro", addr)
		end
		if self.rw[addr] == cnn then
			self.rw[addr] = nil
			log.info("%s lost was rw", addr)
		end
	end,

	connect = function(self)
		for _, addr in ipairs(self.addrs) do
			self.need[addr] = true
			fiber.create(self.__connect_single, self, addr)
		end
	end,
}, {
	__call = function(self, eps, opts)
		opts = opts or {}
		self.__index = self
		self = setmetatable({
			need = {},
			wait = {
				rw = fiber.cond(),
				ro = fiber.cond(),
			},
			ro = {},
			rw = {},
			discovery = fiber.cond(),
			waitcnn = {},
			wrap_rw   = true,
			addrs     = eps,
			timeout   = opts.timeout or 0.5,
			reconnect = opts.reconnect or 0.3,
			pull_timeout = opts.pull_timeout or 0.1,
		}, self)

		if opts.wrap_rw == false then
			self.wrap_rw = false
		end

		self:connect()
		return self
	end,
})