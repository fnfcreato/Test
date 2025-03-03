local ffi = require("ffi")
local bit = require("bit")
local vector = require("vector")

-- Global state initialization (move these to the top)
local missed_shots_data = {}
local resolver_data = {}  -- Initialize this first
local pattern_memory = {}
local exploit_history = {}
local last_prediction = {}
local resolver_history = {}
local backtrack_data = {}
local choked_ticks = {}
local hit_positions = {}
local latency_cache = {}
local cache_duration = 0.1 -- seconds
local last_prediction_value = 0

-- Neural Network Configuration
local NN = {
    input_layer = 15,  -- Increased input size for better pattern recognition
    hidden_layer = 16,
    output_layer = 4,
    learning_rate = 0.01,
    weights = {
        hidden = {},
        output = {}
    },
    biases = {
        hidden = {},
        output = {}
    }
}

local prediction_stats = {
    total_predictions = 0,
    correct_predictions = 0,
    last_accuracy = 100
}


local function init_resolver_data(player, angle)
    if not resolver_data[player] then
        resolver_data[player] = {
            last_real_angle = angle or 0,
            last_applied_angle = angle or 0,
            hit_positions = {},
            missed_shots = 0,
            hit_history = {},
            angle_history = {}
        }
    end
    return resolver_data[player]
end

resolver_data = resolver_data or {}

local last_prediction_value = 0

-- Enhanced UI Elements
local ui_elements = {
    enable_resolver = ui.new_checkbox("LUA", "A", "🧠 Enable Neural Resolver"),
    enable_ai_learning = ui.new_checkbox("LUA", "A", "🤖 AI Learning System"),
    learning_mode = ui.new_combobox("LUA", "A", "📚 Learning Mode", {"Aggressive", "Balanced", "Safe"}),
    enable_pattern_recognition = ui.new_checkbox("LUA", "A", "🎯 Pattern Recognition"),
    enable_exploit_detection = ui.new_checkbox("LUA", "A", "⚡ Exploit Detection"),
    resolution_mode = ui.new_multiselect("LUA", "A", "🔧 Resolution Methods", {
        "Neural Prediction",
        "Adaptive Bruteforce",
        "Pattern Analysis",
        "Dynamic Correction"
    }),
    show_resolver_info = ui.new_checkbox("LUA", "A", "📊 Show Resolver Info"),
    info_position = ui.new_slider("LUA", "A", "💫 Info Position", 0, 100, 50),
    prediction_strength = ui.new_slider("LUA", "A", "🎯 Prediction Strength", 0, 100, 50),
    learning_threshold = ui.new_slider("LUA", "A", "📈 Learning Threshold", 0, 100, 70),
    dt_handling = ui.new_multiselect("LUA", "A", "🚀 DT/HS Handling", {
        "Adaptive Delay",
        "Smart Prediction",
        "Tick Manipulation"
    }),
    show_debug_info = ui.new_checkbox("LUA", "A", "🔍 Show Debug Info")
}

-- Prediction Accuracy Calculator
-- First, add this global variable at the top of your script
local prediction_stats = {
    total_predictions = 0,
    correct_predictions = 0,
    last_accuracy = 100
}

local function math_sign(x)
    return x > 0 and 1 or (x < 0 and -1 or 0)
end

-- Then, replace the existing get_prediction_accuracy function with this improved version
local function get_prediction_accuracy()
    -- If no predictions made yet, return last known accuracy
    if prediction_stats.total_predictions == 0 then
        return prediction_stats.last_accuracy
    end

    local total_predictions = 0
    local correct_predictions = 0
    
    for _, data in pairs(resolver_data) do
        if data.predicted_angle and data.actual_angle then
            -- Only count players with enough history
            if #(data.angle_history or {}) >= 5 then
                total_predictions = total_predictions + 1
                
                -- Check if prediction was accurate within 5 degrees
                if math.abs(data.predicted_angle - data.actual_angle) < 5 then
                    correct_predictions = correct_predictions + 1
                end
            end
        end
    end
    
    -- Calculate accuracy with protection against division by zero
    local accuracy = (correct_predictions / math.max(total_predictions, 1)) * 100
    
    -- Update global stats
    prediction_stats.total_predictions = total_predictions
    prediction_stats.correct_predictions = correct_predictions
    prediction_stats.last_accuracy = accuracy
    
    return accuracy
end

-- Add this function to update prediction data
local function update_prediction_data(player, predicted, actual)
    if not resolver_data[player] then
        resolver_data[player] = {
            angle_history = {},
            predicted_angle = 0,
            actual_angle = 0
        }
    end
    
    resolver_data[player].predicted_angle = predicted
    resolver_data[player].actual_angle = actual
    
    -- Add to angle history
    table.insert(resolver_data[player].angle_history, actual)
    
    -- Keep history at reasonable size
    if #resolver_data[player].angle_history > 10 then
        table.remove(resolver_data[player].angle_history, 1)
    end
end

local function get_latency_adjustment(player)
    if not player then return 0 end
    
    -- Try to get ping, fallback to network latency if ping isn't available
    local ping = entity.get_prop(player, "m_iPing")
    
    -- If ping is nil, try alternative methods to get latency
    if ping == nil then
        -- Try getting latency directly
        ping = entity.get_prop(player, "m_fLatency")
        
        -- If still nil, try getting network latency
        if ping == nil then
            -- Convert to milliseconds if latency is available
            ping = (entity.get_prop(player, "m_NetworkState") or {}).latency
            if ping then
                ping = ping * 1000
            end
        end
        
        -- If everything fails, use a default value
        if ping == nil then
            ping = 50 -- Default ping value
        end
    end
    
    -- Ensure ping is a number and clamp the adjustment value
    ping = tonumber(ping) or 50
    
    -- Calculate and clamp the adjustment value between 0 and 15
    local adjustment = math.min(math.max(ping / 10, 0), 15)
    
    return adjustment
