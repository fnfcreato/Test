local ffi = require("ffi")
local bit = require("bit")
local vector = require("vector")

-- Neural Network Configuration
local NN = {
    input_layer = 10,
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

-- Global Variables
local resolver_data = {}
local pattern_memory = {}
local exploit_history = {}
local last_prediction = {}

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

-- 1. Prediction Accuracy Calculator
local function get_prediction_accuracy()
    local total_predictions = 0
    local correct_predictions = 0
    
    for _, data in pairs(resolver_data) do
        if data.predicted_angle and data.actual_angle then
            if #data.angle_history < 5 then
                return 100 -- Ignore new players from affecting accuracy
            end
            total_predictions = total_predictions + 1
            -- Consider predictions within 5 degrees as correct
            if math.abs(data.predicted_angle - data.actual_angle) < 5 then
                correct_predictions = correct_predictions + 1
            end
        end
    end
    
    return (correct_predictions / math.max(total_predictions, 1)) * 100
end

-- 2. Neural Network Update Function
local function update_neural_network()
    local accuracy = get_prediction_accuracy()
    
    -- Only update if accuracy is good (Prevents overfitting)
    if accuracy > 50 then  
        if accuracy > 85 then
            NN.learning_rate = math.max(NN.learning_rate - 0.001, 0.001)
        else
            NN.learning_rate = math.min(NN.learning_rate + 0.001, 0.1)
        end

        for player, data in pairs(resolver_data) do
            if data.angle_history and #data.angle_history >= 5 then
                local input_data = {}
                for i = 1, 5 do
                    input_data[i] = data.angle_history[#data.angle_history - 5 + i] or 0
                end
                local target = data.actual_angle or 0
                pattern_recognition:train(input_data, target)
            end
        end
    end
end

-- Leaky ReLU Activation Function
local function leaky_relu(x)
    return x > 0 and x or x * 0.01
end

-- 3. Layer Application Function
local function apply_layer(input, weights, biases)
    if not input or not weights or not biases then return {} end
    
    local output = {}
    for i = 1, #weights do
        local sum = biases[i] or 0
        for j = 1, #input do
            sum = sum + (input[j] * math.min(math.max(weights[j][i] or 0, -2), 2))
        end
        output[i] = leaky_relu(sum)
    end
    return output
end

-- 4. Angle Evaluation Function
local function evaluate_angle(player, angle)
    local data = resolver_data[player]
    if not data then return 0 end

    local missed_shots = data.missed_shots or 0
    local last_real_angle = data.last_real_angle or 0
    local hit_history = data.hit_history or {}
    
    -- Calculate base score
    local base_score = 100 - (missed_shots * 10)
    
    -- Adjust score based on angle difference
    local angle_diff = math.abs(angle - last_real_angle)
    local angle_penalty = angle_diff * 0.5
    
    -- Consider hit history
    local history_bonus = 0
    for _, hit in ipairs(hit_history) do
        if math.abs(hit.angle - angle) < 10 then
            history_bonus = history_bonus + 10
        end
    end
    
    return math.max(0, base_score - angle_penalty + history_bonus)
end

-- 5. Resolution Application Function
local function apply_resolution(player, angle)
    if not player or not angle then return end

    local latency_adjustment = get_latency_adjustment(player)
    angle = angle + latency_adjustment  -- Adjust angle based on latency
    
    -- Ensure angle is within valid range (-180 to 180)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    
    -- Adaptive smoothing based on latency
    local current = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local smoothing_factor = math.max(0.1, 1 - (latency_adjustment / 30))
    local max_step = 30  -- Max degrees to adjust per update
local angle_step = math.min(math.abs(angle - current), max_step)
local smoothed_angle = current + math.sign(angle - current) * angle_step
    
    entity.set_prop(player, "m_angEyeAngles[1]", smoothed_angle)
    
    -- Store resolution data
    if not resolver_data[player] then resolver_data[player] = {} end
    resolver_data[player].last_applied_angle = smoothed_angle
end

-- 6. Pattern Recognition Function
local function recognize_pattern(angle_history)
    if not angle_history or #angle_history < 5 then return nil end
    
    local patterns = {
        jitter = 0,
        switch = 0,
        static = 0
    }
    
    -- Analyze last 5 angles
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
    
    -- Determine pattern type
    if patterns.jitter >= 3 then return "Jitter AA"
    elseif patterns.switch >= 3 then return "Switch AA"
    elseif patterns.static >= 4 then return "Static AA"
    end
    
    return nil
end

-- 7. Movement-based Resolution Adjustment
local function adjust_resolution_for_movement(player, predicted_pos)
    if not player or not predicted_pos then return end
    
    local current_pos = vector(entity.get_prop(player, "m_vecOrigin"))
    local velocity = vector(entity.get_prop(player, "m_vecVelocity"))
    
    -- Calculate movement delta
    local distance = (predicted_pos - current_pos):length()
    local speed = velocity:length()
    
    -- Adjust resolution based on movement
    if speed > 250 then -- Running
        apply_resolution(player, resolver_data[player].last_real_angle + 15)
    elseif speed > 130 then -- Walking
        apply_resolution(player, resolver_data[player].last_real_angle - 10)
    elseif distance < 5 then -- Nearly static
        apply_resolution(player, resolver_data[player].last_real_angle)
    end
end

-- 8. Active Resolutions Counter
local function count_active_resolutions()
    return #ui.get(ui_elements.resolution_mode)
end

-- 9. Exploit Handler Function
local function handle_exploit(player, exploit_type)
    if not player or not exploit_type then return end
    
    local data = resolver_data[player]
    if not data then return end
    
    -- Handle different exploit types
    if exploit_type == "doubletap" then
        -- Apply aggressive angle prediction for DT
        local prediction = data.last_real_angle + 35
        apply_resolution(player, prediction)
        data.exploit_history = data.exploit_history or {}
        table.insert(data.exploit_history, {
            type = "doubletap",
            time = globals.realtime(),
            angle = prediction
        })
    elseif exploit_type == "hideshot" then
        -- More conservative prediction for hideshots
        local prediction = data.last_real_angle - 25
        apply_resolution(player, prediction)
        data.exploit_history = data.exploit_history or {}
        table.insert(data.exploit_history, {
            type = "hideshot",
            time = globals.realtime(),
            angle = prediction
        })
    end
    
    -- Cleanup old history
    if data.exploit_history and #data.exploit_history > 10 then
        table.remove(data.exploit_history, 1)
    end
end

-- Initialize the resolver data for a new player
local function initialize_player_data(player)
    resolver_data[player] = {
        angle_history = {},
        missed_shots = 0,
        last_real_angle = 0,
        hit_history = {},
        exploit_history = {},
        prediction_accuracy = 100,
        exploit_count = 0,
        last_exploit_time = 0
    }
end

-- Enhanced predict_next_angle with safety checks
local function predict_next_angle(player)
    local data = resolver_data[player]
    if not data or not data.angle_history then return nil end
    
    -- Ensure sufficient history
    if #data.angle_history < 5 then return nil end
    
    -- Prepare input data
    local input = {}
    for i = 1, 5 do
        input[i] = data.angle_history[#data.angle_history - 5 + i] or 0
    end
    
    -- Apply neural network prediction
    local hidden = apply_layer(input, NN.weights.hidden, NN.biases.hidden)
    if not hidden or #hidden == 0 then return nil end
    
    local output = apply_layer(hidden, NN.weights.output, NN.biases.output)
    if not output or #output == 0 then return nil end
    
    return (output[1] * 360) - 180  -- Corrected math
end

local function render_resolver_info()
    if not ui.get(ui_elements.show_resolver_info) then return end

    local x, y = 100, 100 + ui.get(ui_elements.info_position)

    -- Render background
    renderer.rectangle(x - 5, y - 5, 210, 110, 0, 0, 0, 200)

    -- Render title
    renderer.text(x, y, 255, 255, 255, 255, "", 0, "Neuraul Resolver v2.1")

    -- Render stats
    y = y + 20
    renderer.text(x, y, 0, 255, 0, 255, "", 0, "Active Resolutions: " .. count_active_resolutions())
    y = y + 15
    renderer.text(x, y, 255, 255, 0, 255, "", 0, "Learning Rate: " .. string.format("%.4f", NN.learning_rate))
    y = y + 15
    renderer.text(x, y, 255, 0, 0, 255, "", 0, "Prediction Accuracy: " .. string.format("%.1f%%", get_prediction_accuracy()))
end

-- Debug Info Renderer
local function render_debug_info()
    if not ui.get(ui_elements.show_debug_info) then return end

    local x, y = 400, 100
    renderer.rectangle(x - 5, y - 5, 300, 150, 0, 0, 0, 200)
    renderer.text(x, y, 255, 255, 255, 255, "", 0, "🔍 Resolver Debug Info")

    -- Show last prediction angle
    y = y + 20
    renderer.text(x, y, 0, 255, 255, 255, "", 0, "📌 Last Prediction: " .. string.format("%.1f°", last_prediction[entity.get_local_player()] or 0))

    -- Show detected exploit
    y = y + 15
    local exploit = detect_exploits(entity.get_local_player())
    renderer.text(x, y, 255, 0, 0, 255, "", 0, "⚡ Exploit Detected: " .. (exploit or "None"))

    -- Show total AI accuracy
    y = y + 15
    renderer.text(x, y, 0, 255, 0, 255, "", 0, "📊 AI Accuracy: " .. string.format("%.1f%%", get_prediction_accuracy()))

    -- Show active resolution methods
    y = y + 15
    renderer.text(x, y, 255, 255, 0, 255, "", 0, "🔧 Active Resolutions: " .. count_active_resolutions())
end

-- Main Resolver Logic
local function resolve_player(player)
    if not resolver_data[player] then
        initialize_player_data(player)
    end

    local data = resolver_data[player]

    -- Predict Next Angle using AI
    local predicted_angle = predict_next_angle(player)
    if predicted_angle then
        local confidence = evaluate_angle(player, predicted_angle)
        if confidence > 60 then
            apply_resolution(player, predicted_angle)
        end
    end

    -- Detect Exploits and Handle
    local exploit = detect_exploits(player)
    if exploit then
        handle_exploit(player, exploit)
    end

    -- Recognize Anti-Aim Patterns
    local pattern = recognize_pattern(data.angle_history)
    if pattern then
        client.log("[NeuralOnTop] Pattern detected: " .. pattern)
        
        -- If two consecutive misses, force a flip
        if data.missed_shots >= 2 then
            apply_resolution(player, data.last_real_angle + 35)
        else
            apply_resolution(player, data.last_real_angle + 20)
        end
    end

    -- Adjust based on movement
    local predicted_pos = predict_movement(player)
    adjust_resolution_for_movement(player, predicted_pos)
end

-- Event Handlers
local function on_bullet_impact(event)
    local player = client.userid_to_entindex(event.userid)
    if not resolver_data[player] then return end

    -- Log Bullet Impact
    local impact_angle = entity.get_prop(player, "m_angEyeAngles[1]")
    table.insert(resolver_data[player].angle_history, impact_angle)

    -- Prevent table overflow
    if #resolver_data[player].angle_history > 20 then
        table.remove(resolver_data[player].angle_history, 1)
    end
end

local function on_player_hurt(event)
    local attacker = client.userid_to_entindex(event.attacker)
    local victim = client.userid_to_entindex(event.userid)

    if attacker == entity.get_local_player() then
        if resolver_data[victim] then
            table.insert(resolver_data[victim].hit_history, {
                angle = resolver_data[victim].last_applied_angle,
                time = globals.realtime()
            })
            resolver_data[victim].missed_shots = math.max(0, resolver_data[victim].missed_shots - 1)
        end
    else
        if resolver_data[attacker] then
            resolver_data[attacker].missed_shots = resolver_data[attacker].missed_shots + 1
        end
    end
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

-- Latency Adjustment Function
local function get_latency_adjustment(player)
    local ping = entity.get_prop(player, "m_iPing")
    return math.min(math.max(ping / 10, 0), 15)  -- Adjust resolver angles by ping
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

-- Register Event Callbacks
client.set_event_callback("paint", on_update)
client.set_event_callback("player_hurt", on_player_hurt)
client.set_event_callback("bullet_impact", on_bullet_impact)
client.set_event_callback("shutdown", save_ai_data)
client.set_event_callback("paint", load_ai_data)

-- Initialize the resolver
initialize_neural_network()
load_ai_data()

-- Missing Functions Implementations

-- detect_exploits (Detects DT, Hideshot, Fake Lag)
local function detect_exploits(player)
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
    if exploit_type then
        resolver_data[player].exploit_count = (resolver_data[player].exploit_count or 0) + 1
            if resolver_data[player].exploit_count >= 2 then
    -- Add cooldown to prevent instant toggling abuse
    if resolver_data[player].last_exploit_time and globals.realtime() - resolver_data[player].last_exploit_time < 1 then
        return nil  -- Ignore toggles within 1 second
    end
    resolver_data[player].last_exploit_time = globals.realtime()
            return exploit_type
        end
    else
        resolver_data[player].exploit_count = 0  -- Reset if no exploit detected
    end

    return nil
end

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
