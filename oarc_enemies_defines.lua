-- oarc_enemies_defines.lua
-- Aug 2019
-- Settings and general definitions and stuff.



-- Max number of ongoing attacks at any time.
OE_ATTACKS_MAX = 50

-- Number of chunks around any building that don't allow enemy spawns.
OE_BUILDING_SAFE_AREA_RADIUS = 4

-- Attack timer, scales with activity? (mining and smelting)
OE_MAX_TIME_BETWEEN_ATTACKS_MINS = 30
OE_MIN_TIME_BETWEEN_ATTACKS_MINS = 3

-- Timer backoff on destroyed buildings
-- Evo backoff on destroyed buildings
-- OE_BUILDING_DESTROYED_EVO_REDUCTION ??
-- OE_BUILDING_DESTROYED_TIMER_BACKOFF = ??

-- How far away can attacks start from.
OE_ATTACK_SEARCH_RADIUS_CHUNKS = 40

-- These are the types of targetted attacks that can be requested.
OE_TARGET_TYPE_PLAYER       = 1     -- Attack a player.
OE_TARGET_TYPE_AREA         = 2     -- Attacking a general area is used as a fallback.
OE_TARGET_TYPE_BUILDING     = 3     -- Attack a building of a certain type.
OE_TARGET_TYPE_DSTRYD       = 4     -- Attack areas where buildings are being destroyed (reinforce)
OE_TARGET_TYPE_ENTITY       = 5     -- Any attack on a specific entity. Like a retaliation attack.

-- This is the general flow of steps that an attack will go through
OE_PROCESS_STG_FIND_TARGET      = 0     -- First step is finding a target based on the request type.
OE_PROCESS_STG_FIND_SPAWN       = 1     -- Find a nearby spawn
OE_PROCESS_STG_SPAWN_PATH_REQ   = 2     -- Request a check if it's pathable FROM THE SPAWN POSITION
OE_PROCESS_STG_SPAWN_PATH_CALC  = 3     -- Pathing is pending from OE_PROCESS_STG_SPAWN_PATH_REQ
OE_PROCESS_STG_CREATE_GROUP     = 4     -- Create the group
OE_PROCESS_STG_CMD_GROUP        = 5     -- Command the group
OE_PROCESS_STG_GROUP_ACTIVE     = 6     -- Group is actively executing a command
OE_PROCESS_STG_CMD_FAILED       = 7     -- Group is now in a failed state, retry or fallback.
OE_PROCESS_STG_FALLBACK_ATTACK  = 8     -- Fallback to attacking local area
OE_PROCESS_STG_FALLBACK_FINAL   = 9     -- Final fallback is go autonomous
OE_PROCESS_STG_RETRY_PATH_REQ   = 10    -- This means we had a group, that failed during transit, so we want to retry path checks.
OE_PROCESS_STG_RETRY_PATH_CALC  = 11    -- Pathing is pending from OE_PROCESS_STG_RETRY_PATH_REQ
OE_PROCESS_STG_BUILD_BASE       = 12    -- Sometimes we build bases. Like if an attack was successful.

-- These control all evo/size scaling and stuff.
oe_params = {
    attack_size_min = 1,
    attack_size_max = 150,

    player_time_evo_factor = 0.4,
    player_time_size_factor = 50,
    player_time_peak_hours = 20,

    pollution_evo_factor = 0.4,
    pollution_size_factor = 50,
    pollution_peak_amnt = 5000,

    tech_evo_factor = 0.6,
    tech_size_factor = 50,
    tech_peak_count = 200,

    rand_evo_amnt = 0.15, -- Up to + this amount
    rand_size_amnt = 8, -- Up to + this amount

    minutes_between_attacks_min = 3,
    minutes_between_attacks_max = 30,
}