end

-- Debug function to test latency adjustment
local function debug_latency_adjustment(player)
    local ping = entity.get_prop(player, "m_iPing")
    local latency = entity.get_prop(player, "m_fLatency")
    local network_state = entity.get_prop(player, "m_NetworkState")
    
    print("Debug Latency Values:")
    print("Ping:", ping)
    print("Latency:", latency)
    print("Network State:", network_state)
    print("Final Adjustment:", get_latency_adjustment(player))
end


local function get_cached_latency_adjustment(player)
    local current_time = globals.realtime()
    
    if not latency_cache[player] or 
       (current_time - latency_cache[player].time) > cache_duration then
        latency_cache[player] = {
            value = get_latency_adjustment(player),
            time = current_time
        }
    end
    
    return latency_cache[player].value
end

local function softmax(x)
    if not x or #x == 0 then return {} end
    
    local max_val = x[1]
    for i = 2, #x do
        if x[i] > max_val then max_val = x[i] end
    end
    
    local exp_sum = 0
    local exp_values = {}
    for i = 1, #x do
        exp_values[i] = math.exp(x[i] - max_val)
        exp_sum = exp_sum + exp_values[i]
    end
    
    local output = {}
    for i = 1, #x do
        output[i] = exp_values[i] / exp_sum
    end
    return output
end

-- Helper function to validate network structure
    local function validate_network_structure(input, weights, biases)
        if type(input) ~= "table" or type(weights) ~= "table" or type(biases) ~= "table" then
            return false, "Invalid input types"
        end
        
        if #weights == 0 or #weights[1] == 0 then
            return false, "Empty weights matrix"
        end
        
        if #input == 0 then
            return false, "Empty input vector"
        end
        
        if #biases ~= #weights[1] then
            return false, "Biases don't match output dimension"
        end
        
        return true, nil
    end

-- Layer Application Function
local function apply_layer(input, weights, biases)
    -- Input validation
    if not input or not weights or not biases then
        return {}
    end
    
    -- Ensure input is a valid table with numbers
    for i = 1, #input do
        if type(input[i]) ~= "number" then
            return {}
        end
    end
    
    -- Validate weights structure
    for i = 1, #weights do
        if type(weights[i]) ~= "table" then
            return {}
        end
    end
    
    local output = {}
    for i = 1, #weights[1] do  -- Iterate through output neurons
        local sum = type(biases[i]) == "number" and biases[i] or 0
        
        for j = 1, #input do  -- Iterate through input neurons
            -- Ensure we're working with valid numbers
            local weight = type(weights[j]) == "table" and weights[j][i] or 0
            weight = math.min(math.max(weight, -2), 2)  -- Clamp weight between -2 and 2
            
            if type(input[j]) == "number" and type(weight) == "number" then
                sum = sum + (input[j] * weight)
            end
        end
        
        -- Apply activation function (softmax) to the sum
        local activated = softmax({sum})
        output[i] = activated[1]
    end
    
    return output
end






-- Backpropagation Function
local function backpropagate(input, hidden, output, target)
    -- Input validation
    if not input or not hidden or not output or not target or
       not NN.weights.output or not NN.weights.hidden then
        return
    end

    -- Initialize error arrays
    local output_error = {}
    local hidden_error = {}
    
    -- Calculate output layer error
    for i = 1, #output do
        output_error[i] = target - output[i]
    end

    -- Initialize hidden error array
    for i = 1, #hidden do
        hidden_error[i] = 0
    end

    -- Calculate hidden layer error
    for i = 1, #hidden do
        hidden_error[i] = 0
        for j = 1, #output do
            -- Check if weights exist
            if NN.weights.output[i] and NN.weights.output[i][j] then
                hidden_error[i] = hidden_error[i] + (output_error[j] * NN.weights.output[i][j])
            else
                -- Initialize weight if it doesn't exist
                if not NN.weights.output[i] then
                    NN.weights.output[i] = {}
                end
                NN.weights.output[i][j] = math.random() * math.sqrt(2 / (NN.hidden_layer + NN.output_layer))
            end
        end
    end

    -- Update output layer weights
    for i = 1, #hidden do
        for j = 1, #output do
            if not NN.weights.output[i] then
                NN.weights.output[i] = {}
            end
            if not NN.weights.output[i][j] then
                NN.weights.output[i][j] = math.random() * math.sqrt(2 / (NN.hidden_layer + NN.output_layer))
            end
            NN.weights.output[i][j] = NN.weights.output[i][j] + (NN.learning_rate * output_error[j] * hidden[i])
        end
    end

    -- Update hidden layer weights
    for i = 1, #input do
        for j = 1, #hidden do
            if not NN.weights.hidden[i] then
                NN.weights.hidden[i] = {}
            end
            if not NN.weights.hidden[i][j] then
                NN.weights.hidden[i][j] = math.random() * math.sqrt(2 / (NN.input_layer + NN.hidden_layer))
            end
            NN.weights.hidden[i][j] = NN.weights.hidden[i][j] + (NN.learning_rate * hidden_error[j] * input[i])
        end
    end
end



