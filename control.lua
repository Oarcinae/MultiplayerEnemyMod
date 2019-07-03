-- control.lua
-- Sep 2018

-- Oarc's New Scenario
-- 
-- Feel free to re-use anything you want. It would be nice to give me credit
-- if you can.



-- No spawners?
-- Evolution = number of completed research * 0.005 (200 research complete events = 100% evo)
-- # of waves per time scales (Start with 1hr, work up to 10 min?)
-- size of waves scales (Start with 5, work up to 50?)

-- Enemies spawn in chunks that match the following constraints:
--  Any chunk within 7 chunks of a player building is ruled out
--  Chunk must not have active vision (must be fog of war or not charted)

-- Enemies could target the following:
--  Power generation
--  Science
--  Miners
--  Players (going on an adventure could be risky for example)
--  Default pollution centers

-- Other rules:
--  Only spawn when players are online.
--  Scale based on target force research
--  Scale based on pollution in target area (600 is upper limit)


-- General AI Flow:
--  Track candidate spawn chunks based on player buildings and on chunk generated checks for land space.
--  Pick a tentative spawn chunk.
--  Pick a tentative target entity or location.
--  Request pathing.
--  On successful pathing found, generate enemy unit group (with applied scaling factors)
--  Unit group attempts to path to each waypoint and reach the end target


-- Globals for tracking:
--  Map chunks to track candidate spawns.
--      Each chunk should have info on if it is a valid spawn,
--      and if it has a player building in it.
--  Force tech levels / "evo chance list"
--  Enemy unit groups currently in action.
--      Should have info about current target?
--  Timers for when next attack will occur.

-- Event logic:
--  For tracking player building in chunks:
--      on_built_entity
--      script_raised_built
--      on_robot_built_entity
--  For tracking map chunks
--      on_chunk_generated
--      on_chunk_deleted
--  For tracking AI
--      on_biter_base_built
--      on_entity_spawned
--      on_unit_added_to_group
--      on_unit_group_created
--      on_unit_removed_from_group
--  For executing AI functions
--      on_ai_command_completed
--          Check for failures and success
--      on_tick
--  For tracking force research
--      on_research_finished
--      on_rocket_launched


ENABLE_POWER_ARMOR_QUICK_START = true
---------------------------------------
-- Starting Items
---------------------------------------
-- Items provided to the player the first time they join
PLAYER_SPAWN_START_ITEMS = {
    {name="pistol", count=1},
    {name="firearm-magazine", count=200},
    {name="iron-plate", count=16},
    {name="burner-mining-drill", count = 2},
    {name="stone-furnace", count = 2},
    -- {name="iron-plate", count=20},
    -- {name="burner-mining-drill", count = 1},
    -- {name="stone-furnace", count = 1},
    -- {name="power-armor", count=1},
    -- {name="fusion-reactor-equipment", count=1},
    -- {name="battery-mk2-equipment", count=3},
    -- {name="exoskeleton-equipment", count=1},
    -- {name="personal-roboport-mk2-equipment", count=3},
    -- {name="solar-panel-equipment", count=7},
    -- {name="construction-robot", count=100},
    -- {name="repair-pack", count=100},
    -- {name="steel-axe", count=3},
}

-- Items provided after EVERY respawn (disabled by default)
PLAYER_RESPAWN_START_ITEMS = {
    -- {name="pistol", count=1},
    -- {name="firearm-magazine", count=100}
}

-- Generic Utility Includes
require("lib/oarc_utils")

-- Required Includes
require("oarc_enemies")
require("oarc_enemies_gui")

-- DEBUG prints for me
global.oarcDebugEnabled = true


----------------------------------------
-- On Init - only runs once (hopefully)
----------------------------------------
script.on_init(function(event)
    InitOarcEnemies() -- Setup global tables and such
end)


script.on_event(defines.events.on_player_created, function(event)
    PlayerSpawnItems(event)
    OarcEnemiesPlayerCreatedEvent(event)
end)
script.on_event(defines.events.on_player_respawned, function(event)
    PlayerRespawnItems(event)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    OarcEnemiesGui(event)
end)

script.on_event(defines.events.on_gui_click, function(event)
    OarcEnemiesGuiClick(event)
end)


----------------------------------------
-- Chunk Generation/Deletion
----------------------------------------
script.on_event(defines.events.on_chunk_generated, function(event)
    OarcEnemiesChunkGenerated(event)
end)
script.on_event(defines.events.on_chunk_deleted, function(event)
    OarcEnemiesChunkDeleted(event)
end)


script.on_event({defines.events.on_robot_built_entity,defines.events.on_built_entity}, function (event)
    local e = event.created_entity
    if ((e.type ~= "car") and (e.type ~= "logistic-robot") and (e.type ~= "construction-robot")) then
        OarcEnemiesChunkHasPlayerBuilding(e.position)
    end
    if (e.name == "lab") then
        OarcEnemiesTrackScienceLabs(e)
    end
end)


