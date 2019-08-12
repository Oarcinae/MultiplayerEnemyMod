-- control.lua
-- Aug 2019

-- Oarc's Enemies Mod
--
-- The core purpose of this mod is to provide a way to scale all enemy attacks to the target player and region.
-- Ideally to complement my scenario
--
-- Feel free to re-use anything you want. It would be nice to give me credit
-- if you can.

-- High level:
--  Only spawn when players are online.
--  Scale based on target force research
--  Scale based on pollution in target area
--  Attacks are calculated and dispatched over several ticks, see oarc_enemies_tick_logic to see the flow.

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


-- NOTES AFTER TESTING
--  Check for old groups, destroy after x amount of time. (stuck pathing biters.)
--  Tweak spitter ratio.
--  Faster on base killed spawning if possible.
--  Cap on biter base killed to 100 or 150.
--  Optimize search for valid spawn or spread over ticks (Put all chunks to be checked into a list to be iterated over slowly)
--  Need to make this compatible with my scenario now
--  Surface needs to be dynamic
--  Implement "expansion" of some kind?

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
    {name="stone-furnace", count = 2}
}

-- Items provided after EVERY respawn (disabled by default)
PLAYER_RESPAWN_START_ITEMS = {
    -- {name="pistol", count=1},
    -- {name="firearm-magazine", count=100}
}

-- Generic Utility Includes
require("lib/oarc_utils")

-- Required Includes
require("oarc_enemies_defines")
require("oarc_enemies_evo")
require("oarc_enemies")
require("oarc_enemies_gui")
require("oarc_enemies_tick_logic")

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

script.on_event(defines.events.on_chunk_generated, function(event)
    OarcEnemiesChunkGenerated(event)
end)

script.on_event({defines.events.on_robot_built_entity,defines.events.on_built_entity}, function (event)
    log("on_built_entity")
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
    log("script_raised_built")
    OarcEnemiesChunkHasPlayerBuilding(event.entity.position)
end)

script.on_event(defines.events.on_biter_base_built, function(event)
    log("on_biter_base_built " .. game.tick)
    OarcEnemiesBiterBaseBuilt(event)
end)

script.on_event(defines.events.on_entity_spawned, function(event)
    -- Stop enemies from being created normally:
    event.entity.destroy()
    -- log("on_entity_spawned")
end)

script.on_event(defines.events.on_entity_died, function(event)
    log("on_entity_died")
    OarcEnemiesEntityDiedEvent(event)
end)

-- script.on_event(defines.events.on_unit_group_created, function(event)
--     log("on_unit_group_created")
--     OarcEnemiesGroupCreatedEvent(event)
-- end)

script.on_event(defines.events.on_unit_removed_from_group, function(event)
    log("on_unit_removed_from_group")
    OarcEnemiesUnitRemoveFromGroupEvent(event)
end)

-- script.on_event(defines.events.on_unit_added_to_group, function(event)
    -- Maybe use this to track all units I've created so I can clean up later if needed?
    -- log("Unit added to group? " .. event.unit.name .. event.unit.position.x.. event.unit.position.y)
-- end)

script.on_event(defines.events.on_ai_command_completed, function(event)
    -- log("on_ai_command_completed")
    log("AI cmd completed? " .. event.unit_number .. " : " .. event.result .. " " .. game.tick)
    if (event.result == defines.behavior_result.fail) then
        OarcEnemiesGroupCmdFailed(event)
    end
end)

script.on_event(defines.events.on_tick, function(event)
    OarcEnemiesOnTick()
    TimeoutSpeechBubblesOnTick()
end)

script.on_event(defines.events.on_script_path_request_finished, function(event)
    log("on_script_path_request_finished " .. game.tick)
    ProcessAttackCheckPathComplete(event)
end)


script.on_event(defines.events.on_research_finished, function(event)
   OarcEnemiesResearchFinishedEvent(event)
end)


script.on_event(defines.events.on_force_created, function(event)
    OarcEnemiesForceCreated(event)
end)

script.on_event(defines.events.on_sector_scanned, function (event)
    OarcEnemiesSectorScanned(event)
end)

script.on_event(defines.events.on_rocket_launched, function(event)
    OarcEnemiesRocketLaunched(event)
end)