-- Neural Network Update Function
local function update_neural_network()
    local accuracy = get_prediction_accuracy()
    if accuracy > 50 then
        if accuracy > 85 then
            NN.learning_rate = math.max(NN.learning_rate - 0.001, 0.001)
        else
            NN.learning_rate = math.min(NN.learning_rate + 0.001, 0.1)
        end

        for player, data in pairs(resolver_data) do
            if data.angle_history and #data.angle_history >= 5 then
                local input_data = {}
                for i = 1, 15 do
                    input_data[i] = data.angle_history[#data.angle_history - 15 + i] or 0
                end
                local target = data.actual_angle or 0
                
                -- Apply neural network layers
                local hidden = apply_layer(input_data, NN.weights.hidden, NN.biases.hidden)
                if hidden and #hidden > 0 then
                    local output = apply_layer(hidden, NN.weights.output, NN.biases.output)
                    
                    -- Optional: Add error handling for the output
                    if output and #output > 0 then
                        -- Update weights through backpropagation
                        backpropagate(input_data, hidden, output, target)
                    end
                end
            end
        end
    end
end






-- Angle Evaluation Function
local function evaluate_angle(player, angle)
    local data = resolver_data[player]
    if not data then return 0 end

    local missed_shots = data.missed_shots or 0
    local last_real_angle = data.last_real_angle or 0
    local hit_history = data.hit_history or {}
    
    local base_score = 100 - (missed_shots * 10)
    local angle_diff = math.abs(angle - last_real_angle)
    local angle_penalty = angle_diff * 0.5
    local history_bonus = 0
    for _, hit in ipairs(hit_history) do
        if math.abs(hit.angle - angle) < 10 then
            history_bonus = history_bonus + 10
        end
    end
    
    return math.max(0, base_score - angle_penalty + history_bonus)
end

-- Resolution Application Function
local function apply_resolution(player, angle)
    if not player or not angle then return end

    local miss_data = missed_shots_data[player]
    if miss_data and miss_data.count > 0 then
        -- Adjust angle based on miss history
        local miss_adjustment = miss_data.count * 5
        angle = angle + (miss_data.count % 2 == 0 and miss_adjustment or -miss_adjustment)
    end

    local latency_adjustment = get_latency_adjustment(player)
    angle = angle + latency_adjustment
    
    -- Normalize angle between -180 and 180
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    
    -- Add jitter for hard-to-resolve players
    if missed_shots_data[player] and missed_shots_data[player].count > 3 then
        angle = angle + math.random(-10, 10)
    end
    
    local current = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local smoothing_factor = math.max(0.1, 1 - (latency_adjustment / 30))
    local max_step = 30
    local angle_step = math.min(math.abs(angle - current), max_step)
    local smoothed_angle = current + math_sign(angle - current) * angle_step

    entity.set_prop(player, "m_angEyeAngles[1]", smoothed_angle)
    
    if not resolver_data[player] then 
        resolver_data[player] = {
            last_applied_angle = smoothed_angle,
            last_real_angle = smoothed_angle
        }
    else
        resolver_data[player].last_applied_angle = smoothed_angle
    end
end

-- Pattern Recognition Function
local function recognize_pattern(angle_history)
    if not angle_history or #angle_history < 15 then return nil end
    
    local patterns = { jitter = 0, switch = 0, static = 0 }
    
    for i = 2, #angle_history do
        local diff = math.abs(angle_history[i] - angle_history[i-1])
        if diff > 45 then
            patterns.jitter = patterns.jitter + 1
        elseif diff > 15 then
            patterns.switch = patterns.switch + 1
        elseif diff < 5 then
            patterns.static = patterns.static + 1
        end
    end
    
    if patterns.jitter >= 3 then return "Jitter AA"
    elseif patterns.switch >= 3 then return "Switch AA"
    elseif patterns.static >= 4 then return "Static AA"
    end
    
    return nil
end

local function update_last_real_angle(player, angle)
    if not player then return end
    
    if not resolver_data[player] then
        resolver_data[player] = {
            last_real_angle = angle,
            last_applied_angle = angle
        }
    else
        resolver_data[player].last_real_angle = angle
    end
end

-- Movement-based Resolution Adjustment
local function adjust_resolution_for_movement(player, predicted_pos)
    if not player or not predicted_pos then return end
    
    -- Initialize resolver data if it doesn't exist
    if not resolver_data[player] then
        resolver_data[player] = {
            last_real_angle = 0,  -- Set a default value
            last_applied_angle = 0
        }
    end
    
    -- Additional safety check for last_real_angle
    if not resolver_data[player].last_real_angle then
        resolver_data[player].last_real_angle = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    end
    
    local current_pos = vector(entity.get_prop(player, "m_vecOrigin"))
    if not current_pos then return end
    
    local velocity = vector(entity.get_prop(player, "m_vecVelocity"))
    if not velocity then return end
    
    local distance = (predicted_pos - current_pos):length()
    local speed = velocity:length()
    
    -- Now we can safely access resolver_data[player].last_real_angle
    local last_angle = resolver_data[player].last_real_angle
    
    if speed > 250 then
        apply_resolution(player, last_angle + 15)
    elseif speed > 130 then
        apply_resolution(player, last_angle - 10)
    elseif distance < 5 then
        apply_resolution(player, last_angle)
    end
end

-- Active Resolutions Counter
local function count_active_resolutions()
    return #ui.get(ui_elements.resolution_mode)
end

-- Exploit Handler Function
local function handle_exploit(player, exploit_type)
    if not player or not exploit_type then return end
    
    local data = resolver_data[player]
    if not data then return end
    
    if exploit_type == "doubletap" then
        local prediction = data.last_real_angle + 35
        apply_resolution(player, prediction)
        data.exploit_history = data.exploit_history or {}
        table.insert(data.exploit_history, {
            type = "doubletap",
            time = globals.realtime(),
            angle = prediction
        })
    elseif exploit_type == "hideshot" then
        local prediction = data.last_real_angle - 25
        apply_resolution(player, prediction)
        data.exploit_history = data.exploit_history or {}
        table.insert(data.exploit_history, {
            type = "hideshot",
            time = globals.realtime(),
            angle = prediction
        })
    end
    
    if data.exploit_history and #data.exploit_history > 10 then
        table.remove(data.exploit_history, 1)
    end
end

-- Initialize Resolver Data for a New player
local function initialize_player_data(player)
    resolver_data[player] = {
        angle_history = {},
        missed_shots = 0,
        last_real_angle = 0,
        hit_history = {},
        exploit_history = {},
        prediction_accuracy = 100,
        exploit_count = 0,
        last_exploit_time = 0,
        successful_predictions = 0,
        total_predictions = 0,
        last_prediction = {
            time = 0,
            angle = 0,
            accuracy = 0
        }
    }
end

-- Enhanced Predict Next Angle with Safety Checks
local function predict_next_angle(player)
    local data = resolver_data[player]
    if not data or not data.angle_history then return nil end
    
    if #data.angle_history < 15 then return nil end
    
    local input = {}
    for i = 1, 15 do
        input[i] = data.angle_history[#data.angle_history - 15 + i] or 0
    end
    
    local hidden = apply_layer(input, NN.weights.hidden, NN.biases.hidden)
    if not hidden or #hidden == 0 then return nil end
    
    local output = apply_layer(hidden, NN.weights.output, NN.biases.output)
    if not output or #output == 0 then return nil end
    
    return (output[1] * 360) - 180
end

-- Anti-Aim Detection & Prediction
local function detect_desync(player)
    local eye_angles = entity.get_prop(player, "m_angEyeAngles")
    local body_yaw = entity.get_prop(player, "m_flPoseParameter")
    return math.abs(eye_angles - body_yaw)
end

local function resolve_enemy(player)
    local angle = entity.get_prop(player, "m_angEyeAngles")
    local desync = detect_desync(player)

    if desync > 30 then
        if resolver_history[player] then
            return resolver_history[player]
        else
            return angle + (math.random(1, 2) == 1 and 58 or -58)
        end
    end

    return angle
end

-- Unbeatable Brute-Force Resolver (Smart Brute)
local possible_angles = {-60, -30, 0, 30, 60}
local last_miss = {}

local function resolve_bruteforce(player)
    for _, angle in ipairs(possible_angles) do
        if not last_miss[player] or last_miss[player] ~= angle then
            if check_hit(angle) then
                return angle
            end
        end
    end

    return 0
end

-- Prediction-Based Resolver (Memory + Backtrack Combo)
local enemy_angles = {}

local function resolve_memory(player)
    local angle = entity.get_prop(player, "m_angEyeAngles")

    if enemy_angles[player] then
        local predicted = (enemy_angles[player] + angle) / 2
        return predicted
    else
        enemy_angles[player] = angle
    end

    return angle
end

-- Exploit-Based Resolver (Edge Resolver)
local function resolve_edge(player)
    local is_on_edge = entity.get_prop(player, "m_vecOrigin") + 10

    if is_on_edge then
        return entity.get_prop(player, "m_angEyeAngles") + 180
    end

    return entity.get_prop(player, "m_angEyeAngles")
end

-- Dynamic Hitbox Adjustments
local hitboxes = { "head", "chest", "pelvis" }

local function get_best_hitbox(player)
    for _, hitbox in ipairs(hitboxes) do
        if is_visible(player, hitbox) then
            return hitbox
        end
    end

    return "head"
end


local ai_data_loaded = false

-- Function to sanitize resolver_data for JSON encoding
local function sanitize_data(data)
    local clean_data = {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            clean_data[k] = sanitize_data(v)  -- Recursively clean tables
        elseif type(v) ~= "function" and type(v) ~= "userdata" then
            clean_data[k] = v  -- Only keep serializable values
        end
    end
    return clean_data
end

-- Save AI Data Function
local function save_ai_data()
    local ai_data = {
        resolver_data = sanitize_data(resolver_data or {}),  -- Ensure valid data
        pattern_memory = sanitize_data(pattern_memory or {}),
        exploit_history = sanitize_data(exploit_history or {})
    }

    local success, encoded_data = pcall(json.encode, ai_data)  -- Safe JSON encoding
    if success and encoded_data then
        database.write("ai_data", encoded_data)
        client.log("[NeuraulOnTop] AI data saved successfully! ✅")
    else
        client.log("[NeuraulOnTop] JSON Encoding Failed! ❌ (Data might have invalid values)")
    end
end

-- Load AI Data Function (Only Runs Once)
local function load_ai_data()
    if ai_data_loaded then return end  -- Prevent multiple executions
    ai_data_loaded = true

    local content = database.read("ai_data")
    if content and content ~= "" then
        local success, ai_data = pcall(json.decode, content)
        if success and ai_data then
            resolver_data = ai_data.resolver_data or {}
            pattern_memory = ai_data.pattern_memory or {}
            exploit_history = ai_data.exploit_history or {}
            client.log("[NeuraulOnTop] AI data loaded successfully! ✅")
        else
            client.log("[NeuraulOnTop] JSON Decoding Failed! ❌")
        end
    else
        client.log("[NeuraulOnTop] No AI data found! 🛑 (Creating new empty data)")
        resolver_data = {}  -- Ensure empty data is created
        pattern_memory = {}
        exploit_history = {}
        save_ai_data()  -- Save new empty data to avoid future errors
    end
end

-- Powerful Backtrack Resolver
local function store_backtrack(player)
    if not entity.is_alive(player) then return end

    local tick = globals.tickcount()
    local eye_angles = entity.get_prop(player, "m_angEyeAngles")
    local position = entity.get_prop(player, "m_vecOrigin")

    backtrack_data[player] = {
        tick = tick,
        eye_angles = eye_angles,
        position = position
    }
end

local function resolve_backtrack(player)
    if not backtrack_data[player] then return end

    local stored = backtrack_data[player]
    local latency_ticks = client.latency() / globals.tickinterval()

    if stored.tick >= (globals.tickcount() - latency_ticks) then
        return stored.eye_angles
    end

    return entity.get_prop(player, "m_angEyeAngles")
end

-- Fake Lag Detection
local function detect_fake_lag(player)
    local choked = entity.get_prop(player, "m_nChokedTicks")
    return choked and choked > 5
end

local function detect_exploits(player)
    -- Ensure resolver_data[player] is initialized
    if not resolver_data[player] then
        initialize_player_data(player)
    end

    local tick_base = entity.get_prop(player, "m_nTickBase")
    local sim_time = entity.get_prop(player, "m_flSimulationTime")

    if not tick_base or not sim_time then return nil end

    local exploit_type = nil

    if math.abs(tick_base - sim_time / globals.tickinterval()) > 16 then
        exploit_type = "doubletap"
    elseif globals.chokedcommands() > 6 then
        exploit_type = "hideshot"
    elseif globals.chokedcommands() > 10 then
        exploit_type = "fake lag"
    end

    -- Prevent false positives: Require 2+ detections
    resolver_data[player].exploit_count = (resolver_data[player].exploit_count or 0) + 1
    if exploit_type and resolver_data[player].exploit_count >= 2 then
        -- Add cooldown to prevent instant toggling abuse
        if resolver_data[player].last_exploit_time and globals.realtime() - resolver_data[player].last_exploit_time < 1 then
            return nil  -- Ignore toggles within 1 second
        end
        resolver_data[player].last_exploit_time = globals.realtime()
        return exploit_type
    end

    -- Reset exploit count if no exploit detected
    resolver_data[player].exploit_count = 0

    return nil
end

local function update_learning_rate()
    local accuracy = get_prediction_accuracy()
    if accuracy > 85 then
        NN.learning_rate = math.max(NN.learning_rate - 0.001, 0.01)
    else
        NN.learning_rate = math.min(NN.learning_rate + 0.001, 0.1)
    end
end


-- Render Resolver Info
local function render_resolver_info()
    if not ui.get(ui_elements.show_resolver_info) then return end

    local x, y = 100, 100 + ui.get(ui_elements.info_position)
    
    -- Background
    renderer.rectangle(x - 5, y - 5, 210, 110, 0, 0, 0, 200)
    
    -- Title with version
    renderer.text(x, y, 255, 255, 255, 255, "", 0, "Neuraul Resolver v2.1")
    
    -- Stats with guaranteed values
    y = y + 20
    local active_modes = ui.get(ui_elements.resolution_mode)
    renderer.text(x, y, 0, 255, 0, 255, "", 0, string.format("Active Resolutions: %d", #active_modes))
    
    y = y + 15
    -- Ensure learning rate is never 0
    local learning_rate = math.max(NN.learning_rate, 0.01)
    renderer.text(x, y, 255, 255, 0, 255, "", 0, string.format("Learning Rate: %.4f", learning_rate))
    
    y = y + 15
    local accuracy = get_prediction_accuracy()
    renderer.text(x, y, 255, 0, 0, 255, "", 0, string.format("Prediction Accuracy: %.1f%%", accuracy))
end

-- Debug Info Renderer
local function render_debug_info()
    if not ui.get(ui_elements.show_debug_info) then return end

    local x, y = 400, 100
    renderer.rectangle(x - 5, y - 5, 300, 150, 0, 0, 0, 200)
    renderer.text(x, y, 255, 255, 255, 255, "", 0, "🔍 Resolver Debug Info")

    y = y + 20
    -- Use the global last prediction value
    renderer.text(x, y, 0, 255, 255, 255, "", 0, "📌 Last Prediction: " .. string.format("%.1f°", last_prediction_value))

    y = y + 15
    -- Get exploit status for local player or closest enemy
    local target = entity.get_local_player()
    if not target then
        local players = entity.get_players(true)
        if #players > 0 then
            target = players[1]
        end
    end
    local exploit = target and detect_exploits(target) or "None"
    renderer.text(x, y, 255, 0, 0, 255, "", 0, "⚡ Exploit Detected: " .. exploit)

    y = y + 15
    renderer.text(x, y, 0, 255, 0, 255, "", 0, "📊 AI Accuracy: " .. string.format("%.1f%%", get_prediction_accuracy()))

    y = y + 15
    local active_modes = ui.get(ui_elements.resolution_mode)
    renderer.text(x, y, 255, 255, 0, 255, "", 0, "🔧 Active Resolutions: " .. #active_modes)
end

local function update_angle_history(player, angle, predicted)
    if not resolver_data[player] then
        initialize_player_data(player)
    end
    
    if not resolver_data[player].angle_history then
        resolver_data[player].angle_history = {}
    end

    table.insert(resolver_data[player].angle_history, {
        angle = angle,
        time = globals.realtime(),
        predicted = predicted
    })

    -- Keep history size manageable
    while #resolver_data[player].angle_history > 20 do
        table.remove(resolver_data[player].angle_history, 1)
    end
end

local function get_angle_difference(angle1, angle2)
    if not angle1 or not angle2 then return 0 end
    local diff = (angle1 - angle2) % 360
    return diff > 180 and diff - 360 or diff
end

-- Movement Prediction
local function predict_movement(player)
    local velocity = vector(entity.get_prop(player, "m_vecVelocity"))
    local origin = vector(entity.get_prop(player, "m_vecOrigin"))
    local predicted_pos = origin + velocity * globals.tickinterval()

    -- Apply gravity and friction
    predicted_pos.z = predicted_pos.z - 800 * globals.tickinterval() * globals.tickinterval() / 2

    return predicted_pos
end



-- Main Resolver Logic
local function resolve_player(player)
    -- Initialize player data if not exists
    if not resolver_data[player] then
        initialize_player_data(player)
    end

    local data = resolver_data[player]
    if not data.angle_history then
        data.angle_history = {}
    end

    local current_angle = entity.get_prop(player, "m_angEyeAngles[1]") or 0

    -- Get prediction and store it
    local predicted_angle = predict_next_angle(player)
    if predicted_angle then
        -- Store prediction data
        data.predicted_angle = predicted_angle
        data.actual_angle = current_angle
        
        -- Update angle history with timestamp
        table.insert(data.angle_history, {
            angle = current_angle,
            time = globals.realtime(),
            predicted = predicted_angle
        })
        
        -- Keep only last 10 records
        while #data.angle_history > 10 do
            table.remove(data.angle_history, 1)
        end

        -- Calculate confidence and apply resolution
        local confidence = evaluate_angle(player, predicted_angle)
        if confidence > 60 then
            -- Track successful prediction attempt with more detail
            local prediction_accuracy = math.abs(predicted_angle - current_angle)
            if prediction_accuracy < 5 then
                data.successful_predictions = (data.successful_predictions or 0) + 1
                -- Log successful prediction
                client.color_log(0, 255, 0, string.format("[NeuralOnTop] Successful prediction for player %d (accuracy: %.2f°)", player, prediction_accuracy))
            end
            data.total_predictions = (data.total_predictions or 0) + 1
            
            -- Update global prediction stats
            prediction_stats = prediction_stats or {
                total = 0,
                successful = 0
            }
            prediction_stats.total = prediction_stats.total + 1
            if prediction_accuracy < 5 then
                prediction_stats.successful = prediction_stats.successful + 1
            end
            
            -- Apply the resolution
            apply_resolution(player, predicted_angle)
            
            -- Store last prediction data
            data.last_prediction = {
                time = globals.realtime(),
                angle = predicted_angle,
                accuracy = prediction_accuracy
            }

            -- Update global last prediction value
            last_prediction_value = predicted_angle
        end
    end

    -- Clean up old data (older than 5 seconds)
    local current_time = globals.realtime()
    if data.last_prediction and current_time - data.last_prediction.time > 5 then
        data.predicted_angle = nil
        data.actual_angle = nil
    end

    -- Clean up old angle history (older than 10 seconds)
    if data.angle_history then
        for i = #data.angle_history, 1, -1 do
            if current_time - data.angle_history[i].time > 10 then
                table.remove(data.angle_history, i)
            end
        end
    end

    -- Handle exploits
    local exploit = detect_exploits(player)
    if exploit then
        handle_exploit(player, exploit)
    end

    -- Pattern recognition
    if #data.angle_history > 0 then
        local pattern = recognize_pattern(data.angle_history)
        if pattern then
            client.color_log(255, 255, 0, string.format("[NeuralOnTop] Pattern detected: %s", pattern))
            
            if data.missed_shots >= 2 then
                apply_resolution(player, data.last_real_angle + 35)
            else
                apply_resolution(player, data.last_real_angle + 20)
            end
        end
    end

    -- Movement prediction and adjustment
    local predicted_pos = predict_movement(player)
    adjust_resolution_for_movement(player, predicted_pos)

    -- Backtrack handling
    store_backtrack(player)
    resolve_backtrack(player)
end

function on_hit(attacker, hit_angle)
    if not resolver_data[attacker] then
        resolver_data[attacker] = { hit_positions = {} } -- Initialize first
    end

    table.insert(resolver_data[attacker].hit_positions, {
        time = globals.realtime(),
        hit_angle = hit_angle
    })
end

local init_player_resolver_data
local update_hit_positions
local clean_old_hit_positions
local apply_resolution
local update_angle_history

-- Helper function to safely initialize resolver data for a player
init_player_resolver_data = function(player_index)
    if not player_index or player_index == 0 then 
        return false 
    end
    
    if not resolver_data[player_index] then
        resolver_data[player_index] = {
            missed_shots = 0,
            hit_positions = {},
            last_applied_angle = 0,
            hit_history = {},
            last_real_angle = 0
        }
    end
    
    return true
end

-- Helper function to safely update hit positions
update_hit_positions = function(player_index, angle)
    if not player_index or not resolver_data[player_index] then 
        return false 
    end
    
    if not resolver_data[player_index].hit_positions then
        resolver_data[player_index].hit_positions = {}
    end
    
    table.insert(resolver_data[player_index].hit_positions, {
        hit_angle = angle,
        time = globals.realtime()
    })
    
    return true
end

-- Helper function to clean old hit positions
clean_old_hit_positions = function(max_age)
    local current_time = globals.realtime()
    
    for player_index, data in pairs(resolver_data) do
        if data.hit_positions then
            local i = 1
            while i <= #data.hit_positions do
                if current_time - data.hit_positions[i].time > max_age then
                    table.remove(data.hit_positions, i)
                else
                    i = i + 1
                end
            end
        end
    end
end

local function update_angle_history(player, angle, predicted)
    if not player or not angle then return end
    
    -- Initialize resolver data if needed
    if not resolver_data[player] then
        resolver_data[player] = {
            last_real_angle = angle,
            last_applied_angle = angle,
            hit_positions = {},
            missed_shots = 0,
            hit_history = {},
            angle_history = {}
        }
    end
    
    -- Ensure angle_history exists
    if not resolver_data[player].angle_history then
        resolver_data[player].angle_history = {}
    end

    -- Add new angle data
    table.insert(resolver_data[player].angle_history, {
        angle = angle,
        time = globals.realtime(),
        predicted = predicted
    })

    -- Keep history size manageable
    while #resolver_data[player].angle_history > 20 do
        table.remove(resolver_data[player].angle_history, 1)
    end
end

local function handle_missed_shot(target)
    -- Validate target
    if not target then return nil end
    
    -- Initialize data if it doesn't exist
    if not missed_shots_data[target] then
        missed_shots_data[target] = {
            count = 0,
            last_angles = {},
            patterns = {}
        }
    end
    
    -- Initialize resolver_data if it doesn't exist
    if not resolver_data[target] then
        resolver_data[target] = {
            last_real_angle = 0,
            last_applied_angle = 0,
            hit_positions = {},
            missed_shots = 0,
            hit_history = {},
            angle_history = {}
        }
    end
    
    local data = missed_shots_data[target]
    local miss_count = data.count or 0
    
    -- Get current angle or use default
    local current_angle = resolver_data[target].last_real_angle or 0
    
    -- Progressive angle adjustment based on miss count
    if miss_count <= 2 then
        -- Small adjustments for first few misses
        return current_angle + (miss_count * 15)
    elseif miss_count <= 4 then
        -- Larger adjustments for subsequent misses
        return current_angle - (miss_count * 20)
    else
        -- Reset and try opposite side
        data.count = 0
        return current_angle + 180
    end
end

local function cleanup_missed_shots_data()
    -- Clean up old data periodically
    local current_time = globals.realtime()
    for player, data in pairs(missed_shots_data) do
        -- Remove data older than 5 seconds
        if data.last_update and (current_time - data.last_update) > 5 then
            missed_shots_data[player] = nil
        end
    end
end


-- Bullet Impact Event Handler
local function on_bullet_impact(event)
    -- Validate event
    if not event or not event.userid then return end
    
    local player = client.userid_to_entindex(event.userid)
    if not player then return end
    
    -- Initialize resolver data if needed
    if not resolver_data[player] then
        resolver_data[player] = {
            last_real_angle = 0,
            last_applied_angle = 0,
            hit_positions = {},
            missed_shots = 0,
            hit_history = {},
            angle_history = {}
        }
    end

    local impact_angle = entity.get_prop(player, "m_angEyeAngles[1]")
    if impact_angle then
        -- Update real angle
        update_last_real_angle(player, impact_angle)
        
        -- Update angle history
        update_angle_history(player, impact_angle, nil)
    end

    -- Prevent angle history overflow
    if resolver_data[player].angle_history and #resolver_data[player].angle_history > 20 then
        table.remove(resolver_data[player].angle_history, 1)
    end
end


local function on_player_hurt(event)
    -- Validate event
    if not event or not event.attacker or not event.userid then
        client.log("Invalid event data received")
        return
    end
    
    -- Convert user IDs to entity indices
    local attacker = client.userid_to_entindex(event.attacker)
    local victim = client.userid_to_entindex(event.userid)
    
    -- Validate entity indices
    if not attacker or not victim or attacker == 0 or victim == 0 then
        client.log("Invalid player indices")
        return
    end
    
    -- Initialize resolver data for both players
    local attacker_init = init_player_resolver_data(attacker)
    local victim_init = init_player_resolver_data(victim)
    
    if not attacker_init or not victim_init then
        client.log("Failed to initialize resolver data")
        return
    end
    
    -- Get current angles for both players
    local attacker_angle = entity.get_prop(attacker, "m_angEyeAngles[1]")
    local victim_angle = entity.get_prop(victim, "m_angEyeAngles[1]")
    
    -- Update real angles if available
    if attacker_angle and type(update_last_real_angle) == "function" then
        update_last_real_angle(attacker, attacker_angle)
    end
    
    if victim_angle and type(update_last_real_angle) == "function" then
        update_last_real_angle(victim, victim_angle)
    end
    
    local local_player = entity.get_local_player()
    
    -- Handle local player hits
    if attacker == local_player then
        if resolver_data[victim] then
            -- Update angle history if function exists
            if type(update_angle_history) == "function" then
                update_angle_history(victim, resolver_data[victim].last_applied_angle, nil)
            end
            
            -- Update hit history
            if not resolver_data[victim].hit_history then
                resolver_data[victim].hit_history = {}
            end
            
            table.insert(resolver_data[victim].hit_history, {
                angle = resolver_data[victim].last_applied_angle,
                time = globals.realtime()
            })
            
            -- Update missed shots counter
            resolver_data[victim].missed_shots = math.max(0, resolver_data[victim].missed_shots - 1)
        end
    else
        -- Update attacker's missed shots counter
        if resolver_data[attacker] then
            resolver_data[attacker].missed_shots = resolver_data[attacker].missed_shots + 1
        end
    end
    
    -- Safely store enemy successful hit positions
    if resolver_data[victim] and resolver_data[victim].last_applied_angle then
        update_hit_positions(victim, resolver_data[victim].last_applied_angle)
    end
    
    -- Adjust angle towards enemy successful hit positions
    if resolver_data[attacker] and 
       resolver_data[attacker].hit_positions and 
       #resolver_data[attacker].hit_positions > 0 then
        
        local last_hit_position = resolver_data[attacker].hit_positions[#resolver_data[attacker].hit_positions]
        
        if last_hit_position and 
           last_hit_position.time and 
           globals.realtime() - last_hit_position.time < 1 and
           type(apply_resolution) == "function" then
            
            apply_resolution(attacker, last_hit_position.hit_angle + 10)
            
            if type(update_last_real_angle) == "function" then
                update_last_real_angle(attacker, last_hit_position.hit_angle + 10)
            end
        end
    end
    
    -- Clean up old hit positions (older than 5 seconds)
    clean_old_hit_positions(5)
end

local function cleanup()
    resolver_data = {}
end



-- Then define on_player_miss ensuring it has access to the global apply_resolution
local function on_player_miss(event)
    if not event or not event.userid then return end
    
    local attacker = client.userid_to_entindex(event.userid)
    local target = client.userid_to_entindex(event.target)
    
    if not attacker or not target then return end
    
    -- Initialize missed shots data
    if not missed_shots_data[target] then
        missed_shots_data[target] = {
            count = 0,
            last_angles = {},
            patterns = {}
        }
    end
    
    -- Increment miss counter
    missed_shots_data[target].count = missed_shots_data[target].count + 1
    
    -- Store the angle that missed
    local current_angle = resolver_data[target] and resolver_data[target].last_applied_angle
    if current_angle then
        table.insert(missed_shots_data[target].last_angles, current_angle)
        
        -- Keep only last 5 missed angles
        if #missed_shots_data[target].last_angles > 5 then
            table.remove(missed_shots_data[target].last_angles, 1)
        end
    end
    
    -- Adjust resolver based on miss patterns
    local new_angle = handle_missed_shot(target)
    if new_angle then
        _G.apply_resolution(target, new_angle) -- Try using _G to access the global function
    end
end




-- Neural Network Initialization
local function initialize_neural_network()
    -- Xavier Initialization
    for i = 1, NN.input_layer do
        NN.weights.hidden[i] = {}
        for j = 1, NN.hidden_layer do
            NN.weights.hidden[i][j] = math.random() * math.sqrt(2 / (NN.input_layer + NN.hidden_layer))
        end
    end

    -- Initialize Output Weights
    for i = 1, NN.hidden_layer do
        NN.weights.output[i] = {}
        for j = 1, NN.output_layer do
            NN.weights.output[i][j] = math.random() * math.sqrt(2 / (NN.hidden_layer + NN.output_layer))
        end
    end

    -- Initialize Biases
    for i = 1, NN.hidden_layer do
        NN.biases.hidden[i] = math.random() * 0.1 - 0.05
    end

    for i = 1, NN.output_layer do
        NN.biases.output[i] = math.random() * 0.1 - 0.05
    end
end

-- Main Update Loop
local function on_update()
    if not ui.get(ui_elements.enable_resolver) then return end

    local players = entity.get_players(true)
    if #players == 0 then return end  -- Prevent running if no players

    for _, player in ipairs(players) do
        if resolver_data[player] then
            resolve_player(player)
        end
    end

    if globals.tickcount() % 64 == 0 then
        update_learning_rate()
    end

    if globals.tickcount() % 64 == 0 then
        cleanup_missed_shots_data()
    end
    
    -- AI Learning Update
    if ui.get(ui_elements.enable_ai_learning) and globals.tickcount() % (get_prediction_accuracy() > 75 and 128 or 64) == 0 then
        update_neural_network()
    end
    
    -- Render UI (Only every 10 frames to save FPS)
    if globals.framecount() % 10 == 0 then
        render_resolver_info()
    end

    -- Render Debug Info
    render_debug_info()
end

local function register_callbacks()
    client.set_event_callback("shutdown", save_ai_data)
    client.set_event_callback("paint", on_update)
    client.set_event_callback("player_hurt", on_player_hurt)
    client.set_event_callback("bullet_impact", on_bullet_impact)
    client.set_event_callback("shutdown", cleanup)
    client.set_event_callback("weapon_fire", on_player_miss)
    client.set_event_callback("aim_miss", on_player_miss)
end

-- Initialize the resolver
initialize_neural_network()
load_ai_data()
register_callbacks()

-- Missing Functions Implementations

-- detect_exploits (Detects DT, Hideshot, Fake Lag)


-- reset_resolver_data (Clears AI Learning & History)
local function reset_resolver_data()
    resolver_data = {}
    pattern_memory = {}
    exploit_history = {}
    client.log("[NeuraulonTop] Data reset successfully!")
end

-- get_resolver_stats (Returns Resolver Performance Stats)
local function get_resolver_stats()
    return {
        accuracy = get_prediction_accuracy(),
        active_resolutions = count_active_resolutions(),
        learning_rate = NN.learning_rate
    }
end

-- force_update_resolver (Forces AI Learning Update)
local function force_update_resolver()
    update_neural_network()
    client.log("[NeuraulOnTop] AI learning manually updated!")
end

-- Return the resolver interface
return {
    version = "2.1",
    name = "Neuraul the best Advanced Neural Resolver",
    reset = reset_resolver_data,
    get_stats = get_resolver_stats,
    force_update = force_update_resolver
}
