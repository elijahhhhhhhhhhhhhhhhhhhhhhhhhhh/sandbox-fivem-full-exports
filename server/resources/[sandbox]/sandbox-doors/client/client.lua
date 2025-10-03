initLoaded = false
_showingDoorInfo = false
_lookingAtDoor = false
_lookingAtDoorEntity = nil
_lookingAtDoorCoords = nil
_lookingAtDoorRadius = nil
DOORS_STATE = false
DOORS_IDS = {}
ELEVATOR_STATE = false
_newDuty = false

_showingDoorDisabled = false

DOORS_PERMISSION_CACHE = {}

AddEventHandler('onClientResourceStart', function(resource)
	if resource == GetCurrentResourceName() then
		Wait(1000)
		exports["sandbox-keybinds"]:Add("doors_garage_fob", "f10", "keyboard", "Doors - Use Garage Keyfob", function()
			DoGarageKeyFobAction()
		end)

		exports["sandbox-base"]:RegisterClientCallback("Doors:GetCurrentDoor", function(data, cb)
			cb(_lookingAtDoor)
		end)

		CreateGaragePolyZones()
		CreateElevators()
		Wait(1000)
		InitDoors()
	end
end)

function InitDoors()
	if initLoaded then
		return
	end
	initLoaded = true
	DOORS_STATE = {}
	ELEVATOR_STATE = {}
	exports["sandbox-base"]:ServerCallback("Doors:Fetch", {}, function(fetchedDoors, fetchedElevators)
		for k, v in ipairs(_doorConfig) do
			if v.id and not DOORS_IDS[v.id] then
				DOORS_IDS[v.id] = k
			end

			local doorData = v
			doorData.id = v.id or k
			doorData.doorId = k

			doorData.locked = fetchedDoors[k].locked
			doorData.disabledUntil = fetchedDoors[k].disabledUntil

			AddDoorToSystem(k, doorData.model, doorData.coords.x, doorData.coords.y, doorData.coords.z)

			if type(doorData.autoRate) == "number" and doorData.autoRate > 0.0 then
				DoorSystemSetAutomaticRate(k, doorData.autoRate + 0.0, 0, 1)
			end

			if type(doorData.autoDist) == "number" and doorData.autoDist > 0.0 then
				DoorSystemSetAutomaticDistance(k, doorData.autoDist + 0.0, 0, 1)
			end

			DoorSystemSetDoorState(k, doorData.locked and 1 or 0)

			if doorData.holdOpen then
				DoorSystemSetHoldOpen(k, true)
			end

			if fetchedDoors[k].forcedOpen then
				DoorSystemSetOpenRatio(k, -1.0)
				DoorSystemSetDoorState(k, 1)
			end

			DOORS_STATE[k] = doorData
		end

		for k, v in ipairs(_elevatorConfig) do
			for k2, v2 in pairs(v.floors) do
				v2.locked = fetchedElevators[k].floors[k2].locked
			end
			ELEVATOR_STATE[k] = v
		end

		CreateElevators()
	end)
end

function CreateElevators()
	if ELEVATOR_STATE then
		for k, v in pairs(ELEVATOR_STATE) do
			if v.floors then
				for floorId, floorData in pairs(v.floors) do
					if floorData.zone then
						if #floorData.zone > 0 then
							for j, b in ipairs(floorData.zone) do
								CreateElevatorFloorTarget(b, k, floorId, j)
							end
						else
							CreateElevatorFloorTarget(floorData.zone, k, floorId, 1)
						end
					end
				end
			end
		end
	end
end

function CreateElevatorFloorTarget(zoneData, elevatorId, floorId, zoneId)
	exports.ox_target:addBoxZone({
		id = "elevators_" .. elevatorId .. "_level_" .. floorId .. "_" .. zoneId,
		coords = zoneData.center,
		size = vector3(zoneData.length, zoneData.width, 2.0),
		rotation = zoneData.heading,
		debug = false,
		minZ = zoneData.minZ,
		maxZ = zoneData.maxZ,
		options = {
			{
				icon = "elevator",
				label = "Use Elevator",
				onSelect = function()
					TriggerEvent("Doors:Client:OpenElevator", {
						elevator = elevatorId,
						floor = floorId,
					})
				end,
				distance = 3.0,
				canInteract = function()
					return (
						(not LocalPlayer.state.Character:GetData("ICU")
							or LocalPlayer.state.Character:GetData("ICU").Released)
						and not LocalPlayer.state.isCuffed
					)
				end,
			},
		}
	})
