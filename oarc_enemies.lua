-- oarc_enemies.lua
-- Oarc Sep 2018
-- My crude attempts at changing enemy experience.


-- This is what an attack request should look like:
-- attack_request_example = {
--      target_player=player_name,      -- REQUIRED (Player Name)
--      target_type=TYPE,               -- REQUIRED (OE_ATTACK_TYPE)
--      attempts=3,                     -- REQUIRED (Must be at least 1! Otherwise it won't do anything.)
--      process_stg=TYPE,               -- REQUIRED (Normally starts with OE_PROCESS_STG_FIND_TARGET)
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
            -- game.forces["player"].add_chart_tag(game.surfaces[1],
            --                                     {position={x=x*32 + 16, y=y*32 + 16},
            --                                     text=x..","..y})
            --                                     -- icon={type="item",name="rocket-silo"}})
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
        log("ERROR - CountForceTechCompleted needs a valid force please.")
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

function InitOarcEnemies()
    global.oarc_enemies = {}

    -- We store a map of chunks to help figure out good spawn locations
    global.oarc_enemies.chunk_map = {}

    -- Keep track of groups so we know when we are done with them (abandoned)
    global.oarc_enemies.groups = {}
    -- global.oarc_enemies.units = {}

    -- Keep track of a player's buildings
    global.oarc_enemies.buildings = {}

    -- Keep track of force tech levels
    global.oarc_enemies.tech_levels = {}

    -- Each player has a timer for semi-regular attacks.
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
end

-- Track each force's amount of research completed.
function OarcEnemiesResearchFinishedEvent(event)
    if not (event.research and event.research.force) then return end

    local force_name = event.research.force.name
    if (global.oarc_enemies.tech_levels[force_name] == nil) then
        global.oarc_enemies.tech_levels[force_name] = CountForceTechCompleted(game.forces[force_name])
    else
        global.oarc_enemies.tech_levels[force_name] = global.oarc_enemies.tech_levels[force_name] + 1
    end

    -- Trigger an attack on science!
    OarcEnemiesScienceLabAttack(event.research.force.name)
end

-- Attack science labs of a given force!
function OarcEnemiesScienceLabAttack(force_name)
    -- For each player (connected only), find a random science lab,
    for _,player in pairs(game.connected_players) do
        if (player.force.name == force_name) then
            OarcEnemiesBuildingAttack(player.name, "lab")
        end
    end
end

-- Request an attack on a given player's building type.
function OarcEnemiesBuildingAttack(player_name, entity_type)
    -- Make sure player exists and is connected.
    if (not game.players[player_name] or
        not game.players[player_name].connected) then return end

    local building_attack = {target_player = player_name,
                            target_type = OE_TARGET_TYPE_BUILDING,
                            attempts=3,
                            process_stg=OE_PROCESS_STG_FIND_TARGET,
                            building_types=entity_type}
    SendBroadcastMsg("Building Attack Request: " .. serpent.block(entity_type))
    table.insert(global.oarc_enemies.attacks, building_attack)
end

