RAILCART_ENTITY_UPDATE_TIME = 1
RAILCART_OBJECT_UPDATE_TIME = 5
RAILCART_OBJECT_SAVE_TIME = 10
RAILCART_RELOAD_DISTANCE = 32
RAILCART_SNAP_DISTANCE = 0.5
RAILCART_SPEED_PUSH = 5
RAILCART_SPEED_MIN = 0.1
RAILCART_SPEED_MAX = 20

railcart = {
	timer = 0,
	allcarts = {},
}

railcart.cart = {
	id = nil,
	entity = {},
	pos = nil,
	target = nil,
	prev = nil,
	accel = nil,
	inv = nil,
	dir = {x=0, y=0, z=0},
	vel = {x=0, y=0, z=0},
	acc = {x=0, y=0, z=0},
	timer = 0,
}

function railcart.cart:new(obj)
	obj = obj or {}
	setmetatable(obj, self)
	self.__index = self
	return obj
end

function railcart.cart:is_loaded()
	for _, player in pairs(minetest.get_connected_players()) do
		local pos = player:getpos()
		if pos then
			local dist = railtrack:get_distance(pos, self.pos)
			if dist <= RAILCART_RELOAD_DISTANCE then
				return true
			end
		end
	end
	return false
end

function railcart.cart:on_step(dtime)
	self.timer = self.timer - dtime
	if self.timer > 0 then
		return
	end
	self.timer = RAILCART_OBJECT_UPDATE_TIME
	local entity = railcart:get_cart_ref(self.id)
	if entity.object then
		return
	end
	if self:is_loaded() then
		local object = minetest.add_entity(self.pos, "railcart:cart_entity")
		if object then
			entity = object:get_luaentity() or {}
			entity.cart = self
			object:setvelocity(self.vel)
			object:setacceleration(self.acc)
		end
	else
		self.timer = railcart:update(self, self.timer)
	end
end

function railcart:save()
	local carts = {}
	for id, cart in pairs(railcart.allcarts) do
		local ref = {}
		for k, v in pairs(cart) do
			ref[k] = v
		end
		local inv = {}
		if ref.inv then
			local list = ref.inv:get_list("main")
			for i, stack in ipairs(list) do
			  inv[i] = stack:to_string()
			end
		end
		ref.inv = inv
		ref.entity = nil
		table.insert(carts, ref)
	end
	local output = io.open(minetest.get_worldpath().."/railcart.txt",'w')
	if output then
		output:write(minetest.serialize(carts))
		io.close(output)
	end
end

function railcart:create_detached_inventory(id)
	local inv = minetest.create_detached_inventory("railcart_"..tostring(id), {
		on_put = function(inv, listname, index, stack, player)
			railcart:save()
		end,
		on_take = function(inv, listname, index, stack, player)
			railcart:save()
		end,
		allow_put = function(inv, listname, index, stack, player)
			return 1
		end,
		allow_take = function(inv, listname, index, stack, player)
			return stack:get_count()
		end,
		allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			return count
		end,
	})
	inv:set_size("main", 32)
	return inv
end

function railcart:get_cart_ref(id)
	local cart_ref = {}
	for _, ref in pairs(minetest.luaentities) do
		if ref.cart then
			if ref.cart.id == id then
				cart_ref = ref
				break
			end
		end
	end
	return cart_ref
end

function railcart:get_delta_time(vel, acc, dist)
	if vel > 0 then
		if acc == 0 then
			return dist / vel
		end
		local r = math.sqrt(vel * vel + 2 * acc * dist)
		if r > 0 then
			return (-vel + r) / acc
		end
	end
	return 9999 --INF
end

function railcart:velocity_to_dir(v)
	if math.abs(v.x) > math.abs(v.z) then
		return {x=railtrack:get_sign(v.x), y=railtrack:get_sign(v.y), z=0}
	else
		return {x=0, y=railtrack:get_sign(v.y), z=railtrack:get_sign(v.z)}
	end
end

function railcart:velocity_to_speed(vel)
	local speed = math.max(math.abs(vel.x), math.abs(vel.z))
	if speed < RAILCART_SPEED_MIN then
		speed = 0
	elseif speed > RAILCART_SPEED_MAX then
		speed = RAILCART_SPEED_MAX
	end
	return speed
