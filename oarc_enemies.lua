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
OE_MAX_TIME_BETWEEN_ATTACKS_MINS = 60
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

-- Just set the target player and type, and then the processing takes over
-- and attempts to create an attack...
-- attack_request_example = {
--      target_player=player_name,      -- REQUIRED (Player Name)
--      target_type=TYPE,               -- REQUIRED (OE_ATTACK_TYPE)
--      attempts=3,                     -- REQUIRED (Must be at least 1! Otherwise it won't do anything.)
--      process_stg=TYPE,               -- REQUIRED STARTS WITH OE_PROCESS_STG_FIND_TARGET
--      building_types=entity_types,    -- REQUIRED if attack request is for a building.
--      target_entity=lua_entity,       -- Depends on attack type. Calculated during request processing.
--      target_chunk=c_pos,             -- Depends on attack type. Calculated during request processing.
--      size=x,                         -- Calculated during request processing.
--      evo=x,                          -- Calculated during request processing.
--      spawn_chunk=spawn_chunk,        -- Calculated during request processing.
--      path_id=path_request_id,        -- Set during request processing.
--      path=path,                      -- Set by on_script_path_request_finished.
--      group_id=group_id,              -- Set during request processing.
--      group=lua_unit_group            -- The group created to handle the attack
-- }


-- Adapted from:
-- https://stackoverflow.com/questions/3706219/algorithm-for-iterating-over-an-outward-spiral-on-a-discrete-2d-grid-from-the-or
function SpiralSearch(starting_c_pos, max_radius, max_count, check_function)

    local dx = 1
    local dy = 0
    local segment_length = 1

    local x = starting_c_pos.x
    local y = starting_c_pos.y
    local segment_passed = 0

    local found = {}

    for i=1,(math.pow(max_radius*2+1, 2)) do

        if (true == check_function({x=x, y=y})) then
            game.forces["player"].add_chart_tag(game.surfaces[1],
                                                {position={x=x*32 + 16, y=y*32 + 16},
                                                text=x..","..y})
                                                -- icon={type="item",name="rocket-silo"}})
            SendBroadcastMsg("SpiralSearch: " .. x .. "," .. y)
            table.insert(found, {x=x, y=y})
            if (#found >= max_count) then return found end
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

    if (#found == 0) then
        SendBroadcastMsg("SpiralSearch Failed? " .. x .. "," .. y)
        return nil
    else
        return found
    end
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
        if (player.force.name == force_name) then
            OarcEnemiesBuildingAttack(player.name, "lab")
        end
    end
end

function OarcEnemiesBuildingAttack(player_name, entity_type)
    local building_attack = {target_player = player_name,
                            target_type = OE_TARGET_TYPE_BUILDING,
                            attempts=3,
                            process_stg=OE_PROCESS_STG_FIND_TARGET,
                            building_types=entity_type}
    SendBroadcastMsg("Building Attack: " .. serpent.block(entity_type))
    table.insert(global.oarc_enemies.attacks, building_attack)
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

    -- Check if there is any water in the chunk.
    local water_tiles = game.surfaces[1].find_tiles_filtered{area = event.area, collision_mask = "water-tile", limit=5}
    if (#water_tiles >= 5) then
        enough_land = false
    end

    -- Check if it has spawners
    local spawners = game.surfaces[1].find_entities_filtered{area=event.area,
                                                                type={"unit-spawner", "turret"},
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

-- function OarcEnemiesEntityDiedEvent(event)

--     -- Validate
--     if (not event.entity or
--         not (event.entity.force.name == "enemy") or
--         not (event.cause or event.force)) then return end

--     -- Enemy spawners/turrets
--     if (not (event.entity.type == "unit-spawner")) and
--         (not (event.entity.type == "turret")) then return end

--     local death_attack = {attempts=1,
--                             process_stg=OE_PROCESS_STG_SPAWN_PATH_REQ,
--                             spawn_chunk=GetChunkPosFromTilePos(event.entity.position),
--                             evo=0.5,
--                             size=5}

--     -- If there is just a force, then just attack the area.
--     if (not event.cause) then
--         SendBroadcastMsg("Spawner died ONLY FORCE!")

--         -- death_attack.process_stg = OE_PROCESS_STG_SPAWN_PATH_REQ
--         -- death_attack.target_player = nil
--         death_attack.target_type = OE_TARGET_TYPE_AREA
--         death_attack.target_chunk = GetChunkPosFromTilePos(event.entity.position)
--         death_attack.evo = 0.5
--         death_attack.size = 5

--     -- If we have a cause, go attack that cause.
--     else
--         SendBroadcastMsg("Spawner died HAS CAUSE!")

--         local player = nil
--         if (event.cause.type == "character") then
--             player  = event.cause.player
--         elseif (event.cause.last_user) then
--             player  = event.cause.last_user
--         end

--         -- No attacks on offline player
--         if (not player or not player.connected) then return end

--         -- death_attack.process_stg = OE_PROCESS_STG_CREATE_GROUP
--         -- death_attack.target_player = nil
--         death_attack.target_type = OE_TARGET_TYPE_ENTITY
--         -- death_attack.target_type = OE_TARGET_TYPE_AREA
--         death_attack.target_entity = player.character
--         death_attack.target_chunk = GetChunkPosFromTilePos(player.character.position)
--         death_attack.evo = 0.2
--         death_attack.size = 10
--     end

--     SendBroadcastMsg("Spawner died 4!")

--     if (event.entity.type == "unit-spawner") then
--         SendBroadcastMsg("Spawner died!")
--     elseif (event.entity.type == "turret") then
--         SendBroadcastMsg("Worm died!")
--     end

--     table.insert(global.oarc_enemies.attacks, death_attack)
-- end

function OarcEnemiesEntityDiedEventImmediateAttack(event)

    -- Validate
    if (not event.entity or
        not (event.entity.force.name == "enemy") or
        not (event.cause or event.force)) then return end

    -- Enemy spawners/turrets
    if (not (event.entity.type == "unit-spawner")) and
        (not (event.entity.type == "turret")) then return end

    -- If there is just a force, then just attack the area.
    if (not event.cause) then
        SendBroadcastMsg("Spawner died ONLY FORCE!")


    -- If we have a cause, attack that cause.
    else
        SendBroadcastMsg("Spawner died HAS CAUSE!")

        local player = nil
        if (event.cause.type == "character") then
            player  = event.cause.player
        elseif (event.cause.last_user) then
            player  = event.cause.last_user
        end

        -- No attacks on offline player
        if (not player or not player.connected) then return end

    end
end

function OarcEnemiesTrackBuildings(e)

    SendBroadcastMsg("Building type: " .. e.type)

    if (e.type == "lab") or
        (e.type == "mining-drill") or
        (e.type == "furnace") or
        (e.type == "reactor") or
        (e.type == "solar-panel") or
        (e.type == "assembling-machine") or
        (e.type == "generator") or
        (e.type == "rocket-silo") or
        (e.type == "radar") or
        (e.type == "ammo-turret") or
        (e.type == "electric-turret") or
        (e.type == "fluid-turret") or
        (e.type == "artillery-turret") then

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

function GetRandomBuildingAny(player_name, entity_type_or_types)
    if (type(entity_type_or_types) == "table") then
        return GetRandomBuildingMultipleTypes(player_name, entity_type_or_types)
    else
        return GetRandomBuildingSingleType(player_name, entity_type_or_types)
    end
end

function GetRandomBuildingMultipleTypes(player_name, entity_types)

    local rand_list = {}
    for _,e_type in pairs(entity_types) do
        rand_building = GetRandomBuildingSingleType(player_name, e_type)
        if (rand_building) then
            table.insert(rand_list, rand_building)
        end
    end
    if (#rand_list > 0) then
        return rand_list[math.random(#rand_list)]
    else
        return nil
    end
end

function GetRandomBuildingSingleType(player_name, entity_type, count)

    -- We only use this if there are lots of nil entries, likely from destroyed buildings
    local count = count or 20
    if (count == 0) then
        SendBroadcastMsg("GetRandomBuildingSingleType - recursive limit hit")
        return nil
    end

    if (not global.oarc_enemies.buildings[player_name][entity_type] or
        (#global.oarc_enemies.buildings[player_name][entity_type] == 0)) then
        SendBroadcastMsg("GetRandomBuildingSingleType - none found " .. entity_type)
        return nil
    end

    local rand_key = GetRandomKeyFromTable(global.oarc_enemies.buildings[player_name][entity_type])
    local random_lab = global.oarc_enemies.buildings[player_name][entity_type][rand_key]

    if (not random_lab or not random_lab.valid) then
        global.oarc_enemies.buildings[player_name][entity_type][rand_key] = nil
        return GetRandomBuildingSingleType(player_name, entity_type, count-1)
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


        -- OE_TARGET_TYPE_PLAYER
        -- OE_TARGET_TYPE_DSTRYD
        -- OE_TARGET_TYPE_BUILDING

        -- Attack a building of the player, given a certain building type
        if (attack.target_type == OE_TARGET_TYPE_BUILDING) then

            local random_building = GetRandomBuildingAny(attack.target_player,
                                                            attack.building_types)
            if (random_building ~= nil) then
                global.oarc_enemies.attacks[key].target_entity = random_building
                global.oarc_enemies.attacks[key].size = 10
                global.oarc_enemies.attacks[key].evo = 0.3
                global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_SPAWN
                return true
            else
                SendBroadcastMsg("No building found to attack.")
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
        local spawns = SpiralSearch(c_pos, OE_ATTACK_SEARCH_RADIUS_CHUNKS, 1, OarcEnemiesIsChunkValidSpawn)

        if (spawns ~= nil) then
            global.oarc_enemies.attacks[key].spawn_chunk = spawns[GetRandomKeyFromTable(spawns)]
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
                                                        goal=target_pos,
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
    if (attack.group_id and attack.group and attack.group.valid) then

        -- If we have a target entity, attack that.
        if (attack.target_entity and attack.target_entity.valid and attack.path_id) then
            EnemyGroupGoAttackEntityThenWander(attack.group, attack.target_entity, attack.path)
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_GROUP_ACTIVE
            return true

        -- If we have a target chunk, attack that area.
        elseif (attack.target_chunk) then
            EnemyGroupAttackAreaThenWander(attack.group,
                                            GetCenterTilePosFromChunkPos(attack.target_chunk),
                                            CHUNK_SIZE*2)
            global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_GROUP_ACTIVE
            return true

        -- Otherwise, shit's fucked
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

    -- If we fail to attack the player, it likely means the player moved.
    -- So we try to retry pathing so we can "chase" the player.
    if (attack.target_type == OE_TARGET_TYPE_PLAYER) then
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_RETRY_PATH_REQ
        return true

    -- Fallback for all other attack types is to attack the general area instead.
    -- Might add other special cases here later.
    else
        SendBroadcastMsg("ProcessAttackCommandFailed - performing fallback now?")
        global.oarc_enemies.attacks[key].attempts = attack.attempts - 1
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FALLBACK_ATTACK
        return true
    end

    return false
end

function ProcessAttackFallbackAttack(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_FALLBACK_ATTACK) then return false end

    if (attack.group_id and attack.group and attack.group.valid and attack.target_chunk) then

        EnemyGroupAttackAreaThenWander(attack.group,
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
        -- log(serpent.block(attack))
        log("group-state" .. attack.group.state)
        -- log(serpent.block(attack.group.members))
        log(serpent.block(attack.group_id))
        log("AUTO GAME - TICK: " .. game.tick)
        -- attack.group.set_autonomous()
        attack.group.destroy()
    else
        SendBroadcastMsg("ProcessAttackFallbackAuto - Group no longer valid!")
    end

    global.oarc_enemies.attacks[key] = nil
    return true
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
            -- attack.group.set_autonomous()
            attack.group.destroy()
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
        SendBroadcastMsg("ProcessAttackCleanupInvalidGroups - Group killed?")
        global.oarc_enemies.attacks[key] = nil

    elseif (attack.group.state == defines.group_state.wander_in_group) then
        SendBroadcastMsg("ProcessAttackCleanupInvalidGroups - Group done?")
        EnemyGroupBuildBaseThenWander(attack.group, attack.group.position)
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_BUILD_BASE
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

    -- 21

    -- OE_PROCESS_STG_FIND_TARGET
    -- Find target given request type
    if ((game.tick % (TICKS_PER_SECOND)) == 22) then
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
-- function EnemyGroupUnitsDoCommand(group, new_cmd)

--     if ((group == nil) or (not group.valid)) then
--         SendBroadcastMsg("EnemyGroupUnitsDoCommand - Invalid group!")
--         return
--     end

--     -- Give the group it's command
--     group.set_command(new_cmd)

--     -- -- Tell all contained units to follow the group command
--     -- local unit_cmd = {type = defines.command.group, group = group, distraction = defines.distraction.none}
--     -- for i,u in ipairs(group.members) do
--     --     u.set_command(unit_cmd)
--     -- end
-- end


function EnemyGroupAttackAreaThenWander(group, target_pos, radius)

    if (not group or not group.valid or not target_pos or not radius) then
        SendBroadcastMsg("EnemyGroupAttackAreaThenWander - Missing params!")
        return
    end

    local combined_commands = {}

    -- Attack the target.
    table.insert(combined_commands, {type = defines.command.attack_area,
                                        destination = target_pos,
                                        radius = radius,
                                        distraction = defines.distraction.by_damage})

    -- Then wander and attack anything in the area
    table.insert(combined_commands, {type = defines.command.wander,
                                        distraction = defines.distraction.by_enemy})

    -- Execute all commands in sequence regardless of failures.
    local compound_command =
    {
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = combined_commands
    }

    group.set_command(compound_command)
end

function EnemyGroupGoAttackEntityThenWander(group, target, path)

    if (not group or not group.valid or not target or not path) then
        SendBroadcastMsg("EnemyGroupPathAttandThenWander - Missing params!")
        return
    end

    local combined_commands = {}

    -- Add waypoints for long paths.
    -- Based on number of segments in the path.
    local i = 100
    while (path[i] ~= nil) do
        SendBroadcastMsg("Adding path " .. i)
        table.insert(combined_commands, {type = defines.command.go_to_location,
                                            destination = path[i].position,
                                            pathfind_flags={low_priority=true},
                                            radius = 5,
                                            distraction = defines.distraction.by_damage})
        game.forces["player"].add_chart_tag(game.surfaces[1],
                                            {position=path[i].position,
                                            text="path"})
        i = i + 100
    end

    -- Then attack the target.
    table.insert(combined_commands, {type = defines.command.attack,
                                        target = target,
                                        distraction = defines.distraction.by_damage})

    -- Even if target dies, we should go to it's last known location.
    -- table.insert(combined_commands, {type = defines.command.go_to_location,
    --                                     destination = target.position,
    --                                     pathfind_flags={low_priority=true},
    --                                     radius = 5,
    --                                     distraction = defines.distraction.by_damage})

    -- Then wander and attack anything in the area
    table.insert(combined_commands, {type = defines.command.wander,
                                        distraction = defines.distraction.by_anything})

    -- Execute all commands in sequence regardless of failures.
    local compound_command =
    {
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = combined_commands
    }

    group.set_command(compound_command)
end

function EnemyGroupBuildBaseThenWander(group, target_pos)

    if (not group or not group.valid or not target_pos) then
        SendBroadcastMsg("EnemyGroupBuildBase - Invalid group or missing target!")
        return
    end


    local combined_commands = {}

    -- Build a base
    table.insert(combined_commands, {type = defines.command.build_base,
                                        destination = target_pos,
                                        distraction = defines.distraction.by_damage})

    -- Last resort is wander and attack anything in the area
    table.insert(combined_commands, {type = defines.command.wander,
                                        distraction = defines.distraction.by_anything})

    -- Execute all commands in sequence regardless of failures.
    local compound_command =
    {
        type = defines.command.compound,
        structure_type = defines.compound_command.return_last,
        commands = combined_commands
    }

    group.set_command(compound_command)
end