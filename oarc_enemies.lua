-- oarc_enemies.lua
-- Oarc Sep 2018
-- My crude attempts at changing enemy experience.

-- General ideas for this mod:
--  No attacks are started on a player's stuff while they are offline.
--  Spawners don't send out attack groups based on pollution anymore.
--  Research complete generates attacks (except first few maybe)
--      Attacks target your science buildings.
--  Silo built and rocket launch generate attacks
--      Attacks target your silos.
--  Regular attacks based on a randomized timer
--      Attack pollution sources / players
--  Random attacks on radars or other military targets
--  Very very random attacks on tall power poles that are near train train tracks :)
--  Attack size/evo are based on a force's tech level,
--      number of players on the team,
--      and pollution in the target area.
--  There will still be some kind of incentive to clearing out bases,
--      attacks might still come from spawners, so if you're on an island you could be safe.

-- Attack Evo determined by (tech level and time):
--      player online time (at 20 hours, evo + 0.5)
--      tech level (at 200 techlevels done, evo + 1.0)
-- Attack Count determined by (local pollution levels + tech):
--      pollution in target chunk (+10 * chunk pollution / 1000) (capped at 50?)
--      tech level (+10 * techlevels / 40) (capped at 50?)
-- Attack frequency determined by (activity):
--      Raw resources being mined
--      Key items being produced (iron plates / copper plates / circuits / steel)
-- If lots of buildings destroyed:
--      Scale back evo and size limits temporarily. Some kind of backoff?

-- Required Includes
require("lib/oarc_utils")
require("oarc_enemy_evo")


-- Settings

-- Max number of ongoing attacks at any time.
OE_ATTACKS_MAX = 50

-- Group size
-- Scales with playtime, tech level, pollution in target chunk
OE_ATTACK_MIN_SIZE = 1
OE_ATTACK_MAX_SIZE = 100

-- At 20 hours, evo is +x. Scales linearly with time.
-- Overall evo is also capped by playtime
OE_PLAYER_ONLINE_TIME_EVO_FACTOR = 0.4
OE_PLAYER_ONLINE_TIME_PEAK_HOURS = 20

-- At 5000 pollution in target chunk, evo is +x. Scales linearly with pollution in chunk
OE_POLLUTION_EVO_FACTOR = 0.4
OE_POLLUTION_PEAK_AMOUNT = 5000

-- At 200 techlevels, evo is +x. Scales linearly with tech completed.
OE_TECH_LEVEL_EVO_FACTOR = 0.6
OE_TECH_LEVEL_PEAK_COUNT = 200

-- Number of chunks around any building that don't allow enemy spawns.
OE_BUILDING_SAFE_AREA_RADIUS = 4

-- Attack timer, scales with activity (mining and smelting)
OE_MAX_TIME_BETWEEN_ATTACKS_MINS = 30
OE_MIN_TIME_BETWEEN_ATTACKS_MINS = 3

-- Timer backoff on destroyed buildings
-- Evo backoff on destroyed buildings
-- OE_BUILDING_DESTROYED_EVO_REDUCTION ??
-- OE_BUILDING_DESTROYED_TIMER_BACKOFF = ??

-- How far away can attacks start from.
OE_ATTACK_SEARCH_RADIUS_CHUNKS = 40


-- These are the types of targetted attacks that can be requested.
OE_TARGET_TYPE_SCIENCE      = 0     -- Attack random science labs.
OE_TARGET_TYPE_MINERS       = 1     -- Attack random miners.
OE_TARGET_TYPE_PLAYER       = 2     -- Attack a player.
OE_TARGET_TYPE_SMELTERS     = 3     -- Attack a random smelters.
OE_TARGET_TYPE_STEAM        = 4     -- Attack a steam power production
OE_TARGET_TYPE_NUCLEAR      = 5     -- Attack a nuclear power production
OE_TARGET_TYPE_SOLAR        = 6     -- Attack a solar power production
OE_TARGET_TYPE_ASSMBLR      = 7     -- Attack assembly machines
OE_TARGET_TYPE_SILO         = 8     -- Attack a rocket silo
OE_TARGET_TYPE_PWR_POLE     = 9     -- Attack the tall power poles
OE_TARGET_TYPE_TURRETS      = 10    -- Attack turrets (gun/laser/flame)
OE_TARGET_TYPE_RADAR        = 11    -- Attack radars
OE_TARGET_TYPE_ARTY         = 12    -- Attack artillery (trains/turrets)
OE_TARGET_TYPE_DSTRYD       = 13    -- Attack areas where buildings are being destroyed (reinforce)
OE_TARGET_TYPE_AREA         = 14    -- Attacking a general area is used as a fallback.

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


