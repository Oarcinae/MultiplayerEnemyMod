-- oarc_enemies_tick_logic.lua
-- Aug 2019
--
-- Holds all the code related to the the on_tick "state machine"
-- Where we process on going attacks step by step.


function OarcEnemiesOnTick()

    -- Cleanup attacks that have died or somehow become invalid.
    if ((game.tick % (TICKS_PER_SECOND)) == 20) then
        for key,attack in pairs(global.oarc_enemies.attacks) do
            if ProcessAttackCleanupInvalidGroups(key, attack) then break end
        end
    end

    -- Process player timers
    if ((game.tick % (TICKS_PER_SECOND)) == 21) then
        ProcessPlayerTimersEverySecond()
    end

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
    -- Event Function: ProcessAttackCheckPathComplete(event)

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
    -- Event Function: OarcEnemiesGroupCmdFailed(event)

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
    -- Event Function: ProcessAttackCheckPathComplete(event)

end


function ProcessAttackCleanupInvalidGroups(key, attack)
    if (attack.process_stg ~= OE_PROCESS_STG_GROUP_ACTIVE) then return false end

    if (not attack.group or not attack.group.valid) then
        SendBroadcastMsg("ProcessAttackCleanupInvalidGroups - Group killed?")
        global.oarc_enemies.attacks[key] = nil

    elseif (attack.group.state == defines.group_state.wander_in_group) then
        SendBroadcastMsg("ProcessAttackCleanupInvalidGroups - Group done?")
        EnemyGroupBuildBaseThenWander(attack.group, attack.group.position)
        -- global.oarc_enemies.attacks[key] = nil
        global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_BUILD_BASE
    end

    return false
end


function ProcessPlayerTimersEverySecond()
    for name,timer in pairs(global.oarc_enemies.player_timers) do
        if (game.players[name] and game.players[name].connected) then
            if (timer > 0) then
                global.oarc_enemies.player_timers[name] = timer-1
            else
                OarcEnemiesPlayerAttack(name)
                global.oarc_enemies.player_timers[name] =
                    (math.max(OE_MAX_TIME_BETWEEN_ATTACKS_MINS/game.players[name].online_time,
                                OE_MIN_TIME_BETWEEN_ATTACKS_MINS) + math.random(0,2)) * 60
            end
        end
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

        local player = game.players[attack.target_player]

        -- Attack a building of the player, given a certain building type
        if (attack.target_type == OE_TARGET_TYPE_BUILDING) then

            local random_building = GetRandomBuildingAny(attack.target_player,
                                                            attack.building_types)
            if (random_building ~= nil) then
                global.oarc_enemies.attacks[key].target_entity = random_building

                local e,s = GetEnemyGroup{player=player,
                                            force_name=player.force.name,
                                            surface=game.surfaces[1],
                                            target_position=random_building.position}

                global.oarc_enemies.attacks[key].size = s
                global.oarc_enemies.attacks[key].evo = e
                global.oarc_enemies.attacks[key].process_stg = OE_PROCESS_STG_FIND_SPAWN
                return true
            else
                SendBroadcastMsg("No building found to attack.")
                global.oarc_enemies.attacks[key] = nil
            end

        -- Attack a player directly
        elseif (attack.target_type == OE_TARGET_TYPE_PLAYER) then

            global.oarc_enemies.attacks[key].target_entity = player.character

            local e,s = GetEnemyGroup{player=player,
                                            force_name=player.force.name,
                                            surface=game.surfaces[1],
                                            target_position=player.character.position}

            global.oarc_enemies.attacks[key].size = s
            global.oarc_enemies.attacks[key].evo = e
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
        global.oarc_enemies.groups[attack.group.group_number] = nil
        attack.group.set_autonomous()
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
            global.oarc_enemies.groups[attack.group.group_number] = nil
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