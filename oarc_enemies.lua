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


-- Required Includes
require("lib/oarc_utils")
require("oarc_enemy_evo")


-- Default Enemy Settings
ENEMY_GROUPS_MAX = 10
ENEMY_GROUP_MIN_SIZE = 5
ENEMY_GROUP_MAX_SIZE = 30

ENEMY_GROUP_SPAWN_TIME_MIN = TICKS_PER_MINUTE*1
ENEMY_GROUP_SPAWN_TIME_MAX = TICKS_PER_MINUTE*5

-- Number of chunks around any building that don't allow enemy spawns.
BUILDING_SAFE_AREA_RADIUS = 4

-- First Attack timer
FIRST_PLAYER_ATTACK_TIMER_SEC = 10

-- Different possible types of enemy targets
-- Target player
-- Target building
-- Target area
-- Target auto


-- Flow
--  Trigger event (research complete, player timer up, silo built, rocket launched, whatever.)
--  Find a spawn area near to the event target
--  Find a path to the event target from the spawn area
--  Spawn a group
--  Move and attack towards target


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

-- If group fails...
--      Delete units?


-- These are the types of attacks that can be requested.
OE_ATTACK_TYPE_SCIENCE  = 0     -- Attack random science labs.
OE_ATTACK_TYPE_MINERS   = 1     -- Attack random miners.
OE_ATTACK_TYPE_PLAYER   = 2     -- Attack a player.
OE_ATTACK_TYPE_SMELTERS = 3     -- Attack a random smelters.
OE_ATTACK_TYPE_STEAM    = 4     -- Attack a steam power production
OE_ATTACK_TYPE_NUCLEAR  = 5     -- Attack a nuclear power production
OE_ATTACK_TYPE_SOLAR    = 6     -- Attack a solar power production
OE_ATTACK_TYPE_ASSMBLR  = 7     -- Attack assembly machines
OE_ATTACK_TYPE_SILO     = 8     -- Attack a rocket silo
OE_ATTACK_TYPE_PWR_POLE = 9     -- Attack the tall power poles
OE_ATTACK_TYPE_TURRETS  = 10    -- Attack turrets (gun/laser/flame)
OE_ATTACK_TYPE_RADAR    = 11    -- Attack radars
OE_ATTACK_TYPE_ARTY     = 12    -- Attack artillery (trains/turrets)
OE_ATTACK_TYPE_DSTRYD   = 13    -- Attack areas where buildings are being destroyed (reinforce)


-- Just set the target player and type, and then the processing takes over
-- and attempts to create an attack...
-- attack_request_example = {
--      target_player=player_name,  -- REQUIRED (Player Name)
--      target_type=TYPE,           -- REQUIRED (OE_ATTACK_TYPE)
--      retry_attempts=3,           -- REQUIRED (If attack fails to be generated, how many times we retry)
--      target_entity=entity,       -- Depends on attack type. Calculated during request processing.
--      target_chunk=c_pos,         -- Depends on attack type. Calculated during request processing.
--      size=x,                     -- Calculated during request processing.
--      evo=x,                      -- Calculated during request processing.
--      spawn_chunk=spawn_chunk,    -- Calculated during request processing.
--      path_id=path_request_id,    -- Set during request processing.
--      path=path,                  -- Set by on_script_path_request_finished.
--      path_success=bool,          -- Set by on_script_path_request_finished.
--      group_id=group_id,          -- Set during request processing.
--      active=false,               -- Set to true while a cmd is active. Set to false after a failure.
-- }