-- Just set the target player and type, and then the processing takes over
-- and attempts to create an attack...
-- attack_request_example = {
--      target_player=player_name,  -- REQUIRED (Player Name)
--      target_type=TYPE,           -- REQUIRED (OE_ATTACK_TYPE)
--      attempts=3,                 -- REQUIRED (Must be at least 1! Otherwise it won't do anything.)
--      process_stg=TYPE,           -- STARTS WITH OE_PROCESS_STG_FIND_TARGET
--      target_entity=lua_entity,   -- Depends on attack type. Calculated during request processing.
--      target_chunk=c_pos,         -- Depends on attack type. Calculated during request processing.
--      size=x,                     -- Calculated during request processing.
--      evo=x,                      -- Calculated during request processing.
--      spawn_chunk=spawn_chunk,    -- Calculated during request processing.
--      path_id=path_request_id,    -- Set during request processing.
--      path=path,                  -- Set by on_script_path_request_finished.
--      group_id=group_id,          -- Set during request processing.
--      group=lua_unit_group        -- The group created to handle the attack
-- }


-- Adapted from:
-- https://stackoverflow.com/questions/3706219/algorithm-for-iterating-over-an-outward-spiral-on-a-discrete-2d-grid-from-the-or
function SpiralSearch(starting_c_pos, max_radius, check_function)

    local dx = 1
    local dy = 0
    local segment_length = 1

    local x = starting_c_pos.x
    local y = starting_c_pos.y
    local segment_passed = 0

    for i=1,(math.pow(max_radius*2+1, 2)) do

        if (true == check_function({x=x, y=y})) then
            game.forces["player"].add_chart_tag(game.surfaces[1],
                                                {position={x=x*32 + 16, y=y*32 + 16},
                                                text=x..","..y})
                                                -- icon={type="item",name="rocket-silo"}})
            SendBroadcastMsg("SpiralSearch: " .. x .. "," .. y)
            return {x=x, y=y}
        end

        x = x + dx;
        y = y + dy;
        segment_passed  = segment_passed + 1

        if (segment_passed == segment_length) then

            segment_passed = 0

            local buffer = dx
            dx = -dy;
            dy = buffer

            if (dy == 0) then
                segment_length  = segment_length + 1
            end
        end
    end

    SendBroadcastMsg("SpiralSearch Failed? " .. x .. "," .. y)
    return nil
end


function OarcEnemiesForceCreated(event)
    if (not event.force) then return end
    global.oarc_enemies.tech_levels[event.force.name] = 0
end

function CountForceTechCompleted(force)
    if (not force.technologies) then
        SendBroadcastMsg("CountForceTechCompleted needs a valid force please.")
        return 0
    end

    local tech_done = 0
    for name,tech in pairs(force.technologies) do
        if tech.researched then
            tech_done = tech_done + 1
        end
    end

    return tech_done
end

-- type = mining-drill
-- type = furnace
-- type = reactor
-- type = solar-panel
-- type = assembling-machine
-- type = generator

-- burner-mining-drill
-- electric-mining-drill
-- pumpjack

-- nuclear-reactor
-- solar-panel
-- assembling-machine-1
-- assembling-machine-2
-- assembling-machine-3
-- centrifuge
-- chemical-plant
-- escape-pod-assembler
-- oil-refinery

-- electric-furnace
-- steel-furnace
-- stone-furnace


function InitOarcEnemies()

    global.oarc_enemies = {}

    global.oarc_enemies.chunk_map = {}
    global.oarc_enemies.chunk_map.min_x = 0
    global.oarc_enemies.chunk_map.max_x = 0
    global.oarc_enemies.chunk_map.x_index = 0
    global.oarc_enemies.chunk_map.min_y = 0
    global.oarc_enemies.chunk_map.max_y = 0
    global.oarc_enemies.chunk_map.y_index = 0

    -- global.oarc_enemies.groups = {}
    -- global.oarc_enemies.units = {}

    global.oarc_enemies.buildings = {}
    global.oarc_enemies.tech_levels = {}

    global.oarc_enemies.player_timers = {}

    -- Ongoing attacks
    global.oarc_enemies.attacks = {}


    -- Copied from wave defense
    -- game.map_settings.path_finder.use_path_cache = false
    -- game.map_settings.path_finder.max_steps_worked_per_tick = 1000
    -- game.map_settings.path_finder.max_clients_to_accept_any_new_request = 5000
    -- game.map_settings.path_finder.ignore_moving_enemy_collision_distance = 0
    -- game.map_settings.short_request_max_steps = 1000000
    -- game.map_settings.short_request_ratio = 1
    -- game.map_settings.max_failed_behavior_count = 2
    -- game.map_settings.steering.moving.force_unit_fuzzy_goto_behavior = true
    -- game.map_settings.steering.moving.radius = 6
    -- game.map_settings.steering.moving.separation_force = 0.02
    -- game.map_settings.steering.moving.separation_factor = 8
    -- game.map_settings.steering.default.force_unit_fuzzy_goto_behavior = true
    -- game.map_settings.steering.default.radius = 1
    -- game.map_settings.steering.default.separation_force = 0.01
    -- game.map_settings.steering.default.separation_factor  = 1

    -- CalculateEvoChanceList(0.3)
end

-- Track each force's amount of research completed.
function OarcEnemiesResearchFinishedEvent(event)
    if not (event.research and event.research.force) then return end

    local force_name = event.research.force.name
    if (global.oarc_enemies.tech_levels[force_name] == nil) then
        global.oarc_enemies.tech_levels[force_name] = 1
    else
        global.oarc_enemies.tech_levels[force_name] = global.oarc_enemies.tech_levels[force_name] + 1
    end

    -- Trigger an attack on science!
    OarcEnemiesScienceLabAttack(event.research.force.name)
end