script.on_event(defines.events.script_raised_built, function(event)
    OarcEnemiesChunkHasPlayerBuilding(event.entity.position)
end)

----------------------------------------
-- On Entity Spawned
-- This is where I modify biter spawning based on location and other factors.
----------------------------------------
script.on_event(defines.events.on_entity_spawned, function(event)
    
    -- SendBroadcastMsg(event.entity.name .. "spawned @" .. event.entity.position.x .. "," .. event.entity.position.y)

    -- if (not event.entity or not (event.entity.force.name == "enemy") or not event.entity.position) then
    --     SendBroadcastMsg("ModifyBiterSpawns - Unexpected use.")
    --     return
    -- end

    -- local enemy_pos = event.entity.position
    -- local surface = event.entity.surface
    -- local enemy_name = event.entity.name

    -- if (getDistance(enemy_pos, {x=0,y=0}) > 500) then
    --     if (enemy_name == "small-biter") then
    --         event.entity.destroy()
    --         local unit_position = surface.find_non_colliding_position("behemoth-biter", enemy_pos, 16, 2)
    --         surface.create_entity{name = "behemoth-biter", position = unit_position, force = game.forces.enemy}
    --     end
    -- end

    event.entity.destroy()

end)

script.on_event(defines.events.on_unit_group_created, function(event)
    SendBroadcastMsg("Unit group created: " .. event.group.group_number)
end)

script.on_event(defines.events.on_unit_removed_from_group, function(event)
    SendBroadcastMsg("Unit removed from group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)
    -- event.unit.die(nil, event.unit)
    local build_a_base = 
    {
        type = defines.command.build_base,
        destination = event.unit.position,
        distraction = defines.distraction.by_damage,
        ignore_planner = true
    }
    event.unit.set_command(build_a_base)
end)

script.on_event(defines.events.on_unit_added_to_group, function(event)
    -- SendBroadcastMsg("Unit added to group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)
end)

script.on_event(defines.events.on_ai_command_completed, function(event)
    SendBroadcastMsg("AI cmd completed? " .. event.unit_number .. " : " .. event.result)

    if (event.result == defines.behavior_result.fail) then
        OarcEnemiesGroupCmdFailed(event)
    end
end)

script.on_event(defines.events.on_tick, function(event)
    OarcEnemiesOnTick()
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
    
    for key,attack in pairs(global.oarc_enemies.attacks) do
        if (attack.path_id == event.id) then
            if (event.path) then
                SendBroadcastMsg("on_script_path_request_finished: " .. #event.path)
                global.oarc_enemies.attacks[key].path = event.path
                RenderPath(event.path, TICKS_PER_MINUTE*5, {game.players["Oarc"]})
            else
                SendBroadcastMsg("on_script_path_request_finished: FAILED")
                if (event.try_again_later) then
                    SendBroadcastMsg("on_script_path_request_finished: TRY AGAIN LATER?")
                end
                global.oarc_enemies.attacks[key] = nil
            end
        end
    end

end)


script.on_event(defines.events.on_research_finished, function(event)
   OarcEnemiesResearchFinishedEvent(event)
end)


script.on_event(defines.events.on_force_created, function(event)
    OarcEnemiesForceCreated(event)
end)



local group
local comp_cmd =    {
                        type = defines.command.compound,
                        structure_type = defines.compound_command.return_last,
                        commands =
                        {
                            {type = defines.command.attack_area, destination = {x=-50, y=-50}, radius = 10, distraction = defines.distraction.by_enemy},
                            {type = defines.command.wander, distraction = defines.distraction.none}
                        }
                    }
local group_cmd = {type = defines.command.go_to_location, destination = {x=-50, y=-50}, distraction = defines.distraction.by_enemy}



commands.add_command("spawn_group", "spawn a group", function(command)

    local surface = game.surfaces[1]
    local group_position = {x=50, y=50}

    local chance_list = CalculateEvoChanceListBiters(0.3)

    units = {}
    for i=1,10 do
        table.insert(units, GetEnemyFromChanceList(chance_list))
    end

    group = CreateEnemyGroup(surface, group_position, units)
end)


commands.add_command("kill_group", "kill a group", function(command)
    
    if ((group == nil) or (not group.valid)) then
        return
    end

    for i,u in ipairs(group.members) do
        u.destroy()
    end
    group.destroy()

end)

commands.add_command("move_group", "move a group", function(command)
    
    if ((group == nil) or (not group.valid)) then
        return
    end

    group.set_command(comp_cmd)

    local unit_cmd = {type = defines.command.group, group = group, distraction = defines.distraction.none}

    for i,u in ipairs(group.members) do
        u.set_command(unit_cmd)
    end
end)

commands.add_command("group_info", "info about a group", function(command)
    if ((group == nil) or (not group.valid)) then
        return
    end

    SendBroadcastMsg(group.position)
    SendBroadcastMsg(group.state)

end)

commands.add_command("test_evo", "test", function(command)
    CalculateEvoChanceList(0.3)
end)