-- Group data
-- {
--     group=lua_group,
--     units={lua_entities...},
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

        -- TAG it on the main force at least.
        -- game.forces["player"].add_chart_tag(game.surfaces[1],
        --                                     {position={x=x*32 + 16, y=y*32 + 16}, text=x..","..y,
        --                                         icon={type="item",name="rocket-silo"}})

        -- if (OarcEnemiesIsChunkValidSpawn({x=x, y=y})) then
        --     SendBroadcastMsg("Spiral Test: " .. x .. "," .. y)
        --     return
        -- end

        -- SendBroadcastMsg("Spiral Test: " .. x .. "," .. y)

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


function OarcEnemiesFindNearestSpawn(target_pos)

    -- Find neareset enemy spawner

    -- Use chunk_map to find nearest candidate?

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




function InitOarcEnemies()
    
    global.oarc_enemies = {}

    global.oarc_enemies.chunk_map = {}
    global.oarc_enemies.chunk_map.min_x = 0
    global.oarc_enemies.chunk_map.max_x = 0
    global.oarc_enemies.chunk_map.x_index = 0
    global.oarc_enemies.chunk_map.min_y = 0
    global.oarc_enemies.chunk_map.max_y = 0
    global.oarc_enemies.chunk_map.y_index = 0

    global.oarc_enemies.groups = {}
    global.oarc_enemies.units = {}

    global.oarc_enemies.science_labs = {}
    global.oarc_enemies.tech_levels = {}

    global.oarc_enemies.player_timers = {}

    -- Ongoing attacks
    global.oarc_enemies.attacks = {}
    -- This is what an attack entry looks like:

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
        if (player.force.name == force_name) and (global.oarc_enemies.science_labs[player.name]) then
            if (#global.oarc_enemies.science_labs[player.name] > 0) then
                
                local science_attack = {target_player = player.name,
                                        target_type = OE_ATTACK_TYPE_SCIENCE,
                                        retry_attempts=3}
                SendBroadcastMsg("Science Lab Attack!")
                table.insert(global.oarc_enemies.attacks, science_attack)
            end
        end
    end
end

-- Attack a player
function OarcEnemiesPlayerAttack(player_name)

    if (not game.players[player_name] or
        not game.players[player_name].connected or
        not game.players[player_name].character or
        not game.players[player_name].character.valid) then
        SendBroadcastMsg("OarcEnemiesPlayerAttack - player invalid or not connected?")
        return
    end

    local player_attack =   {target_player = player_name,
                                target_type = OE_ATTACK_TYPE_PLAYER,
                                retry_attempts=0}
    SendBroadcastMsg("Player Attack!")
    table.insert(global.oarc_enemies.attacks, player_attack)
end

-- First time player init stuff
function OarcEnemiesPlayerCreatedEvent(event)
    if (game.players[event.player_index] == nil) then return end
    local p_name = game.players[event.player_index].name
    
    if (global.oarc_enemies.player_timers[p_name] == nil) then
        global.oarc_enemies.player_timers[p_name] = FIRST_PLAYER_ATTACK_TIMER_SEC -- CHANGE THIS TO SOMETHING RANDOM?
    end

    if (global.oarc_enemies.science_labs[p_name] == nil) then
        global.oarc_enemies.science_labs[p_name] = {}
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

function OarcEnemiesChunkDeleted(event)
    if (not event.positions) then
        log("OarcEnemiesChunkDeleted - ERROR")
        return
    end

    for chunk in event.positions do
        if (global.oarc_enemies.chunk_map[c_pos.x] ~= nil) then
            if (global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] ~= nil) then
                global.oarc_enemies.chunk_map[c_pos.x][c_pos.y] = nil
            end
        end
    end
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

    for i=-BUILDING_SAFE_AREA_RADIUS,BUILDING_SAFE_AREA_RADIUS do
        for j=-BUILDING_SAFE_AREA_RADIUS,BUILDING_SAFE_AREA_RADIUS do
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

function OarcEnemiesTrackScienceLabs(e)

    if (e.last_user == nil) then
        SendBroadcastMsg("OarcEnemiesTrackScienceLabs - entity.last_user is nil! " .. e.name)
        return
    end

    if (global.oarc_enemies.science_labs == nil) then
        global.oarc_enemies.science_labs = {}
    end

    if (global.oarc_enemies.science_labs[e.last_user.name] == nil) then
        global.oarc_enemies.science_labs[e.last_user.name] = {e}
    else
        table.insert(global.oarc_enemies.science_labs[e.last_user.name], e)
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

    if (#global.oarc_enemies.science_labs[player_name] == 0) then
        SendBroadcastMsg("GetRandomScienceLab - none found")
        return nil
    end

    local rand_key = GetRandomKeyFromTable(global.oarc_enemies.science_labs[player_name])
    local random_lab = global.oarc_enemies.science_labs[player_name][rand_key]

    if (not random_lab or not random_lab.valid) then
        global.oarc_enemies.science_labs[player_name][rand_key] = nil
        return GetRandomScienceLab(player_name)
    else
        return random_lab
    end
end

function OarcEnemiesOnTick()

    -- Validation checks and cleanup?
    if ((game.tick % (TICKS_PER_SECOND)) == 31) then

        -- Validate active groups and units
        -- Cleanup failed groups or lost units
        if (#global.oarc_enemies.groups > 0) then
            for i,group in pairs(global.oarc_enemies.groups) do
                if (not group.valid) then
                    global.oarc_enemies.groups[i] = nil
                elseif (group.state == defines.group_state.gathering) then
                    EnemyGroupAttackEntity(group, game.players["Oarc"].character)
                end
            end
        end
    end

    -- Randomized player timers generating attacks
    -- if ((game.tick % (TICKS_PER_SECOND)) == 32) then

    --     for name,timer in pairs(global.oarc_enemies.player_timers) do
    --         if (global.oarc_enemies.science_labs[name] ~= nil) and
    --             (#global.oarc_enemies.science_labs[name] > 0) then
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


    -- Find target given request type
    if ((game.tick % (TICKS_PER_SECOND)) == 33) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ((attack.target_entity == nil and attack.target_chunk == nil) and 
               (attack.target_player and attack.target_type and attack.retry_attempts)) then

                if (attack.target_type == OE_ATTACK_TYPE_SCIENCE) then

                    local random_lab = GetRandomScienceLab(attack.target_player)

                    if (random_lab ~= nil) then
                        global.oarc_enemies.attacks[key].target_entity = random_lab
                        global.oarc_enemies.attacks[key].size = 10
                        global.oarc_enemies.attacks[key].evo = 0.3
                    else
                        SendBroadcastMsg("No labs found to attack.")
                        global.oarc_enemies.attacks[key] = nil
                    end
                
                elseif (attack.target_type == OE_ATTACK_TYPE_PLAYER) then
                    global.oarc_enemies.attacks[key].target_entity = game.players[attack.target_player].character
                    global.oarc_enemies.attacks[key].size = 10
                    global.oarc_enemies.attacks[key].evo = 0.3
                end


            end
        end
    end

    -- Find spawn location
    if ((game.tick % (TICKS_PER_SECOND)) == 33) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if (attack.target_entity or attack.target_chunk) and (attack.spawn_chunk == nil) then

                if (not attack.target_entity.valid) then
                    global.oarc_enemies.attacks[key].target_entity = nil
                    attack.retry_attempts = attack.retry_attempts - 1
                    if (attack.retry_attempts == 0) then
                        SendBroadcastMsg("attack.retry_attempts = 0 - ATTACK FAILURE")
                        global.oarc_enemies.attacks[key] = nil
                    end
                    break
                end

                local c_pos = GetChunkPosFromTilePos(attack.target_entity.position)
                local spawn = SpiralSearch(c_pos, 50, OarcEnemiesIsChunkValidSpawn)

                if (spawn ~= nil) then
                    global.oarc_enemies.attacks[key].spawn_chunk = spawn
                else
                    global.oarc_enemies.attacks[key].target_entity = nil
                    attack.retry_attempts = attack.retry_attempts - 1
                    if (attack.retry_attempts == 0) then
                        SendBroadcastMsg("attack.retry_attempts = 0 - ATTACK FAILURE")
                        global.oarc_enemies.attacks[key] = nil
                    end
                end

                break -- Only one search per tick.
            end
        end
    end

    -- Find path
    if ((game.tick % (TICKS_PER_SECOND)) == 34) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if (attack.spawn_chunk ~= nil) and (attack.path_id == nil) then

                spawn_pos = game.surfaces[1].find_non_colliding_position("rocket-silo",
                                                                        GetCenterTilePosFromChunkPos(attack.spawn_chunk),
                                                                        32,
                                                                        1)
                global.oarc_enemies.attacks[key].spawn_pos = spawn_pos
                global.oarc_enemies.attacks[key].path_id = game.surfaces[1].request_path{bounding_box={{0,0},{1,1}},
                                                                collision_mask={"player-layer"},
                                                                start=spawn_pos,
                                                                goal=attack.target_entity.position,
                                                                force=game.forces["enemy"],
                                                                radius=8,
                                                                pathfind_flags={low_priority=true},
                                                                can_open_gates=false,
                                                                path_resolution_modifier=-1}
                break
            end
        end
    end

    -- Spawn group
    if ((game.tick % (TICKS_PER_SECOND)) == 35) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if (attack.path) and (attack.group_id == nil) then
            -- if (attack.spawn_chunk) and (attack.group_id == nil) then
                local group = CreateEnemyGroupGivenEvoAndCount(game.surfaces[1],
                                                attack.spawn_pos,
                                                0.25,
                                                10)
                global.oarc_enemies.attacks[key].group_id = group.group_number
            end
        end
    end

    -- Send group on attack
    if ((game.tick % (TICKS_PER_SECOND)) == 36) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if (attack.group_id) and (attack.path_id) and (not attack.active) then
                for _,group in pairs(global.oarc_enemies.groups) do
                    if (attack.group_id == group.group_number) and (group.valid) then
                        -- EnemyGroupAttackEntity(group, attack.target_entity)
                        EnemyGroupAttackEntityCompoundCmd(group, attack.target_entity, attack.path)
                        global.oarc_enemies.attacks[key].active = true
                    end
                end
            end
        end
    end


    -- Every minute
    if ((game.tick % (TICKS_PER_MINUTE/2)) == 40) then

        if (#global.oarc_enemies.groups < 5) then
            -- TestSpawnGroup()
        end

    end

    -- Every hour
    if ((game.tick % (TICKS_PER_HOUR)) == 50) then

    end

end


function OarcEnemiesGroupCmdFailed(event)
    local attack_key = FindAttackKeyFromGroupIdNumber(event.unit_number)
    if (attack_key == nil) then
        SendBroadcastMsg("OarcEnemiesGroupCmdFailed - ATTACK KEY NIL?! " .. event.unit_number)
        return
    end
    local attack = global.oarc_enemies.attacks[attack_key]

    -- Wander means we won't lose the group if it's finished a command and has nothing to do.
    -- local wander_cmd = 
    -- {
    --     type = defines.command.wander,
    --     distraction = distraction
    -- }
    -- local group = FindEnemyGroupFromIdNumber(event.unit_number)
    -- group.set_command(wander_cmd)

    if (attack.target_type == OE_ATTACK_TYPE_PLAYER) then

        -- Request new path checks?

        -- global.oarc_enemies.attacks[attack_key].path_id = nil
        global.oarc_enemies.attacks[attack_key].active = false
    -- elseif (attack.retry_attempts > 0) then
    --     global.oarc_enemies.attacks[attack_key].retry_attempts = attack.retry_attempts-1
    -- elseif (attack.retry_attempts == 0) then

    else
        SendBroadcastMsg("OarcEnemiesGroupCmdFailed - Group is autonomous now " .. event.unit_number)
        group.set_autonomous()
        global.oarc_enemies.attacks[attack_key] = nil
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
            table.insert(global.oarc_enemies.units, new_unit)
        end
    end

    table.insert(global.oarc_enemies.groups, new_enemy_group)

    SendBroadcastMsg("DEBUG - Enemy Group Number: " ..  new_enemy_group.group_number)

    -- Return the new group
    return new_enemy_group
end


function FindEnemyGroupFromIdNumber(id)

    for _,group in pairs(global.oarc_enemies.groups) do
        if (group.group_number == id) then
            return group
        end
    end

    return nil
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
    -- for k,v in pairs(path) do
    --     table.insert(waypoint_cmds, {type = defines.command.go_to_location,
    --                                     destination = v.position,
    --                                     distraction = distraction})
    -- end

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