-- Attack a player's character
function OarcEnemiesPlayerAttack(player_name)

    -- Validation checks.
    if (not game.players[player_name] or
        not game.players[player_name].connected or
        not game.players[player_name].character or
        not game.players[player_name].character.valid) then
        SendBroadcastMsg("OarcEnemiesPlayerAttack - player not connected or is dead?")
        return
    end

    -- Create the attack request
    local player_attack = {target_player = player_name,
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
        global.oarc_enemies.player_timers[p_name] = oe_params.minutes_between_attacks_max*60
    end

    if (global.oarc_enemies.buildings[p_name] == nil) then
        global.oarc_enemies.buildings[p_name] = {}
    end

    local force = game.players[event.player_index].force
    if (global.oarc_enemies.tech_levels[force.name] == nil) then
        global.oarc_enemies.tech_levels[force.name] = CountForceTechCompleted(force)
    end
end

function OarcEnemiesChunkGenerated(event)
    if (not event.area or not event.area.left_top) then
        log("OarcEnemiesChunkGenerated - ERROR")
        return
    end

    local c_pos = GetChunkPosFromTilePos(event.area.left_top)

    local enough_land = true

    -- Check if there is any water in the chunk.
    local water_tiles = event.surface.find_tiles_filtered{area = event.area, collision_mask = "water-tile", limit=5}
    if (#water_tiles >= 5) then
        enough_land = false
    end

    -- Check if it has spawners
    local spawners = event.surface.find_entities_filtered{area=event.area,
                                                                type={"unit-spawner", "turret"},
                                                                force="enemy"}

    -- If this is the first chunk in that row:
    if (global.oarc_enemies.chunk_map[c_pos.x] == nil) then
        global.oarc_enemies.chunk_map[c_pos.x] = {}
    end

    -- Save chunk info.
    global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] = {player_building=false,
                                                        near_building=false,
                                                        valid_spawn=enough_land,
                                                        enemy_spawners=spawners}
end

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

function OarcEnemiesEntityDiedEvent(event)

    -- Validate
    if (not event.entity or
        not (event.entity.force.name == "enemy") or
        not (event.cause or event.force)) then return end

    -- Enemy spawners/turrets
    if (not (event.entity.type == "unit-spawner")) and
        (not (event.entity.type == "turret")) then return end

    local death_attack = {attempts=1,
                            spawn_chunk=GetChunkPosFromTilePos(event.entity.position)}

    -- If there is just a force, then just attack the area.
    if (not event.cause) then
        SendBroadcastMsg("Spawner died ONLY FORCE!")

        death_attack.process_stg = OE_PROCESS_STG_CREATE_GROUP
        death_attack.spawn_pos = event.entity.position
        -- death_attack.target_player = nil
        death_attack.target_type = OE_TARGET_TYPE_AREA
        death_attack.target_chunk = GetChunkPosFromTilePos(event.entity.position)

        death_attack.evo,death_attack.size = GetEnemyGroup{player=nil,
                                                force_name=event.force.name,
                                                surface=game.surfaces[1],
                                                target_position=event.entity.position,
                                                min_size=8,min_evo=0.25}


    -- If we have a cause, go attack that cause.
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

        death_attack.process_stg = OE_PROCESS_STG_SPAWN_PATH_REQ
        death_attack.target_player = player.name
        death_attack.target_type = OE_TARGET_TYPE_ENTITY
        death_attack.target_entity = event.cause
        death_attack.target_chunk = GetChunkPosFromTilePos(player.character.position)

        death_attack.evo,death_attack.size = GetEnemyGroup{player=player,
                                                force_name=event.force.name,
                                                surface=game.surfaces[1],
                                                target_position=event.entity.position,
                                                min_size=8,min_evo=0.25}
    end

    SendBroadcastMsg("Spawner died 4!")

    if (event.entity.type == "unit-spawner") then
        SendBroadcastMsg("Spawner died!")
    elseif (event.entity.type == "turret") then
        SendBroadcastMsg("Worm died!")
    end

    table.insert(global.oarc_enemies.attacks, death_attack)
end


function OarcEnemiesTrackBuildings(e)

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
    if (global.oarc_enemies.groups == nil) then
        global.oarc_enemies.groups = {}
    end
    if (global.oarc_enemies.groups[event.group.group_number] == nil) then
        global.oarc_enemies.groups[event.group.group_number] = event.group
    else
        SendBroadcastMsg("A group with this ID was already created???" .. event.group.group_number)
    end
end

function OarcEnemiesUnitRemoveFromGroupEvent(event)
    SendBroadcastMsg("Unit removed from group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)

    -- Force the unit back into its group
    if ((global.oarc_enemies.groups[event.group.group_number] ~= nil) and
        event.group and
        event.group.valid) then
        event.group.add_member(event.unit)
    end
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
                                        distraction = defines.distraction.by_enemy})

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
                                        distraction = defines.distraction.by_enemy})

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