-- Attack science labs!
function OarcEnemiesScienceLabAttack(force_name)

    -- For each player, find a random science lab,
    for _,player in pairs(game.connected_players) do
        if (player.force.name == force_name) and
            (global.oarc_enemies.buildings[player.name]["lab"]) and
            (#global.oarc_enemies.buildings[player.name]["lab"] > 0) then

            local science_attack = {target_player = player.name,
                                    target_type = OE_TARGET_TYPE_SCIENCE,
                                    attempts=3,
                                    process_stg=OE_PROCESS_STG_FIND_TARGET}
            SendBroadcastMsg("Science Lab Attack!")
            table.insert(global.oarc_enemies.attacks, science_attack)
        end
    end
end

-- Attack a player
function OarcEnemiesPlayerAttack(player_name)

    -- Validation checks.
    if (not game.players[player_name] or
        not game.players[player_name].connected or
        not game.players[player_name].character or
        not game.players[player_name].character.valid) then
        SendBroadcastMsg("OarcEnemiesPlayerAttack - player invalid or not connected?")
        return
    end

    -- Create the attack request
    local player_attack =   {target_player = player_name,
                                target_type = OE_TARGET_TYPE_PLAYER,
                                attempts=3,
                                process_stg=OE_PROCESS_STG_FIND_TARGET}
    SendBroadcastMsg("Player Attack!")
    table.insert(global.oarc_enemies.attacks, player_attack)
end

-- First time player init stuff
function OarcEnemiesPlayerCreatedEvent(event)
    if (game.players[event.player_index] == nil) then return end
    local p_name = game.players[event.player_index].name

    if (global.oarc_enemies.player_timers[p_name] == nil) then
        global.oarc_enemies.player_timers[p_name] = OE_MAX_TIME_BETWEEN_ATTACKS_MINS*60
    end

    if (global.oarc_enemies.buildings[p_name] == nil) then
        global.oarc_enemies.buildings[p_name] = {}
    end

    local force = game.players[event.player_index].force
    if (global.oarc_enemies.tech_levels[force.name] == nil) then
        global.oarc_enemies.tech_levels[force.name] = CountForceTechCompleted(force)
    end

    SendBroadcastMsg("OarcEnemiesPlayerCreatedEvent " .. p_name)
end

function OarcEnemiesChunkGenerated(event)
    if (not event.area or not event.area.left_top) then
        log("OarcEnemiesChunkGenerated - ERROR")
        return
    end

    local c_pos = GetChunkPosFromTilePos(event.area.left_top)

    local enough_land = true

    -- Check if there is lots of water
    local water_tiles = game.surfaces[1].find_tiles_filtered{area = event.area, collision_mask = "water-tile", limit=200}
    if (#water_tiles > 200) then
        enough_land = false
    end

    -- Check if it has spawners
    local spawners = game.surfaces[1].find_entities_filtered{area=event.area,
                                                                name={"biter-spawner",
                                                                "spitter-spawner"},
                                                                type="unit-spawner",
                                                                force="enemy"}

    -- If this is the first chunk in that row:
    if (global.oarc_enemies.chunk_map[c_pos.x] == nil) then
        global.oarc_enemies.chunk_map[c_pos.x] = {}
    end

    -- Save chunk settings.
    global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] = {player_building=false,
                                                        near_building=false,
                                                        valid_spawn=enough_land,
                                                        enemy_spawners=spawners}

    -- Store min/max values for x/y dimensions:
    if (c_pos.x < global.oarc_enemies.chunk_map.min_x) then
        global.oarc_enemies.chunk_map.min_x = c_pos.x
    end
    if (c_pos.x > global.oarc_enemies.chunk_map.max_x) then
        global.oarc_enemies.chunk_map.max_x = c_pos.x
    end
    if (c_pos.y < global.oarc_enemies.chunk_map.min_y) then
        global.oarc_enemies.chunk_map.min_y = c_pos.y
    end
    if (c_pos.y > global.oarc_enemies.chunk_map.max_y) then
        global.oarc_enemies.chunk_map.max_y = c_pos.y
    end

end

-- function OarcEnemiesChunkDeleted(event)
--     if (not event.positions) then
--         log("OarcEnemiesChunkDeleted - ERROR")
--         return
--     end

--     for chunk in event.positions do
--         if (global.oarc_enemies.chunk_map[c_pos.x] ~= nil) then
--             if (global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] ~= nil) then
--                 global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] = nil
--             end
--         end
--     end
-- end

function OarcEnemiesChunkIsNearPlayerBuilding(c_pos)
    if (global.oarc_enemies.chunk_map[c_pos.x] == nil) then
        global.oarc_enemies.chunk_map[c_pos.x] = {}
    end
    if (global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] == nil) then
        global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] = {player_building=false, near_building=true, valid_spawn=true}
    else
        global.oarc_enemies.chunk_map[c_pos.x][c_pos.y].near_building = true
    end
end

function OarcEnemiesChunkHasPlayerBuilding(position)
    local c_pos = GetChunkPosFromTilePos(position)

    for i=-OE_BUILDING_SAFE_AREA_RADIUS,OE_BUILDING_SAFE_AREA_RADIUS do
        for j=-OE_BUILDING_SAFE_AREA_RADIUS,OE_BUILDING_SAFE_AREA_RADIUS do
            OarcEnemiesChunkIsNearPlayerBuilding({x=c_pos.x+i,y=c_pos.y+j})
        end
    end

end

