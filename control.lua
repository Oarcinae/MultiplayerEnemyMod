-- control.lua
-- Sep 2018

-- Oarc's Enemies
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
    OarcEnemiesCreateGui(event)
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
    if ((e.type ~= "car") and
        (e.type ~= "logistic-robot") and
        (e.type ~= "construction-robot") and
        (e.type ~= "combat-robot")) then
        OarcEnemiesChunkHasPlayerBuilding(e.position)
    end
    OarcEnemiesTrackBuildings(e)
end)


script.on_event(defines.events.script_raised_built, function(event)
    OarcEnemiesChunkHasPlayerBuilding(event.entity.position)
end)

----------------------------------------
-- On Entity Spawned
-- This is where I modify biter spawning based on location and other factors.
----------------------------------------
script.on_event(defines.events.on_entity_spawned, function(event)
    -- Stop enemies from being created normally:
    event.entity.destroy()
end)

script.on_event(defines.events.on_entity_died, function(event)
    OarcEnemiesEntityDiedEvent(event)
end)


script.on_event(defines.events.on_unit_group_created, function(event)
    OarcEnemiesGroupCreatedEvent(event)
end)

script.on_event(defines.events.on_unit_removed_from_group, function(event)
    SendBroadcastMsg("Unit removed from group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)

    -- Force the unit back into its group or kill it.
    if (event.group and event.group.valid) then
        event.group.add_member(event.unit)
    else
        event.unit.die(nil, event.unit)
    end
end)

script.on_event(defines.events.on_unit_added_to_group, function(event)
    -- Maybe use this to track all units I've created so I can clean up later if needed?
    -- SendBroadcastMsg("Unit added to group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)
end)

script.on_event(defines.events.on_ai_command_completed, function(event)
    SendBroadcastMsg("AI cmd completed? " .. event.unit_number .. " : " .. event.result)

    if (event.result == defines.behavior_result.fail) then
        log("AI_FAIL GAME - TICK: " .. game.tick)
        log("AI_FAIL unit number: " .. event.unit_number)
        OarcEnemiesGroupCmdFailed(event)
    end
end)

script.on_event(defines.events.on_tick, function(event)
    OarcEnemiesOnTick()
    TimeoutSpeechBubblesOnTick()
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
    ProcessAttackCheckPathComplete(event)
end)


script.on_event(defines.events.on_research_finished, function(event)
   OarcEnemiesResearchFinishedEvent(event)
end)


script.on_event(defines.events.on_force_created, function(event)
    OarcEnemiesForceCreated(event)
end)
