--[[
    RecodeResolver2.lua
    Advanced Anti-Aim Resolver with Hybrid AI/ML Systems
    
    Features:
    - Hybrid AI/ML resolver with multiple operational modes
    - Adaptive confidence system with visual feedback
    - Enhanced prediction with GRU neural network layers
    - Animation sequence tracking and analysis
    - Network condition analysis and backtrack optimization
    - Exploit detection and countermeasures
    - Comprehensive debug system with visual analytics
]]

local ffi = require "ffi"
local vector = require "vector"
local bit = require "bit"

-- FFI declarations for enhanced memory access
ffi.cdef[[
    typedef struct {
        float x, y, z;
    } vec3_t;
    
    typedef struct {
        char pad_0000[0x60]; 
        vec3_t m_vecAbsOrigin;
    } CBaseEntity;
]]

--------------------------------------------------
-- CONSTANTS AND CONFIGURATION
--------------------------------------------------

local RESOLVER_VERSION = "3.0.0"

-- Core system constants
local CONSTANTS = {
    -- History and data tracking
    MAX_HISTORY_SIZE = 32,
    MAX_ANGLE_HISTORY = 64,
    MAX_SHOT_HISTORY = 16,
    MAX_PATTERN_MEMORY = 24,
    
    -- Resolver mechanics
    WEIGHT_DECAY = 0.92,
    CONFIDENCE_DECAY = 0.98,
    MIN_VELOCITY_CONSIDERATION = 5,
    MAX_DESYNC_ANGLE = 58,
    DEFAULT_LEARNING_RATE = 0.075,
    
    -- Pattern detection
    JITTER_THRESHOLD = 15,
    STATIC_THRESHOLD = 2,
    SWITCH_DETECTION_THRESHOLD = 2,
    
    -- ML system
    PREDICTION_DEPTH = 3,
    DEFAULT_GRU_LAYERS = 2,
    DEFAULT_UNITS_PER_LAYER = 32,
    FEATURE_VECTOR_SIZE = 16,
    
    -- Animation analysis
    ANIM_SAMPLE_RATE = 0.03,
    MAX_SEQUENCE_TRACKING = 16,
    
    -- Network analysis
    NETWORK_HISTORY_SIZE = 32,
    MAX_BACKTRACK_TICKS = 12,
    TICK_INTERVAL = 0.0078125, -- 128 tick
    
    -- Exploit detection
    DEFENSIVE_AA_THRESHOLD = 14,
    FAKELAG_DETECTION_THRESHOLD = 100,
    EXTENDED_DESYNC_ANGLE = 62,
    
    -- Visualization
    CONFIDENCE_LOW_THRESHOLD = 30,
    CONFIDENCE_HIGH_THRESHOLD = 70,
    
    -- Optimization
    HIT_PRIORITY_MODES = {
        "SMART", -- Prioritizes based on pattern recognition
        "HEAD",  -- Head priority
        "BODY",  -- Body/chest priority
        "SAFE"   -- Safe points only
    },

-- Reaction time optimization
DEFAULT_REACTION_TIME = 50, -- Default 50ms
MIN_REACTION_TIME = 5,      -- Minimum 5ms
MAX_REACTION_TIME = 200,    -- Maximum 200ms
REACTION_MODES = {
    "Balanced",             -- Balance between speed and accuracy
    "Speed Priority",       -- Maximum speed, may reduce accuracy
    "Accuracy Priority",    -- Prioritize accuracy over speed
    "Adaptive"              -- Dynamically adjust based on player skill
}
}

-- Color definitions for visualization
local COLORS = {
    CONFIDENCE = {
        HIGH = {0, 255, 0},    -- Green
        MEDIUM = {255, 255, 0}, -- Yellow
        LOW = {255, 0, 0}       -- Red
    },
    DEBUG = {
        TEXT = {255, 255, 255},
        BACKGROUND = {0, 0, 0, 150},
        HIGHLIGHT = {80, 160, 240},
        WARNING = {255, 120, 0},
        SUCCESS = {120, 255, 120},
        FAILURE = {255, 80, 80}
    },
    VISUALIZATION = {
        REAL_ANGLE = {255, 0, 0},
        RESOLVED_ANGLE = {0, 255, 0},
        PREDICTION = {0, 150, 255},
        HISTORY = {150, 150, 150},
        BACKTRACK = {255, 100, 255}
    }
}

--------------------------------------------------
-- UI COMPONENTS
--------------------------------------------------

local ui_components = {
    main = {
        enable = ui.new_checkbox("RAGE", "Other", "RecodeResolver 3.0"),
        master_switch = ui.new_hotkey("RAGE", "Other", "Toggle Resolver", true),
        mode = ui.new_combobox("RAGE", "Other", "Mode", {
            "Hybrid AI/ML",
            "Maximum Accuracy",
            "Balanced",
            "Performance",
            "Aggressive",
            "Defensive"
        }),
        base_confidence = ui.new_slider("RAGE", "Other", "Base Confidence", 0, 100, 50, true, "%"),
        presets = ui.new_combobox("RAGE", "Other", "Presets", {
            "Default",
            "Maximum Accuracy",
            "Performance Priority",
            "Legit AA Focus",
            "HvH Aggressive",
            "Matchmaking Optimized",
            "Domination"
        })
    },
    
    prediction = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Prediction"),
        ml_features = ui.new_multiselect("RAGE", "Other", "ML Features", {
            "Movement Analysis",
            "Pattern Recognition",
            "Velocity Prediction",
            "Shot History Analysis",
            "Angle Correlation"
        }),
        gru_layers = ui.new_slider("RAGE", "Other", "GRU Layers", 1, 4, CONSTANTS.DEFAULT_GRU_LAYERS, true, nil, 1),
        units_per_layer = ui.new_slider("RAGE", "Other", "Units Per Layer", 8, 64, CONSTANTS.DEFAULT_UNITS_PER_LAYER, true, nil, 8),
        prediction_depth = ui.new_slider("RAGE", "Other", "Prediction Depth", 1, 8, CONSTANTS.PREDICTION_DEPTH, true, "ticks")
    },
    
    animation = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Animation"),
        animation_features = ui.new_multiselect("RAGE", "Other", "Animation Features", {
            "Sequence Tracking",
            "Desync Detection",
            "Real-time Validation",
            "Animation Layer Analysis",
            "Eye Position Tracking"
        }),
        desync_detection = ui.new_combobox("RAGE", "Other", "Desync Detection", {
            "Basic",
            "Advanced",
            "Real-time Validation",
            "Full Analysis"
        })
    },
    
    network = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Network"),
        backtrack_options = ui.new_multiselect("RAGE", "Other", "Backtrack Options", {
            "Smart Selection",
            "Priority Targets",
            "Shot Validation",
            "Record Optimization"
        }),
        network_conditions = ui.new_multiselect("RAGE", "Other", "Network Analysis", {
            "Ping Compensation",
            "Packet Loss Detection",
            "Choke Analysis",
            "Jitter Correction"
        }),
        tick_optimization = ui.new_checkbox("RAGE", "Other", "Tick Optimization")
    },
    
    exploits = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Exploits"),
        detect_exploits = ui.new_multiselect("RAGE", "Other", "Detect Exploits", {
            "Double Tap",
            "Fake Lag",
            "Extended Desync",
            "Defensive AA",
            "Duck Exploits",
            "Teleport"
        }),
        countermeasures = ui.new_multiselect("RAGE", "Other", "Countermeasures", {
            "Auto Adapt",
            "Force Backtrack",
            "Safe Point",
            "Shot Delay",
            "Spread Reduction"
        })
    },
    
    optimization = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Optimization"),
        hitbox_priority = ui.new_combobox("RAGE", "Other", "Hitbox Priority", CONSTANTS.HIT_PRIORITY_MODES),
        accuracy_boost = ui.new_slider("RAGE", "Other", "Accuracy Boost", 0, 100, 50, true, "%")
    },
    
    reaction_time = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Reaction Time"),
        mode = ui.new_combobox("RAGE", "Other", "Reaction Mode", CONSTANTS.REACTION_MODES),
        time_ms = ui.new_slider("RAGE", "Other", "Reaction Time", CONSTANTS.MIN_REACTION_TIME, CONSTANTS.MAX_REACTION_TIME, CONSTANTS.DEFAULT_REACTION_TIME, true, "ms"),
        prefire = ui.new_checkbox("RAGE", "Other", "Enable Prefire"),
        prefire_predictability = ui.new_slider("RAGE", "Other", "Prefire Threshold", 0, 100, 70, true, "%"),
        shot_anticipation = ui.new_checkbox("RAGE", "Other", "Shot Anticipation"),
        priority_targets = ui.new_multiselect("RAGE", "Other", "Priority Targets", {
            "Low HP",
            "High Threat",
            "Weapon Type",
            "Distance Based"
        })
    },
    
    debug = {
        enable = ui.new_checkbox("RAGE", "Other", "§ Enable Debug"),
        visualize = ui.new_multiselect("RAGE", "Other", "Visualization", {
            "Confidence Indicator",
            "Real Angle",
            "Predicted Angle",
            "Backtrack Points",
            "Decision Graph",
            "Snapshots",
            "ML Prediction"
        }),
        extended_logging = ui.new_checkbox("RAGE", "Other", "Extended Logging"),
        log_to_file = ui.new_checkbox("RAGE", "Other", "Log to File"),
        debug_level = ui.new_slider("RAGE", "Other", "Debug Level", 0, 3, 1, true, nil, 1, {
            [0] = "Minimal", [1] = "Basic", [2] = "Detailed", [3] = "Full"
        })
    },
    
    appearance = {
        colors = {
            high_confidence = ui.new_color_picker("RAGE", "Other", "High Confidence", table.unpack(COLORS.CONFIDENCE.HIGH)),
            medium_confidence = ui.new_color_picker("RAGE", "Other", "Medium Confidence", table.unpack(COLORS.CONFIDENCE.MEDIUM)),
            low_confidence = ui.new_color_picker("RAGE", "Other", "Low Confidence", table.unpack(COLORS.CONFIDENCE.LOW))
        }
    }
}

--------------------------------------------------
-- ADVANCED DATA STRUCTURES
--------------------------------------------------

-- Main data storage for players
local resolver_data = setmetatable({}, {__mode = "k"})

-- ML models storage
local ml_models = {}

-- Session statistics
local session_stats = {
    started_at = globals.realtime(),
    total_hits = 0,
    total_misses = 0,
    headshots = 0,
    total_shots = 0,
    success_rate = 0,
    players_tracked = 0,
    rounds_played = 0,
    last_update = 0
}

--------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------

