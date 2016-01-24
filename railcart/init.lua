local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath.."/railcart.lua")

local worldpath = minetest.get_worldpath()
local input = io.open(worldpath.."/railcart.txt", "r")
if input then
	local data = input:read('*all')
	if data then
		local carts = minetest.deserialize(data) or {}
		for id, ref in pairs(carts) do
			local cart = railcart.cart:new(ref)
			local inv = railcart:create_detached_inventory(cart.id)
			ref.inv = ref.inv or {}
			for i, stack in pairs(ref.inv) do
				inv:set_stack("main", i, stack)
			end
			cart.inv = inv
			railcart.allcarts[id] = cart
		end
	end
	input = nil
end

local function is_valid_player(object)
	if object then
		return object:is_player()
	end
end

minetest.register_globalstep(function(dtime)
	for _, cart in pairs(railcart.allcarts) do
		cart:on_step(dtime)
	end
	railcart.timer = railcart.timer + dtime
	if railcart.timer > RAILCART_OBJECT_SAVE_TIME then
		railcart:save()
		railcart.timer = 0
	end
end)

minetest.register_on_shutdown(function()
	railcart:save()
end)

minetest.register_privilege("carts", "Player can pick-up and place carts.")

minetest.register_entity("railcart:cart_entity", {
	physical = false,
	collisionbox = {-0.5,-0.5,-0.5, 0.5,0.5,0.5},
	visual = "mesh",
	mesh = "railcart.x",
	visual_size = {x=1, y=1},
	textures = {"cart.png"},
	cart = nil,
	driver = nil,
	timer = 0,
	on_activate = function(self, staticdata, dtime_s)
		self.object:set_armor_groups({immortal=1})
		if staticdata == "expired" then
			self.object:remove()
		end
	end,
	on_punch = function(self, puncher, _, _, direction)
		if not is_valid_player(puncher) then
			return
		end	
		if puncher:get_player_control().sneak then
			if self.cart then
				if self.cart.id then
					if self.cart.inv then
						if not self.cart.inv:is_empty("main") then
							return
						end
					end
					railcart:remove_cart(self.cart.id)
				end
			end
			self.object:remove()
			local inv = puncher:get_inventory()
			if minetest.setting_getbool("creative_mode") then
				if not inv:contains_item("main", "railcart:cart") then
					inv:add_item("main", "railcart:cart")
				end
			else
				inv:add_item("main", "railcart:cart")
			end
			return
		end
		if self.cart and direction then
			if self.driver then
				direction = {x=0, y=0, z=0}
				local ld = self.driver:get_look_dir()
				if ld.y > -0.99 then
					direction = {
						x = railtrack:get_sign(ld.x),
						z = railtrack:get_sign(ld.z),
						y = self.cart.dir.y
					}
				end
			end
			local pos = vector.round(self.object:getpos())
			local dir = vector.round(vector.normalize(direction))
			local speed = railcart:velocity_to_speed(self.cart.vel)
			self.timer = 0
			self.cart.target = nil
			self.cart.prev = pos
			self.cart.vel = vector.multiply(dir, RAILCART_SPEED_PUSH)
			self.cart.accel = railtrack:get_acceleration(pos)
			self.object:setvelocity(self.cart.vel)
		end
	end,
	on_rightclick = function(self, clicker)
		if not is_valid_player(clicker) then
			return
		end
		if clicker:get_player_control().sneak then
			local name = clicker:get_player_name()
			local cart = self.cart or {}
			if cart.id and name then
				local formspec = "size[8,9]"..
					default.gui_bg..default.gui_bg_img..default.gui_slots..
					"list[detached:railcart_"..cart.id..";main;0,0.3;8,4;]"..
					"list[current_player;main;0,4.85;8,1;]"..
					"list[current_player;main;0,6.08;8,3;8]"..
					"listring[detached:railcart_"..cart.id..";main]"..
					"listring[current_player;main]"..
					default.get_hotbar_bg(0,4.85)
				minetest.show_formspec(name, "inventory", formspec)
			end
			return
		end
		if self.driver and clicker == self.driver then
			self.driver = nil
			clicker:set_detach()
		elseif not self.driver then
			self.driver = clicker
			clicker:set_attach(self.object, "", {x=0,y=5,z=0}, {x=0,y=0,z=0})
		end
	end,
	on_step = function(self, dtime)
		local cart = self.cart
		local object = self.object
		if not cart or not object then
			return
		end
		self.timer = self.timer - dtime
		if self.timer > 0 then
			return
		end
		self.timer = railcart:update(cart, RAILCART_ENTITY_UPDATE_TIME, object)
	end,
	get_staticdata = function(self)
		if self.cart then
			if self.cart:is_loaded() == false then
				self.cart.timer = 0
				self.object:remove()
			end
		end
		return "expired"
	end,
})

minetest.register_craftitem("railcart:cart", {
	description = "Railcart",
	inventory_image = minetest.inventorycube("cart_top.png", "cart_side.png", "cart_side.png"),
	wield_image = "cart_side.png",
	on_place = function(itemstack, placer, pointed_thing)
		local name = placer:get_player_name()
		if not name or pointed_thing.type ~= "node" then
			return
		end
		if not minetest.is_singleplayer() then
			if not minetest.check_player_privs(name, {carts=true}) then
				minetest.chat_send_player(name, "Requires carts privilege")
				return
			end
		end
		local pos = pointed_thing.under
		if not railtrack:is_railnode(pos) then
			return
		end
		local carts = railcart:get_carts_in_radius(pos, 0.9)
		if #carts > 0 then
			return
		end
		local cart = railcart.cart:new()
		cart.id = railcart:get_new_id()
		cart.inv = railcart:create_detached_inventory(cart.id)
		cart.pos = vector.new(pos)
		cart.prev = vector.new(pos)
		cart.accel = railtrack:get_acceleration(pos)
		cart.dir = railcart:get_rail_direction(pos)
		table.insert(railcart.allcarts, cart)
		railcart:save()
		if not minetest.setting_getbool("creative_mode") then
			itemstack:take_item()
		end
		return itemstack
	end,
})

minetest.register_craft({
	output = "railcart:cart",
	recipe = {
		{"default:steel_ingot", "", "default:steel_ingot"},
		{"default:steel_ingot", "", "default:steel_ingot"},
		{"group:wood", "default:steel_ingot", "group:wood"},
	},
})

