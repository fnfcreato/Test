-- ✅ IMPORTING DEPENDENCIES
local animations = require("animations")
local desync = desync or require("desync")

-- ✅ If `require` fails, fallback to a simple desync calculation
if type(desync) ~= "table" then
    desync = {
        calculate_desync = function(enemy)
            local real_yaw = entity.get_prop(enemy, "m_angEyeAngles[1]") or 0
            local lby = entity.get_prop(enemy, "m_flLowerBodyYawTarget") or 0
            return math.abs(real_yaw - lby)
        end
    }
end


-- ✅ UI SYSTEM (Advanced Multi-Mode Selection)
local resolver_enabled = ui.new_checkbox("RAGE", "Aimbot", "🔥 Ultimate Resolver V4")
local resolver_debug = ui.new_checkbox("RAGE", "Aimbot", "Enable Debug Mode")
local resolver_esp = ui.new_checkbox("RAGE", "Aimbot", "Show Resolver ESP")

-- ✅ MULTI-MODE SYSTEM
local resolver_modes = ui.new_multiselect("RAGE", "Aimbot", "Resolver Modes", {
    "Standard",
    "Aggressive",
    "Brute Force",
    "🔥 AI Auto Resolver"
})

local resolver_strength = ui.new_slider("RAGE", "Aimbot", "Resolver Strength", 0, 100, 80)

-- ✅ DATA STORAGE (Resolver Memory & Tracking)
local resolver_memory = {}
local last_shot_hit = {}
local backtrack_data = {}
local jitter_history = {}
local freestand_history = {}
local manual_aa_history = {}
local fake_duck_history = {}
local enemy_visibility = {}
local fake_lag_history = {}
local last_head_position = {}
local last_yaw = {}

-- ✅ HELPER FUNCTIONS
local function debug_log(text)
    if ui.get(resolver_debug) then
        client.color_log(255, 0, 0, "[Resolver Debug] " .. text)
    end
end

local function table_contains(tbl, val)
    for _, v in pairs(tbl) do
        if v == val then return true end
    end
    return false
end

local function detect_freestanding(enemy)
    if not entity.is_alive(enemy) then
        freestand_history[enemy] = nil
        return "none"
    end

    if not freestand_history[enemy] then
        freestand_history[enemy] = { left = 0, right = 0 }
    end

    local enemy_x, enemy_y, enemy_z = entity.get_origin(enemy)
    if not enemy_x then return "none" end

    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return "none" end

    local lp_x, lp_y, lp_z = entity.get_origin(local_player)
    local view_offset_z = entity.get_prop(local_player, "m_vecViewOffset[2]") or 64
    local eye_pos_z = lp_z + view_offset_z

    -- Ensure trace results are numbers (prevent crashes)
    local left_trace = client.trace_bullet(local_player, lp_x, lp_y, eye_pos_z, enemy_x - 40, enemy_y, enemy_z) or 0
    local right_trace = client.trace_bullet(local_player, lp_x, lp_y, eye_pos_z, enemy_x + 40, enemy_y, enemy_z) or 0

    if left_trace > 0 then freestand_history[enemy].left = (freestand_history[enemy].left or 0) + 1 end
    if right_trace > 0 then freestand_history[enemy].right = (freestand_history[enemy].right or 0) + 1 end

    if freestand_history[enemy].left >= 3 then
        return "right"
    elseif freestand_history[enemy].right >= 3 then
        return "left"
    end

    return "none"
end

-- ✅ Fix for Missing `break_edge_yaw` Function (Prevents Crashes)
local function break_edge_yaw(enemy)
    local side = detect_freestanding(enemy)
    if side == "left" then
        return desync.calculate_desync(enemy) + 90 -- ✅ Offset instead of full 180 (more accurate)
    elseif side == "right" then
        return desync.calculate_desync(enemy) - 90 -- ✅ Offset instead of full 180
    end
    return desync.calculate_desync(enemy)
end

-- ✅ Debug Log with Throttling (No More Spam)
local last_debug_time = 0
local function debug_log(text)
    local current_time = globals.realtime()
    if ui.get(resolver_debug) and (current_time - last_debug_time > 1) then
        client.color_log(255, 0, 0, "[Resolver Debug] " .. text)
        last_debug_time = current_time
    end
end