end

exports('IsLocked', function(doorId)
	if type(doorId) == "string" then
		doorId = DOORS_IDS[doorId]
	end

	if DOORS_STATE and DOORS_STATE[doorId] and DOORS_STATE[doorId].locked then
		return true
	end
	return false
end)

exports('CheckRestriction', function(doorId)
	if not DOORS_STATE then
		return false
	end

	if type(doorId) == "string" then
		doorId = DOORS_IDS[doorId]
	end

	local doorData = DOORS_STATE[doorId]
	if doorData and LocalPlayer.state.Character then
		if type(doorData.restricted) ~= "table" then
			return true
		end

		if exports['sandbox-jobs']:HasJob("dgang", false, false, 99, true) then
			return true
		end

		local stateId = LocalPlayer.state.Character:GetData("SID")

		for k, v in ipairs(doorData.restricted) do
			if v.type == "character" then
				if stateId == v.SID then
					return true
				end
			elseif v.type == "job" then
				if v.job then
					if
						exports['sandbox-jobs']:HasJob(
							v.job,
							v.workplace,
							v.grade,
							v.gradeLevel,
							v.reqDuty,
							v.jobPermission
						)
					then
						return true
					end
				elseif v.jobPermission then
					if exports['sandbox-jobs']:HasPermission(v.jobPermission) then
						return true
					end
				end
			elseif v.type == "propertyData" then
				if exports['sandbox-properties']:HasAccessWithData(v.key, v.value) then
					return true
				end
			end
		end
	end
	return false
end)

exports('GetCurrentDoor', function()
	return _lookingAtDoor or false, _lookingAtDoorEntity or false, _lookingAtDoorCoords or false,
		_lookingAtDoorRadius or false, _lookingAtDoorSpecial or false
end)

function CheckDoorAuth(doorId)
	if
		DOORS_STATE[doorId].hasPermission == nil
		or (GetGameTimer() - DOORS_STATE[doorId].lastPermissionCheck) >= 60000
		or DOORS_STATE[doorId].lastDutyCheck ~= _newDuty
	then
		DOORS_STATE[doorId].hasPermission = exports['sandbox-doors']:CheckRestriction(doorId)
		DOORS_STATE[doorId].lastPermissionCheck = GetGameTimer()
		DOORS_STATE[doorId].lastDutyCheck = LocalPlayer.state.onDuty
		return DOORS_STATE[doorId].hasPermission
	end
	return DOORS_STATE[doorId].hasPermission
end

function StopShowingDoorInfo()
	if not _showingDoorInfo then
		return
	end
	exports['sandbox-hud']:ActionHide("doors")
	_showingDoorInfo = false
end

function StartShowingDoorInfo(doorId)
	_showingDoorInfo = doorId
	_showingDoorDisabled = false

	if DOORS_STATE[doorId].disabledUntil and DOORS_STATE[doorId].disabledUntil > GetCloudTimeAsInt() then
		_showingDoorDisabled = true
		exports['sandbox-hud']:ActionShow("doors", "This Door is Disabled")
		return
	end

	local actionMsg = "{keybind}primary_action{/keybind} "
		.. (DOORS_STATE[doorId].locked and "Unlock Door" or "Lock Door")
	exports['sandbox-hud']:ActionShow("doors", actionMsg)
end

function StartCharacterThreads()
	ResetLockpickAttempts()
	GLOBAL_PED = PlayerPedId()

	CreateThread(function()
		while LocalPlayer.state.loggedIn do
			GLOBAL_PED = PlayerPedId()
			Wait(5000)
		end
	end)
end

function UselessWrapper()
	local p = promise.new()
	CreateThread(function()
		p:resolve(DoorSystemGetActive())
	end)
	return Citizen.Await(p)
end