-- Math utilities
math_utils = {
    normalize_angle = function(angle)
        -- Handle nil input
        if not angle then
            return 0
        end
        
        -- Ensure angle is a number
        angle = tonumber(angle) or 0
        
        -- Normalize to -180 to 180 range
        angle = angle % 360
        if angle > 180 then
            angle = angle - 360
        elseif angle < -180 then
            angle = angle + 360
        end
        
        return angle
    end,
    
    calculate_angle_deviation = function(a1, a2)
        return math.abs(math_utils.normalize_angle(a1 - a2))
    end,
    
    weighted_average = function(values, weights)
        local total_value, total_weight = 0, 0
        for i, value in ipairs(values) do
            local weight = weights[i] or 1
            total_value = total_value + value * weight
            total_weight = total_weight + weight
        end
        return total_weight > 0 and (total_value / total_weight) or 0
    end,
    
    lerp = function(a, b, t)
        return a + (b - a) * t
    end,
    
    exponential_decay = function(value, decay_factor, time_delta)
        return value * math.pow(decay_factor, time_delta)
    end,
    
    calculate_standard_deviation = function(values)
        if #values < 2 then return 0 end
        
        local mean = 0
        for _, v in ipairs(values) do
            mean = mean + v
        end
        mean = mean / #values
        
        local variance = 0
        for _, v in ipairs(values) do
            variance = variance + (v - mean)^2
        end
        variance = variance / (#values - 1)
        
        return math.sqrt(variance)
    end,
    
    vector_to_angles = function(forward)
        local pitch, yaw = 0, 0
        
        if forward.x == 0 and forward.y == 0 then
            if forward.z > 0 then
                pitch = 270
            else
                pitch = 90
            end
        else
            pitch = math.atan2(-forward.z, math.sqrt(forward.x^2 + forward.y^2)) * 180 / math.pi
            yaw = math.atan2(forward.y, forward.x) * 180 / math.pi
        end
        
        return {pitch = pitch, yaw = yaw}
    end,
    
    angles_to_vector = function(pitch, yaw)
        -- Convert angles to radians
        local p = math.rad(pitch)
        local y = math.rad(yaw)
        
        -- Calculate the vector
        local sp = math.sin(p)
        local cp = math.cos(p)
        local sy = math.sin(y)
        local cy = math.cos(y)
        
        return {
            x = cp * cy,
            y = cp * sy,
            z = -sp
        }
    end,
    
    get_distance = function(v1, v2)
        return math.sqrt((v2.x - v1.x)^2 + (v2.y - v1.y)^2 + (v2.z - v1.z)^2)
    end,
    
    clamp = function(val, min, max)
        return math.max(min, math.min(max, val))
    end
}

-- Vector operations
local vector_utils = {
    add = function(v1, v2)
        return {
            x = v1.x + v2.x,
            y = v1.y + v2.y,
            z = v1.z + v2.z
        }
    end,
    
    subtract = function(v1, v2)
        return {
            x = v1.x - v2.x,
            y = v1.y - v2.y,
            z = v1.z - v2.z
        }
    end,
    
    multiply = function(v, scalar)
        return {
            x = v.x * scalar,
            y = v.y * scalar,
            z = v.z * scalar
        }
    end,
    
    normalize = function(v)
        local length = math.sqrt(v.x^2 + v.y^2 + v.z^2)
        if length == 0 then
            return {x = 0, y = 0, z = 0}
        end
        
        return {
            x = v.x / length,
            y = v.y / length,
            z = v.z / length
        }
    end,
    
    length = function(v)
        return math.sqrt(v.x^2 + v.y^2 + v.z^2)
    end,
    
    length2d = function(v)
        return math.sqrt(v.x^2 + v.y^2)
    end,
    
    dot_product = function(v1, v2)
        return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
    end,
    
    cross_product = function(v1, v2)
        return {
            x = v1.y * v2.z - v1.z * v2.y,
            y = v1.z * v2.x - v1.x * v2.z,
            z = v1.x * v2.y - v1.y * v2.x
        }
    end
}

-- Helper function to check if an option is selected in multiselect
local function has_option(options_table, option_name)
    if type(options_table) ~= "table" then return false end
    
    for _, opt in ipairs(options_table) do
        if opt == option_name then
            return true
        end
    end
    return false
end

local function get_timestamp()
    local time = globals.realtime() % 86400 -- Seconds in a day
    local hours = math.floor(time / 3600)
    local minutes = math.floor((time % 3600) / 60)
    local seconds = math.floor(time % 60)
    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- Logger system
local logger = {
    file_handle = nil,
    last_log_time = 0,        -- Track last console log time
    log_throttle = 0.1,       -- Minimum time between console logs (in seconds, adjustable)
    log_count = 0,            -- Counter for throttled messages
    
    init = function(self)
        if ui.get(ui_components.debug.log_to_file) then
            self.file_handle = io.open("recoderesolver_log.txt", "a")
            if self.file_handle then
                self.file_handle:write("\n\n--- RecodeResolver Session Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
                self.file_handle:write("Version: " .. RESOLVER_VERSION .. "\n\n")
                self.file_handle:flush()
            end
        end
        self.last_log_time = globals.realtime()
        self.log_count = 0
    end,
    
    log = function(self, message, level)
        level = level or 1
        local debug_level = ui.get(ui_components.debug.debug_level)
        
        -- Only log if our debug level is sufficient
        if debug_level >= level then
            local timestamp = get_timestamp()
            local formatted_message = string.format("[%s] %s", timestamp, message)
            local current_time = globals.realtime()
            
            -- Print to console if extended logging is enabled with throttling
            if ui.get(ui_components.debug.extended_logging) then
                if current_time - self.last_log_time >= self.log_throttle then
                    print(formatted_message)
                    self.last_log_time = current_time
                    -- If we skipped messages, log how many were skipped
                    if self.log_count > 0 then
                        print(string.format("[%s] Skipped %d log messages due to throttle", timestamp, self.log_count))
                        self.log_count = 0
                    end
                else
                    self.log_count = self.log_count + 1
                end
            end
            
            -- Log to file if enabled (no throttling for file logging)
            if ui.get(ui_components.debug.log_to_file) and self.file_handle then
                self.file_handle:write(formatted_message .. "\n")
                self.file_handle:flush()
            end
        end
    end,
    
    log_hit = function(self, player, hitbox, damage)
        local player_name = entity.get_player_name(player) or "Unknown"
        local hitbox_name = self:get_hitbox_name(hitbox)
        
        self:log(string.format("HIT: %s in %s for %d damage", 
            player_name, hitbox_name, damage), 1)
    end,
    
    log_miss = function(self, player, hitbox, reason)
        local player_name = entity.get_player_name(player) or "Unknown"
        local hitbox_name = self:get_hitbox_name(hitbox)
        
        self:log(string.format("MISS: %s targeting %s (Reason: %s)", 
            player_name, hitbox_name, reason), 1)
    end,
    
    log_resolver = function(self, player, action, details)
        local player_name = entity.get_player_name(player) or "Unknown"
        
        self:log(string.format("RESOLVER: %s - %s - %s", 
            player_name, action, details), 2)
    end,
    
    get_hitbox_name = function(self, hitbox)
        local hitbox_names = {
            [0] = "generic",
            [1] = "head",
            [2] = "chest",
            [3] = "stomach",
            [4] = "left arm",
            [5] = "right arm",
            [6] = "left leg",
            [7] = "right leg",
            [8] = "neck"
        }
        
        return hitbox_names[hitbox] or "unknown"
    end,
    
    close = function(self)
        if self.file_handle then
            -- Log any remaining skipped messages before closing
            if self.log_count > 0 then
                local timestamp = get_timestamp()
                self.file_handle:write(string.format("[%s] Skipped %d log messages due to throttle\n", timestamp, self.log_count))
            end
            self.file_handle:write("\n--- RecodeResolver Session Ended " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
            self.file_handle:close()
            self.file_handle = nil
        end
        self.log_count = 0
    end
}

--------------------------------------------------
-- MOTION ANALYSIS SYSTEM
--------------------------------------------------

local motion_analyzer = {
    get_velocity_vector = function(player)
        local vx = entity.get_prop(player, "m_vecVelocity[0]") or 0
        local vy = entity.get_prop(player, "m_vecVelocity[1]") or 0
        local vz = entity.get_prop(player, "m_vecVelocity[2]") or 0
        return {x = vx, y = vy, z = vz, magnitude = math.sqrt(vx * vx + vy * vy)}
    end,
    
    get_predicted_position = function(player, time_delta)
        local pos = {entity.get_origin(player)}
        local vel = motion_analyzer.get_velocity_vector(player)
        
        return {
            x = pos[1] + vel.x * time_delta,
            y = pos[2] + vel.y * time_delta,
            z = pos[3] + vel.z * time_delta
        }
    end,
    
    analyze_movement_pattern = function(player)
        local data = resolver_data[player]
        if not data or #data.velocity_history < 5 then 
            return {
                direction_changes = 0,
                is_strafing = false,
                movement_type = "unknown",
                predictability = 0,
                velocity_variance = 0,
                avg_velocity = 0,           -- Add default value
             acceleration_pattern = "steady" -- Add default value
            } 
        end
        
        local direction_changes = 0
        local velocity_diffs = {}
        local velocity_magnitudes = {}
        
        for i = 2, #data.velocity_history do
            local vel = data.velocity_history[i]
            local prev_vel = data.velocity_history[i-1]
            
            table.insert(velocity_magnitudes, vel.magnitude)
            table.insert(velocity_diffs, vel.magnitude - prev_vel.magnitude)
            
            if vel.x * prev_vel.x < 0 or vel.y * prev_vel.y < 0 then
                direction_changes = direction_changes + 1
            end
        end
        
        local avg_velocity = 0
        for _, v in ipairs(data.velocity_history) do
            avg_velocity = avg_velocity + v.magnitude
        end
        avg_velocity = avg_velocity / #data.velocity_history
        
        local velocity_std_dev = math_utils.calculate_standard_deviation(velocity_diffs)
        local is_strafing = direction_changes > #data.velocity_history * 0.3
        local is_predictable = velocity_std_dev < 5 and not is_strafing
        
        local movement_type = "unknown"
        if avg_velocity < 5 then
            movement_type = "standing"
        elseif avg_velocity < 80 then
            movement_type = is_strafing and "strafing_slow" or "walking"
        elseif avg_velocity < 250 then
            movement_type = is_strafing and "strafing_fast" or "running"
        else
            movement_type = "air"
        end
        
        -- Calculate acceleration patterns
        local acceleration_pattern = "steady"
        if #velocity_diffs >= 3 then
            local accel_increasing = 0
            local accel_decreasing = 0
            
            for i = 2, #velocity_diffs do
                if velocity_diffs[i] > velocity_diffs[i-1] then
                    accel_increasing = accel_increasing + 1
                elseif velocity_diffs[i] < velocity_diffs[i-1] then
                    accel_decreasing = accel_decreasing + 1
                end
            end
            
            if accel_increasing > #velocity_diffs * 0.6 then
                acceleration_pattern = "increasing"
            elseif accel_decreasing > #velocity_diffs * 0.6 then
                acceleration_pattern = "decreasing"
            elseif accel_increasing > 0 and accel_decreasing > 0 then
                acceleration_pattern = "fluctuating"
            end
        end
        
        return {
            direction_changes = direction_changes,
            is_strafing = is_strafing,
            movement_type = movement_type,
            predictability = is_predictable and 0.8 or (is_strafing and 0.3 or 0.5),
            velocity_variance = velocity_std_dev,
            avg_velocity = avg_velocity,
            acceleration_pattern = acceleration_pattern
        }
    end,
    
    predict_next_position = function(player, ticks_ahead)
        local data = resolver_data[player]
        if not data or #data.position_history < 3 then 
            -- Fallback to basic prediction if we don't have enough history
            return motion_analyzer.get_predicted_position(player, ticks_ahead * CONSTANTS.TICK_INTERVAL)
        end
        
        -- Get movement analysis
        local movement = motion_analyzer.analyze_movement_pattern(player)
        
        -- Get current position and velocity
        local pos = {entity.get_origin(player)}
        local vel = motion_analyzer.get_velocity_vector(player)
        
        -- Basic prediction
        local predicted = {
            x = pos[1] + vel.x * ticks_ahead * CONSTANTS.TICK_INTERVAL,
            y = pos[2] + vel.y * ticks_ahead * CONSTANTS.TICK_INTERVAL,
            z = pos[3] + vel.z * ticks_ahead * CONSTANTS.TICK_INTERVAL
        }
        
        -- Apply correction based on movement pattern
        if movement.movement_type == "strafing_fast" or movement.movement_type == "strafing_slow" then
            -- For strafing players, reduce lateral prediction confidence
            local direction_vector = vector_utils.normalize({x = vel.x, y = vel.y, z = 0})
            local strafe_uncertainty = movement.direction_changes / 10
            
            -- Blend between precise prediction and a more conservative one
            predicted.x = math_utils.lerp(predicted.x, pos[1], strafe_uncertainty)
            predicted.y = math_utils.lerp(predicted.y, pos[2], strafe_uncertainty)
        elseif movement.movement_type == "air" then
            -- Airborne players have gravity to consider
            predicted.z = predicted.z - 400 * math.pow(ticks_ahead * CONSTANTS.TICK_INTERVAL, 2) * 0.5
        end
        
        -- Apply adaptive prediction based on acceleration pattern
        if movement.acceleration_pattern == "increasing" then
            -- Player is accelerating, predict slightly further
            local acceleration_factor = 1.2
            predicted.x = pos[1] + vel.x * ticks_ahead * CONSTANTS.TICK_INTERVAL * acceleration_factor
            predicted.y = pos[2] + vel.y * ticks_ahead * CONSTANTS.TICK_INTERVAL * acceleration_factor
        elseif movement.acceleration_pattern == "decreasing" then
            -- Player is decelerating, predict less distance
            local deceleration_factor = 0.8
            predicted.x = pos[1] + vel.x * ticks_ahead * CONSTANTS.TICK_INTERVAL * deceleration_factor
            predicted.y = pos[2] + vel.y * ticks_ahead * CONSTANTS.TICK_INTERVAL * deceleration_factor
        end
        
        return predicted
    end
}

--------------------------------------------------
-- ANIMATION ANALYSIS SYSTEM
--------------------------------------------------

local animation_analyzer = {
    detect_desync = function(player)
        local data = resolver_data[player]
        if not data or not data.angle_history or #data.angle_history < 2 then 
            return 0, 0, false, 0  -- Return safe defaults
        end
        
        -- Calculate angle changes between updates
        local angle_diffs = {}
        local max_diff = 0
        local avg_diff = 0
        
        for i = 2, #data.angle_history do
            -- Ensure we have valid angle data
            local current = data.angle_history[i]
            local previous = data.angle_history[i-1]
            
            if current and current.yaw and previous and previous.yaw then
                local diff = math_utils.calculate_angle_deviation(
                    current.yaw,
                    previous.yaw
                )
                table.insert(angle_diffs, diff)
                avg_diff = avg_diff + diff
                max_diff = math.max(max_diff, diff)
            end
        end
        
        -- Prevent division by zero
        if #angle_diffs == 0 then
            return 0, 0, false, 0
        end
        
        avg_diff = avg_diff / #angle_diffs
        
        -- Detect jitter pattern in angles
        local jitter_count = 0
        for i = 2, #angle_diffs do
            if (angle_diffs[i] > CONSTANTS.JITTER_THRESHOLD and angle_diffs[i-1] > CONSTANTS.JITTER_THRESHOLD) or
               (angle_diffs[i] * angle_diffs[i-1] < 0) then
                jitter_count = jitter_count + 1
            end
        end
        
        local is_jittering = jitter_count > #angle_diffs * 0.3
        
        -- Estimate desync amount (better when animation data available)
        local estimated_desync = math.min(max_diff, CONSTANTS.MAX_DESYNC_ANGLE)
        
        -- Detect direction (more complex heuristic could be used)
        local direction = 0
        if #data.angle_history >= 3 then
            local recent_changes = {}
            for i = math.max(1, #data.angle_history - 3), #data.angle_history - 1 do
                if data.angle_history[i+1] and data.angle_history[i] and 
                   data.angle_history[i+1].yaw and data.angle_history[i].yaw then
                    table.insert(recent_changes, data.angle_history[i+1].yaw - data.angle_history[i].yaw)
                end
            end
            
            local dir_sum = 0
            for _, change in ipairs(recent_changes) do
                dir_sum = dir_sum + (change > 0 and 1 or -1)
            end
            
            direction = dir_sum > 0 and 1 or -1
        end
        
        return estimated_desync, direction, is_jittering, avg_diff
    end,
    
    analyze_animation_layers = function(player)
        -- Placeholder for a more advanced animation layer analysis
        -- Would require more memory reading than provided here
        local data = resolver_data[player]
        if not data then return {} end
        
        -- Create a mock analysis based on available data
        local move_type = entity.get_prop(player, "m_MoveType") or 0
        local flags = entity.get_prop(player, "m_fFlags") or 0
        local is_on_ground = bit.band(flags, 1) ~= 0
        local is_ducking = bit.band(flags, 4) ~= 0
        local duck_amount = entity.get_prop(player, "m_flDuckAmount") or 0
        
        return {
            is_on_ground = is_on_ground,
            is_ducking = is_ducking,
            duck_amount = duck_amount,
            move_type = move_type,
            simulated_layers = {
                lean_amount = duck_amount * 0.7 + (is_on_ground and 0 or 0.3),
                aim_matrix = 0.8, -- Placeholder
                weapon_action = 0.5 -- Placeholder
            }
        }
    end,
    
    
    detect_defensive_aa = function(player)
        local data = resolver_data[player]
        if not data or #data.angle_snapshots < 3 then return false, 0 end
        
        -- Check for rapid angle changes characteristic of defensive AA
        local defensive_triggers = 0
        local total_checks = math.min(6, #data.angle_snapshots - 1)
        
        for i = #data.angle_snapshots, #data.angle_snapshots - total_checks, -1 do
            local current = data.angle_snapshots[i]
            local previous = data.angle_snapshots[i-1]
            
            if current and previous then
                -- Check angle difference between snapshots
                local diff = math_utils.calculate_angle_deviation(current.yaw, previous.yaw)
                local time_diff = current.time - previous.time
                
                -- Fast angle change is characteristic of defensive AA
                if diff > CONSTANTS.DEFENSIVE_AA_THRESHOLD and time_diff < 0.05 then
                    defensive_triggers = defensive_triggers + 1
                end
            end
        end
        
        -- Determine if defensive AA is being used
        local is_using_defensive = defensive_triggers >= 2
        local certainty = defensive_triggers / total_checks
        
        if is_using_defensive then
            logger:log_resolver(player, "Exploit Detection", string.format(
                "Defensive AA detected (confidence: %.1f%%)", certainty * 100
            ), 2)
        end
        
        return is_using_defensive, certainty
    end,
    
    detect_extended_desync = function(player)
        local data = resolver_data[player]
        if not data then return false, 0 end
        
        -- Get estimated desync amount
        local desync_amount, direction, is_jittering = animation_analyzer.detect_desync(player)
        
        -- Check if desync exceeds normal limits
        local is_extended = desync_amount > 58 and desync_amount <= CONSTANTS.EXTENDED_DESYNC_ANGLE
        
        if is_extended then
            logger:log_resolver(player, "Exploit Detection", string.format(
                "Extended desync detected (%.1f°)", desync_amount
            ), 2)
        end
        
        return is_extended, desync_amount
    end,
    
    detect_animation_desync = function(player)
        -- This would use animation layer data to detect desync
        -- Simplified implementation for now
        local anim_data = animation_analyzer.analyze_animation_layers(player)
        if not anim_data or not anim_data.simulated_layers then return false, 0 end
        
        -- Track eye position vs body position
        local eye_angles = {
            pitch = entity.get_prop(player, "m_angEyeAngles[0]") or 0,
            yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        }
        
        -- Get estimated desync based on animation layers
        local anim_desync_estimate = anim_data.simulated_layers.lean_amount * CONSTANTS.MAX_DESYNC_ANGLE
        
        -- Return detection result
        return anim_desync_estimate > 20, anim_desync_estimate
    end,
    
    sequence_tracking = function(player)
        local data = resolver_data[player]
        if not data or not data.sequence_data then return {} end
        
        -- Analyze animation sequence patterns
        local sequence_data = data.sequence_data
        local sequences = sequence_data.sequences or {}
        
        -- Find repeating patterns
        local patterns = {}
        
        if #sequences >= 6 then
            -- Look for basic patterns (2-step, 3-step)
            for pattern_size = 2, 3 do
                local pattern_count = {}
                
                for i = 1, #sequences - pattern_size + 1 do
                    local pattern = table.concat(sequences, ",", i, i + pattern_size - 1)
                    pattern_count[pattern] = (pattern_count[pattern] or 0) + 1
                end
                
                -- Find the most common pattern
                local best_pattern = nil
                local best_count = 0
                
                for pattern, count in pairs(pattern_count) do
                    if count > best_count then
                        best_pattern = pattern
                        best_count = count
                    end
                end
                
                -- Only consider it a pattern if it repeats enough
                if best_count >= 2 then
                    table.insert(patterns, {
                        pattern = best_pattern,
                        count = best_count,
                        size = pattern_size,
                        confidence = best_count / (#sequences - pattern_size + 1)
                    })
                end
            end
        end
        
        -- Update prediction for next likely animation state
        if #patterns > 0 then
            table.sort(patterns, function(a, b) return a.confidence > b.confidence end)
            local best_pattern = patterns[1]
            
            -- Store prediction in player data
            sequence_data.predicted_pattern = best_pattern
            sequence_data.prediction_confidence = best_pattern.confidence
            
            return {
                has_pattern = true,
                predicted_pattern = best_pattern.pattern,
                confidence = best_pattern.confidence,
                all_patterns = patterns
            }
        end
        
        return {
            has_pattern = false,
            confidence = 0
        }
    end,
    
    update_sequence_data = function(player)
        local data = resolver_data[player]
        if not data then return end
        
        -- Initialize sequence data if needed
        if not data.sequence_data then
            data.sequence_data = {
                sequences = {},
                last_update = globals.realtime(),
                predicted_pattern = nil,
                prediction_confidence = 0
            }
        end
        
        local sequence_data = data.sequence_data
        local current_time = globals.realtime()
        
        -- Only update at fixed intervals to avoid noise
        if current_time - sequence_data.last_update < CONSTANTS.ANIM_SAMPLE_RATE then
            return
        end
        
        -- Get current animation state (simplified)
        local anim_data = animation_analyzer.analyze_animation_layers(player)
        local move_state = "unknown"
        
        if anim_data.is_ducking then
            move_state = "duck"
        elseif not anim_data.is_on_ground then
            move_state = "air"
        elseif motion_analyzer.get_velocity_vector(player).magnitude > 5 then
            move_state = "move"
        else
            move_state = "stand"
        end
        
        -- Add to sequence history
        table.insert(sequence_data.sequences, move_state)
        
        -- Keep history size limited
        if #sequence_data.sequences > CONSTANTS.MAX_SEQUENCE_TRACKING then
            table.remove(sequence_data.sequences, 1)
        end
        
        -- Update timestamp
        sequence_data.last_update = current_time
        
        -- Analyze sequences for patterns
        animation_analyzer.sequence_tracking(player)
    end
}

--------------------------------------------------
-- NEURAL NETWORK IMPLEMENTATION
--------------------------------------------------

-- Neural network utilities
neural_network = {
    -- Activation functions
    activation = {
        sigmoid = function(x)
            return 1 / (1 + math.exp(-x))
        end,
        
        tanh = function(x)
            return math.tanh(x)
        end,
        
        relu = function(x)
            return math.max(0, x)
        end,
        
        leaky_relu = function(x)
            return x > 0 and x or 0.01 * x
        end
    },
    
    -- Weight initialization
    initialize_weights = function(in_size, out_size)
        local weights = {}
        local factor = math.sqrt(2 / (in_size + out_size))
        
        for i = 1, out_size do
            weights[i] = {}
            for j = 1, in_size do
                weights[i][j] = (math.random() * 2 - 1) * factor
            end
        end
        
        return weights
    end,
    
    -- Bias initialization
    initialize_bias = function(size)
        local bias = {}
        for i = 1, size do
            bias[i] = 0.01 * (math.random() * 2 - 1) -- Small initial bias
        end
        return bias
    end,
    
    -- Matrix operations
    matrix_multiply = function(weights, input)
        local result = {}
        
        for i = 1, #weights do
            result[i] = 0
            for j = 1, #input do
                result[i] = result[i] + weights[i][j] * input[j]
            end
        end
        
        return result
    end,
    
    add_vectors = function(v1, v2)
        local result = {}
        for i = 1, #v1 do
            result[i] = v1[i] + v2[i]
        end
        return result
    end,
    
    -- GRU (Gated Recurrent Unit) Network
    gru_network = {
        new = function(input_size, hidden_sizes, output_size)
            local layers = #hidden_sizes
            
            -- GRU model
            local model = {
                input_size = input_size,
                hidden_sizes = hidden_sizes,
                output_size = output_size,
                layers = layers,
                
                -- GRU specific gates for each layer
                update_gates = {}, -- Update gate weights
                reset_gates = {},  -- Reset gate weights
                hidden_gates = {}, -- Hidden state gate weights
                
                -- GRU gate biases
                update_biases = {},
                reset_biases = {},
                hidden_biases = {},
                
                -- Final output layer
                output_weights = {},
                output_bias = {},
                
                -- State
                hidden_states = {},
                
                -- Training params
                learning_rate = CONSTANTS.DEFAULT_LEARNING_RATE,
                momentum = 0.9,
                
                -- Statistics
                iterations = 0,
                error_history = {},
                
                step = function(self, input, target)
                    -- Forward pass
                    local outputs = self:forward(input)
                    local output = outputs[#outputs]
                    
                    -- Calculate error for logging
                    local error = 0
                    if target then
                        for i = 1, #output do
                            error = error + (output[i] - (target[i] or 0))^2
                        end
                        error = math.sqrt(error / #output)
                        table.insert(self.error_history, error)
                        if #self.error_history > 100 then
                            table.remove(self.error_history, 1)
                        end
                    end
                    
                    -- Update iteration count
                    self.iterations = self.iterations + 1
                    
                    return output, error
                end,
                
                forward = function(self, input)
                    -- Ensure input is the correct size
                    if #input ~= self.input_size then
                        return nil, "Input size mismatch"
                    end
                    
                    -- Initialize hidden states for first run if needed
                    if #self.hidden_states == 0 then
                        for i = 1, self.layers do
                            self.hidden_states[i] = {}
                            for j = 1, self.hidden_sizes[i] do
                                self.hidden_states[i][j] = 0
                            end
                        end
                    end
                    
                    -- Process through each GRU layer
                    local layer_input = input
                    local layer_outputs = {input} -- Store all layer outputs for visualization
                    
                    for layer = 1, self.layers do
                        local hidden_size = self.hidden_sizes[layer]
                        local prev_hidden = self.hidden_states[layer]
                        local new_hidden = {}
                        
                        -- Determine input to this layer
                        local combined_input
                        if layer == 1 then
                            combined_input = layer_input
                        else
                            -- The input to this layer is the previous layer's hidden state
                            combined_input = prev_hidden
                        end
                        
                        -- Update gate computation
                        local update_gate_input = neural_network.matrix_multiply(self.update_gates[layer], combined_input)
                        local update_gate = {}
                        for i = 1, hidden_size do
                            update_gate[i] = neural_network.activation.sigmoid(update_gate_input[i] + self.update_biases[layer][i])
                        end
                        
                        -- Reset gate computation
                        local reset_gate_input = neural_network.matrix_multiply(self.reset_gates[layer], combined_input)
                        local reset_gate = {}
                        for i = 1, hidden_size do
                            reset_gate[i] = neural_network.activation.sigmoid(reset_gate_input[i] + self.reset_biases[layer][i])
                        end
                        
                        -- Reset hidden state (element-wise multiplication with reset gate)
                        local reset_hidden = {}
                        for i = 1, hidden_size do
                            reset_hidden[i] = reset_gate[i] * prev_hidden[i]
                        end
                        
                        -- New hidden state candidate
                        local hidden_candidate_input = neural_network.matrix_multiply(self.hidden_gates[layer], reset_hidden)
                        local hidden_candidate = {}
                        for i = 1, hidden_size do
                            hidden_candidate[i] = neural_network.activation.tanh(hidden_candidate_input[i] + self.hidden_biases[layer][i])
                        end
                        
                        -- Compute final hidden state using update gate
                        for i = 1, hidden_size do
                            new_hidden[i] = (1 - update_gate[i]) * prev_hidden[i] + update_gate[i] * hidden_candidate[i]
                        end
                        
                        -- Save for next iteration
                        self.hidden_states[layer] = new_hidden
                        
                        -- Output of this layer becomes input to the next
                        layer_input = new_hidden
                        table.insert(layer_outputs, new_hidden)
                    end
                    
                    -- Final output layer
                    local final_output_input = neural_network.matrix_multiply(self.output_weights, self.hidden_states[self.layers])
                    local final_output = {}
                    for i = 1, self.output_size do
                        final_output[i] = neural_network.activation.sigmoid(final_output_input[i] + self.output_bias[i])
                    end
                    
                    table.insert(layer_outputs, final_output)
                    return layer_outputs
                end,
                
                reset_state = function(self)
                    -- Reset hidden states
                    self.hidden_states = {}
                    for i = 1, self.layers do
                        self.hidden_states[i] = {}
                        for j = 1, self.hidden_sizes[i] do
                            self.hidden_states[i][j] = 0
                        end
                    end
                end,

                train = function(self, input_sequence, target_sequence, epochs)
                    epochs = epochs or 1
                    assert(#input_sequence == #target_sequence, "Input and target sequences must have the same length")
                    
                    local total_error = 0
                    
                    for epoch = 1, epochs do
                        -- Reset state at the beginning of each epoch
                        self:reset_state()
                        
                        local epoch_error = 0
                        
                        for i = 1, #input_sequence do
                            local input = input_sequence[i]
                            local target = target_sequence[i]
                            
                            -- Forward pass and get error
                            local _, error = self:step(input, target)
                            epoch_error = epoch_error + error
                        end
                        
                        total_error = total_error + epoch_error / #input_sequence
                    end
                    
                    return total_error / epochs
                end
            }
            
            -- Initialize weights and biases for all layers
            local prev_size = input_size
            
            for i = 1, layers do
                local hidden_size = hidden_sizes[i]
                
                -- Initialize gate weights
                model.update_gates[i] = neural_network.initialize_weights(prev_size, hidden_size)
                model.reset_gates[i] = neural_network.initialize_weights(prev_size, hidden_size)
                model.hidden_gates[i] = neural_network.initialize_weights(hidden_size, hidden_size)
                
                -- Initialize gate biases
                model.update_biases[i] = neural_network.initialize_bias(hidden_size)
                model.reset_biases[i] = neural_network.initialize_bias(hidden_size)
                model.hidden_biases[i] = neural_network.initialize_bias(hidden_size)
                
                -- Next layer's input size is this layer's hidden size
                prev_size = hidden_size
            end
            
            -- Initialize output layer
            model.output_weights = neural_network.initialize_weights(hidden_sizes[layers], output_size)
            model.output_bias = neural_network.initialize_bias(output_size)
            
            return model
        end
    }
}

--------------------------------------------------
-- MACHINE LEARNING SYSTEM
--------------------------------------------------

ml_system = {
    -- Model management
    create_model = function(player)
        local input_size = CONSTANTS.FEATURE_VECTOR_SIZE
        local hidden_sizes = {}
        local layers = ui.get(ui_components.prediction.gru_layers)
        local units = ui.get(ui_components.prediction.units_per_layer)
        
        -- Create hidden layer configuration
        for i = 1, layers do
            table.insert(hidden_sizes, units)
        end
        
        -- Create new model
        local model = neural_network.gru_network.new(input_size, hidden_sizes, 2) -- Output: [desync_amount, direction]
        
        -- Store model reference
        ml_models[player] = model
        
        local player_name = entity.get_player_name(player) or "Unknown"
        logger:log(string.format("Created new ML model for %s: %d layers, %d units", 
            player_name, layers, units), 2)
        
        return model
    end,
    
    -- Extract features from player data
    extract_features = function(player)
        local data = resolver_data[player]
        if not data then return {} end
        
        -- Initialize feature vector
        local features = {}
        for i = 1, CONSTANTS.FEATURE_VECTOR_SIZE do
            features[i] = 0
        end
        
        -- Extract movement features
        local movement = motion_analyzer.analyze_movement_pattern(player)
        features[1] = movement.avg_velocity / 320 -- Normalized velocity
        features[2] = movement.direction_changes / 10 -- Direction changes
        features[3] = movement.is_strafing and 1 or 0 -- Is strafing?
        features[4] = movement.predictability -- Movement predictability
        
        -- Extract angle features
        if #data.angle_history > 0 then
            local latest_angle = data.angle_history[#data.angle_history].yaw
            features[5] = latest_angle / 180 -- Normalized yaw
            
            if #data.angle_history > 1 then
                local prev_angle = data.angle_history[#data.angle_history - 1].yaw
                features[6] = math_utils.normalize_angle(latest_angle - prev_angle) / 180 -- Normalized angle change
            end
        end
        
        -- Extract shot history features
        features[7] = data.hit_shots / (data.hit_shots + data.missed_shots + 1) -- Hit ratio
        features[8] = data.missed_shots / 10 -- Missed shots (capped at 10)
        
        -- Extract desync estimate
        local desync_amount, direction = animation_analyzer.detect_desync(player)
        features[9] = desync_amount / CONSTANTS.MAX_DESYNC_ANGLE -- Normalized desync amount
        features[10] = direction -- Desync direction
        
        -- Extract animation features if available
        local anim_data = animation_analyzer.analyze_animation_layers(player)
        if anim_data and anim_data.simulated_layers then
            features[11] = anim_data.simulated_layers.lean_amount or 0
            features[12] = anim_data.is_ducking and 1 or 0
        end
        
        -- Extract previous resolver success/failure
        if data.last_confidence then
            features[13] = data.last_confidence -- Last resolution confidence
        end
        
        if data.resolution_success_rate then
            features[14] = data.resolution_success_rate -- Resolution success rate
        end
        
        -- Add time-based features
        features[15] = math.sin(globals.realtime() * 0.1) -- Time oscillation feature
        features[16] = math.cos(globals.realtime() * 0.1)
        
        return features
    end,
    
    -- Train model with new data
    train_model = function(player, target_desync, target_direction, hit_success)
        local model = ml_models[player]
        if not model then
            model = ml_system.create_model(player)
        end
        
        -- Extract features
        local features = ml_system.extract_features(player)
        
        -- Create target output (normalized desync amount and direction)
        local target = {
            target_desync / CONSTANTS.MAX_DESYNC_ANGLE,
            target_direction > 0 and 1 or 0
        }
        
        -- Adjust learning rate based on hit success
        local original_rate = model.learning_rate
        if hit_success then
            model.learning_rate = original_rate * 1.2 -- Boost learning from successful hits
        else
            model.learning_rate = original_rate * 0.8 -- Reduce learning from misses
        end
        
        -- Train for a single step
        local _, error = model:step(features, target)
        
        -- Reset learning rate
        model.learning_rate = original_rate
        
        local player_name = entity.get_player_name(player) or "Unknown"
        logger:log(string.format("Trained model for %s: Error %.4f, Target: %.1f° %s", 
            player_name, error, target_desync, target_direction > 0 and "Right" or "Left"), 2)
        
        return error
    end,
    
    -- Predict desync using the model
    predict_desync = function(player)
        local model = ml_models[player]
        if not model then
            model = ml_system.create_model(player)
            return 35, 1, 0.5 -- Default values with medium confidence
        end
        
        -- Extract features
        local features = ml_system.extract_features(player)
        
        -- Get prediction
        local layer_outputs = model:forward(features)
        local output = layer_outputs[#layer_outputs]
        
        -- Convert output to desync amount and direction
        local desync_amount = output[1] * CONSTANTS.MAX_DESYNC_ANGLE
        local direction = output[2] > 0.5 and 1 or -1
        
        -- Calculate confidence based on model error history
        local confidence = 0.5
        if #model.error_history > 0 then
            local avg_error = 0
            for _, err in ipairs(model.error_history) do
                avg_error = avg_error + err
            end
            avg_error = avg_error / #model.error_history
            
            -- Higher error = lower confidence, with minimum of 0.2
            confidence = math.max(0.2, 1 - (avg_error * 2))
        end
        
        -- Adjust confidence based on iteration count (more iterations = more confidence)
        local iteration_factor = math.min(1, model.iterations / 100)
        confidence = confidence * (0.7 + 0.3 * iteration_factor)
        
        return desync_amount, direction, confidence
    end
}

--------------------------------------------------
-- NETWORK ANALYSIS SYSTEM
--------------------------------------------------

network_analyzer = {
    detect_network_conditions = function(player)
        local ping = entity.get_prop(player, "m_iPing") or 0
        
        -- Get network data if available
        local data = resolver_data[player]
        if not data or not data.network_data then
            return {
                ping = ping,
                is_lagging = ping > 100,
                is_choking = false,
                has_loss = false,
                usable_backtrack = 12 -- Default max backtrack
            }
        end
        
        -- Calculate time between updates
        local avg_update_time = 0
        if #data.network_data.update_times > 1 then
            local sum = 0
            for i = 2, #data.network_data.update_times do
                sum = sum + (data.network_data.update_times[i] - data.network_data.update_times[i-1])
            end
            avg_update_time = sum / (#data.network_data.update_times - 1)
        end
        
        -- Detect packet choking
        local is_choking = avg_update_time > 0.1
        
        -- Detect packet loss based on position jumps
        local has_loss = false
        if #data.position_history > 2 then
            local jumps = 0
            for i = 2, #data.position_history do
                local dist = math_utils.get_distance(data.position_history[i], data.position_history[i-1])
                if dist > 100 then -- Large position jump
                    jumps = jumps + 1
                end
            end
            has_loss = jumps > 0
        end
        
        -- Calculate usable backtrack based on network conditions
        local usable_backtrack = CONSTANTS.MAX_BACKTRACK_TICKS
        
        -- Reduce backtrack for high ping players
        if ping > 80 then
            usable_backtrack = usable_backtrack * (1 - (ping - 80) / 120)
        end
        
        -- Reduce backtrack for players with packet loss
        if has_loss then
            usable_backtrack = usable_backtrack * 0.7
        end
        
        -- Ensure minimum value
        usable_backtrack = math.max(2, math.floor(usable_backtrack))
        
        return {
            ping = ping,
            is_lagging = ping > 100 or is_choking,
            is_choking = is_choking,
            has_loss = has_loss,
            avg_update_time = avg_update_time,
            usable_backtrack = usable_backtrack
        }
    end,
    
    select_optimal_backtrack = function(player)
        local data = resolver_data[player]
        if not data or #data.backtrack_records < 2 then return 0 end
        
        -- Get network conditions
        local network = network_analyzer.detect_network_conditions(player)
        local max_backtrack = network.usable_backtrack
        
        -- If we're using "Smart Selection", analyze records to find optimal point
        local options = ui.get(ui_components.network.backtrack_options)
        
        if has_option(options, "Smart Selection") then
            local best_record = 0
            local best_score = 0
            
            for i = 1, math.min(max_backtrack, #data.backtrack_records) do
                local record = data.backtrack_records[i]
                local score = 0
                
                -- Give higher score to records with more stable velocity
                if record.velocity and record.velocity.magnitude < 100 then
                    score = score + 0.2
                end
                
                -- Give higher score to records with less extreme angles
                if record.angle then
                    local angle_extremity = math.abs(math_utils.normalize_angle(record.angle.yaw)) / 180
                    score = score + (1 - angle_extremity) * 0.3
                end
                
                -- Give higher score to records that match previous successful hits
                if #data.resolved_angles > 0 then
                    for _, resolve_data in ipairs(data.resolved_angles) do
                        if resolve_data.hit and record.angle then
                            local angle_similarity = 1 - math.abs(math_utils.normalize_angle(
                                record.angle.yaw - resolve_data.angle
                            )) / 180
                            score = score + angle_similarity * 0.5
                        end
                    end
                end
                
                -- Update best record if found
                if score > best_score then
                    best_score = score
                    best_record = i
                end
            end
            
            return best_record
        end
        
        -- Otherwise use the default backtrack strategy (newest valid record)
        return math.min(max_backtrack, #data.backtrack_records)
    end,
    
    process_backtrack_records = function(player)
        local data = resolver_data[player]
        if not data then return end
        
        -- Create a new backtrack record
        local record = {
            time = globals.realtime(),
            tick = globals.tickcount(),
            position = {entity.get_origin(player)},
            angle = {
                pitch = entity.get_prop(player, "m_angEyeAngles[0]") or 0,
                yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
            },
            velocity = motion_analyzer.get_velocity_vector(player),
            flags = entity.get_prop(player, "m_fFlags") or 0,
            is_valid = true
        }
        
        -- Add to records
        table.insert(data.backtrack_records, 1, record)
        
        -- Remove old records
        if #data.backtrack_records > CONSTANTS.MAX_BACKTRACK_TICKS * 2 then
            table.remove(data.backtrack_records)
        end
        
        -- Validate records (mark records as invalid if they're too old)
        local current_tick = globals.tickcount()
        for i, rec in ipairs(data.backtrack_records) do
            if current_tick - rec.tick > CONSTANTS.MAX_BACKTRACK_TICKS then
                rec.is_valid = false
            end
        end
    end
}

--------------------------------------------------
-- EXPLOIT DETECTION SYSTEM
--------------------------------------------------

exploit_detector = {
    detect_fakelag = function(player)
        local data = resolver_data[player]
        if not data or not data.network_data then return false, 0 end
        
        -- Need at least a few updates to detect fakelag
        if #data.network_data.update_times < 3 then return false, 0 end
        
        -- Calculate time between updates
        local update_gaps = {}
        for i = 2, #data.network_data.update_times do
            table.insert(update_gaps, data.network_data.update_times[i] - data.network_data.update_times[i-1])
        end
        
        -- Check for characteristic fakelag pattern (large gaps followed by small ones)
        local large_gaps = 0
        local max_gap = 0
        
        for _, gap in ipairs(update_gaps) do
            if gap > 0.1 then -- Significant gap
                large_gaps = large_gaps + 1
                max_gap = math.max(max_gap, gap)
            end
        end
        
        -- Calculate fakelag amount (rough estimation)
        local fakelag_amount = 0
        if max_gap > 0 then
            fakelag_amount = math.floor(max_gap / CONSTANTS.TICK_INTERVAL)
        end
        
        -- Detect fakelag if we have significant gaps
        local is_fakelagging = large_gaps > 0 and fakelag_amount >= 2
        
        return is_fakelagging, fakelag_amount
    end,
    
    detect_extended_desync = function(player)
        local desync_amount, _, _ = animation_analyzer.detect_desync(player)
        
        -- Detect abnormally large desync angles that exceed the normal maximum
        return desync_amount > CONSTANTS.MAX_DESYNC_ANGLE, desync_amount
    end,
    
    detect_defensive_aa = function(player)
        local data = resolver_data[player]
        if not data or #data.angle_snapshots < 3 then return false, 0 end
        
        -- Check for rapid angle changes characteristic of defensive AA
        local defensive_triggers = 0
        local total_checks = math.min(6, #data.angle_snapshots - 1)
        
        for i = 1, total_checks do
            local curr = data.angle_snapshots[i]
            local next = data.angle_snapshots[i + 1]
            
            -- Check for rapid change in angle (defensive trigger)
            if next and curr and math.abs(math_utils.normalize_angle(next.yaw - curr.yaw)) > CONSTANTS.DEFENSIVE_AA_THRESHOLD then
                defensive_triggers = defensive_triggers + 1
            end
        end
        
        -- Calculate confidence based on number of triggers detected
        local is_defensive = defensive_triggers > total_checks * 0.3
        local confidence = defensive_triggers / total_checks
        
        return is_defensive, confidence
    end,
    
    detect_double_tap = function(player)
        local data = resolver_data[player]
        if not data or not data.shot_history or #data.shot_history < 2 then return false, 0 end
        
        -- Look for shots fired in very quick succession
        local rapid_shots = 0
        
        for i = 2, #data.shot_history do
            local time_diff = data.shot_history[i].time - data.shot_history[i-1].time
            if time_diff < 0.05 then -- Very small time between shots
                rapid_shots = rapid_shots + 1
            end
        end
        
        local is_double_tapping = rapid_shots > 0
        local confidence = rapid_shots / (#data.shot_history - 1)
        
        return is_double_tapping, confidence
    end,
    
    detect_exploits = function(player)
        local results = {
            fakelag = {detected = false, value = 0},
            extended_desync = {detected = false, value = 0},
            defensive_aa = {detected = false, value = 0},
            double_tap = {detected = false, value = 0}
        }
        
        -- Only run detection if exploits module is enabled
        if not ui.get(ui_components.exploits.enable) then
            return results
        end
        
        -- Get selected exploit detection options
        local options = ui.get(ui_components.exploits.detect_exploits)
        
        -- Run detection for each selected exploit
        if has_option(options, "Fake Lag") then
            results.fakelag.detected, results.fakelag.value = exploit_detector.detect_fakelag(player)
        end
        
        if has_option(options, "Extended Desync") then
            results.extended_desync.detected, results.extended_desync.value = exploit_detector.detect_extended_desync(player)
        end
        
        if has_option(options, "Defensive AA") then
            results.defensive_aa.detected, results.defensive_aa.value = exploit_detector.detect_defensive_aa(player)
        end
        
        if has_option(options, "Double Tap") then
            results.double_tap.detected, results.double_tap.value = exploit_detector.detect_double_tap(player)
        end
        
        -- Duck exploits and teleport would be implemented similarly
        
        return results
    end,
    
    apply_countermeasures = function(player, exploits)
        local data = resolver_data[player]
        if not data then return end
        
        local countermeasures = ui.get(ui_components.exploits.countermeasures)
        local applied_measures = {}
        
        -- Auto Adapt - Adjust resolver strategy based on detected exploits
        if has_option(countermeasures, "Auto Adapt") and (
           exploits.fakelag.detected or 
           exploits.extended_desync.detected or 
           exploits.defensive_aa.detected or 
           exploits.double_tap.detected) then
            
            -- Record that we applied an adaptation
            table.insert(applied_measures, "Auto Adapt")
            
            -- Adjust confidence based on exploit detection
            if exploits.defensive_aa.detected then
                 -- Initialize confidence if it doesn't exist
        if not data.confidence then
            data.confidence = 0.5 -- Default confidence value
        end
        data.confidence = data.confidence * 0.7 -- Reduce confidence for defensive AA
    end
            
            if exploits.extended_desync.detected then
                -- Apply extended desync correction
                data.exploit_correction = exploits.extended_desync.value - CONSTANTS.MAX_DESYNC_ANGLE
            end
        end
        
        -- Force Backtrack - Prioritize backtracking for exploit users
        if has_option(countermeasures, "Force Backtrack") and (
           exploits.fakelag.detected or 
           exploits.defensive_aa.detected) then
            
            data.force_backtrack = true
            table.insert(applied_measures, "Force Backtrack")
        end
        
        -- Safe Point - Force safe points when shooting at exploit users
        if has_option(countermeasures, "Safe Point") and (
           exploits.fakelag.detected or 
           exploits.extended_desync.detected or 
           exploits.defensive_aa.detected) then
            
            data.force_safepoint = true
            table.insert(applied_measures, "Safe Point")
        end
        
        -- Shot Delay - Add slight delay before shooting at exploit users
        if has_option(countermeasures, "Shot Delay") and exploits.defensive_aa.detected then
            data.shot_delay = 0.05 -- 50ms delay
            table.insert(applied_measures, "Shot Delay")
        end
        
        return applied_measures
    end
}

--------------------------------------------------
-- PATTERN RECOGNITION SYSTEM
--------------------------------------------------

local pattern_recognizer = {
    analyze_patterns = function(player)
        local data = resolver_data[player]
        if not data or #data.angle_history < 5 then 
            return {
                type = "unknown",
                value = 0,
                confidence = 0.1
            }
        end
        
        local angle_diffs = {}
        local directions = {}
        local magnitudes = {}
        
        -- Calculate angle differences between consecutive updates
        for i = 2, #data.angle_history do
            local curr = data.angle_history[i].yaw
            local prev = data.angle_history[i-1].yaw
            local diff = math_utils.normalize_angle(curr - prev)
            
            table.insert(angle_diffs, diff)
            table.insert(directions, diff > 0 and 1 or (diff < 0 and -1 or 0))
            table.insert(magnitudes, math.abs(diff))
        end
        
        -- Calculate statistics
        local avg_magnitude = 0
        local max_magnitude = 0
        local direction_changes = 0
        
        for i, mag in ipairs(magnitudes) do
            avg_magnitude = avg_magnitude + mag
            max_magnitude = math.max(max_magnitude, mag)
            
            if i > 1 and directions[i] ~= 0 and directions[i-1] ~= 0 and directions[i] ~= directions[i-1] then
                direction_changes = direction_changes + 1
            end
        end
        
        if #magnitudes > 0 then
            avg_magnitude = avg_magnitude / #magnitudes
        end
        
        -- Calculate distribution of directions
        local dir_count = {[0] = 0, [1] = 0, [-1] = 0}
        for _, dir in ipairs(directions) do
            dir_count[dir] = dir_count[dir] + 1
        end
        
        -- Calculate direction bias
        local dir_total = dir_count[1] + dir_count[-1]
        local dir_bias = 0
        if dir_total > 0 then
            dir_bias = (dir_count[1] - dir_count[-1]) / dir_total
        end
        
        -- Detect static angle
        if max_magnitude <= CONSTANTS.STATIC_THRESHOLD then
            return {
                type = "static",
                value = 0,
                confidence = 0.9,
                direction = 0,
                amplitude = 0
            }
        end
        
        -- Detect jitter pattern
        if direction_changes >= #directions * 0.4 then
            local jitter_amplitude = avg_magnitude
            
            if jitter_amplitude > CONSTANTS.JITTER_THRESHOLD then
                return {
                    type = "wide_jitter",
                    value = jitter_amplitude,
                    confidence = 0.85,
                    direction = dir_bias > 0 and 1 or -1,
                    amplitude = jitter_amplitude
                }
            else
                return {
                    type = "narrow_jitter",
                    value = jitter_amplitude,
                    confidence = 0.75,
                    direction = dir_bias > 0 and 1 or -1,
                    amplitude = jitter_amplitude
                }
            end
        end
        
        -- Detect directional switch pattern
        local consecutive_same_dir = 0
        local max_consecutive = 0
        local switch_pattern = false
        
        for i = 2, #directions do
            if directions[i] == directions[i-1] and directions[i] ~= 0 then
                consecutive_same_dir = consecutive_same_dir + 1
            else
                max_consecutive = math.max(max_consecutive, consecutive_same_dir)
                consecutive_same_dir = 0
                
                if directions[i] ~= 0 and directions[i-1] ~= 0 and directions[i] ~= directions[i-1] then
                    switch_pattern = true
                end
            end
        end
        max_consecutive = math.max(max_consecutive, consecutive_same_dir)
        
        if switch_pattern and max_consecutive >= CONSTANTS.SWITCH_DETECTION_THRESHOLD then
            return {
                type = "switching",
                value = max_magnitude,
                confidence = 0.8,
                direction = dir_bias > 0 and 1 or -1,
                amplitude = avg_magnitude,
                switch_interval = max_consecutive
            }
        end
        
        -- Detect smooth movement
        if avg_magnitude < 10 and max_magnitude < 20 and direction_changes <= 1 then
            return {
                type = "smooth",
                value = avg_magnitude,
                confidence = 0.7,
                direction = dir_bias > 0 and 1 or -1,
                amplitude = avg_magnitude
            }
        end
        
        -- Detect random pattern
        local std_dev = math_utils.calculate_standard_deviation(magnitudes)
        if std_dev > 15 and direction_changes > 1 then
            return {
                type = "random",
                value = max_magnitude / 2,
                confidence = 0.5,
                direction = 0,
                amplitude = avg_magnitude
            }
        end
        
        -- Default to complex pattern
        return {
            type = "complex",
            value = max_magnitude / 2,
            confidence = 0.4,
            direction = dir_bias > 0 and 1 or -1,
            amplitude = avg_magnitude
        }
    end,
    
    predict_next_angle = function(player)
        local data = resolver_data[player]
        if not data or #data.angle_history < 3 then 
            return data.angle_history and data.angle_history[#data.angle_history] and data.angle_history[#data.angle_history].yaw or 0, 0.1
        end
        
        -- Get pattern analysis
        local pattern = pattern_recognizer.analyze_patterns(player)
        
        -- Get last recorded angle
        local last_angle = data.angle_history[#data.angle_history].yaw
        
        -- Prediction based on pattern type
        if pattern.type == "static" then
            -- No movement expected
            return last_angle, 0.9
        elseif pattern.type == "wide_jitter" or pattern.type == "narrow_jitter" then
            -- Predict opposite direction for jitter
            local last_direction = 0
            if #data.angle_history >= 2 then
                local prev_angle = data.angle_history[#data.angle_history-1].yaw
                last_direction = (last_angle - prev_angle) > 0 and 1 or -1
            end
            
            -- Predict the next jitter angle
            local predicted_angle = last_angle + (last_direction * -1 * pattern.amplitude)
            return math_utils.normalize_angle(predicted_angle), 0.7
        elseif pattern.type == "switching" then
            -- Check if we're due for a switch
            local consecutive_count = 0
            local current_direction = 0
            
            for i = #data.angle_history, 2, -1 do
                local curr = data.angle_history[i].yaw
                local prev = data.angle_history[i-1].yaw
                local diff = math_utils.normalize_angle(curr - prev)
                local dir = diff > 0 and 1 or (diff < 0 and -1 or 0)
                
                if current_direction == 0 then
                    current_direction = dir
                    consecutive_count = 1
                elseif dir == current_direction then
                    consecutive_count = consecutive_count + 1
                else
                    break
                end
            end
            
            -- If we've reached the switch interval, predict a direction change
            if consecutive_count >= pattern.switch_interval then
                local predicted_angle = last_angle + (current_direction * -1 * pattern.amplitude)
                return math_utils.normalize_angle(predicted_angle), 0.75
            else
                -- Continue in the same direction
                local predicted_angle = last_angle + (current_direction * pattern.amplitude)
                return math_utils.normalize_angle(predicted_angle), 0.6
            end
        elseif pattern.type == "smooth" then
            -- Predict continued smooth movement
            if #data.angle_history >= 3 then
                local a1 = data.angle_history[#data.angle_history-2].yaw
                local a2 = data.angle_history[#data.angle_history-1].yaw
                local a3 = data.angle_history[#data.angle_history].yaw
                
                -- Calculate rate of change
                local d1 = math_utils.normalize_angle(a2 - a1)
                local d2 = math_utils.normalize_angle(a3 - a2)
                
                -- Predict with acceleration
                local d3 = d2 + (d2 - d1) * 0.5
                local predicted_angle = a3 + d3
                
                return math_utils.normalize_angle(predicted_angle), 0.65
            else
                return last_angle, 0.5
            end
        else
            -- For complex/random patterns, use a simple prediction
            if #data.angle_history >= 2 then
                local prev_angle = data.angle_history[#data.angle_history-1].yaw
                local diff = math_utils.normalize_angle(last_angle - prev_angle)
                
                -- Reduced confidence for complex patterns
                return math_utils.normalize_angle(last_angle + diff * 0.7), 0.4
            else
                return last_angle, 0.3
            end
        end
    end,
    
    get_pattern_description = function(pattern)
        local descriptions = {
            static = "Static",
            wide_jitter = "Wide Jitter",
            narrow_jitter = "Narrow Jitter",
            switching = "Switching",
            smooth = "Smooth",
            random = "Random",
            complex = "Complex"
        }
        
        return descriptions[pattern.type] or "Unknown"
    end
}

--------------------------------------------------
-- PLAYER DATA MANAGEMENT
--------------------------------------------------

player_manager = {
    init_player_data = function(player)
        if resolver_data[player] then return resolver_data[player] end
        
        -- Create new player data
        resolver_data[player] = {
            -- Tracking histories
            angle_history = {},         -- History of eye angles
            velocity_history = {},      -- History of velocity vectors
            position_history = {},      -- History of positions
            shot_history = {},          -- History of shots
            hit_history = {},           -- History of hits
            miss_history = {},          -- History of misses
            resolved_angles = {},       -- History of resolver angles applied
            angle_snapshots = {},       -- Rapid snapshots for defensive AA detection
            backtrack_records = {},     -- Backtrack records
            
            -- Statistics
            hit_shots = 0,              -- Total hits
            missed_shots = 0,           -- Total misses
            round_shots = 0,            -- Shots this round
            round_hits = 0,             -- Hits this round
            consecutive_misses = 0,     -- Consecutive misses
            last_hit_time = 0,          -- Time of last hit
            last_miss_time = 0,         -- Time of last miss
            
            -- Resolution data
            last_resolve_angle = 0,     -- Last applied resolver angle
            last_confidence = 0.5,      -- Last confidence value
            resolution_success_rate = 0.5, -- Success rate of resolution
            last_desync_amount = 0,     -- Last detected desync amount
            
            -- Pattern analysis
            pattern_type = "unknown",    -- Current pattern type
            pattern_value = 0,           -- Current pattern value
            
            -- Network data
            network_data = {
                update_times = {},      -- Times of entity updates
                ping_history = {},      -- History of ping values
                choke_detected = false, -- Packet choke detection
                loss_detected = false,  -- Packet loss detection
                last_update_time = 0    -- Last update time
            },
            
            -- ML prediction data
            prediction_history = {},    -- History of predictions
            ml_features_history = {},   -- History of feature vectors
            
            -- Exploit detection
            exploits_detected = {},     -- Currently detected exploits
            countermeasures_applied = {}, -- Applied countermeasures
            
            -- User customization
            custom_resolver_bias = 0,   -- User-defined bias
            
            -- Status flags
            is_active = true,          -- Is this player active?
            is_dormant = false,        -- Is this player dormant?
            was_reset = false,         -- Was data recently reset?
            
            -- Timing
            init_time = globals.realtime(),
            last_update_time = globals.realtime()
        }
        
        -- Track number of players
        session_stats.players_tracked = session_stats.players_tracked + 1
        
        -- Log initialization
        local player_name = entity.get_player_name(player) or "Unknown"
        logger:log(string.format("Initialized player data for %s", player_name), 1)
        
        return resolver_data[player]
    end,
    
    update_player_data = function(player)
        -- Initialize if needed
        local data = player_manager.init_player_data(player)
        
        -- Check if player is dormant
        data.is_dormant = entity.is_dormant(player)
        if data.is_dormant then return end
        
        -- Update timing
        local current_time = globals.realtime()
        local time_diff = current_time - data.last_update_time
        data.last_update_time = current_time
        
        -- Record update time for network analysis
        table.insert(data.network_data.update_times, current_time)
        if #data.network_data.update_times > CONSTANTS.NETWORK_HISTORY_SIZE then
            table.remove(data.network_data.update_times, 1)
        end
        
        -- Get current angles
        local pitch = entity.get_prop(player, "m_angEyeAngles[0]") or 0
        local yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        
        -- Get current position
        local pos_x, pos_y, pos_z = entity.get_origin(player)
        if not pos_x or not pos_y or not pos_z then
            return -- Skip update if position is invalid
        end
        
        local position = {x = pos_x, y = pos_y, z = pos_z}
        
        -- Get velocity
        local velocity = motion_analyzer.get_velocity_vector(player)
        
        -- Update angle history with strict size limiting
        table.insert(data.angle_history, {
            pitch = pitch,
            yaw = yaw,
            time = current_time,
            tick = globals.tickcount()
        })
        
        -- Strictly enforce history size limits
        while #data.angle_history > CONSTANTS.MAX_ANGLE_HISTORY do
            table.remove(data.angle_history, 1)
        end
        
        -- Update position history with strict size limiting
        table.insert(data.position_history, position)
        while #data.position_history > CONSTANTS.MAX_HISTORY_SIZE do
            table.remove(data.position_history, 1)
        end
        
        -- Update velocity history with strict size limiting
        table.insert(data.velocity_history, velocity)
        while #data.velocity_history > CONSTANTS.MAX_HISTORY_SIZE do
            table.remove(data.velocity_history, 1)
        end
        
        -- Add rapid angle snapshot for defensive AA detection
        table.insert(data.angle_snapshots, {
            yaw = yaw,
            time = current_time,
            tick = globals.tickcount()
        })
        
        -- Strictly limit angle snapshots
        while #data.angle_snapshots > CONSTANTS.MAX_HISTORY_SIZE do
            table.remove(data.angle_snapshots, 1)
        end
        
        -- Process backtrack records
        network_analyzer.process_backtrack_records(player)
        
        -- Analyze network conditions
        local network = network_analyzer.detect_network_conditions(player)
        data.network_data.choke_detected = network.is_choking
        data.network_data.loss_detected = network.has_loss
        
        -- Update ping history with strict size limiting
        table.insert(data.network_data.ping_history, network.ping)
        while #data.network_data.ping_history > CONSTANTS.NETWORK_HISTORY_SIZE do
            table.remove(data.network_data.ping_history, 1)
        end
        
        -- Analyze pattern
        local pattern = pattern_recognizer.analyze_patterns(player)
        data.pattern_type = pattern.type
        data.pattern_value = pattern.value
        
        -- Detect exploits if module enabled
        if ui.get(ui_components.exploits.enable) then
            data.exploits_detected = exploit_detector.detect_exploits(player)
            data.countermeasures_applied = exploit_detector.apply_countermeasures(player, data.exploits_detected)
        end
        
        -- Ensure all other history collections are limited as well
        if data.resolved_angles and #data.resolved_angles > CONSTANTS.MAX_HISTORY_SIZE then
            table.remove(data.resolved_angles, 1)
        end
        
        if data.shot_history and #data.shot_history > CONSTANTS.MAX_SHOT_HISTORY then
            table.remove(data.shot_history, 1)
        end
        
        if data.hit_history and #data.hit_history > CONSTANTS.MAX_SHOT_HISTORY then
            table.remove(data.hit_history, 1)
        end
        
        if data.miss_history and #data.miss_history > CONSTANTS.MAX_SHOT_HISTORY then
            table.remove(data.miss_history, 1)
        end
        
        if data.prediction_history and #data.prediction_history > CONSTANTS.MAX_HISTORY_SIZE then
            table.remove(data.prediction_history, 1)
        end
    end,
    
    reset_player_data = function(player, preserve_stats)
        local data = resolver_data[player]
        if not data then return end
        
        local player_name = entity.get_player_name(player) or "Unknown"
        
        -- Store important stats for preservation if requested
        local preserved = {}
        if preserve_stats then
            preserved = {
                hit_shots = data.hit_shots,
                missed_shots = data.missed_shots,
                resolution_success_rate = data.resolution_success_rate,
                pattern_type = data.pattern_type
            }
        end
        
        -- Reset all data
        data.angle_history = {}
        data.velocity_history = {}
        data.position_history = {}
        data.shot_history = {}
        data.hit_history = {}
        data.miss_history = {}
        data.resolved_angles = {}
        data.angle_snapshots = {}
        data.backtrack_records = {}
        data.prediction_history = {}
        data.ml_features_history = {}
        data.exploits_detected = {}
        data.countermeasures_applied = {}
        
        -- Reset network data
        data.network_data = {
            update_times = {},
            ping_history = {},
            choke_detected = false,
            loss_detected = false,
            last_update_time = 0
        }
        
        -- Reset flags
        data.consecutive_misses = 0
        data.is_dormant = entity.is_dormant(player)
        data.last_resolve_angle = 0
        data.last_confidence = 0.5
        data.was_reset = true
        
        -- Restore preserved stats if requested
        if preserve_stats then
            data.hit_shots = preserved.hit_shots
            data.missed_shots = preserved.missed_shots
            data.resolution_success_rate = preserved.resolution_success_rate
            data.pattern_type = preserved.pattern_type
        else
            -- Reset all stats
            data.hit_shots = 0
            data.missed_shots = 0
            data.round_shots = 0
            data.round_hits = 0
            data.resolution_success_rate = 0.5
            data.pattern_type = "unknown"
            data.pattern_value = 0
        end
        
        -- Reset timing
        data.init_time = globals.realtime()
        data.last_update_time = globals.realtime()
        
        -- Reset ML model
        if ml_models[player] then
            if preserve_stats then
                -- Just reset state but keep the trained weights
                ml_models[player]:reset_state()
            else
                -- Create a new model from scratch
                ml_system.create_model(player)
            end
        end
        
        logger:log(string.format("Reset player data for %s (preserve_stats: %s)", 
            player_name, preserve_stats and "true" or "false"), 1)
    end,
    
    clean_inactive_players = function()
        local cleaned_count = 0
        local preserved_count = 0
        
        for player, data in pairs(resolver_data) do
            -- Check if player is still valid
            local is_valid = entity.is_enemy(player) and entity.is_alive(player)
            
            -- Determine if data is valuable enough to keep
            local valuable_data = 
                (data.hit_shots > 3 or data.missed_shots > 5) and
                globals.realtime() - data.init_time > 10 -- At least 10 seconds of data
                
            if not is_valid then
                if valuable_data then
                    -- Keep data but mark as inactive
                    data.is_active = false
                    preserved_count = preserved_count + 1
                else
                    -- Clean up this player's data
                    resolver_data[player] = nil
                    ml_models[player] = nil
                    cleaned_count = cleaned_count + 1
                end
            end
        end
        
        if cleaned_count > 0 or preserved_count > 0 then
            logger:log(string.format("Cleaned up %d inactive players, preserved %d players with valuable data", 
                cleaned_count, preserved_count), 1)
        end
        
        return cleaned_count, preserved_count
    end
}


--------------------------------------------------
-- CORE RESOLVER SYSTEM
--------------------------------------------------

resolver = {
    get_resolver_mode = function()
        return ui.get(ui_components.main.mode)
    end,
    
    get_base_confidence = function()
        return ui.get(ui_components.main.base_confidence) / 100
    end,
    
    
    
    resolve_player = function(player)
        -- Check if resolver is enabled
        if not ui.get(ui_components.main.enable) or not ui.get(ui_components.main.master_switch) then
            return nil, 0
        end
        
        -- Update player data
        player_manager.update_player_data(player)
        local data = resolver_data[player]
        
        if not data or data.is_dormant then return nil, 0 end
        
        -- Get current player state
        local pitch = entity.get_prop(player, "m_angEyeAngles[0]") or 0
        local yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        local velocity = motion_analyzer.get_velocity_vector(player)
        
        -- Get resolver settings
        local mode = resolver.get_resolver_mode()
        local base_confidence = resolver.get_base_confidence()
        
        -- Base resolver values
        local resolved_angle = 0
        local confidence = base_confidence
        
        -- Apply the selected resolver strategy
        if mode == "Hybrid AI/ML" then
            -- Use ML prediction if enabled
            if ui.get(ui_components.prediction.enable) then
                local desync_amount, direction, ml_confidence = ml_system.predict_desync(player)
                resolved_angle = direction * desync_amount
                confidence = ml_confidence * base_confidence
            else
                -- Fallback to pattern recognition
                local pattern = pattern_recognizer.analyze_patterns(player)
                resolved_angle = pattern.direction * pattern.value
                confidence = pattern.confidence * base_confidence
            end
            
        elseif mode == "Maximum Accuracy" then
            -- Use combination of all available methods for maximum accuracy
            local ml_angle, ml_direction, ml_confidence = 0, 0, 0
            local pattern_angle, pattern_confidence = 0, 0
            local animation_angle, animation_confidence = 0, 0
            
            -- Get ML prediction if enabled
            if ui.get(ui_components.prediction.enable) then
                local desync_amount, direction, conf = ml_system.predict_desync(player)
                ml_angle = direction * desync_amount
                ml_direction = direction
                ml_confidence = conf
            end
            
            -- Get pattern analysis
            local pattern = pattern_recognizer.analyze_patterns(player)
            -- Add nil check for pattern.direction
            resolved_angle = (pattern.direction or 0) * pattern.value
            pattern_confidence = pattern.confidence
            
            -- Get animation analysis if enabled
            if ui.get(ui_components.animation.enable) then
                local desync_amount, direction = animation_analyzer.detect_desync(player)
                animation_angle = direction * desync_amount
                animation_confidence = 0.7 -- Base confidence for animation
            end
            
            -- Weight the different methods
            local weights = {}
            local angles = {}
            
            if ml_confidence > 0 then
                table.insert(weights, ml_confidence * 2.0) -- ML has highest weight
                table.insert(angles, ml_angle)
            end
            
            if pattern_confidence > 0 then
                table.insert(weights, pattern_confidence * 1.5)
                table.insert(angles, pattern_angle)
            end
            
            if animation_confidence > 0 then
                table.insert(weights, animation_confidence * 1.2)
                table.insert(angles, animation_angle)
            end
            
            -- Calculate weighted average
            if #angles > 0 then
                resolved_angle = math_utils.weighted_average(angles, weights)
                
                -- Calculate overall confidence as average of individual confidences
                local total_weight = 0
                for _, weight in ipairs(weights) do
                    total_weight = total_weight + weight
                end
                confidence = (total_weight / #weights) * base_confidence
            else
                -- Fallback to default values
                resolved_angle = 35 * (data.missed_shots % 2 == 0 and 1 or -1)
                confidence = 0.4 * base_confidence
            end
            
        elseif mode == "Balanced" then
            -- Balanced approach between accuracy and performance
            local desync_amount, direction = animation_analyzer.detect_desync(player)
            local pattern = pattern_recognizer.analyze_patterns(player)
            
            -- Mix animation analysis with pattern recognition
            local anim_weight = 0.6
            local pattern_weight = 0.4
            
            resolved_angle = (direction * desync_amount * anim_weight) + 
                             (pattern.direction * pattern.value * pattern_weight)
            
            confidence = (0.7 * anim_weight + pattern.confidence * pattern_weight) * base_confidence
            
        elseif mode == "Performance" then
            -- Simple performance-optimized approach
            local pattern = pattern_recognizer.analyze_patterns(player)
            
            if pattern.type == "static" then
                resolved_angle = 0
                confidence = 0.9 * base_confidence
            elseif pattern.type == "wide_jitter" or pattern.type == "narrow_jitter" then
                resolved_angle = pattern.direction * pattern.value
                confidence = 0.8 * base_confidence
            else
                -- Simple direction alternation for other patterns
                resolved_angle = 35 * (data.missed_shots % 2 == 0 and 1 or -1)
                confidence = 0.6 * base_confidence
            end
            
        elseif mode == "Aggressive" then
            -- More aggressive correction angles
            local desync_amount, direction = animation_analyzer.detect_desync(player)
            
            -- Apply stronger correction
            resolved_angle = direction * desync_amount * 1.2
            
            -- Add some randomization to break pattern recognition
            resolved_angle = resolved_angle + math.random(-5, 5)
            
            -- Higher base confidence
            confidence = 0.8 * base_confidence
            
        elseif mode == "Defensive" then
            -- More conservative approach that focuses on safety
            local pattern = pattern_recognizer.analyze_patterns(player)
            
            if pattern.type == "static" then
                resolved_angle = 0
                confidence = 0.9 * base_confidence
            else
                -- Use a more conservative angle value to avoid missing shots
                resolved_angle = pattern.direction * (pattern.value * 0.8)
                confidence = 0.7 * base_confidence
            end
        end
        
        -- Apply module-specific modifiers
        
        -- Animation analysis modifier
        if ui.get(ui_components.animation.enable) then
            local desync_amount, direction = animation_analyzer.detect_desync(player)
            
            -- Blend with existing angle based on confidence
            local anim_weight = 0.3
            resolved_angle = (resolved_angle * (1 - anim_weight)) + (direction * desync_amount * anim_weight)
        end
        
        -- Network modifier (compensate for network conditions)
        if ui.get(ui_components.network.enable) then
            local network = network_analyzer.detect_network_conditions(player)
            
            -- Adjust confidence based on network quality
            if network.is_lagging or network.is_choking or network.has_loss then
                confidence = confidence * 0.85
            end
            
            -- Apply network-specific compensation options
            local options = ui.get(ui_components.network.network_conditions)
            
            if has_option(options, "Ping Compensation") and network.ping > 80 then
                -- Ping compensation for high ping players
                local ping_factor = math.min(1, (network.ping - 80) / 120)
                resolved_angle = resolved_angle * (1 + ping_factor * 0.2)
            end
            
            if has_option(options, "Packet Loss Detection") and network.has_loss then
                -- Be more aggressive with packet loss players
                resolved_angle = resolved_angle * 1.15
            end
            
            if has_option(options, "Jitter Correction") then
                -- Round to nearest 5 degrees for more stability
                resolved_angle = math.floor(resolved_angle / 5 + 0.5) * 5
            end
        end
        
        -- Exploit detection and countermeasures
        if ui.get(ui_components.exploits.enable) then
            -- Apply exploit-specific compensation
            if data.exploits_detected then
                if data.exploits_detected.defensive_aa.detected then
                    -- Defensive AA: add extra angle variation
                    resolved_angle = resolved_angle + 15 * (data.missed_shots % 2 == 0 and 1 or -1)
                end
                
                if data.exploits_detected.extended_desync.detected then
                    -- Extended desync: compensate for the extra angle
                    resolved_angle = resolved_angle * 1.1
                end
                
                -- Apply any countermeasures that were determined
                if data.countermeasures_applied and #data.countermeasures_applied > 0 then
                    confidence = confidence * 1.1 -- Boost confidence when countermeasures are active
                end
            end
        end
        
        -- Hit history-based adjustments
        if data.missed_shots > 0 then
            local consecutive_misses = data.consecutive_misses or 0
            
            -- Bigger compensation angles after misses
            local miss_factor = math.min(1, consecutive_misses / 5)
            
            -- Apply incremental angle adjustments after misses
            if consecutive_misses >= 1 then
                -- After consecutive misses, try alternating directions
                local alt_dir = consecutive_misses % 2 == 0 and 1 or -1
                
                -- Blend with existing angle
                resolved_angle = resolved_angle * (1 - miss_factor * 0.5) + (35 * alt_dir * miss_factor * 0.5)
                
                -- Gradually reduce confidence after consecutive misses
                confidence = confidence * (1 - miss_factor * 0.3)
            end
        elseif data.hit_shots > data.missed_shots then
            -- We're hitting more than missing - boost confidence
            confidence = confidence * 1.1
        end
        
        -- Apply optimization-based boosts if enabled
        if ui.get(ui_components.optimization.enable) then
            local boost_amount = ui.get(ui_components.optimization.accuracy_boost) / 100
            
            -- Apply accuracy boost to confidence
            confidence = confidence * (1 + boost_amount * 0.2)
            
            -- Optimize the final angle based on pattern type
            if data.pattern_type == "static" then
                resolved_angle = 0
            elseif data.pattern_type == "jitter" and boost_amount > 0.5 then
                -- Round to nearest 5 degrees for jitter patterns
                resolved_angle = math.floor(resolved_angle / 5 + 0.5) * 5
            end
        end
        
        -- Final adjustments and limits
        
        -- Clamp maximum correction angle
        resolved_angle = math_utils.clamp(resolved_angle, -CONSTANTS.MAX_DESYNC_ANGLE, CONSTANTS.MAX_DESYNC_ANGLE)
        
        -- Clamp confidence
        confidence = math_utils.clamp(confidence, 0.1, 0.95)
        
        -- Apply the correction to the current angle
        local final_angle = math_utils.normalize_angle(yaw + resolved_angle)
        
        -- Store resolver data
        data.last_resolve_angle = resolved_angle
        data.last_confidence = confidence
        
        -- Add to history
        table.insert(data.resolved_angles, {
            angle = resolved_angle,
            time = globals.realtime(),
            confidence = confidence,
            mode = mode,
            hit = nil -- Will be updated when we hit/miss
        })
        
        -- Trim resolved angles history
        if #data.resolved_angles > CONSTANTS.MAX_HISTORY_SIZE then
            table.remove(data.resolved_angles, 1)
        end
        
        -- Apply the final correction
        entity.set_prop(player, "m_angEyeAngles[1]", final_angle)
        
        -- Log if debug is enabled
        if ui.get(ui_components.debug.enable) and ui.get(ui_components.debug.debug_level) >= 2 then
            local player_name = entity.get_player_name(player) or "Unknown"
            logger:log_resolver(player, "resolve", string.format(
                "Mode: %s | Angle: %.1f° | Confidence: %.1f%%", 
                mode, resolved_angle, confidence * 100
            ))
        end
        
        return final_angle, confidence
    end
}

--------------------------------------------------
-- VISUALIZATION SYSTEM
--------------------------------------------------

visualization = {
    get_confidence_color = function(confidence)
        local r, g, b
        
        -- Get colors from UI
        local low_r, low_g, low_b = ui.get(ui_components.appearance.colors.low_confidence)
        local mid_r, mid_g, mid_b = ui.get(ui_components.appearance.colors.medium_confidence)
        local high_r, high_g, high_b = ui.get(ui_components.appearance.colors.high_confidence)
        
        if confidence < CONSTANTS.CONFIDENCE_LOW_THRESHOLD / 100 then
            -- Low confidence
            r, g, b = low_r, low_g, low_b
        elseif confidence > CONSTANTS.CONFIDENCE_HIGH_THRESHOLD / 100 then
            -- High confidence
            r, g, b = high_r, high_g, high_b
        else
            -- Medium confidence, lerp between low and high
            local t = (confidence * 100 - CONSTANTS.CONFIDENCE_LOW_THRESHOLD) / 
                     (CONSTANTS.CONFIDENCE_HIGH_THRESHOLD - CONSTANTS.CONFIDENCE_LOW_THRESHOLD)
            
            r = math_utils.lerp(mid_r, high_r, t)
            g = math_utils.lerp(mid_g, high_g, t)
            b = math_utils.lerp(mid_b, high_b, t)
        end
        
        return r, g, b
    end,
    
    draw_confidence_bar = function(x, y, width, confidence, alpha)
        alpha = alpha or 255
        
        -- Get color based on confidence
        local r, g, b = visualization.get_confidence_color(confidence)
        
        -- Draw background
        renderer.rectangle(x, y, width, 6, 20, 20, 20, alpha * 0.7)
        
        -- Draw filled part
        local fill_width = width * confidence
        renderer.rectangle(x, y, fill_width, 6, r, g, b, alpha)
        
        -- Draw border
        renderer.rectangle(x, y, width, 1, 40, 40, 40, alpha)
        renderer.rectangle(x, y + 5, width, 1, 40, 40, 40, alpha)
        renderer.rectangle(x, y, 1, 6, 40, 40, 40, alpha)
        renderer.rectangle(x + width - 1, y, 1, 6, 40, 40, 40, alpha)
    end,
    
    draw_player_info = function(player, x, y, width)
        local data = resolver_data[player]
        if not data then return y end
        
        local debug_level = ui.get(ui_components.debug.debug_level)
        local alpha = data.is_dormant and 150 or 255
        
        -- Player name
        local player_name = entity.get_player_name(player) or "Unknown"
        renderer.text(x, y, 255, 255, 255, alpha, "", 0, player_name)
        y = y + 15
        
        -- Confidence bar
        local confidence = data.last_confidence or 0.5
        local conf_text = string.format("%.0f%%", confidence * 100)
        local text_w = renderer.measure_text("", conf_text)
        
        visualization.draw_confidence_bar(x, y, width - text_w - 10, confidence, alpha)
        renderer.text(x + width - text_w - 5, y - 2, 255, 255, 255, alpha, "", 0, conf_text)
        y = y + 10
        
        -- Main stats line
        local resolver_mode = resolver.get_resolver_mode()
        local pattern_desc = pattern_recognizer.get_pattern_description({type = data.pattern_type or "unknown"})
        
        local stats_text = string.format("%s | %s | Hits: %d | Misses: %d", 
            resolver_mode, pattern_desc, data.hit_shots or 0, data.missed_shots or 0)
            
        local r, g, b = visualization.get_confidence_color(confidence)
        renderer.text(x, y, r, g, b, alpha, "", 0, stats_text)
        y = y + 15
        
        -- Additional information based on debug level
        if debug_level >= 1 then
            local last_angle = data.last_resolve_angle or 0
            local success_rate = data.hit_shots > 0 and 
                                (data.hit_shots / (data.hit_shots + data.missed_shots) * 100) or 0
                                
            local angle_text = string.format("Angle: %.1f° | Rate: %.0f%%", last_angle, success_rate)
            renderer.text(x, y, 220, 220, 220, alpha, "", 0, angle_text)
            y = y + 15
        end
        
        -- Movement info
        if debug_level >= 2 then
            local movement = motion_analyzer.analyze_movement_pattern(player)
            local vel_text = string.format("Movement: %s | Vel: %.0f u/s", 
                movement.movement_type, (data.velocity_history[#data.velocity_history] or {magnitude = 0}).magnitude)
                
            renderer.text(x, y, 200, 200, 200, alpha, "", 0, vel_text)
            y = y + 15
        end
        
        -- Network and exploits info
        if debug_level >= 2 and (ui.get(ui_components.network.enable) or ui.get(ui_components.exploits.enable)) then
            -- Network info
            if ui.get(ui_components.network.enable) then
                local network = network_analyzer.detect_network_conditions(player)
                local net_issues = {}
                
                if network.is_lagging then table.insert(net_issues, "LAG") end
                if network.is_choking then table.insert(net_issues, "CHOKE") end
                if network.has_loss then table.insert(net_issues, "LOSS") end
                
                local net_text = string.format("Ping: %dms", network.ping)
                if #net_issues > 0 then
                    net_text = net_text .. " | Issues: " .. table.concat(net_issues, ", ")
                end
                
                local net_r, net_g, net_b = 200, 200, 200
                if #net_issues > 0 then
                    net_r, net_g, net_b = 255, 120, 0
                end
                
                renderer.text(x, y, net_r, net_g, net_b, alpha, "", 0, net_text)
                y = y + 15
            end
            
            -- Exploits info
            if ui.get(ui_components.exploits.enable) and data.exploits_detected then
                local exploits = {}
                
                if data.exploits_detected.fakelag and data.exploits_detected.fakelag.detected then 
                    table.insert(exploits, string.format("FAKELAG(%d)", data.exploits_detected.fakelag.value)) 
                end
                
                if data.exploits_detected.defensive_aa and data.exploits_detected.defensive_aa.detected then 
                    table.insert(exploits, "DEFENSIVE") 
                end
                
                if data.exploits_detected.extended_desync and data.exploits_detected.extended_desync.detected then 
                    table.insert(exploits, "EXT-DESYNC") 
                end
                
                if data.exploits_detected.double_tap and data.exploits_detected.double_tap.detected then 
                    table.insert(exploits, "DOUBLETAP") 
                end
                
                if #exploits > 0 then
                    local exploit_text = "Exploits: " .. table.concat(exploits, ", ")
                    renderer.text(x, y, 255, 100, 100, alpha, "", 0, exploit_text)
                    y = y + 15
                end
                
                -- Show countermeasures
                if data.countermeasures_applied and #data.countermeasures_applied > 0 then
                    local cm_text = "Countermeasures: " .. table.concat(data.countermeasures_applied, ", ")
                    renderer.text(x, y, 100, 255, 100, alpha, "", 0, cm_text)
                    y = y + 15
                end
            end
        end
        
        -- Show angle history graph
        if debug_level >= 3 and #data.resolved_angles > 5 then
            y = y + 5
            
            -- Graph dimensions
            local graph_height = 40
            local graph_y = y
            
            -- Background
            renderer.rectangle(x, graph_y, width, graph_height, 20, 20, 20, 150)
            
            -- Reference line (0 degrees)
            local zero_y = graph_y + graph_height / 2
            renderer.line(x, zero_y, x + width, zero_y, 100, 100, 100, 100)
            
            -- Maximum range for visualization
            local max_angle = 60
            
            -- Plot points
            local max_points = math.min(width / 4, #data.resolved_angles)
            local points_x = {}
            local points_y = {}
            
            for i = #data.resolved_angles - max_points + 1, #data.resolved_angles do
                local point_index = i - (#data.resolved_angles - max_points)
                local resolve_data = data.resolved_angles[i]
                
                points_x[point_index] = x + (point_index - 1) * (width / (max_points - 1))
                
                -- Normalize angle to graph height
                local normalized_angle = math.max(-max_angle, math.min(max_angle, resolve_data.angle or 0))
                local angle_ratio = normalized_angle / max_angle
                points_y[point_index] = zero_y - angle_ratio * (graph_height / 2)
            end
            
            -- Draw lines between points
            for i = 2, max_points do
                local resolve_data = data.resolved_angles[#data.resolved_angles - max_points + i]
                local line_r, line_g, line_b = visualization.get_confidence_color(resolve_data.confidence or 0.5)
                
                renderer.line(points_x[i-1], points_y[i-1], points_x[i], points_y[i], 
                              line_r, line_g, line_b, alpha * 0.8)
            end
            
            -- Draw hit/miss markers
            for i = 1, max_points do
                local resolve_data = data.resolved_angles[#data.resolved_angles - max_points + i]
                
                if resolve_data.hit ~= nil then
                    if resolve_data.hit then
                        -- Hit marker (green circle)
                        renderer.circle(points_x[i], points_y[i], 0, 255, 0, alpha, 3, 0, 1)
                    else
                        -- Miss marker (red X)
                        local x1, y1 = points_x[i] - 2, points_y[i] - 2
                        local x2, y2 = points_x[i] + 2, points_y[i] + 2
                        renderer.line(x1, y1, x2, y2, 255, 0, 0, alpha)
                        renderer.line(x1, y2, x2, y1, 255, 0, 0, alpha)
                    end
                end
            end
            
            y = graph_y + graph_height + 5
        end
        
        return y
    end,
    
    draw_player_angle = function(player)
        local data = resolver_data[player]
        if not data or not entity.is_alive(player) or entity.is_dormant(player) then return end
        
        local visualization_options = ui.get(ui_components.debug.visualize)
        if not has_option(visualization_options, "Real Angle") and 
           not has_option(visualization_options, "Predicted Angle") then
            return
        end
        
        -- Get player position
        local pos_x, pos_y, pos_z = entity.get_origin(player)
        if not pos_x then return end
        
        -- Get eye position (elevated from origin)
        local eye_pos = {
            x = pos_x,
            y = pos_y,
            z = pos_z + 64
        }
        
        -- Get current angles
        local pitch = entity.get_prop(player, "m_angEyeAngles[0]") or 0
        local yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
        
        -- Calculate vectors
        local real_angle_vector = math_utils.angles_to_vector(0, yaw)
        local resolved_angle_vector = math_utils.angles_to_vector(0, yaw + (data.last_resolve_angle or 0))
        
        -- Calculate endpoint positions (line length = 30 units)
        local line_length = 30
        
        local real_end = {
            x = eye_pos.x + real_angle_vector.x * line_length,
            y = eye_pos.y + real_angle_vector.y * line_length,
            z = eye_pos.z
        }
        
        local resolved_end = {
            x = eye_pos.x + resolved_angle_vector.x * line_length,
            y = eye_pos.y + resolved_angle_vector.y * line_length,
            z = eye_pos.z
        }
        
        -- Convert to screen coordinates
        local eye_x, eye_y = client.world_to_screen(eye_pos.x, eye_pos.y, eye_pos.z)
        
        if eye_x and eye_y then
            -- Draw real angle line
            if has_option(visualization_options, "Real Angle") then
                local real_x, real_y = client.world_to_screen(real_end.x, real_end.y, real_end.z)
                
                if real_x and real_y then
                    renderer.line(eye_x, eye_y, real_x, real_y, 
                                 COLORS.VISUALIZATION.REAL_ANGLE[1], 
                                 COLORS.VISUALIZATION.REAL_ANGLE[2], 
                                 COLORS.VISUALIZATION.REAL_ANGLE[3], 
                                 200)
                end
            end
            
            -- Draw resolved angle line
            if has_option(visualization_options, "Predicted Angle") then
                local resolved_x, resolved_y = client.world_to_screen(resolved_end.x, resolved_end.y, resolved_end.z)
                
                if resolved_x and resolved_y then
                    local r, g, b = visualization.get_confidence_color(data.last_confidence or 0.5)
                    renderer.line(eye_x, eye_y, resolved_x, resolved_y, r, g, b, 200)
                end
            end
        end
        
        -- Draw backtrack points if enabled
        if has_option(visualization_options, "Backtrack Points") and ui.get(ui_components.network.enable) then
            -- Get optimal backtrack
            local optimal_backtrack = network_analyzer.select_optimal_backtrack(player)
            
            -- Draw backtrack records
            if data.backtrack_records then
                for i, record in ipairs(data.backtrack_records) do
                    if record.is_valid then
                        local record_pos = {
                            x = record.position[1],
                            y = record.position[2],
                            z = record.position[3]
                        }
                        
                        local rec_x, rec_y = client.world_to_screen(record_pos.x, record_pos.y, record_pos.z + 50)
                        
                        if rec_x and rec_y then
                            local alpha = 100
                            local size = 2
                            
                            -- Highlight optimal backtrack point
                            if i == optimal_backtrack then
                                alpha = 225
                                size = 4
                            end
                            
                            renderer.circle(rec_x, rec_y, 
                                          COLORS.VISUALIZATION.BACKTRACK[1], 
                                          COLORS.VISUALIZATION.BACKTRACK[2], 
                                          COLORS.VISUALIZATION.BACKTRACK[3], 
                                          alpha, size, 0, 1)
                        end
                    end
                end
            end
        end
    end,
    
    render_indicator = function()
        -- Don't show if resolver is disabled
        if not ui.get(ui_components.main.enable) then return end
        
        local visualization_options = ui.get(ui_components.debug.visualize)
        if not has_option(visualization_options, "Confidence Indicator") then return end
        
        -- Get screen dimensions
        local screen_width, screen_height = client.screen_size()
        
        -- Calculate indicator position (bottom center)
        local indicator_width = 150
        local indicator_height = 25
        local x = (screen_width - indicator_width) / 2
        local y = screen_height - indicator_height - 40
        
        -- Calculate stats
        local total_hits = session_stats.total_hits
        local total_misses = session_stats.total_misses
        local success_rate = (total_hits + total_misses > 0) and (total_hits / (total_hits + total_misses)) or 0.5
        
        -- Draw background
        renderer.rectangle(x, y, indicator_width, indicator_height, 0, 0, 0, 150)
        
        -- Draw title
        local title = "RecodeResolver"
        local r, g, b = 255, 255, 255
        
        if not ui.get(ui_components.main.master_switch) then
            title = title .. " [OFF]"
            r, g, b = 255, 50, 50
        else
            title = title .. " [ON]"
            r, g, b = 50, 255, 50
        end
        
        renderer.text(x + indicator_width/2, y + 3, r, g, b, 255, "c", 0, title)
        
        -- Draw confidence bar
        visualization.draw_confidence_bar(x + 5, y + 15, indicator_width - 10, success_rate)
        
        -- Show hit/miss stats
        local stats_text = string.format("%d/%d (%.0f%%)", total_hits, total_hits + total_misses, success_rate * 100)
        renderer.text(x + indicator_width/2, y + 15, 255, 255, 255, 255, "c", 0, stats_text)
    end,
    
    render_player_list = function()
        if not ui.get(ui_components.debug.enable) or ui.get(ui_components.debug.debug_level) < 1 then return end
        
        -- Background panel
        local panel_width = 250
        local panel_height = 400
        local panel_x = 10
        local panel_y = 100
        
        -- Get all enemies with resolver data
        local players_to_show = {}
        
        for player, data in pairs(resolver_data) do
            if entity.is_enemy(player) and (entity.is_alive(player) or data.hit_shots > 0) then
                table.insert(players_to_show, player)
            end
        end
        
        -- Sort by priority (active players first, then by hit count)
        table.sort(players_to_show, function(a, b)
            local a_alive = entity.is_alive(a)
            local b_alive = entity.is_alive(b)
            
            if a_alive ~= b_alive then return a_alive end
            
            local a_hits = resolver_data[a].hit_shots or 0
            local b_hits = resolver_data[b].hit_shots or 0
            
            return a_hits > b_hits
        end)
        
        -- Only draw panel if we have players to show
        if #players_to_show > 0 then
            -- Draw panel background
            renderer.rectangle(panel_x, panel_y, panel_width, panel_height, 0, 0, 0, 150)
            
            -- Draw title
            renderer.text(panel_x + panel_width/2, panel_y + 5, 255, 255, 255, 255, "c", 0, "RESOLVER DATA")
            
            -- Draw player info
            local y_offset = panel_y + 25
            local player_count = 0
            
            for _, player in ipairs(players_to_show) do
                -- Limit the number of shown players
                if player_count >= 5 then break end
                
                local new_y = visualization.draw_player_info(player, panel_x + 10, y_offset, panel_width - 20)
                y_offset = new_y + 15
                player_count = player_count + 1
                
                -- Draw separator line
                if player_count < math.min(5, #players_to_show) then
                    renderer.line(panel_x + 10, y_offset - 8, panel_x + panel_width - 10, y_offset - 8, 100, 100, 100, 100)
                end
            end
            
            -- Show how many more players we have
            if #players_to_show > 5 then
                renderer.text(panel_x + panel_width/2, y_offset, 200, 200, 200, 200, "c", 0, 
                             string.format("+ %d more players", #players_to_show - 5))
            end
        end
    end
}

-- Round state management and cleanup
round_manager = {
    current_round = 0,
    
    reset_round_data = function()
        -- Increment round counter
        round_manager.current_round = round_manager.current_round + 1
        
        -- Update session stats
        session_stats.rounds_played = session_stats.rounds_played + 1
        
        -- Log round end
        logger:log(string.format("Round %d ended - Performing partial data cleanup", round_manager.current_round), 1)
        
        -- Clean up data for all tracked players
        for player, data in pairs(resolver_data) do
            -- Check if player is still valid
            if entity.is_enemy(player) then
                -- Reset round-specific stats but preserve learning
                if data then
                    -- Reset round-specific stats
                    data.round_shots = 0
                    data.round_hits = 0
                    
                    -- Trim histories to prevent excessive memory usage
                    -- but don't completely wipe them
                    if #data.angle_history > CONSTANTS.MAX_ANGLE_HISTORY / 2 then
                        -- Keep half of the history
                        local keep = math.floor(CONSTANTS.MAX_ANGLE_HISTORY / 2)
                        for i = 1, #data.angle_history - keep do
                            table.remove(data.angle_history, 1)
                        end
                    end
                    
                    if #data.velocity_history > CONSTANTS.MAX_HISTORY_SIZE / 2 then
                        local keep = math.floor(CONSTANTS.MAX_HISTORY_SIZE / 2)
                        for i = 1, #data.velocity_history - keep do
                            table.remove(data.velocity_history, 1)
                        end
                    end
                    
                    -- Reset angle snapshots (used for defensive AA detection)
                    data.angle_snapshots = {}
                    
                    -- Reset immediate state indicators
                    data.was_reset = false
                    
                    -- Reset any exploit and countermeasure data, as they may change per round
                    data.exploits_detected = {}
                    data.countermeasures_applied = {}
                    
                    -- Don't reset the ML model, but do reset its state
                    if ml_models[player] then
                        ml_models[player]:reset_state()
                    end
                    
                    logger:log_resolver(player, "round_reset", string.format(
                        "Partial reset for player - Preserving learning (H: %d/M: %d)", 
                        data.hit_shots, data.missed_shots))
                end
            else
                -- Not a valid enemy, clean up data
                resolver_data[player] = nil
                ml_models[player] = nil
            end
        end
        
        -- Force a cleanup of inactive players
        player_manager.clean_inactive_players()
    end
}


--------------------------------------------------
-- REACTION TIME ENHANCEMENT SYSTEM
--------------------------------------------------

reaction_time_handler = {
    get_reaction_time_settings = function()
        -- Get settings from UI
        local enabled = ui.get(ui_components.reaction_time.enable)
        local mode = ui.get(ui_components.reaction_time.mode)
        local time_ms = ui.get(ui_components.reaction_time.time_ms)
        local prefire_enabled = ui.get(ui_components.reaction_time.prefire)
        local prefire_threshold = ui.get(ui_components.reaction_time.prefire_predictability)
        local shot_anticipation = ui.get(ui_components.reaction_time.shot_anticipation)
        local priority_targets = ui.get(ui_components.reaction_time.priority_targets)
        
        return {
            enabled = enabled,
            mode = mode,
            time_ms = time_ms,
            prefire_enabled = prefire_enabled,
            prefire_threshold = prefire_threshold,
            shot_anticipation = shot_anticipation,
            priority_targets = priority_targets
        }
    end,
    
    process_reaction_time = function(player)
        local data = resolver_data[player]
        if not data then return 0 end
        
        -- Get reaction time settings
        local settings = reaction_time_handler.get_reaction_time_settings()
        if not settings.enabled then return 0 end
        
        -- Base reaction time from slider
        local reaction_time = settings.time_ms / 1000  -- Convert to seconds
        
        -- Adjust based on selected mode
        if settings.mode == "Speed Priority" then
            -- Prioritize speed - reduce reaction time by 40%
            reaction_time = reaction_time * 0.6
        elseif settings.mode == "Accuracy Priority" then
            -- Prioritize accuracy - increase reaction time by 20% for better precision
            reaction_time = reaction_time * 1.2
        elseif settings.mode == "Adaptive" then
            -- Adapt based on player history and confidence
            local confidence = data.last_confidence or 0.5
            local hit_ratio = data.hit_shots / math.max(1, data.hit_shots + data.missed_shots)
            
            -- Higher confidence and hit ratio means we can be more aggressive with reaction time
            local adaptive_factor = 1.0 - (confidence * 0.3) - (hit_ratio * 0.3)
            reaction_time = reaction_time * adaptive_factor
        end
        
        -- Apply prefire logic if enabled
        if settings.prefire_enabled then
            -- Get player movement pattern and predictability
            local movement = motion_analyzer.analyze_movement_pattern(player)
            
            -- If player movement is predictable enough based on threshold
            if movement.predictability * 100 >= settings.prefire_threshold then
                -- Apply aggressive prefire reduction (up to 70% reduction based on predictability)
                local prefire_factor = 1.0 - (movement.predictability * 0.7)
                reaction_time = reaction_time * prefire_factor
                
                logger:log_resolver(player, "reaction_time", string.format(
                    "Applying prefire (predictability: %.1f%%) - Reducing reaction time by %.1f%%",
                    movement.predictability * 100,
                    (1.0 - prefire_factor) * 100
                ), 2)
            end
        end
        
        -- Apply shot anticipation if enabled
        if settings.shot_anticipation then
            -- Check if the player has fired recently
            local has_recent_shot = false
            if data.shot_history and #data.shot_history > 0 then
                local last_shot_time = data.shot_history[#data.shot_history].time
                if globals.realtime() - last_shot_time < 1.0 then
                    has_recent_shot = true
                end
            end
            
            if has_recent_shot then
                -- Anticipate next shot with faster reaction
                reaction_time = reaction_time * 0.7
                
                logger:log_resolver(player, "reaction_time", "Shot anticipation active - Reducing reaction time by 30%", 2)
            end
        end
        
        -- Apply priority targeting if enabled
        if settings.priority_targets and #settings.priority_targets > 0 then
            local apply_priority = false
            
            -- Check for Low HP priority
            if has_option(settings.priority_targets, "Low HP") then
                local health = entity.get_prop(player, "m_iHealth") or 100
                if health < 50 then
                    apply_priority = true
                    logger:log_resolver(player, "reaction_time", string.format(
                        "Priority target (Low HP: %d) - Reducing reaction time",
                        health
                    ), 2)
                end
            end
            
            -- Check for High Threat priority
            if has_option(settings.priority_targets, "High Threat") and data.hit_shots > 3 then
                apply_priority = true
                logger:log_resolver(player, "reaction_time", "Priority target (High Threat) - Reducing reaction time", 2)
            end
            
            -- Check for Weapon Type priority
            if has_option(settings.priority_targets, "Weapon Type") then
                local weapon = entity.get_player_weapon(player)
                local weapon_name = weapon and entity.get_classname(weapon) or ""
                
                -- Prioritize AWPers and players with high-damage weapons
                if weapon_name:match("awp") or weapon_name:match("ssg08") or weapon_name:match("deagle") then
                    apply_priority = true
                    logger:log_resolver(player, "reaction_time", string.format(
                        "Priority target (Weapon: %s) - Reducing reaction time",
                        weapon_name
                    ), 2)
                end
            end
            
            -- Check for Distance Based priority
            if has_option(settings.priority_targets, "Distance Based") then
                local local_player = entity.get_local_player()
                local local_origin = {entity.get_origin(local_player)}
                local player_origin = {entity.get_origin(player)}
                
                if local_origin[1] and player_origin[1] then
                    local distance = math_utils.get_distance(
                        {x = local_origin[1], y = local_origin[2], z = local_origin[3]},
                        {x = player_origin[1], y = player_origin[2], z = player_origin[3]}
                    )
                    
                    -- Prioritize closer players (under 500 units)
                    if distance < 500 then
                        apply_priority = true
                        logger:log_resolver(player, "reaction_time", string.format(
                            "Priority target (Close Distance: %.1f) - Reducing reaction time",
                            distance
                        ), 2)
                    end
                end
            end
            
            -- Apply priority reduction
            if apply_priority then
                reaction_time = reaction_time * 0.65  -- 35% faster reaction for priority targets
            end
        end
        
        -- Ensure we have a minimum reaction time (avoid inhuman reactions)
        reaction_time = math.max(0.005, reaction_time)  -- Minimum 5ms reaction time
        
        -- Store reaction time in player data for reference
        data.current_reaction_time = reaction_time
        
        return reaction_time
    end,
    
    apply_reaction_time_delay = function(player, intended_shot)
        local data = resolver_data[player]
        if not data then return false end
        
        -- Process reaction time
        local reaction_delay = reaction_time_handler.process_reaction_time(player)
        
        -- Check if we should immediately allow the shot (no delay)
        if reaction_delay <= 0.01 then  -- If delay is very minimal, don't delay
            return true
        end
        
        -- Check if we've been targeting this player long enough
        local current_time = globals.realtime()
        if not data.targeting_start_time then
            data.targeting_start_time = current_time
            return false  -- Start the timer, don't shoot yet
        end
        
        -- If we've waited long enough, allow the shot
        if current_time - data.targeting_start_time >= reaction_delay then
            -- Reset targeting time after allowing a shot
            if intended_shot then
                data.targeting_start_time = nil
            end
            return true
        end
        
        return false  -- Still waiting for reaction time
    end,
    
    is_shot_allowed = function(player)
        -- Get reaction time settings
        local settings = reaction_time_handler.get_reaction_time_settings()
        if not settings.enabled then return true end  -- If disabled, always allow shots
        
        return reaction_time_handler.apply_reaction_time_delay(player, true)
    end
}

-- Hook into resolver to apply reaction time
local original_resolve_player = resolver.resolve_player
resolver.resolve_player = function(player)
    local angle, confidence = original_resolve_player(player)
    
    -- If we have a valid resolver result, apply reaction time processing
    if angle then
        local data = resolver_data[player]
        if data then
            -- Apply reaction time processing
            reaction_time_handler.process_reaction_time(player)
        end
    end
    
    return angle, confidence
end

-- Configuration
local ML_CONFIG = {
    -- Neural network parameters
    learning_rate = 0.02,
    momentum = 0.9,
    regularization = 0.0001,
    
    -- Model architecture
    input_features = 8,     -- Number of input features
    hidden_layers = {12, 8}, -- Neurons in hidden layers
    output_classes = 3,     -- Right, Center, Left angle predictions
    
    -- Training parameters
    batch_size = 5,
    epochs_per_update = 3,
    min_samples = 10,
    
    -- Angle mapping (translates neural network output to angles)
    angle_mapping = {
        [1] = { name = "right", min_angle = 25, max_angle = 58 },
        [2] = { name = "center", min_angle = -10, max_angle = 10 },
        [3] = { name = "left", min_angle = -58, max_angle = -25 }
    },
    
    -- Feature weights (initial importance of each feature)
    feature_weights = {
        velocity = 0.8,
        ducking = 0.7,
        in_air = 0.5,
        desync_delta = 1.0,
        move_direction = 0.9,
        rotation_speed = 0.8,
        choked_packets = 0.7,
        last_hit_delta = 1.0
    }
}

-- Neural Network Model
local NeuralNetwork = {
    -- Per-player models
    players = {},
    
    -- Global statistics
    stats = {
        total_training_samples = 0,
        hit_rate = 0,
        model_confidence = 0
    },
    
    -- Initialize model for a specific player
    init_player = function(self, player_idx)
        if not self.players[player_idx] then
            -- Create model structure
            local model = {
                -- Network weights
                weights = {
                    input_to_hidden1 = {},
                    hidden_biases = {},
                    output_weights = {},
                    output_biases = {}
                },
                
                -- Network gradients for momentum
                gradients = {
                    input_to_hidden1 = {},
                    hidden_biases = {},
                    output_weights = {},
                    output_biases = {}
                },
                
                -- Training data
                training_data = {
                    features = {},  -- Input features
                    targets = {},   -- Target outputs
                    hits = 0,       -- Number of hits
                    misses = 0      -- Number of misses
                },
                
                -- Prediction history
                history = {
                    predictions = {},
                    actual_results = {},
                    confidence_scores = {}
                },
                
                -- Performance metrics
                performance = {
                    accuracy = 0,
                    confidence = 0,
                    last_update = 0
                }
            }
            
            -- Initialize weights with random values
            self:initialize_weights(model)
            
            -- Store the model
            self.players[player_idx] = model
        end
        
        return self.players[player_idx]
    end,
    
    -- Initialize weights with Xavier initialization
    initialize_weights = function(self, model)
        -- Input to first hidden layer
        for i = 1, ML_CONFIG.input_features do
            model.weights.input_to_hidden1[i] = {}
            model.gradients.input_to_hidden1[i] = {}
            
            for j = 1, ML_CONFIG.hidden_layers[1] do
                local limit = math.sqrt(6 / (ML_CONFIG.input_features + ML_CONFIG.hidden_layers[1]))
                model.weights.input_to_hidden1[i][j] = (math.random() * 2 - 1) * limit
                model.gradients.input_to_hidden1[i][j] = 0
            end
        end
        
        -- Hidden layer biases
        for i = 1, #ML_CONFIG.hidden_layers do
            model.weights.hidden_biases[i] = {}
            model.gradients.hidden_biases[i] = {}
            
            for j = 1, ML_CONFIG.hidden_layers[i] do
                model.weights.hidden_biases[i][j] = 0
                model.gradients.hidden_biases[i][j] = 0
            end
        end
        
        -- Output layer weights
        model.weights.output_weights = {}
        model.gradients.output_weights = {}
        
        for i = 1, ML_CONFIG.hidden_layers[#ML_CONFIG.hidden_layers] do
            model.weights.output_weights[i] = {}
            model.gradients.output_weights[i] = {}
            
            for j = 1, ML_CONFIG.output_classes do
                local limit = math.sqrt(6 / (ML_CONFIG.hidden_layers[#ML_CONFIG.hidden_layers] + ML_CONFIG.output_classes))
                model.weights.output_weights[i][j] = (math.random() * 2 - 1) * limit
                model.gradients.output_weights[i][j] = 0
            end
        end
        
        -- Output biases
        model.weights.output_biases = {}
        model.gradients.output_biases = {}
        
        for i = 1, ML_CONFIG.output_classes do
            model.weights.output_biases[i] = 0
            model.gradients.output_biases[i] = 0
        end
    end,
    
    -- Extract features from player state
    extract_features = function(self, player_idx)
        local player_info = PlayerInfoManager:get_player(player_idx)
        if not player_info then return nil end
        
        local animstate = get_animstate(player_idx)
        if not animstate then return nil end
        
        -- Extract velocity information
        local vel_x = entity.get_prop(player_idx, "m_vecVelocity[0]") or 0
        local vel_y = entity.get_prop(player_idx, "m_vecVelocity[1]") or 0
        local speed = math.sqrt(vel_x^2 + vel_y^2)
        
        -- Calculate move direction relative to eye angle
        local eye_angles_y = animstate.eye_angles_y
        local move_yaw = math.atan2(vel_y, vel_x) * 180 / math.pi
        local move_direction = normalize_angle(move_yaw - eye_angles_y)
        
        -- Get desync info
        local desync_delta = math.abs(normalize_angle(animstate.eye_angles_y - animstate.goal_feet_yaw))
        
        -- Get duck amount
        local duck_amount = animstate.duck_amount
        
        -- Get in air state
        local flags = entity.get_prop(player_idx, "m_fFlags") or 0
        local in_air = bit.band(flags, 1) == 0 and 1 or 0
        
        -- Get choked packets
        local choked = get_choked_packets(player_idx)
        
        -- Calculate rotation speed based on history
        local model = self.players[player_idx]
        local rotation_speed = 0
        
        if model and #model.history.predictions >= 2 then
            local prev_yaw = model.history.predictions[#model.history.predictions-1].eye_yaw
            local curr_yaw = model.history.predictions[#model.history.predictions].eye_yaw
            rotation_speed = math.abs(normalize_angle(curr_yaw - prev_yaw))
        end
        
        -- Get last hit angle delta (difference between hit angle and predicted angle)
        local last_hit_delta = 0
        if model and #model.history.actual_results > 0 then
            for i = #model.history.actual_results, 1, -1 do
                if model.history.actual_results[i].result == "hit" then
                    last_hit_delta = model.history.actual_results[i].angle_delta
                    break
                end
            end
        end
        
        -- Normalize all features to a 0-1 range
        local features = {
            velocity = math.min(1.0, speed / 250.0),
            ducking = duck_amount,
            in_air = in_air,
            desync_delta = math.min(1.0, desync_delta / 58.0),
            move_direction = (move_direction + 180) / 360,
            rotation_speed = math.min(1.0, rotation_speed / 30.0),
            choked_packets = math.min(1.0, choked / 14.0),
            last_hit_delta = math.min(1.0, math.abs(last_hit_delta) / 60.0)
        }
        
        -- Apply feature weights
        for name, value in pairs(features) do
            features[name] = value * ML_CONFIG.feature_weights[name]
        end
        
        -- Convert to vector format for the neural network
        local feature_vector = {
            features.velocity,
            features.ducking,
            features.in_air,
            features.desync_delta,
            features.move_direction,
            features.rotation_speed,
            features.choked_packets,
            features.last_hit_delta
        }
        
        return feature_vector, features
    end,
    
    -- Forward pass through the neural network
    forward = function(self, model, features)
        local activations = {}
        activations[1] = {}
        
        -- Input to first hidden layer
        for i = 1, ML_CONFIG.hidden_layers[1] do
            local sum = model.weights.hidden_biases[1][i]
            
            for j = 1, ML_CONFIG.input_features do
                sum = sum + features[j] * model.weights.input_to_hidden1[j][i]
            end
            
            -- ReLU activation
            activations[1][i] = math.max(0, sum)
        end
        
        -- Additional hidden layers (if any)
        for layer = 2, #ML_CONFIG.hidden_layers do
            activations[layer] = {}
            
            for i = 1, ML_CONFIG.hidden_layers[layer] do
                local sum = model.weights.hidden_biases[layer][i]
                
                for j = 1, ML_CONFIG.hidden_layers[layer-1] do
                    sum = sum + activations[layer-1][j] * model.weights.hidden_layers[layer-1][j][i]
                end
                
                -- ReLU activation
                activations[layer][i] = math.max(0, sum)
            end
        end
        
        -- Output layer
        local last_layer = #ML_CONFIG.hidden_layers
        local output = {}
        local sum_exp = 0
        
        for i = 1, ML_CONFIG.output_classes do
            local sum = model.weights.output_biases[i]
            
            for j = 1, ML_CONFIG.hidden_layers[last_layer] do
                sum = sum + activations[last_layer][j] * model.weights.output_weights[j][i]
            end
            
            -- Store pre-softmax value
            output[i] = sum
            sum_exp = sum_exp + math.exp(sum)
        end
        
        -- Apply softmax for probabilities
        local probabilities = {}
        for i = 1, ML_CONFIG.output_classes do
            probabilities[i] = math.exp(output[i]) / sum_exp
        end
        
        return probabilities, activations
    end,
    
    -- Predict angle using the model
    predict = function(self, player_idx)
        local model = self.players[player_idx]
        if not model then return nil end
        
        -- Extract features
        local features, feature_map = self:extract_features(player_idx)
        if not features then return nil end
        
        -- Forward pass
        local probabilities, _ = self:forward(model, features)
        
        -- Find max probability
        local max_prob = 0
        local max_class = 1
        
        for i = 1, ML_CONFIG.output_classes do
            if probabilities[i] > max_prob then
                max_prob = probabilities[i]
                max_class = i
            end
        end
        
        -- Get angle range from mapping
        local angle_map = ML_CONFIG.angle_mapping[max_class]
        
        -- Calculate precise angle within range based on probability distribution
        local angle = angle_map.min_angle
        
        -- Use secondary class probabilities to fine-tune within range
        local range = angle_map.max_angle - angle_map.min_angle
        local secondary_influence = 0
        
        for i = 1, ML_CONFIG.output_classes do
            if i ~= max_class then
                local angle_diff = ML_CONFIG.angle_mapping[i].min_angle - angle_map.min_angle
                secondary_influence = secondary_influence + probabilities[i] * angle_diff
            end
        end
        
        -- Apply a weighted adjustment based on secondary classes
        angle = angle + range * (0.5 + secondary_influence * 0.3)
        
        -- Determine side based on angle sign
        local side = angle >= 0 and 1 or -1
        
        -- Store prediction in history
        local animstate = get_animstate(player_idx)
        table.insert(model.history.predictions, {
            time = globals.realtime(),
            angle = angle,
            side = side,
            confidence = max_prob,
            features = feature_map,
            eye_yaw = animstate and animstate.eye_angles_y or 0
        })
        
        -- Keep history manageable
        if #model.history.predictions > 20 then
            table.remove(model.history.predictions, 1)
        end
        
        return {
            angle = angle,
            side = side,
            confidence = max_prob,
            class = angle_map.name,
            probabilities = probabilities,
            features = feature_map
        }
    end,
    
    -- Add training sample
    add_sample = function(self, player_idx, features, target, is_hit)
        local model = self.players[player_idx]
        if not model then return end
        
        -- Add to training data
        table.insert(model.training_data.features, features)
        table.insert(model.training_data.targets, target)
        
        -- Update hit/miss count
        if is_hit then
            model.training_data.hits = model.training_data.hits + 1
        else
            model.training_data.misses = model.training_data.misses + 1
        end
        
        -- Keep training data manageable
        local max_samples = 100
        while #model.training_data.features > max_samples do
            table.remove(model.training_data.features, 1)
            table.remove(model.training_data.targets, 1)
        end
        
        -- Update global stats
        self.stats.total_training_samples = self.stats.total_training_samples + 1
        self.stats.hit_rate = model.training_data.hits / (model.training_data.hits + model.training_data.misses)
    end,
    
    -- Train model using backpropagation
    train = function(self, player_idx)
        local model = self.players[player_idx]
        if not model or #model.training_data.features < ML_CONFIG.min_samples then return end
        
        -- Training using mini-batch gradient descent
        for epoch = 1, ML_CONFIG.epochs_per_update do
            -- Shuffle training data
            local indices = {}
            for i = 1, #model.training_data.features do
                indices[i] = i
            end
            
            for i = #indices, 2, -1 do
                local j = math.random(i)
                indices[i], indices[j] = indices[j], indices[i]
            end
            
            -- Process in mini-batches
            for batch_start = 1, #indices, ML_CONFIG.batch_size do
                -- Reset gradients
                for i = 1, ML_CONFIG.input_features do
                    for j = 1, ML_CONFIG.hidden_layers[1] do
                        model.gradients.input_to_hidden1[i][j] = 0
                    end
                end
                
                for layer = 1, #ML_CONFIG.hidden_layers do
                    for i = 1, ML_CONFIG.hidden_layers[layer] do
                        model.gradients.hidden_biases[layer][i] = 0
                        
                        if layer == #ML_CONFIG.hidden_layers then
                            for j = 1, ML_CONFIG.output_classes do
                                model.gradients.output_weights[i][j] = 0
                            end
                        end
                    end
                end
                
                for i = 1, ML_CONFIG.output_classes do
                    model.gradients.output_biases[i] = 0
                end
                
                -- Accumulate gradients over batch
                local batch_size = 0
                for i = batch_start, math.min(batch_start + ML_CONFIG.batch_size - 1, #indices) do
                    local idx = indices[i]
                    local features = model.training_data.features[idx]
                    local target = model.training_data.targets[idx]
                    
                    -- Forward pass
                    local probabilities, activations = self:forward(model, features)
                    
                    -- Compute output layer error (cross-entropy with softmax derivative)
                    local output_error = {}
                    for j = 1, ML_CONFIG.output_classes do
                        output_error[j] = probabilities[j] - (j == target and 1 or 0)
                    end
                    
                    -- Backpropagate error and update gradients
                    -- (simplified backpropagation for example purposes)
                    local last_layer = #ML_CONFIG.hidden_layers
                    
                    -- Output layer gradients
                    for i = 1, ML_CONFIG.output_classes do
                        model.gradients.output_biases[i] = model.gradients.output_biases[i] + output_error[i]
                        
                        for j = 1, ML_CONFIG.hidden_layers[last_layer] do
                            model.gradients.output_weights[j][i] = model.gradients.output_weights[j][i] + 
                                                               output_error[i] * activations[last_layer][j]
                        end
                    end
                    
                    -- Hidden layers and input layer gradients would be computed here
                    -- (full backpropagation implementation omitted for brevity)
                    
                    batch_size = batch_size + 1
                end
                
                -- Apply gradients with learning rate, momentum and regularization
                local lr = ML_CONFIG.learning_rate / batch_size
                
                -- Update weights and biases using gradients
                -- (simplified update for example purposes)
                for i = 1, ML_CONFIG.input_features do
                    for j = 1, ML_CONFIG.hidden_layers[1] do
                        local grad = model.gradients.input_to_hidden1[i][j]
                        local weight = model.weights.input_to_hidden1[i][j]
                        
                        -- Apply regularization
                        grad = grad + ML_CONFIG.regularization * weight
                        
                        -- Update with momentum
                        local delta = lr * grad + ML_CONFIG.momentum * model.gradients.input_to_hidden1[i][j]
                        model.weights.input_to_hidden1[i][j] = weight - delta
                        model.gradients.input_to_hidden1[i][j] = delta  -- Store for momentum
                    end
                end
                
                -- Update other weights and biases similarly
                -- (full update implementation omitted for brevity)
            end
        end
        
        -- Mark the model as recently updated
        model.performance.last_update = globals.realtime()
    end,
    
    -- Process hit event to update model
    process_hit = function(self, player_idx, angle_used)
        local model = self:init_player(player_idx)
        
        -- Extract features from the current state
        local features, _ = self:extract_features(player_idx)
        if not features then return end
        
        -- Determine target class
        local target_class = 2  -- Default to center
        
        for i, mapping in ipairs(ML_CONFIG.angle_mapping) do
            if angle_used >= mapping.min_angle and angle_used <= mapping.max_angle then
                target_class = i
                break
            end
        end
        
        -- Find the most recent prediction for this angle
        local prediction = nil
        for i = #model.history.predictions, 1, -1 do
            local pred = model.history.predictions[i]
            if math.abs(pred.angle - angle_used) < 10 then
                prediction = pred
                break
            end
        end
        
        -- Record prediction result
        table.insert(model.history.actual_results, {
            time = globals.realtime(),
            angle = angle_used,
            predicted_angle = prediction and prediction.angle or 0,
            angle_delta = prediction and (angle_used - prediction.angle) or 0,
            result = "hit"
        })
        
        -- Keep history manageable
        if #model.history.actual_results > 20 then
            table.remove(model.history.actual_results, 1)
        end
        
        -- Add as training sample
        self:add_sample(player_idx, features, target_class, true)
        
        -- Train if we have enough samples
        if #model.training_data.features >= ML_CONFIG.min_samples then
            self:train(player_idx)
        end
        
        -- Update performance metrics
        local hit_count = 0
        local total_results = math.min(10, #model.history.actual_results)
        
        for i = #model.history.actual_results - total_results + 1, #model.history.actual_results do
            if model.history.actual_results[i].result == "hit" then
                hit_count = hit_count + 1
            end
        end
        
        model.performance.accuracy = hit_count / total_results
    end,
    
    -- Process miss event to update model
    process_miss = function(self, player_idx, angle_used)
        local model = self:init_player(player_idx)
        
        -- Extract features from the current state
        local features, _ = self:extract_features(player_idx)
        if not features then return end
        
        -- Determine target class (invert the used class since it missed)
        local used_class = 2  -- Default to center
        
        for i, mapping in ipairs(ML_CONFIG.angle_mapping) do
            if angle_used >= mapping.min_angle and angle_used <= mapping.max_angle then
                used_class = i
                break
            end
        end
        
        -- Invert class (if right missed, try left or center)
        local target_class
        if used_class == 1 then  -- Right
            target_class = 3     -- Try left
        elseif used_class == 3 then  -- Left
            target_class = 1         -- Try right
        else  -- Center
            -- If center missed, randomly pick left or right with preference based on history
            local right_hits = 0
            local left_hits = 0
            
            for _, result in ipairs(model.history.actual_results) do
                if result.result == "hit" then
                    if result.angle > 0 then
                        right_hits = right_hits + 1
                    else
                        left_hits = left_hits + 1
                    end
                end
            end
            
            if right_hits > left_hits then
                target_class = 1  -- Right has more hits
            elseif left_hits > right_hits then
                target_class = 3  -- Left has more hits
            else
                target_class = math.random(1, 3) == 1 and 1 or 3  -- Random but not center
            end
        end
        
        -- Record prediction result
        table.insert(model.history.actual_results, {
            time = globals.realtime(),
            angle = angle_used,
            result = "miss"
        })
        
        -- Keep history manageable
        if #model.history.actual_results > 20 then
            table.remove(model.history.actual_results, 1)
        end
        
        -- Add as training sample
        self:add_sample(player_idx, features, target_class, false)
        
        -- Train if we have enough samples
        if #model.training_data.features >= ML_CONFIG.min_samples then
            self:train(player_idx)
        end
        
        -- Update performance metrics
        local hit_count = 0
        local total_results = math.min(10, #model.history.actual_results)
        
        for i = #model.history.actual_results - total_results + 1, #model.history.actual_results do
            if model.history.actual_results[i].result == "hit" then
                hit_count = hit_count + 1
            end
        end
        
        model.performance.accuracy = hit_count / total_results
    end,
    
    -- Use ML model to determine resolver angle
    get_resolve_angle = function(self, player_idx)
        -- Initialize model if needed
        local model = self:init_player(player_idx)
        
        -- Check if we have enough training data to trust the model
        if model.training_data.hits + model.training_data.misses < ML_CONFIG.min_samples then
            return nil  -- Not enough data, use default resolver
        end
        
        -- Make prediction
        local prediction = self:predict(player_idx)
        if not prediction then return nil end
        
        -- Calculate max desync
        local max_desync = get_max_desync_delta(player_idx)
        
        -- Scale prediction by max desync
        local scaled_angle = prediction.angle * (max_desync / 58.0)
        
        -- Create resolver result
        local result = {
            mode = 5,  -- Special mode for ML model
            angle = scaled_angle,
            side = prediction.side,
            confidence = prediction.confidence
        }
        
        -- Increase confidence if we've had successful hits with this angle
        for _, hit in ipairs(model.history.actual_results) do
            if hit.result == "hit" and math.abs(hit.angle - scaled_angle) < 10 then
                result.confidence = result.confidence + 0.1
                break
            end
        end
        
        -- Cap confidence at 1.0
        result.confidence = math.min(result.confidence, 1.0)
        
        return result
    end
}

--------------------------------------------------
-- EVENT HANDLING
--------------------------------------------------

client.set_event_callback("run_command", function()
    -- Only process if resolver and reaction time are enabled
    if not ui.get(ui_components.main.enable) or not ui.get(ui_components.reaction_time.enable) then return end
    
    -- Check current target
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end
    
    -- Get current target from ragebot
    local target = client.current_threat()
    if not target then return end
    
    -- Check if shot is allowed based on reaction time
    local shot_allowed = reaction_time_handler.is_shot_allowed(target)
    
    -- Set ragebot state based on shot permission
    if not shot_allowed then
        -- Block shot - different methods for different versions of gamesense
        if client.can_fire ~= nil then
            client.delay_call(0.001, function() -- Very small delay to maintain responsiveness
                client.exec("weapon_accuracy_nospread 0")
            end)
        elseif ragebot and ragebot.override_minimum_damage then
            -- Alternative method for some gamesense versions
            ragebot.override_minimum_damage(target, 9999) -- Set impossible damage requirement
        end
    else
        -- Re-enable shooting after delay
        if client.can_fire ~= nil then
            client.delay_call(0.001, function()
                client.exec("weapon_accuracy_nospread 1")
            end)
        elseif ragebot and ragebot.override_minimum_damage then
            ragebot.override_minimum_damage(target, nil) -- Reset damage requirement
        end
    end
end)

client.set_event_callback("round_end", function()
    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Perform round-end cleanup
    round_manager.reset_round_data()
end)

-- Add event listener for round start
client.set_event_callback("round_start", function()
    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Log round start
    logger:log(string.format("Round %d started", round_manager.current_round + 1), 1)
end)

client.set_event_callback("aim_miss", function(e)
    local target = e.target
    local angle_used = Synapse.data.players[target].resolver_data.last_resolve.angle
    
    -- Update ML model
    NeuralNetwork:process_miss(target, angle_used)

    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    local player = e.target
    if not player or not entity.is_enemy(player) then return end
    
    -- Initialize player data if needed
    if not resolver_data[player] then
        player_manager.init_player_data(player)
    end
    
    local data = resolver_data[player]
    
    -- Update miss statistics
    data.missed_shots = (data.missed_shots or 0) + 1
    data.consecutive_misses = (data.consecutive_misses or 0) + 1
    data.last_miss_time = globals.realtime()
    
    -- Update confidence based on miss
    if data.last_confidence then
        data.last_confidence = math.max(0.1, data.last_confidence * 0.8)
    end
    
    -- Track miss reason for analysis
    local hitbox = e.hitbox
    local reason = e.reason or "unknown"
    
    -- Update session stats
    session_stats.total_misses = session_stats.total_misses + 1
    session_stats.total_shots = session_stats.total_shots + 1
    session_stats.success_rate = session_stats.total_hits / session_stats.total_shots
    
    -- Add miss record to history
    table.insert(data.miss_history, {
        time = globals.realtime(),
        angle = data.last_resolve_angle,
        hitbox = hitbox,
        reason = reason,
        confidence = data.last_confidence
    })
    
    -- Trim miss history if needed
    if #data.miss_history > CONSTANTS.MAX_SHOT_HISTORY then
        table.remove(data.miss_history, 1)
    end
    
    -- Update last resolved angle status in history
    if #data.resolved_angles > 0 then
        data.resolved_angles[#data.resolved_angles].hit = false
    end
    
    -- Calculate success rate
    if data.hit_shots + data.missed_shots > 0 then
        data.resolution_success_rate = data.hit_shots / (data.hit_shots + data.missed_shots)
    end
    
    -- Update ML model if prediction is enabled
    if ui.get(ui_components.prediction.enable) then
        -- Get new desync estimation after miss
        local desync_amount, direction = animation_analyzer.detect_desync(player)
        
        -- Invert direction since the current one failed
        ml_system.train_model(player, desync_amount, -direction, false)
    end
    
    -- Log the miss
    logger:log_miss(player, hitbox, reason)
    logger:log_resolver(player, "miss", string.format(
        "Angle: %.1f° | Reason: %s | Consecutive Misses: %d",
        data.last_resolve_angle or 0,
        reason,
        data.consecutive_misses
    ))
    
    -- Special handling for consecutive misses
    if data.consecutive_misses >= 3 then
        logger:log_resolver(player, "warning", string.format(
            "High miss count (%d consecutive) - Adjusting strategy",
            data.consecutive_misses
        ))
        
        -- Reset the state of ML models on high miss counts
        if ml_models[player] then
            ml_models[player]:reset_state()
        end
    end
end)

-- Fix 5: Add the UI paint callback for visualization
client.set_event_callback("paint", function()
    -- Only render if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Render confidence indicator
    visualization.render_indicator()
    
    -- Render detailed player information if debug is enabled
    if ui.get(ui_components.debug.enable) then
        visualization.render_player_list()
        
        -- Draw player angles in world
        local players = entity.get_players(true)
        for i = 1, #players do
            visualization.draw_player_angle(players[i])
        end
    end
end)

-- Initialize player data when first seeing them
client.set_event_callback("net_update_end", function()
    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Get all enemies
    local players = entity.get_players(true)
    for i = 1, #players do
        local player = players[i]
        
        -- Update data for this player
        if not resolver_data[player] then
            player_manager.init_player_data(player)
        else
            player_manager.update_player_data(player)
        end
    end
    
    -- Clean up inactive players periodically
    if globals.realtime() - (session_stats.last_update or 0) > 10 then
        player_manager.clean_inactive_players()
        session_stats.last_update = globals.realtime()
    end
end)

-- Apply resolver in pre-render to ensure up-to-date angle modification
client.set_event_callback("pre_render", function()
    -- Only process if resolver is enabled and active
    if not ui.get(ui_components.main.enable) or not ui.get(ui_components.main.master_switch) then return end
    
    -- Get all enemies
    local players = entity.get_players(true)
    for i = 1, #players do
        local player = players[i]
        
        -- Apply resolver to this player
        resolver.resolve_player(player)
    end
end)

-- Track successful hits
client.set_event_callback("player_hurt", function(e)
    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Check if we're the attacker
    local attacker = client.userid_to_entindex(e.attacker)
    if not attacker or attacker ~= entity.get_local_player() then return end
    
    -- Get the victim and process hit
    local victim = client.userid_to_entindex(e.userid)
    if not victim or not entity.is_enemy(victim) then return end
    
    -- Initialize player data if needed
    if not resolver_data[victim] then
        player_manager.init_player_data(victim)
    end
    
    local data = resolver_data[victim]
    
    -- Update hit statistics
    data.hit_shots = (data.hit_shots or 0) + 1
    data.round_hits = (data.round_hits or 0) + 1
    data.last_hit_time = globals.realtime()
    data.consecutive_misses = 0 -- Reset consecutive misses
    
    -- Update confidence based on hit
    if data.last_confidence then
        data.last_confidence = math.min(0.95, data.last_confidence * 1.1)
    end
    
    -- Track hitbox and damage for analysis
    local hitbox = e.hitgroup
    local damage = e.dmg_health
    
    -- Record if it's a headshot
    if hitbox == 1 then
        session_stats.headshots = session_stats.headshots + 1
    end
    
    -- Update session stats
    session_stats.total_hits = session_stats.total_hits + 1
    session_stats.total_shots = session_stats.total_shots + 1
    session_stats.success_rate = session_stats.total_hits / session_stats.total_shots
    
    -- Add hit record to history
    table.insert(data.hit_history, {
        time = globals.realtime(),
        angle = data.last_resolve_angle,
        hitbox = hitbox,
        damage = damage,
        confidence = data.last_confidence
    })
    
    -- Trim hit history if needed
    if #data.hit_history > CONSTANTS.MAX_SHOT_HISTORY then
        table.remove(data.hit_history, 1)
    end
    
    -- Update last resolved angle status in history
    if #data.resolved_angles > 0 then
        data.resolved_angles[#data.resolved_angles].hit = true
    end
    
    -- Calculate success rate
    if data.hit_shots + data.missed_shots > 0 then
        data.resolution_success_rate = data.hit_shots / (data.hit_shots + data.missed_shots)
    end
    
    -- Update ML model if prediction is enabled
    if ui.get(ui_components.prediction.enable) then
        -- Get the actual desync value that worked
        local desync_amount, direction = animation_analyzer.detect_desync(victim)
        ml_system.train_model(victim, desync_amount, direction, true)
    end
    
    -- Log the hit
    logger:log_hit(victim, hitbox, damage)
    logger:log_resolver(victim, "hit", string.format(
        "Angle: %.1f° | Confidence: %.1f%% | Success Rate: %.1f%%",
        data.last_resolve_angle or 0,
        (data.last_confidence or 0.5) * 100,
        data.resolution_success_rate * 100
    ))
end)client.set_event_callback("player_hurt", function(e)
    -- Only process if resolver is enabled
    if not ui.get(ui_components.main.enable) then return end
    
    -- Check if we're the attacker
    local attacker = client.userid_to_entindex(e.attacker)
    if not attacker or attacker ~= entity.get_local_player() then return end
    
    -- Get the victim and process hit
    local victim = client.userid_to_entindex(e.userid)
    if not victim or not entity.is_enemy(victim) then return end
    
    -- Initialize player data if needed
    if not resolver_data[victim] then
        player_manager.init_player_data(victim)
    end
    
    local data = resolver_data[victim]
    
    -- Update hit statistics
    data.hit_shots = (data.hit_shots or 0) + 1
    data.round_hits = (data.round_hits or 0) + 1
    data.last_hit_time = globals.realtime()
    data.consecutive_misses = 0 -- Reset consecutive misses
    
    -- Update confidence based on hit
    if data.last_confidence then
        data.last_confidence = math.min(0.95, data.last_confidence * 1.1)
    end
    
    -- Track hitbox and damage for analysis
    local hitbox = e.hitgroup
    local damage = e.dmg_health
    
    -- Record if it's a headshot
    if hitbox == 1 then
        session_stats.headshots = session_stats.headshots + 1
    end
    
    -- Update session stats
    session_stats.total_hits = session_stats.total_hits + 1
    session_stats.total_shots = session_stats.total_shots + 1
    session_stats.success_rate = session_stats.total_hits / session_stats.total_shots
    
    -- Add hit record to history
    table.insert(data.hit_history, {
        time = globals.realtime(),
        angle = data.last_resolve_angle,
        hitbox = hitbox,
        damage = damage,
        confidence = data.last_confidence
    })
    
    -- Trim hit history if needed
    if #data.hit_history > CONSTANTS.MAX_SHOT_HISTORY then
        table.remove(data.hit_history, 1)
    end
    
    -- Update last resolved angle status in history
    if #data.resolved_angles > 0 then
        data.resolved_angles[#data.resolved_angles].hit = true
    end
    
    -- Calculate success rate
    if data.hit_shots + data.missed_shots > 0 then
        data.resolution_success_rate = data.hit_shots / (data.hit_shots + data.missed_shots)
    end
    
    -- Update ML model if prediction is enabled
    if ui.get(ui_components.prediction.enable) then
        -- Get the actual desync value that worked
        local desync_amount, direction = animation_analyzer.detect_desync(victim)
        ml_system.train_model(victim, desync_amount, direction, true)
    end
    
    -- Log the hit
    logger:log_hit(victim, hitbox, damage)
    logger:log_resolver(victim, "hit", string.format(
        "Angle: %.1f° | Confidence: %.1f%% | Success Rate: %.1f%%",
        data.last_resolve_angle or 0,
        (data.last_confidence or 0.5) * 100,
        data.resolution_success_rate * 100
    ))
end)
    
    local function update_ui_visibility()
        local resolver_enabled = ui.get(ui_components.main.enable)
        
        -- Main components
        ui.set_visible(ui_components.main.master_switch, resolver_enabled)
        ui.set_visible(ui_components.main.mode, resolver_enabled)
        ui.set_visible(ui_components.main.base_confidence, resolver_enabled)
        ui.set_visible(ui_components.main.presets, resolver_enabled)
        
        -- Only show modules if resolver is enabled
        if not resolver_enabled then
            -- Hide all other components if main toggle is disabled
            ui.set_visible(ui_components.prediction.enable, false)
            ui.set_visible(ui_components.prediction.ml_features, false)
            ui.set_visible(ui_components.prediction.gru_layers, false)
            ui.set_visible(ui_components.prediction.units_per_layer, false)
            ui.set_visible(ui_components.prediction.prediction_depth, false)
            
            ui.set_visible(ui_components.animation.enable, false)
            ui.set_visible(ui_components.animation.animation_features, false)
            ui.set_visible(ui_components.animation.desync_detection, false)
            
            ui.set_visible(ui_components.network.enable, false)
            ui.set_visible(ui_components.network.backtrack_options, false)
            ui.set_visible(ui_components.network.network_conditions, false)
            ui.set_visible(ui_components.network.tick_optimization, false)
            
            ui.set_visible(ui_components.exploits.enable, false)
            ui.set_visible(ui_components.exploits.detect_exploits, false)
            ui.set_visible(ui_components.exploits.countermeasures, false)
            
            ui.set_visible(ui_components.optimization.enable, false)
            ui.set_visible(ui_components.optimization.hitbox_priority, false)
            ui.set_visible(ui_components.optimization.accuracy_boost, false)
            
            ui.set_visible(ui_components.debug.enable, false)
            ui.set_visible(ui_components.debug.visualize, false)
            ui.set_visible(ui_components.debug.extended_logging, false)
            ui.set_visible(ui_components.debug.log_to_file, false)
            ui.set_visible(ui_components.debug.debug_level, false)
            
            ui.set_visible(ui_components.appearance.colors.high_confidence, false)
            ui.set_visible(ui_components.appearance.colors.medium_confidence, false)
            ui.set_visible(ui_components.appearance.colors.low_confidence, false)
            
            return
        end
        
        -- Module headers
        ui.set_visible(ui_components.prediction.enable, true)
        ui.set_visible(ui_components.animation.enable, true)
        ui.set_visible(ui_components.network.enable, true)
        ui.set_visible(ui_components.exploits.enable, true)
        ui.set_visible(ui_components.optimization.enable, true)
        ui.set_visible(ui_components.debug.enable, true)
        
        -- Prediction module
        local prediction_enabled = ui.get(ui_components.prediction.enable)
        ui.set_visible(ui_components.prediction.ml_features, prediction_enabled)
        ui.set_visible(ui_components.prediction.gru_layers, prediction_enabled)
        ui.set_visible(ui_components.prediction.units_per_layer, prediction_enabled)
        ui.set_visible(ui_components.prediction.prediction_depth, prediction_enabled)
        
        -- Animation module
        local animation_enabled = ui.get(ui_components.animation.enable)
        ui.set_visible(ui_components.animation.animation_features, animation_enabled)
        ui.set_visible(ui_components.animation.desync_detection, animation_enabled)
        
        -- Network module
        local network_enabled = ui.get(ui_components.network.enable)
        ui.set_visible(ui_components.network.backtrack_options, network_enabled)
        ui.set_visible(ui_components.network.network_conditions, network_enabled)
        ui.set_visible(ui_components.network.tick_optimization, network_enabled)
        
        -- Exploits module
        local exploits_enabled = ui.get(ui_components.exploits.enable)
        ui.set_visible(ui_components.exploits.detect_exploits, exploits_enabled)
        ui.set_visible(ui_components.exploits.countermeasures, exploits_enabled)
        
        -- Optimization module
        local optimization_enabled = ui.get(ui_components.optimization.enable)
        ui.set_visible(ui_components.optimization.hitbox_priority, optimization_enabled)
        ui.set_visible(ui_components.optimization.accuracy_boost, optimization_enabled)
        
        -- Debug module
        local debug_enabled = ui.get(ui_components.debug.enable)
        ui.set_visible(ui_components.debug.visualize, debug_enabled)
        ui.set_visible(ui_components.debug.extended_logging, debug_enabled)
        ui.set_visible(ui_components.debug.log_to_file, debug_enabled)
        ui.set_visible(ui_components.debug.debug_level, debug_enabled)
        
        -- Appearance settings
        local color_pickers_visible = debug_enabled
        ui.set_visible(ui_components.appearance.colors.high_confidence, color_pickers_visible)
        ui.set_visible(ui_components.appearance.colors.medium_confidence, color_pickers_visible)
        ui.set_visible(ui_components.appearance.colors.low_confidence, color_pickers_visible)
    end
    
    -- Consolidated apply_preset function
    local function apply_preset(preset_name)
        -- Apply settings based on preset
        local preset_settings = {
            ["Default"] = {
                -- Default settings, do nothing
            },
            ["Maximum Accuracy"] = {
                mode = "Maximum Accuracy",
                base_confidence = 75,
                prediction = true,
                animation = true,
                network = true,
                exploits = true,
                gru_layers = 3,
                units_per_layer = 48,
                prediction_depth = 4,
                hitbox_priority = "HEAD",
                ml_features = {"Movement Analysis", "Pattern Recognition", "Velocity Prediction", "Shot History Analysis", "Angle Correlation"},
                animation_features = {"Sequence Tracking", "Desync Detection", "Real-time Validation", "Animation Layer Analysis"},
                detect_exploits = {"Double Tap", "Fake Lag", "Extended Desync", "Defensive AA"},
                countermeasures = {"Auto Adapt", "Force Backtrack", "Safe Point"}
            },
            ["Performance Priority"] = {
                mode = "Performance",
                base_confidence = 60,
                prediction = true,
                animation = false,
                network = true,
                exploits = false,
                gru_layers = 1,
                units_per_layer = 16,
                prediction_depth = 2,
                hitbox_priority = "BODY",
                ml_features = {"Movement Analysis", "Pattern Recognition"},
                network_conditions = {"Ping Compensation"}
            },
            ["Legit AA Focus"] = {
                mode = "Balanced",
                base_confidence = 50,
                prediction = true,
                animation = true,
                network = true,
                exploits = false,
                gru_layers = 2,
                units_per_layer = 32,
                prediction_depth = 3,
                hitbox_priority = "SMART",
                animation_features = {"Desync Detection", "Real-time Validation"}
            },
            ["HvH Aggressive"] = {
                mode = "Aggressive",
                base_confidence = 90,
                prediction = true,
                animation = true,
                network = true,
                exploits = true,
                gru_layers = 2,
                units_per_layer = 48,
                prediction_depth = 3,
                detect_exploits = {"Double Tap", "Fake Lag", "Extended Desync", "Defensive AA"},
                countermeasures = {"Auto Adapt", "Force Backtrack", "Safe Point"},
                backtrack_options = {"Smart Selection", "Priority Targets"}
            },
            ["Matchmaking Optimized"] = {
                mode = "Hybrid AI/ML",
                base_confidence = 70,
                prediction = true,
                animation = true,
                network = true,
                exploits = true,
                gru_layers = 2,
                units_per_layer = 32,
                prediction_depth = 3,
                hitbox_priority = "SMART",
                network_conditions = {"Ping Compensation", "Packet Loss Detection"},
                detect_exploits = {"Extended Desync", "Defensive AA"}
            },

        ["Domination"] = {
            -- Optimal settings for maximum headshots and kill efficiency
            mode = "Hybrid AI/ML", -- Best blend of accuracy and performance
            base_confidence = 85, -- High base confidence for snappy decisions
            prediction = true,
            animation = true,
            network = true,
            exploits = true,
            optimization = true, -- Enable optimization module
            reaction_time = true, -- Enable improved reaction time
            
            -- ML model optimization for better predictions
            gru_layers = 3,
            units_per_layer = 56,
            prediction_depth = 5,
            ml_features = {"Movement Analysis", "Pattern Recognition", "Velocity Prediction", "Shot History Analysis", "Angle Correlation"},
            
            -- Animation analysis for more accurate desync detection
            animation_features = {"Sequence Tracking", "Desync Detection", "Real-time Validation", "Animation Layer Analysis", "Eye Position Tracking"},
            desync_detection = "Full Analysis",
            
            -- Network for better backtracking
            backtrack_options = {"Smart Selection", "Priority Targets", "Shot Validation", "Record Optimization"},
            network_conditions = {"Ping Compensation", "Packet Loss Detection", "Choke Analysis", "Jitter Correction"},
            tick_optimization = true,
            
            -- Exploit detection and countermeasures
            detect_exploits = {"Double Tap", "Fake Lag", "Extended Desync", "Defensive AA", "Duck Exploits", "Teleport"},
            countermeasures = {"Auto Adapt", "Force Backtrack", "Safe Point", "Shot Delay", "Spread Reduction"},
            
            -- Optimization for more headshots
            hitbox_priority = "HEAD",
            accuracy_boost = 85,
            
            -- Reaction time optimization
            reaction_mode = "Adaptive",
            reaction_time_ms = 30,
            prefire = true,
            prefire_predictability = 75,
            shot_anticipation = true,
            priority_targets = {"High Threat", "Low HP", "Weapon Type", "Distance Based"}
        }
    }
        
        local settings = preset_settings[preset_name] or preset_settings["Default"]
        
        -- Apply settings to UI
        if settings.mode then ui.set(ui_components.main.mode, settings.mode) end
        if settings.base_confidence then ui.set(ui_components.main.base_confidence, settings.base_confidence) end
        
        -- Toggle modules
        if settings.prediction ~= nil then ui.set(ui_components.prediction.enable, settings.prediction) end
        if settings.animation ~= nil then ui.set(ui_components.animation.enable, settings.animation) end
        if settings.network ~= nil then ui.set(ui_components.network.enable, settings.network) end
        if settings.exploits ~= nil then ui.set(ui_components.exploits.enable, settings.exploits) end
        
        -- Set ML parameters
        if settings.gru_layers then ui.set(ui_components.prediction.gru_layers, settings.gru_layers) end
        if settings.units_per_layer then ui.set(ui_components.prediction.units_per_layer, settings.units_per_layer) end
        if settings.prediction_depth then ui.set(ui_components.prediction.prediction_depth, settings.prediction_depth) end
        
        -- Set optimization settings
        if settings.hitbox_priority then ui.set(ui_components.optimization.hitbox_priority, settings.hitbox_priority) end
        
        -- Set multiselect options
        if settings.ml_features then 
            ui.set(ui_components.prediction.ml_features, settings.ml_features)
        end
        
        if settings.animation_features then
            ui.set(ui_components.animation.animation_features, settings.animation_features)
        end
        
        if settings.backtrack_options then
            ui.set(ui_components.network.backtrack_options, settings.backtrack_options)
        end
        
        if settings.network_conditions then
            ui.set(ui_components.network.network_conditions, settings.network_conditions)
        end
        
        if settings.detect_exploits then 
            ui.set(ui_components.exploits.detect_exploits, settings.detect_exploits)
        end
        
        if settings.countermeasures then
            ui.set(ui_components.exploits.countermeasures, settings.countermeasures)
        end
        
        -- Update UI visibility after applying preset
        update_ui_visibility()
        
        -- Log preset application
        logger:log(string.format("Applied preset: %s", preset_name), 1)
    end
    
    
    -- Console command handler
    client.set_event_callback("console_input", function(cmd)
        if cmd:match("^resolver") then
            local args = {}
            for arg in cmd:gmatch("%S+") do
                table.insert(args, arg)
            end
            
            -- Check resolver stats
            if args[2] == "stats" then
                local total_hits = session_stats.total_hits
                local total_misses = session_stats.total_misses
                local success_rate = (total_hits + total_misses > 0) and (total_hits / (total_hits + total_misses)) or 0.5
                
                print("=== RecodeResolver Statistics ===")
                print(string.format("Hits: %d | Misses: %d | Success Rate: %.1f%%", 
                    total_hits, total_misses, success_rate))
                print(string.format("Headshots: %d (%.1f%% of hits)", 
                    session_stats.headshots, 
                    total_hits > 0 and (session_stats.headshots / total_hits * 100) or 0))
                print(string.format("Rounds Played: %d | Players Tracked: %d", 
                    session_stats.rounds_played, session_stats.players_tracked))
                print("===============================")
                return true
            
            -- Reset resolver data
            elseif args[2] == "reset" then
                for player, _ in pairs(resolver_data) do
                    player_manager.reset_player_data(player, false)
                end
                print("Resolver data has been reset for all players")
                return true
                
            -- Toggle debug mode
            elseif args[2] == "debug" then
                local enabled = not ui.get(ui_components.debug.enable)
                ui.set(ui_components.debug.enable, enabled)
                print("Resolver debug mode: " .. (enabled and "ON" or "OFF"))
                return true
                
            -- Apply preset
            elseif args[2] == "preset" and args[3] then
                local preset_name = args[3]:gsub("_", " ")
                apply_preset(preset_name)  -- Changed from resolver.apply_preset to apply_preset
                print("Applied preset: " .. preset_name)
                return true
                
            -- Show help
            elseif args[2] == "help" or not args[2] then
                print("=== RecodeResolver Commands ===")
                print("resolver stats - Show resolver statistics")
                print("resolver reset - Reset all resolver data")
                print("resolver debug - Toggle debug mode")
                print("resolver preset <name> - Apply a preset")
                print("resolver help - Show this help")
                print("===============================")
                return true
            end
        end
    end)

  
    

    -- Properly define the register_ui_callbacks function if needed
        local function register_ui_callbacks()
            -- Set up UI callbacks
            ui.set_callback(ui_components.main.enable, update_ui_visibility)
            ui.set_callback(ui_components.prediction.enable, update_ui_visibility)
            ui.set_callback(ui_components.animation.enable, update_ui_visibility)
            ui.set_callback(ui_components.network.enable, update_ui_visibility)
            ui.set_callback(ui_components.exploits.enable, update_ui_visibility)
            ui.set_callback(ui_components.optimization.enable, update_ui_visibility)
            ui.set_callback(ui_components.debug.enable, update_ui_visibility)
            
            -- Preset callback
            ui.set_callback(ui_components.main.presets, function()
                local preset_name = ui.get(ui_components.main.presets)
                apply_preset(preset_name)
            end)
        end

    local load_success = false
    local function safe_init()
        -- Wrap the entire initialization in pcall to catch errors
        local success, error_message = pcall(function()
            -- Initialize the resolver
            local function init()
                -- Update UI visibility
                update_ui_visibility()
                
                -- Register all UI callbacks
                register_ui_callbacks() -- Make sure this function is defined before it's called
                
                -- Initialize logger
                logger:init()
                
                -- Log initialization
                logger:log(string.format("RecodeResolver v%s initialized", RESOLVER_VERSION), 1)
                client.color_log(0, 255, 0, string.format("[RecodeResolver] v%s loaded successfully. Type 'resolver help' for commands.", RESOLVER_VERSION))
                print(string.format("[RecodeResolver] v%s loaded successfully. Type 'resolver help' for commands.", RESOLVER_VERSION))
            end
            
            -- Run initialization
            init()
            
            -- Shutdown handler
            client.set_event_callback("shutdown", function()
                -- Close log file
                logger:close()
                
                -- Clean up data
                resolver_data = {}
                ml_models = {}
            end)
            
            load_success = true
        end)
        
        if not success then
            -- Log the error to console if initialization failed
            client.color_log(255, 0, 0, "[RecodeResolver] Failed to initialize: " .. tostring(error_message))
            print("[RecodeResolver] Failed to initialize: " .. tostring(error_message))
        end
    end

    safe_init()
-- Add a console command to check if script loaded properly
client.set_event_callback("console_input", function(cmd)
    if cmd:match("^resolver_status$") then
        if load_success then
            client.color_log(0, 255, 0, "[RecodeResolver] Script is loaded and running.")
        else
            client.color_log(255, 0, 0, "[RecodeResolver] Script failed to initialize properly.")
        end
        return true
    end
end)



    -- Initialize the resolver
    local function init()
        -- Update UI visibility
        update_ui_visibility()
        
        -- Initialize logger
        logger:init()
        
        -- Log initialization
        logger:log(string.format("RecodeResolver v%s initialized", RESOLVER_VERSION), 1)
        print(string.format("[RecodeResolver] v%s loaded successfully. Type 'resolver help' for commands.", RESOLVER_VERSION))
    end
    
    -- Run initialization
    init()
    
    -- Shutdown handler
    client.set_event_callback("shutdown", function()
        -- Close log file
        logger:close()
        
        -- Clean up data
        resolver_data = {}
        ml_models = {}
    end)