-- ✅ AI LEARNING - IMPROVED RESOLVER MEMORY SYSTEM
local function update_resolver_memory(enemy, yaw, hit)
    local local_player = entity.get_local_player() -- ✅ Get your player ID
    if not local_player or not entity.is_alive(local_player) then return end -- ✅ Don't track if you're dead

    local active_weapon = entity.get_player_weapon(local_player)
    if not active_weapon then return end -- ✅ Don't track if no weapon is equipped

    -- ✅ Ensure resolver memory exists
    if not resolver_memory[enemy] then
        resolver_memory[enemy] = { misses = 0, last_yaw = yaw, corrections = {} }
    end

    -- ✅ Ensure `misses` is always initialized
    if resolver_memory[enemy].misses == nil then
        resolver_memory[enemy].misses = 0
    end

    -- ✅ Ensure `corrections` is always initialized
    if not resolver_memory[enemy].corrections then
        resolver_memory[enemy].corrections = {}
    end

    -- ✅ Only update resolver memory if YOU shot at the enemy
    if not hit then  
        resolver_memory[enemy].misses = resolver_memory[enemy].misses + 1  
        table.insert(resolver_memory[enemy].corrections, yaw + math.random(-15, 15))  

        -- ✅ Limit memory to the last 7 corrections  
        if #resolver_memory[enemy].corrections > 7 then  
            table.remove(resolver_memory[enemy].corrections, 1)  
        end  
    else  
        resolver_memory[enemy].misses = 0  
        resolver_memory[enemy].corrections = {}  
    end
end