end

function railcart:get_target(pos, vel)
	local meta = minetest.get_meta(vector.round(pos))
	local dir = self:velocity_to_dir(vel)
	local targets = {}
	local rots = RAILTRACK_ROTATIONS
	local contype = meta:get_string("contype") or ""
	local s_junc = meta:get_string("junctions") or ""
	local s_cons = meta:get_string("connections") or ""
	local s_rots = meta:get_string("rotations") or ""
	if contype == "section" then
		local junctions = minetest.deserialize(s_junc) or {}
		for _, p in pairs(junctions) do
			table.insert(targets, p)
		end
	else
		local cons = minetest.deserialize(s_cons) or {}
		for _, p in pairs(cons) do
			table.insert(targets, p)
		end
		if s_rots ~= "" then
			local fwd = false
			for _, p in pairs(cons) do
				if vector.equals(vector.add(pos, dir), p) then
					fwd = true
				end
			end
			if fwd == true or #cons == 1 then
				rots = s_rots
			end
		end
	end
	local rotations = railtrack:get_rotations(rots, dir)
	for _, r in ipairs(rotations) do
		for _, t in pairs(targets) do
			local d = railtrack:get_direction(t, pos)
			if r.x == d.x and r.z == d.z then
				return t
			end
		end
	end
end

function railcart:update(cart, time, object)
	if object then
		cart.pos = object:getpos()
		cart.vel = object:getvelocity()
	end
	if not cart.target then
		cart.pos = vector.new(cart.prev)
		cart.target = railcart:get_target(cart.pos, cart.vel)
		if object then
			object:moveto(cart.pos)
		end
	end
	local speed = railcart:velocity_to_speed(cart.vel)
	if not cart.target then
		speed = 0
	end
	if speed > RAILCART_SPEED_MIN then
		cart.dir = railtrack:get_direction(cart.target, cart.pos)
		local d1 = railtrack:get_distance(cart.prev, cart.target)
		local d2 = railtrack:get_distance(cart.prev, cart.pos)
		local dist = d1 - d2
		if dist > RAILCART_SNAP_DISTANCE then
			local accel = RAILTRACK_ACCEL_FLAT
			if cart.dir.y == -1 then
				accel = RAILTRACK_ACCEL_DOWN
			elseif cart.dir.y == 1 then
				accel = RAILTRACK_ACCEL_UP
			end
			accel = cart.accel or accel
			if object then
				dist = math.max(dist - RAILCART_SNAP_DISTANCE, 0)
			end
			local dt = railcart:get_delta_time(speed, accel, dist)
			if dt < time then
				time = dt
			end
			local dp = speed * time + 0.5 * accel * time * time
			local vf = speed + accel * time
			if object then
				if vf <= 0 then
					speed = 0
					accel = 0
				end
				cart.vel = vector.multiply(cart.dir, speed)
				cart.acc = vector.multiply(cart.dir, accel)
			elseif dp > 0 then
				cart.vel = vector.multiply(cart.dir, vf)
				cart.pos = vector.add(cart.pos, vector.multiply(cart.dir, dp))
			end
		else
			cart.pos = vector.new(cart.target)
			cart.prev = vector.new(cart.target)
			cart.accel = railtrack:get_acceleration(cart.target)
			cart.target = nil
			return 0
		end
	else
		cart.vel = {x=0, y=0, z=0}
		cart.acc = {x=0, y=0, z=0}
	end
	if object then
		if cart.dir.y == -1 then
			object:set_animation({x=1, y=1}, 1, 0)
		elseif cart.dir.y == 1 then
			object:set_animation({x=2, y=2}, 1, 0)
		else
			object:set_animation({x=0, y=0}, 1, 0)
		end
		if cart.dir.x < 0 then
			object:setyaw(math.pi / 2)
		elseif cart.dir.x > 0 then
			object:setyaw(3 * math.pi / 2)
		elseif cart.dir.z < 0 then
			object:setyaw(math.pi)
		elseif cart.dir.z > 0 then
			object:setyaw(0)
		end
		object:setvelocity(cart.vel)
		object:setacceleration(cart.acc)
	end
	return time
end