CreateThread(function()
	while true do
		Wait(500)

		if LocalPlayer.state.loggedIn and DOORS_STATE then
			local ped = PlayerPedId()
			local pedCoords = GetEntityCoords(ped)
			local closestDoor = nil
			local closestDist = 999.0

			for doorId, doorData in pairs(DOORS_STATE) do
				if not doorData.special then
					local dist = #(pedCoords - vector3(doorData.coords.x, doorData.coords.y, doorData.coords.z))
					local maxDist = doorData.maxDist or 2.0

					if dist <= maxDist and dist < closestDist then
						closestDoor = doorId
						closestDist = dist
					end
				end
			end

			if closestDoor then
				if closestDoor ~= _lookingAtDoor then
					_lookingAtDoor = closestDoor
					_lookingAtDoorCoords = vector3(DOORS_STATE[closestDoor].coords.x, DOORS_STATE[closestDoor].coords.y,
						DOORS_STATE[closestDoor].coords.z)
					_lookingAtDoorRadius = DOORS_STATE[closestDoor].maxDist or 2.0
					_lookingAtDoorSpecial = DOORS_STATE[closestDoor].special
				end

				local canSee = CheckDoorAuth(closestDoor)
				if not _showingDoorInfo and canSee then
					StartShowingDoorInfo(closestDoor)
				elseif _showingDoorInfo and not canSee then
					StopShowingDoorInfo()
				end
			elseif _lookingAtDoor then
				_lookingAtDoor = false
				_lookingAtDoorEntity = nil
				_lookingAtDoorCoords = nil
				StopShowingDoorInfo()
			end
		end
	end
end)

AddEventHandler("Keybinds:Client:KeyUp:primary_action", function()
	if _lookingAtDoor and _showingDoorInfo and not _showingDoorDisabled then
		StopShowingDoorInfo()
		DoorAnim()
		exports["sandbox-base"]:ServerCallback("Doors:ToggleLocks", _lookingAtDoor, function(success, newState)
			if success then
				exports["sandbox-sounds"]:PlayOne("doorlocks.ogg", 0.2)
			end
		end)
	end
end)

RegisterNetEvent("Characters:Client:Spawn")
AddEventHandler("Characters:Client:Spawn", function()
	StartCharacterThreads()
	StopShowingDoorInfo()
end)

RegisterNetEvent("Characters:Client:Logout")
AddEventHandler("Characters:Client:Logout", function()
	StopShowingDoorInfo()
end)

-- RegisterNetEvent("Characters:Client:SetData")
-- AddEventHandler("Characters:Client:SetData", function(cData)
-- 	showing = false
-- end)

RegisterNetEvent("Doors:Client:UpdateState", function(door, state)
	if DOORS_STATE and DOORS_STATE[door] then
		DOORS_STATE[door].locked = state

		if DOORS_STATE[door].forcedOpen then
			DoorSystemSetDoorState(door, 0)
			Wait(250)
			DoorSystemSetOpenRatio(door, 0.0)
			DOORS_STATE[door].forcedOpen = false
		end

		DoorSystemSetDoorState(door, state and 1 or 0)

		if _showingDoorInfo == door then
			StartShowingDoorInfo(door)
		end
	end
end)

RegisterNetEvent("Doors:Client:SetForcedOpen", function(door)
	if DOORS_STATE and DOORS_STATE[door] then
		DOORS_STATE[door].forcedOpen = true

		DoorSystemSetOpenRatio(door, -1.0)
		DoorSystemSetDoorState(door, 1)
	end
end)

RegisterNetEvent("Doors:Client:DisableDoor", function(door, state)
	if DOORS_STATE and DOORS_STATE[door] then
		DOORS_STATE[door].disabledUntil = state

		if _showingDoorInfo == door then
			StartShowingDoorInfo(door)
		end
	end
end)

RegisterNetEvent("Doors:Client:UpdateElevatorState", function(elevator, floor, state)
	if ELEVATOR_STATE[elevator] and ELEVATOR_STATE[elevator].floors and ELEVATOR_STATE[elevator].floors[floor] then
		--ELEVATOR_STATE[elevator].locked = state

		ELEVATOR_STATE[elevator].floors[floor].locked = state
	end
end)

function DoorAnim()
	CreateThread(function()
		while not HasAnimDictLoaded("anim@heists@keycard@") do
			RequestAnimDict("anim@heists@keycard@")
			Wait(10)
		end

		TaskPlayAnim(LocalPlayer.state.ped, "anim@heists@keycard@", "exit", 8.0, 1.0, -1, 48, 0, 0, 0, 0)
		Wait(750)
		StopAnimTask(LocalPlayer.state.ped, "anim@heists@keycard@", "exit", 1.0)
	end)
end

RegisterNetEvent("Job:Client:DutyChanged", function(state)
	_newDuty = state
end)