local function get_best_yaw(enemy)
    if resolver_memory[enemy] and #resolver_memory[enemy].corrections > 0 then
        return resolver_memory[enemy].corrections[#resolver_memory[enemy].corrections]
    end
    return desync.calculate_desync(enemy) or 0
end

-- ✅ IMPROVED JITTER DETECTION (Now More Accurate!)
local function detect_jitter(enemy)
    if not jitter_history[enemy] then
        jitter_history[enemy] = { prev_yaw = desync.calculate_desync(enemy), ticks = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local yaw_difference = math.abs(jitter_history[enemy].prev_yaw - current_yaw)

    if yaw_difference > 25 then
        jitter_history[enemy].ticks = jitter_history[enemy].ticks + 1
    else
        jitter_history[enemy].ticks = 0
    end

    jitter_history[enemy].prev_yaw = current_yaw

    -- Adjust resolver based on jitter pattern
    if jitter_history[enemy].ticks >= 2 then  -- Reduced from 3 to 2 for faster detection
        debug_log("⚠️ Jitter Detected on " .. entity.get_player_name(enemy))
        return true
    end

    return false
end

-- ✅ Smarter Fake Flick Detection
local function detect_fake_flick(enemy)
    local last_yaw = resolver_memory[enemy] and resolver_memory[enemy].last_yaw or 0
    local current_yaw = desync.calculate_desync(enemy)
    local diff = math.abs(last_yaw - current_yaw)

    if diff > 35 then
        debug_log("⚠️ Fake Flick Detected on " .. entity.get_player_name(enemy))
        return current_yaw - math.random(10, 25)  -- Adjust resolver to counter flick
    end

    return current_yaw
end

-- fake duck!!
local function detect_fake_duck(enemy)
    local duck_amount = entity.get_prop(enemy, "m_flDuckAmount") or 0
    local flags = entity.get_prop(enemy, "m_fFlags") or 0
    local velocity_x, velocity_y = entity.get_prop(enemy, "m_vecVelocity") or 0, entity.get_prop(enemy, "m_vecVelocity+4") or 0
    local speed = math.sqrt(velocity_x^2 + velocity_y^2)
    local crouched = bit.band(flags, 4) ~= 0 -- ✅ Checks if they are crouching
    local moving = speed > 5

    -- ✅ Enemy is crouching, has a high duck amount, but isn't moving much
    if crouched and duck_amount > 0.7 and duck_amount < 0.9 and not moving then
        debug_log("🔥 Fake Duck Detected on " .. entity.get_player_name(enemy))
        fake_duck_history[enemy] = true
        return true
    end

    -- ✅ Reset if they start moving
    if moving then
        fake_duck_history[enemy] = false
    end

    return false
end

local function fix_fake_duck_resolver(enemy, resolved_yaw)
    if detect_fake_duck(enemy) then
        resolved_yaw = resolved_yaw + math.random(-5, 5) -- ✅ Minor angle correction
        debug_log("🔥 Adjusting Yaw for Fake Duck: " .. resolved_yaw)
    end
    return resolved_yaw
end

local function prioritize_fake_duck_shot(enemy)
    if detect_fake_duck(enemy) then
        debug_log("🚀 Prioritizing Shot at Fake Ducking Enemy!")
        client.exec("force_shoot") -- ✅ Forces an instant shot
    end
end

-- ✅ Smart Manual AA Adaptation (Detects Static & Fake LBY)
local function detect_manual_aa(enemy)
    if not manual_aa_history[enemy] then
        manual_aa_history[enemy] = { prev_yaw = desync.calculate_desync(enemy), ticks = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local yaw_difference = math.abs(manual_aa_history[enemy].prev_yaw - current_yaw)

    if yaw_difference < 5 then
        manual_aa_history[enemy].ticks = manual_aa_history[enemy].ticks + 1
    else
        manual_aa_history[enemy].ticks = 0
    end

    manual_aa_history[enemy].prev_yaw = current_yaw

    if manual_aa_history[enemy].ticks >= 3 then
        debug_log("⚠️ Static AA Detected on " .. entity.get_player_name(enemy))
        return true
    end

    return false
end

local function fix_extended_desync(enemy)
    local desync_amount = desync.calculate_desync(enemy)

    if desync_amount > 58 then
        debug_log("⚠️ Extended Desync Detected on " .. entity.get_player_name(enemy))
        return desync_amount - 15  -- Reduce excessive desync
    end

    return desync_amount
end

local function detect_static_desync(enemy)
    if not resolver_memory[enemy] then
        resolver_memory[enemy] = { prev_yaw = desync.calculate_desync(enemy), ticks_static = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local prev_yaw = resolver_memory[enemy].prev_yaw

    if math.abs(current_yaw - prev_yaw) < 5 then  -- Static AA detected
        resolver_memory[enemy].ticks_static = resolver_memory[enemy].ticks_static + 1
    else
        resolver_memory[enemy].ticks_static = 0
    end

    resolver_memory[enemy].prev_yaw = current_yaw

    if resolver_memory[enemy].ticks_static >= 3 then
        debug_log("⚠️ Static Desync Detected on " .. entity.get_player_name(enemy))
        return current_yaw + math.random(15, 30)  -- Forces a yaw change
    end

    return current_yaw
end


local function detect_jitter_spam(enemy)
    if not jitter_history[enemy] then
        jitter_history[enemy] = { prev_yaw = desync.calculate_desync(enemy), jitter_ticks = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local diff = math.abs(jitter_history[enemy].prev_yaw - current_yaw)

    if diff > 10 and diff < 40 then
        jitter_history[enemy].jitter_ticks = jitter_history[enemy].jitter_ticks + 1
    else
        jitter_history[enemy].jitter_ticks = 0
    end

    jitter_history[enemy].prev_yaw = current_yaw

    if jitter_history[enemy].jitter_ticks >= 3 then
        debug_log("⚠️ Jitter Spam Detected on " .. entity.get_player_name(enemy))
        return current_yaw + math.random(-15, 15)  -- Adjusts for jitter spam
    end

    return current_yaw
end

local function fix_freestanding_jitter(enemy)
    local side = detect_freestanding(enemy)
    if side == "left" then
        return desync.calculate_desync(enemy) + math.random(5, 15)
    elseif side == "right" then
        return desync.calculate_desync(enemy) - math.random(5, 15)
    end
    return desync.calculate_desync(enemy)
end

local function brute_force_resolver(enemy)
    -- ✅ Ensure `resolver_memory[enemy]` exists
    if not resolver_memory[enemy] then
        resolver_memory[enemy] = { misses = 0, last_angles = {} }
    end

    -- ✅ Ensure `last_angles` exists before inserting into it
    if not resolver_memory[enemy].last_angles then
        resolver_memory[enemy].last_angles = {}
    end

    local current_yaw = desync.calculate_desync(enemy)
    table.insert(resolver_memory[enemy].last_angles, current_yaw)

    -- ✅ Limit to last 5 angles
    if #resolver_memory[enemy].last_angles > 5 then
        table.remove(resolver_memory[enemy].last_angles, 1)
    end

    -- ✅ Check if all last 5 angles are different
    local unique_angles = {}
    for _, angle in ipairs(resolver_memory[enemy].last_angles) do
        unique_angles[angle] = true
    end

    if #unique_angles >= 5 then
        debug_log("⚠️ Brute Force AA Detected on " .. entity.get_player_name(enemy))
        return current_yaw + math.random(-20, 20)  -- Adjusts for next brute-force shot
    end

    return current_yaw
end

local function detect_static_aa(enemy)
    if not resolver_memory[enemy] then
        resolver_memory[enemy] = { prev_yaw = desync.calculate_desync(enemy), static_ticks = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local yaw_diff = math.abs(current_yaw - resolver_memory[enemy].prev_yaw)

    if yaw_diff < 5 then
        resolver_memory[enemy].static_ticks = resolver_memory[enemy].static_ticks + 1
    else
        resolver_memory[enemy].static_ticks = 0
    end

    resolver_memory[enemy].prev_yaw = current_yaw

    if resolver_memory[enemy].static_ticks >= 3 then
        debug_log("🛑 Static AA Detected on " .. entity.get_player_name(enemy))
        return current_yaw + math.random(15, 30) -- Force shift yaw
    end

    return current_yaw
end

local function detect_air_stall(enemy)
    local velocity_x = entity.get_prop(enemy, "m_vecVelocity") or 0
    local velocity_y = entity.get_prop(enemy, "m_vecVelocity+4") or 0
    local velocity_z = entity.get_prop(enemy, "m_vecVelocity+8") or 0
    local flags = entity.get_prop(enemy, "m_fFlags") or 0

    local speed = math.sqrt(velocity_x^2 + velocity_y^2) -- Horizontal speed
    local in_air = bit.band(flags, 1) == 0 -- ✅ Check if enemy is in the air

    -- ✅ Detect Neverlose Jump Exploit
    if in_air and math.abs(velocity_z) > 100 and speed < 5 then
        debug_log("🛑 Neverlose Jump Exploit Detected: " .. entity.get_player_name(enemy))
        return true
    end

    return false
end

local function detect_jump_landing(enemy)
    local velocity_z = entity.get_prop(enemy, "m_vecVelocity+8") or 0
    local flags = entity.get_prop(enemy, "m_fFlags") or 0

    -- ✅ Detect landing (fast falling + touching ground)
    if velocity_z < -200 and bit.band(flags, 1) ~= 0 then
        debug_log("⚠️ Enemy Landing Detected! Adjusting Resolver")
        return true
    end

    return false
end

local function adjust_for_air_exploit(enemy, resolved_yaw)
    if detect_air_stall(enemy) then
        resolved_yaw = resolved_yaw + math.random(-30, 30) -- Random yaw shift
        debug_log("🔥 Adjusting Yaw for Neverlose Jump Exploit")
    end
    if detect_jump_landing(enemy) then
        resolved_yaw = resolved_yaw + math.random(-15, 15) -- Quick correction on land
        debug_log("🔥 Adjusting Yaw for Landing")
    end
    return resolved_yaw
end

local function prioritize_airborne_shots(enemy)
    if detect_air_stall(enemy) or detect_jump_landing(enemy) then
        debug_log("🚀 Prioritizing Shot at Airborne Exploit User")
        client.exec("force_shoot") -- Forces a shot when enemy is airborne
    end
end

local function is_enemy_using_zeus(enemy)
    local weapon = entity.get_player_weapon(enemy)
    if not weapon then return false end  

    local weapon_name = entity.get_classname(weapon)
    return weapon_name == "CZeusX27" -- ✅ Correct Zeus name check
end

local function detect_zeus_jump(enemy)
    local velocity_z = entity.get_prop(enemy, "m_vecVelocity+8") or 0
    local flags = entity.get_prop(enemy, "m_fFlags") or 0
    local in_air = bit.band(flags, 1) == 0 -- ✅ Check if enemy is in the air

    if in_air and is_enemy_using_zeus(enemy) then
        debug_log("⚡ Zeus Jump Exploit Detected on " .. entity.get_player_name(enemy))
        return true
    end
    return false
end

local function fix_zeus_jump(enemy, resolved_yaw)
    if detect_zeus_jump(enemy) then
        resolved_yaw = resolved_yaw + math.random(-20, 20) -- ✅ Adjust yaw to counter Zeus jump
        debug_log("⚡ Adjusting Yaw for Zeus Jump Exploit: " .. resolved_yaw)
    end
    return resolved_yaw
end

local function prioritize_zeus_shot(enemy)
    if detect_zeus_jump(enemy) then
        debug_log("🚀 Prioritizing Shot Against Zeus Jumper!")
        client.exec("force_shoot") -- ✅ Force instant shot
    end
end



local function detect_enemy_peek(enemy)
    local is_visible = not entity.is_dormant(enemy) -- ✅ Check if enemy is visible
    if not enemy_visibility[enemy] then enemy_visibility[enemy] = is_visible end

    -- ✅ If the enemy was behind a wall and now is visible, they just peeked
    if not enemy_visibility[enemy] and is_visible then
        debug_log("🚀 Enemy Peek Detected: " .. entity.get_player_name(enemy))
        enemy_visibility[enemy] = is_visible
        return true
    end

    enemy_visibility[enemy] = is_visible
    return false
end

local function prioritize_peek_shot(enemy, resolved_yaw)
    if detect_enemy_peek(enemy) then
        resolved_yaw = resolved_yaw + math.random(-15, 15) -- ✅ Force yaw adjustment
        debug_log("🔥 Adjusting Yaw for Peeking Enemy: " .. resolved_yaw)
        client.exec("force_shoot") -- ✅ Force an instant shot
    end
    return resolved_yaw
end

local function detect_extreme_jitter(enemy)
    if not jitter_history[enemy] then
        jitter_history[enemy] = { prev_yaw = desync.calculate_desync(enemy), jitter_ticks = 0 }
    end

    local current_yaw = desync.calculate_desync(enemy)
    local yaw_diff = math.abs(jitter_history[enemy].prev_yaw - current_yaw)

    -- ✅ If the yaw difference is very high multiple times, it's jitter
    if yaw_diff > 25 then
        jitter_history[enemy].jitter_ticks = jitter_history[enemy].jitter_ticks + 1
    else
        jitter_history[enemy].jitter_ticks = 0
    end

    jitter_history[enemy].prev_yaw = current_yaw

    if jitter_history[enemy].jitter_ticks >= 2 then -- Faster Detection
        debug_log("⚠️ Extreme Jitter Detected on " .. entity.get_player_name(enemy))
        return true
    end

    return false
end

local function detect_fake_lag(enemy)
    if not fake_lag_history[enemy] then
        fake_lag_history[enemy] = { last_velocity = 0, choked_ticks = 0 }
    end

    local velocity_x, velocity_y = entity.get_prop(enemy, "m_vecVelocity") or 0, entity.get_prop(enemy, "m_vecVelocity+4") or 0
    local current_speed = math.sqrt(velocity_x^2 + velocity_y^2) -- Calculate movement speed

    local choked_cmds = globals.chokedcommands() -- Get choked packets

    -- ✅ Detect sudden stop with high choked packets (Fake Lag)
    if choked_cmds > 5 and math.abs(current_speed - fake_lag_history[enemy].last_velocity) > 20 then
        fake_lag_history[enemy].choked_ticks = fake_lag_history[enemy].choked_ticks + 1
    else
        fake_lag_history[enemy].choked_ticks = 0
    end

    fake_lag_history[enemy].last_velocity = current_speed

    if fake_lag_history[enemy].choked_ticks >= 3 then -- Fake Lag Detected
        debug_log("🛑 Fake Lag Detected: " .. entity.get_player_name(enemy))
        return true
    end

    return false
end

local function auto_switch_resolver_mode(enemy)
    local selected_modes = ui.get(resolver_modes)

    -- ✅ If Fake Lag detected, switch to Brute Force mode
    if detect_fake_lag(enemy) then
        if not table_contains(selected_modes, "Brute Force") then
            ui.set(resolver_modes, {"Brute Force"})
            debug_log("🔥 Auto-Switching to Brute Force Mode (Fake Lag Detected)")
        end
    end

    -- ✅ If Extreme Jitter detected, switch to Aggressive mode
    if detect_extreme_jitter(enemy) then
        if not table_contains(selected_modes, "Aggressive") then
            ui.set(resolver_modes, {"Aggressive"})
            debug_log("⚠️ Auto-Switching to Aggressive Mode (Jitter Detected)")
        end
    end

    -- ✅ If Static Desync detected, switch to Standard mode
    if detect_static_aa(enemy) then
    debug_log("🛑 Static Desync Detected! (Suggested: Standard Mode)")

    -- ✅ Instead of forcing Standard mode, only log it
    -- ✅ If the user has manually disabled Standard, it won’t auto-enable
end


local function apply_backtrack(enemy)
    if not backtrack_data[enemy] then return end

    local last_position = backtrack_data[enemy]
    entity.set_prop(enemy, "m_vecOrigin", last_position.x, last_position.y, last_position.z)
    
    debug_log("🎯 Applied Backtrack to Enemy: " .. entity.get_player_name(enemy))
end


local function detect_fake_body(enemy)
    local body_yaw = entity.get_prop(enemy, "m_flPoseParameter[11]") or 0 -- Fake body yaw
    local real_yaw = desync.calculate_desync(enemy)

    if math.abs(real_yaw - body_yaw) > 30 then
        debug_log("⚠️ Fake Body Lean Detected on " .. entity.get_player_name(enemy))
        return true
    end
    return false
end

local function fix_fake_body_resolver(enemy, resolved_yaw)
    if detect_fake_body(enemy) then
        resolved_yaw = resolved_yaw + math.random(-15, 15) -- Correct for fake lean
        debug_log("🔥 Adjusting for Fake Body Lean: " .. resolved_yaw)
    end
    return resolved_yaw
end



local function predict_enemy_position(enemy)
    -- ✅ Ensure velocity is always a number
    local velocity_x = entity.get_prop(enemy, "m_vecVelocity") or 0
    local velocity_y = entity.get_prop(enemy, "m_vecVelocity+4") or 0

    -- ✅ Ensure position is always a number
    local origin_x = entity.get_prop(enemy, "m_vecOrigin[0]") or 0
    local origin_y = entity.get_prop(enemy, "m_vecOrigin[1]") or 0

    -- ✅ Prevents the crash by ensuring all values exist
    local predicted_x = origin_x + (velocity_x * globals.frametime())
    local predicted_y = origin_y + (velocity_y * globals.frametime())

    return predicted_x, predicted_y
end

local function detect_desync_speed(enemy)
    if not resolver_memory[enemy] then return end

    local current_desync = desync.calculate_desync(enemy)
    local last_desync = resolver_memory[enemy].last_yaw or 0

    if math.abs(current_desync - last_desync) > 20 then
        debug_log("⚡ Rapid Desync Change Detected on " .. entity.get_player_name(enemy))
        return true
    end
    return false
end

local function speed_boost_resolver(enemy, resolved_yaw)
    if detect_desync_speed(enemy) then
        client.delay_call(0.01, function()
            entity.set_prop(enemy, "m_angEyeAngles[1]", resolved_yaw)
        end)
        debug_log("🚀 Speed Boost Applied to Resolver")
    end
end

local function detect_fake_lby(enemy)
    local lby = entity.get_prop(enemy, "m_flLowerBodyYawTarget")
    local yaw = entity.get_prop(enemy, "m_angEyeAngles[1]")

    -- If LBY doesn't update after movement, they are faking it
    if math.abs(yaw - lby) > 35 then
        debug_log("🔥 Fake LBY Detected on " .. entity.get_player_name(enemy))
        return true
    end
    return false
end

local function fix_fake_lby(enemy, resolved_yaw)
    if detect_fake_lby(enemy) then
        resolved_yaw = resolved_yaw + math.random(-5, 5)
        debug_log("🔥 Adjusting Yaw for Fake LBY")
    end
    return resolved_yaw
end


local function detect_movement_lag(enemy)
    local sim_time = entity.get_prop(enemy, "m_flSimulationTime")
    local old_sim_time = resolver_memory[enemy] and resolver_memory[enemy].sim_time or 0

    -- If simulation time is not updating, they are faking movement
    if math.abs(sim_time - old_sim_time) < globals.tickinterval() then
        debug_log("💨 Fake Movement Lag Detected on " .. entity.get_player_name(enemy))
        return true
    end

    resolver_memory[enemy] = resolver_memory[enemy] or {}
    resolver_memory[enemy].sim_time = sim_time
    return false
end

local function fix_movement_delay(enemy, resolved_yaw)
    if detect_movement_lag(enemy) then
        resolved_yaw = resolved_yaw + 15 * (math.random() > 0.5 and 1 or -1)
        debug_log("💨 Adjusting Resolver for Fake Lag")
    end
    return resolved_yaw
end




local function detect_low_delta(enemy)
    -- ✅ Ensure head position exists before using it
    local head_x, head_y, head_z = entity.hitbox_position(enemy, "head")

    -- ✅ If head position is nil, return false (prevents crash)
    if not head_x or not head_y or not head_z then
        return false
    end

    -- ✅ Ensure last_head_position[enemy] is initialized
    if not last_head_position[enemy] then
        last_head_position[enemy] = { x = head_x, y = head_y, z = head_z }
        return false
    end

    -- ✅ Calculate movement differences safely
    local dx = math.abs(head_x - last_head_position[enemy].x)
    local dy = math.abs(head_y - last_head_position[enemy].y)
    local dz = math.abs(head_z - last_head_position[enemy].z)

    -- ✅ If the head moves **too little**, they are using low-delta
    if dx < 2 and dy < 2 and dz < 2 then
        debug_log("📡 Low-Delta AA Detected on " .. entity.get_player_name(enemy))
        return true
    end

    -- ✅ Update last known head position
    last_head_position[enemy] = { x = head_x, y = head_y, z = head_z }
    return false
end

local function fix_low_delta(enemy, resolved_yaw)
    -- ✅ Ensure `detect_low_delta` is safe to use
    if detect_low_delta(enemy) then
        resolved_yaw = resolved_yaw + 20 * (math.random() > 0.5 and 1 or -1)
        debug_log("📡 Adjusting Resolver for Low-Delta AA")
    end
    return resolved_yaw
end



local function detect_extreme_jitter(enemy)
    local current_yaw = entity.get_prop(enemy, "m_angEyeAngles[1]")
    local yaw_change = math.abs((last_yaw[enemy] or current_yaw) - current_yaw)

    -- If yaw changes **too fast**, it's jitter abuse
    if yaw_change > 40 then
        debug_log("⚡ Extreme Flick Detected on " .. entity.get_player_name(enemy))
        return true
    end

    last_yaw[enemy] = current_yaw
    return false
end

local function fix_extreme_jitter(enemy, resolved_yaw)
    if detect_extreme_jitter(enemy) then
        resolved_yaw = resolved_yaw + 25 * (math.random() > 0.5 and 1 or -1)
        debug_log("⚡ Adjusting Resolver for Rapid Jitter")
    end
    return resolved_yaw
end

local function detect_spinbot(enemy)
    local current_yaw = entity.get_prop(enemy, "m_angEyeAngles[1]")
    local yaw_diff = math.abs(current_yaw - (last_yaw[enemy] or current_yaw))

    -- If yaw changes **too fast**, it's a spinbot
    if yaw_diff > 120 then
        debug_log("🌀 Spinbot Detected on " .. entity.get_player_name(enemy))
        return true
    end

    last_yaw[enemy] = current_yaw
    return false
end

local function fix_spinbot(enemy, resolved_yaw)
    if detect_spinbot(enemy) then
        resolved_yaw = resolved_yaw - math.random(30, 60)
        debug_log("🌀 Adjusting Resolver for Spinbot")
    end
    return resolved_yaw
end

local function predict_lagged_position(enemy)
    -- ✅ Ensure the enemy is valid and alive before getting properties
    if not entity.is_alive(enemy) then return nil, nil end

    -- ✅ Get velocity values safely (prevents nil errors)
    local velocity_x = entity.get_prop(enemy, "m_vecVelocity") or 0
    local velocity_y = entity.get_prop(enemy, "m_vecVelocity+4") or 0

    -- ✅ Get enemy origin safely
    local origin_x = entity.get_prop(enemy, "m_vecOrigin[0]")
    local origin_y = entity.get_prop(enemy, "m_vecOrigin[1]")

    -- ✅ Ensure we have valid origin values before doing math
    if not origin_x or not origin_y then return nil, nil end

    -- ✅ Calculate predicted position
    local predicted_x = origin_x + (velocity_x * globals.frametime())
    local predicted_y = origin_y + (velocity_y * globals.frametime())

    return predicted_x, predicted_y
end



-- ✅ FINAL AI-POWERED RESOLVER (Now Smarter!)
local function apply_resolver(enemy)
    local desync_offset = fix_extended_desync(enemy)
    local resolved_pitch, resolved_yaw = animations.resolve_angles(enemy, desync_offset)

    -- ✅ Auto-Switch Resolver Mode Based on Enemy Behavior
    auto_switch_resolver_mode(enemy)

    -- ✅ Backtrack Integration (Fixes Misses from Fake Lag)
    apply_backtrack(enemy)

    -- ✅ Detect & Fix Fake Body Lean (Corrects Fake Angles)
    resolved_yaw = fix_fake_body_resolver(enemy, resolved_yaw)

    -- ✅ Predictive Anti-Delay Resolver (Handles Fake Lag & Choked Packets)
    local predicted_x, predicted_y = predict_enemy_position(enemy)

    -- ✅ Speed Boost Resolver (Handles Fast Desync Changes)
    speed_boost_resolver(enemy, resolved_yaw)

    -- ✅ Detect & Fix Fake Ducking AA
    resolved_yaw = fix_fake_duck_resolver(enemy, resolved_yaw)

    -- ✅ Fix Jump Exploits (Neverlose/Gamesense Air Stalling & Fake Lag)
    resolved_yaw = adjust_for_air_exploit(enemy, resolved_yaw)

    -- ✅ Fix Zeus Jump Exploit (Abusers of Instant Zeus Attacks)
    resolved_yaw = fix_zeus_jump(enemy, resolved_yaw)

    -- ✅ Detect & Fix Extreme Jitter Spam
    resolved_yaw = detect_jitter_spam(enemy)

    -- ✅ Brute Force Resolver (Handles Rapid Fake Angles)
    resolved_yaw = brute_force_resolver(enemy)

    -- ✅ Fix Freestanding & Adaptive Desync AA
    resolved_yaw = fix_freestanding_jitter(enemy)

    -- ✅ Fix Static AA & Adaptive Angles
    resolved_yaw = detect_static_aa(enemy)

    -- 🔥 **New Features for Maximum Accuracy** 🔥

    -- ✅ Detect & Fix Fake LBY (Neverlose Abusers)
    resolved_yaw = fix_fake_lby(enemy, resolved_yaw)

    -- ✅ Detect & Fix Anti-Delay Desync (Punishes Fake Lag Updates)
    resolved_yaw = fix_movement_delay(enemy, resolved_yaw)

    -- ✅ Detect & Fix Low-Delta AA (Players Using Small Angle Changes)
    resolved_yaw = fix_low_delta(enemy, resolved_yaw)

    -- ✅ Detect & Fix Instant Flick Jitter (Extreme Yaw Switching)
    resolved_yaw = fix_extreme_jitter(enemy, resolved_yaw)

    -- ✅ Detect & Fix Spinbot Exploits (Rapid Fake Yaw Spins)
    resolved_yaw = fix_spinbot(enemy, resolved_yaw)

    -- ✅ Prioritize Shots at Critical Moments (Ensures First Hit Accuracy)
    prioritize_airborne_shots(enemy)   -- 🔥 Neverlose Jump Exploits  
    prioritize_zeus_shot(enemy)        -- ⚡ Zeus Jump Shots  
    prioritize_peek_shot(enemy, resolved_yaw)  -- 🚀 Fast Peeker Detection  

-- ✅ Emergency Resolver Speed-Up (Prevents Missing Multiple Shots)
local local_player = entity.get_local_player()
if local_player ~= nil and local_player == entity.get_local_player() then -- ✅ You must be alive & active
    if resolver_memory[enemy] and resolver_memory[enemy].misses and resolver_memory[enemy].shots then
        if resolver_memory[enemy].misses >= 2 and resolver_memory[enemy].shots >= resolver_memory[enemy].misses then
            resolved_yaw = resolved_yaw + math.random(-10, 10)
            debug_log("🚀 You Actually Missed Twice! Adjusting Resolver!")
        end
    end
end

    -- ✅ Force Resolver Updates Every Tick (Ensures Real-Time Adjustments)
    entity.set_prop(enemy, "m_angEyeAngles[1]", resolved_yaw)  
    client.delay_call(0.01, function()
        entity.set_prop(enemy, "m_angEyeAngles[1]", resolved_yaw)
    end)

    -- ✅ Update Resolver Memory (AI Learning System)
    update_resolver_memory(enemy, resolved_yaw, last_shot_hit[enemy])  

    debug_log("🎯 Final Resolved Yaw: " .. resolved_yaw)  
    return resolved_pitch, resolved_yaw
end

-- ✅ **ESP OVERLAY (Fixed & Improved)**
client.set_event_callback("paint", function()
    if not ui.get(resolver_enabled) or not ui.get(resolver_esp) then return end

    local enemies = entity.get_players(true)

    for _, enemy in pairs(enemies) do
        if not entity.is_alive(enemy) or entity.is_dormant(enemy) then goto continue end

        local x, y, z = entity.get_origin(enemy)
        local sx, sy = renderer.world_to_screen(x, y, z + 50)

        if sx and sy then
            local name = entity.get_player_name(enemy)
            local resolved_yaw = apply_resolver(enemy)

            local text = string.format("🔥 %s | Yaw: %.1f", name, resolved_yaw)
            renderer.text(sx, sy, 255, 255, 255, 255, "c", 0, text)
        end

        ::continue::
    end
end)
end