function OarcEnemiesIsChunkValidSpawn(c_pos)

    -- Chunk should exist.
    if (game.surfaces[1].is_chunk_generated(c_pos) == false) then
        return false
    end

    -- Check entry exists.
    if (global.oarc_enemies.chunk_map[c_pos.x] == nil) then
        return false
    end
    if (global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] == nil) then
        return false
    end

    -- Get entry
    local chunk = global.oarc_enemies.chunk_map[c_pos.x][c_pos.y]

    -- Check basic flags
    if (chunk.player_building or chunk.near_building or not chunk.valid_spawn) then
        return false
    end

    -- Check for spawners
    if (not chunk.enemy_spawners or (#chunk.enemy_spawners == 0)) then
        return false
    end

    -- Check visibility
    for _,force in pairs(game.forces) do
        if (force.name ~= "enemy") then
            if (force.is_chunk_visible(game.surfaces[1], c_pos)) then
                return false
            end
        end
    end

    return true
end

function OarcEnemiesTrackBuildings(e)

    SendBroadcastMsg("Building type: " .. e.type)

    if (e.type == "lab") or
        (e.type == "mining-drill") or
        (e.type == "furnace") or
        (e.type == "reactor") or
        (e.type == "solar-panel") or
        (e.type == "assembling-machine") or
        (e.type == "generator") then

        if (e.last_user == nil) then
            SendBroadcastMsg("OarcEnemiesTrackBuildings - entity.last_user is nil! " .. e.name)
            return
        end

        if (global.oarc_enemies.buildings[e.last_user.name] == nil) then
            global.oarc_enemies.buildings[e.last_user.name] = {}
        end

        if (global.oarc_enemies.buildings[e.last_user.name][e.type] == nil) then
            global.oarc_enemies.buildings[e.last_user.name][e.type] = {}
        end

        table.insert(global.oarc_enemies.buildings[e.last_user.name][e.type], e)

    end
end

function TestSpawnGroup()

    local surface = game.surfaces[1]
    local group_position = {x=50, y=50}

    local chance_list = CalculateEvoChanceListBiters(0.3)

    units = {}
    for i=1,5 do
        table.insert(units, GetEnemyFromChanceList(chance_list))
    end

    group = CreateEnemyGroup(surface, group_position, units)

end

function GetRandomScienceLab(player_name)

    if (#global.oarc_enemies.buildings[player_name]["lab"] == 0) then
        SendBroadcastMsg("GetRandomScienceLab - none found")
        return nil
    end

    local rand_key = GetRandomKeyFromTable(global.oarc_enemies.buildings[player_name]["lab"])
    local random_lab = global.oarc_enemies.buildings[player_name]["lab"][rand_key]

    if (not random_lab or not random_lab.valid) then
        global.oarc_enemies.buildings[player_name]["lab"][rand_key] = nil
        return GetRandomScienceLab(player_name)
    else
        return random_lab
    end
end


function ProcessAttackFindTarget(key, attack)

    if (attack.process_stg ~= OE_PROCESS_STG_FIND_TARGET) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ATTACK FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    if (attack.target_player and
        attack.target_type) then

        -- OE_TARGET_TYPE_SCIENCE
        -- OE_TARGET_TYPE_MINERS
        -- OE_TARGET_TYPE_PLAYER
        -- OE_TARGET_TYPE_SMELTERS
        -- OE_TARGET_TYPE_STEAM
        -- OE_TARGET_TYPE_NUCLEAR
        -- OE_TARGET_TYPE_SOLAR
        -- OE_TARGET_TYPE_ASSMBLR
        -- OE_TARGET_TYPE_SILO
        -- OE_TARGET_TYPE_PWR_POLE
        -- OE_TARGET_TYPE_TURRETS
        -- OE_TARGET_TYPE_RADAR
        -- OE_TARGET_TYPE_ARTY
        -- OE_TARGET_TYPE_DSTRYD

        -- Attack a science lab of the player.
        if (attack.target_type == OE_TARGET_TYPE_SCIENCE) then

            local random_lab = GetRandomScienceLab(attack.target_player)
            if (random_lab ~= nil) then
                global.oarc_enemies.attacks[key].target_entity = random_lab
                global.oarc_enemies.attacks[key].size = 10
                global.oarc_enemies.attacks[key].evo = 0.3
                global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_SPAWN
                return true
            else
                SendBroadcastMsg("No labs found to attack.")
                global.oarc_enemies.attacks[key] = nil
            end

        -- Attack a player directly
        elseif (attack.target_type == OE_TARGET_TYPE_PLAYER) then
            global.oarc_enemies.attacks[key].target_entity = game.players[attack.target_player].character
            global.oarc_enemies.attacks[key].size = 15
            global.oarc_enemies.attacks[key].evo = 0.1
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_SPAWN
            return true
        end

    else
        SendBroadcastMsg("Missing info in attack or no retry atempts remaining!" .. key)
    end

    return false
end

function ProcessAttackFindSpawn(key, attack)

    if (attack.process_stg ~= OE_PROCESS_STG_FIND_SPAWN) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ProcessAttackFindSpawn FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    if (attack.target_entity or attack.target_chunk) then

        -- Invalid entity check?
        if (attack.target_entity and not attack.target_entity.valid) then
            global.oarc_enemies.attacks[key].target_entity = nil
            global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_TARGET
            return false
        end

        -- Use entity or target chunk info to start search
        local c_pos
        if (attack.target_entity) then
            c_pos = GetChunkPosFromTilePos(attack.target_entity.position)
            global.oarc_enemies.attacks[key].target_chunk = c_pos -- ALWAYS SET FOR BACKUP
        elseif (attack.target_chunk) then
            c_pos = attack.target_chunk
        end
        local spawn = SpiralSearch(c_pos, OE_ATTACK_SEARCH_RADIUS_CHUNKS, OarcEnemiesIsChunkValidSpawn)

        if (spawn ~= nil) then
            global.oarc_enemies.attacks[key].spawn_chunk = spawn
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_SPAWN_PATH_REQ
        else
            SendBroadcastMsg("Could not find a spawn near target...")
            global.oarc_enemies.attacks[key].target_entity = nil
            global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_TARGET
        end

        return true
    else
        SendBroadcastMsg("Missing attack info: target_entity or target_chunk!" .. key)
    end

    return false
end

function ProcessAttackCheckPathFromSpawn(key, attack)

    if (attack.process_stg ~= OE_PROCESS_STG_SPAWN_PATH_REQ) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ProcessAttackCheckPathFromSpawn FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    if (attack.spawn_chunk) then

        -- Check group doesn't already exist
        if (attack.group and attack.group_id and attack.group.valid) then
            SendBroadcastMsg("ERROR - group should not be valid - ProcessAttackCheckPathFromSpawn!")
            global.oarc_enemies.attacks[key] = nil
            return false
        end

        local spawn_pos = game.surfaces[1].find_non_colliding_position("rocket-silo",
                                                                GetCenterTilePosFromChunkPos(attack.spawn_chunk),
                                                                32,
                                                                1)
        global.oarc_enemies.attacks[key].spawn_pos = spawn_pos


        local target_pos = nil
        if (attack.target_entity and attack.target_entity.valid) then
            target_pos = attack.target_entity.position
        elseif (attack.target_chunk) then
            target_pos = GetCenterTilePosFromChunkPos(attack.target_chunk)
        end

        if (not target_pos) then
            SendBroadcastMsg("Lost target during ProcessAttackCheckPathFromSpawn")
            global.oarc_enemies.attacks[key].target_entity = nil
            global.oarc_enemies.attacks[key].target_chunk = nil
            global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_TARGET
            return false
        end

        global.oarc_enemies.attacks[key].path_id = game.surfaces[1].request_path{bounding_box={{0,0},{0,0}},
                                                        collision_mask={"player-layer"},
                                                        start=spawn_pos,
                                                        goal=attack.target_entity.position,
                                                        force=game.forces["enemy"],
                                                        radius=8,
                                                        pathfind_flags={low_priority=true},
                                                        can_open_gates=false,
                                                        path_resolution_modifier=-1}
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_SPAWN_PATH_CALC
        return true
    else
        SendBroadcastMsg("Missing attack info: spawn_chunk or path_id!" .. key)
    end

    return false
end

function ProcessAttackCheckPathComplete(event)
    if (not event.id) then return end
    local path_success = (event.path ~= nil)

    -- Debug help info
    if (path_success) then
        SendBroadcastMsg("on_script_path_request_finished: " .. #event.path)
        RenderPath(event.path, TICKS_PER_MINUTE*5, game.connected_players)
    else
        SendBroadcastMsg("on_script_path_request_finished: FAILED")
        if (event.try_again_later) then
            SendBroadcastMsg("on_script_path_request_finished: TRY AGAIN LATER?")
        end
    end

    for key,attack in pairs(global.oarc_enemies.attacks) do
        if (attack.path_id == event.id) then

            local group_exists_already = (attack.group and attack.group_id and attack.group.valid)

            -- First time path check before a group is spawned
            if (attack.process_stg == OE_PROCESS_STG_SPAWN_PATH_CALC) then
                if (group_exists_already) then
                    SendBroadcastMsg("ERROR - OE_PROCESS_STG_SPAWN_PATH_CALC has a valid group?!")
                    -- attack.group.set_autonomous()
                end

                if (path_success) then
                    global.oarc_enemies.attacks[key].path = event.path
                    global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_CREATE_GROUP
                else
                    global.oarc_enemies.attacks[key].path_id = nil
                    global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
                    global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_TARGET
                end

            -- Retry path check on a command failure
            elseif  (attack.process_stg == OE_PROCESS_STG_RETRY_PATH_CALC) then

                if (not group_exists_already) then
                    SendBroadcastMsg("ERROR - OE_PROCESS_STG_RETRY_PATH_CALC has NO valid group?!")
                end

                if (path_success) then
                    global.oarc_enemies.attacks[key].path = event.path
                    global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_CMD_GROUP
                else
                    SendBroadcastMsg("Group can no longer path to target. Performing fallback attack instead" .. attack.group.group_id)
                    -- attack.group.set_autonomous()
                    global.oarc_enemies.attacks[key].path_id = nil
                    global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
                    global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FALLBACK_ATTACK
                end

            else
                SendBroadcastMsg("Path calculated but process stage is wrong!??!")
            end

            return
        end
    end
end

function ProcessAttackCreateGroup(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_CREATE_GROUP) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ProcessAttackCreateGroup FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    if (attack.group_id == nil) then
        local group = CreateEnemyGroupGivenEvoAndCount(game.surfaces[1],
                                                        attack.spawn_pos,
                                                        attack.evo,
                                                        attack.size)
        global.oarc_enemies.attacks[key].group_id = group.group_number
        global.oarc_enemies.attacks[key].group = group
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_CMD_GROUP

        if (attack.target_type == OE_TARGET_TYPE_PLAYER) then
            DisplaySpeechBubble(game.players[attack.target_player],
                                "Uh oh... Something is coming!", 10)
        end

        return true
    else
        SendBroadcastMsg("ERROR - ProcessAttackCreateGroup already has a group?" .. key)
    end

    return false
end

function ProcessAttackCommandGroup(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_CMD_GROUP) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ProcessAttackCommandGroup FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    -- Sanity check we have a group and a path
    if (attack.group_id and attack.path_id and attack.group and attack.group.valid) then

        if (attack.target_entity and attack.target_entity.valid) then
            -- EnemyGroupAttackEntity(attack.group, attack.target_entity)
            EnemyGroupAttackEntityCompoundCmd(attack.group, attack.target_entity, attack.path)
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_GROUP_ACTIVE
            return true

        elseif (attack.target_chunk) then
            EnemyGroupAttackArea(attack.group,
                                    GetCenterTilePosFromChunkPos(attack.target_chunk),
                                    48)
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_GROUP_ACTIVE
            return true

        else
            SendBroadcastMsg("ProcessAttackCommandGroup invalid target?" .. key)
            global.oarc_enemies.attacks[key].path_id = nil
            global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_TARGET
            return false
        end
    else
        SendBroadcastMsg("ProcessAttackCommandGroup invalid group or path?" .. key)
    end

    return false
end

function ProcessAttackCommandFailed(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_CMD_FAILED) then return false end

    if (attack.attempts == 0) then
        SendBroadcastMsg("attack.attempts = 0 - ProcessAttackCommandFailed FAILURE")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    -- If we fail to attack the player, it like means the player moved.
    -- So we try to retry pathing so we can "chase" the player.
    if (attack.target_type == OE_TARGET_TYPE_PLAYER) then
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_RETRY_PATH_REQ
        return true

    -- Fallback for all other attack types is to attack the general area instead.
    -- Might add other special cases here later.
    else
        SendBroadcastMsg("ProcessAttackCommandFailed - performing fallback now " .. event.unit_number)
        global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FALLBACK_ATTACK
        return true
    end

    return false
end

function ProcessAttackFallbackAttack(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_FALLBACK_ATTACK) then return false end

    if (attack.group_id and attack.group and attack.group.valid and attack.target_chunk) then

        EnemyGroupAttackArea(attack.group,
                              GetCenterTilePosFromChunkPos(attack.target_chunk),
                              CHUNK_SIZE*2)
        global.oarc_enemies.attacks[key].target_type = OE_TARGET_TYPE_AREA
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_GROUP_ACTIVE
    else
        SendBroadcastMsg("ProcessAttackFallbackAttack invalid group or target?" .. key)
    end

    return false

end

function ProcessAttackFallbackAuto(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_FALLBACK_FINAL) then return false end

    if (attack.group and attack.group.valid) then
        SendBroadcastMsg("ProcessAttackFallbackAuto - Group now autonomous...")
        attack.group.set_autonomous()
    else
        SendBroadcastMsg("ProcessAttackFallbackAuto - Group no longer valid!")
    end

    global.oarc_enemies.attacks[key] = nil

    return false
end

function ProcessAttackRetryPath(key, attack)

    if (attack.process_stg ~= OE_PROCESS_STG_RETRY_PATH_REQ) then return false end

    -- Validation checks
    if ((attack.target_type ~= OE_TARGET_TYPE_PLAYER) or
        (attack.attempts == 0) or
        (not attack.target_entity) or
        (not attack.target_entity.valid)) then
        SendBroadcastMsg("ProcessAttackRetryPath FAILURE")
        if (attack.group and attack.group.valid) then
            attack.group.set_autonomous()
        end
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    -- Check group still exists
    if (attack.group and attack.group_id and attack.group.valid) then

        -- Path request
        global.oarc_enemies.attacks[key].path_id =
            game.surfaces[1].request_path{bounding_box={{0,0},{0,0}},
                                            collision_mask={"player-layer"},
                                            start=attack.group.members[1].position,
                                            goal=attack.target_entity.position,
                                            force=game.forces["enemy"],
                                            radius=8,
                                            pathfind_flags={low_priority=true},
                                            can_open_gates=false,
                                            path_resolution_modifier=-1}
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_RETRY_PATH_CALC
        return true

    else
        SendBroadcastMsg("ERROR - group should BE valid - ProcessAttackRetryPath!")
        global.oarc_enemies.attacks[key] = nil
        return false
    end

    return false
end

function ProcessAttackCleanupInvalidGroups(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_GROUP_ACTIVE) then return false end

    if (not attack.group or not attack.group.valid) then
        SendBroadcastMsg("ProcessAttackCleanupInvalidGroups - Group finished?")
        global.oarc_enemies.attacks[key] = nil
    end

    return false
end

function OarcEnemiesOnTick()

    -- Cleanup attacks that have died or somehow become invalid.
    if ((game.tick % (TICKS_PER_SECOND)) == 20) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCleanupInvalidGroups(key, attack) then break end
        end
    end

    -- Randomized player timers generating attacks
    -- if ((game.tick % (TICKS_PER_SECOND)) == 32) then

    --     for name,timer in pairs(global.oarc_enemies.player_timers) do
    --         if (global.oarc_enemies["lab"][name] ~= nil) and
    --             (#global.oarc_enemies["lab"][name] > 0) then
    --             if (timer <= 0) then
    --                 SendBroadcastMsg("Attack now?!")
    --                 attack_example = {target=game.player,
    --                                     size=10,
    --                                     evo=0.1,
    --                                     spawn_chunk=nil,
    --                                     group_id=nil,
    --                                     path=nil}
    --                 table.insert(global.oarc_enemies.attacks, attack_example)

    --                 global.oarc_enemies.player_timers[name] = 30 -- CHANGE THIS TO SOMETHING RANDOM?
    --             else
    --                 global.oarc_enemies.player_timers[name] = timer - 1
    --             end
    --         end
    --     end

    -- end


    -- OE_PROCESS_STG_FIND_TARGET
    -- Find target given request type
    if ((game.tick % (TICKS_PER_SECOND)) == 23) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackFindTarget(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_FIND_SPAWN
    -- Find spawn location
    if ((game.tick % (TICKS_PER_SECOND)) == 23) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackFindSpawn(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_SPAWN_PATH_REQ
    -- Find path
    if ((game.tick % (TICKS_PER_SECOND)) == 24) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCheckPathFromSpawn(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_SPAWN_PATH_CALC -- WAIT FOR EVENT

    -- OE_PROCESS_STG_CREATE_GROUP
    -- Spawn group
    if ((game.tick % (TICKS_PER_SECOND)) == 25) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCreateGroup(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_CMD_GROUP
    -- Send group on attack
    if ((game.tick % (TICKS_PER_SECOND)) == 26) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCommandGroup(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_GROUP_ACTIVE -- ACTIVE STATE, WAIT FOR EVENT

    -- OE_PROCESS_STG_CMD_FAILED
    -- Handle failed groups?
    if ((game.tick % (TICKS_PER_SECOND)) == 27) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCommandFailed(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_FALLBACK_ATTACK
    -- Attempt fallback attack on general area of target
    if ((game.tick % (TICKS_PER_SECOND)) == 28) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackFallbackAttack(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_FALLBACK_FINAL
    -- Final fallback just abandons attack and sets the group to autonomous
    if ((game.tick % (TICKS_PER_SECOND)) == 29) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackFallbackAuto(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_RETRY_PATH_REQ
    -- Handle pathing retries
    if ((game.tick % (TICKS_PER_SECOND)) == 30) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackRetryPath(key, attack) then break end
        end
    end

    -- OE_PROCESS_STG_RETRY_PATH_CALC -- WAIT FOR EVENT

    -- Every minute
    if ((game.tick % (TICKS_PER_MINUTE/2)) == 40) then

        -- if (#global.oarc_enemies.groups < 5) then
        --     -- TestSpawnGroup()
        -- end

    end

    -- Every hour
    if ((game.tick % (TICKS_PER_HOUR)) == 50) then

    end

end

function OarcEnemiesGroupCmdFailed(event)
    local attack_key = FindAttackKeyFromGroupIdNumber(event.unit_number)

    -- This group cmd failure is not associated with an attack. Must be a unit or something.
    if (not attack_key) then return end

    local attack = global.oarc_enemies.attacks[attack_key]

    -- Is group no longer valid?
    if (not attack.group or not attack.group.valid) then
        global.oarc_enemies.attacks[attack_key] = nil
        return
    end

    -- Check if it's a fallback attack.
    if (attack.target_type == OE_TARGET_TYPE_AREA) then
        global.oarc_enemies.attacks[attack_key].process_stg = OE_PROCESS_STG_FALLBACK_FINAL

    -- Else handle failure based on attack type.
    else
        global.oarc_enemies.attacks[attack_key].process_stg = OE_PROCESS_STG_CMD_FAILED
    end
end

function CreateEnemyGroupGivenEvoAndCount(surface, position, evo, count)

    local chance_list = CalculateEvoChanceListBiters(evo)

    local enemy_units = {}
    for i=1,count do
        table.insert(enemy_units, GetEnemyFromChanceList(chance_list))
    end

    return CreateEnemyGroup(surface, position, enemy_units)
end


-- Create an enemy group at given position, with array of unit names provided.
function CreateEnemyGroup(surface, position, units)

    -- Create new group at given position
    local new_enemy_group = surface.create_unit_group{position = position}

    -- Attempt to spawn all units nearby
    for k,biter_name in pairs(units) do
        local unit_position = surface.find_non_colliding_position(biter_name, position, 32, 2)
        if (unit_position) then
            new_unit = surface.create_entity{name = biter_name, position = unit_position}
            new_enemy_group.add_member(new_unit)
            -- table.insert(global.oarc_enemies.units, new_unit)
        end
    end

    -- table.insert(global.oarc_enemies.groups, new_enemy_group)

    -- Return the new group
    return new_enemy_group
end


function OarcEnemiesGroupCreatedEvent(event)
    SendBroadcastMsg("Unit group created: " .. event.group.group_number)
    -- if (global.oarc_enemies.groups == nil) then
    --     global.oarc_enemies.groups = {}
    -- end
    -- if (global.oarc_enemies.groups[event.group.group_number] == nil) then
    --     global.oarc_enemies.groups[event.group.group_number] = event.group
    -- else
    --     SendBroadcastMsg("A group with this ID was already created???" .. event.group.group_number)
    -- end
end

function FindAttackKeyFromGroupIdNumber(id)

    for key,attack in pairs(global.oarc_enemies.attacks) do
        if (attack.group_id and (attack.group_id == id)) then
            return key
        end
    end

    return nil
end

-- Tell a group AND ALL THE UNITS to follow a given command
function EnemyGroupUnitsDoCommand(group, new_cmd)

    if ((group == nil) or (not group.valid)) then
        SendBroadcastMsg("EnemyGroupUnitsDoCommand - Invalid group!")
        return
    end

    -- Give the group it's command
    group.set_command(new_cmd)

    -- -- Tell all contained units to follow the group command
    -- local unit_cmd = {type = defines.command.group, group = group, distraction = defines.distraction.none}
    -- for i,u in ipairs(group.members) do
    --     u.set_command(unit_cmd)
    -- end
end

-- Tell a unit group to attack a given area
function EnemyGroupAttackArea(group, destination, radius)
    local attack_area_cmd = {type = defines.command.attack_area, destination = destination, radius = radius, distraction = defines.distraction.damage}
    EnemyGroupUnitsDoCommand(group, attack_area_cmd)
end

function EnemyGroupAttackEntity(group, target)
    local attack_entity_cmd = {type = defines.command.attack, target = target, distraction = defines.distraction.damage}
    EnemyGroupUnitsDoCommand(group, attack_entity_cmd)
end

function EnemyGroupAttackEntityCompoundCmd(group, target, path)

    if ((group == nil) or (target == nil)) then
        SendBroadcastMsg("EnemyGroupAttackEntityCompoundCmd - Invalid group/target!")
        return
    end

    local distraction = defines.distraction.by_damage

    -- Add all the waypoints in order I hope.
    local waypoint_cmds = {}
    if (#path > 200) then
        local i = 200
        while (path[i] ~= nil) do
            table.insert(waypoint_cmds, {type = defines.command.go_to_location,
                                        destination = path[i].position,
                                        distraction = distraction})
            i = i + 200
        end
    end


    -- Last step is the attacking of the target
    local attack_entity_cmd =
    {
        type = defines.command.attack,
        target = target,
        distraction = distraction
    }

    local wander_cmd =
    {
        type = defines.command.wander,
        -- wander_in_group = false,
        -- ticks_to_wait = 60*10,
        distraction = distraction
    }

    -- A build a base command
    local build_base =
    {
        type = defines.command.build_base,
        destination = {0,0},
        distraction = distraction,
        ignore_planner = true
    }

    table.insert(waypoint_cmds, attack_entity_cmd)
    table.insert(waypoint_cmds, wander_cmd)
    -- table.insert(waypoint_cmds, build_base)

    -- Make this a compound command that attempts to execute all commands?
    local move_attack_comp_cmd =
    {
        type = defines.command.compound,
        -- structure_type = defines.compound_command.logical_and,
        structure_type = defines.compound_command.return_last,
        commands = waypoint_cmds
    }



    local fallback_comp_cmd =
    {
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = {
            move_attack_comp_cmd,
            build_base
        }
    }

    EnemyGroupUnitsDoCommand(group, move_attack_comp_cmd)
end


-- Tell a unit group to just do it's normal attack run at the closest pollution source.
function EnemyGroupDefaultBehavior(group)
    group.set_autonomous()
end





-- local group
-- local comp_cmd =    {
--                         type = defines.command.compound,
--                         structure_type = defines.compound_command.return_last,
--                         commands =
--                         {
--                             {type = defines.command.attack_area, destination = {x=-50, y=-50}, radius = 10, distraction = defines.distraction.none},
--                             {type = defines.command.wander, distraction = defines.distraction.none}
--                         }
--                     }
-- local group_cmd = {type = defines.command.go_to_location, destination = {x=-50, y=-50}, distraction = defines.distraction.none}



-- commands.add_command("spawn_group", "spawn a group", function(command)

--     local surface = game.surfaces[1]
--     local group_position = {x=50, y=50}
--     local biter_name = "small-biter"

--     group = surface.create_unit_group{position = group_position}

--     for i=1,10 do
--         local unit_position = surface.find_non_colliding_position(biter_name, group_position, 32, 2)
--         if (unit_position) then
--             group.add_member(surface.create_entity{name = biter_name, position = unit_position})
--         end
--     end
-- end)


-- commands.add_command("kill_group", "kill a group", function(command)
--     if (group ~= nil) then
--         group.destroy()
--     end
-- end)

-- commands.add_command("move_group", "move a group", function(command)

--     if (group ~= nil) then
--         group.set_command(comp_cmd)

--         local unit_cmd = {type = defines.command.group, group = group, distraction = defines.distraction.none}

--         for i,u in ipairs(group.members) do
--             u.set_command(unit_cmd)
--         end

--     end


-- end)

-- commands.add_command("group_info", "info about a group", function(command)
--     if (group) then
--         game.player.print(group.position)
--         game.player.print(group.state)
--     end
-- end)

