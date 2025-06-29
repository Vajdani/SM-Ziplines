local Line = class()
function Line:init( thickness, colour, pole )
    self.effect = sm.effect.createEffect("ShapeRenderable")
	self.effect:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
    self.effect:setParameter("color", colour)
    self.effect:setScale( sm.vec3.one() * thickness )

    self.trigger = sm.areaTrigger.createBox(sm.vec3.one() * thickness, vec3_zero, sm.quat.identity(), nil, { pole = pole })

    self.thickness = thickness
	self.spinTime = 0
end

---@param startPos Vec3
---@param endPos Vec3
function Line:update( startPos, endPos )
	local delta = endPos - startPos
    local length = delta:length()

    if length < 0.0001 then
        return
	end

    local pos = startPos + delta * 0.5
    local rot = sm.vec3.getRotation(vec3_up, delta)
	self.effect:setPosition(pos)
	self.effect:setScale(vec3_new(self.thickness, self.thickness, length))
	self.effect:setRotation(rot)

    self.trigger:setWorldPosition(pos)
    self.trigger:setSize(vec3_new(self.thickness, self.thickness, length * 0.5))
    self.trigger:setWorldRotation(rot)

    if not self.effect:isPlaying() then
        self.effect:start()
    end
end

function Line:destroy()
    self.effect:destroy()
    sm.areaTrigger.destroy(self.trigger)
end

function Line:stop()
    self.effect:stop()
end



---@class Rider
---@field acceleration number
---@field isReverse? boolean
---@field boosting boolean
---@field char? Character
---@field player? Player
---@field shape? Shape
---@field int? Interactable
---@field moveDir? number

---@class ZiplinePole : ShapeClass
---@field riders Rider[]
ZiplinePole = class()
ZiplinePole.connectionInput = 2^25
ZiplinePole.connectionOutput = 2^25
ZiplinePole.maxParentCount = 1
ZiplinePole.maxChildCount = 1

function ZiplinePole:server_onCreate()
    self.sv_riders = {}

    local data = self.params or self.storage:load() or {}
    self:sv_updateTarget(data.target)
end

function ZiplinePole:sv_updateTarget(target)
    if target then
        target.interactable.publicData = { poleParent = self.shape }
    elseif self.sv_targetPole then
        self.sv_targetPole.interactable.publicData = {}
    end

    if not (self.interactable.publicData or {}).poleParent then
        self.interactable.publicData = { poleParent = self.shape }
    end

    self.sv_targetPole = target
    self.storage:save({ target = self.sv_targetPole })
    self.network:setClientData(self.sv_targetPole, 1)
    self:sv_freeRiders(true)
end

function ZiplinePole:server_onDestroy()
    self:sv_freeRiders(false)
end

function ZiplinePole:server_onFixedUpdate(dt)
    local child = self.interactable:getChildren()[1]
    if child and not self.sv_targetPole then
        local shape = child.shape
        if self:CheckIfCanConnect(shape, dt) then
            self:sv_updateTarget(shape)
        end
    end

    if not self.sv_targetPole then return end

    if not sm.exists(self.sv_targetPole) then
        self.sv_targetPole = nil
        self:sv_freeRiders(true)
        return
    end

    local succes, zipDir, zipDir_noZ, ziplineLength, startPos, targetPos  = self:CheckIfCanConnect(self.sv_targetPole, dt)
    if not succes then
        self:sv_updateTarget(nil)
        return
    end

    self:UpdateRiders(zipDir, zipDir_noZ, startPos, targetPos, dt)
end

function ZiplinePole:sv_freeRiders(applyImpulse)
    for k, data in pairs(self.sv_riders) do
        self:sv_freeRider(k, applyImpulse)
    end

    self.network:setClientData(self.sv_riders, 2)
end

function ZiplinePole:sv_freeRider(index, applyImpulse)
    if not sm.isServerMode() then
        -- sm.log.warning("sv_freeRider called from client")
        return
    end

    local data = self.sv_riders[index]
    local char = data.char
    if char then
        if sm.exists(char) then
            char:setLockingInteractable(nil)

            if not char:isOnGround() and applyImpulse then
                local vel = char.velocity
                sm.physics.applyImpulse(char, vec3_new(vel.x, vel.y, -vel.z) * char.mass)
            end
        end

        sm.event.sendToTool(g_ziplineInteraction, "sv_setZiplineState", { player = data.player, state = false })
    elseif sm.exists(data.shape) then
        sm.event.sendToInteractable(data.int, "sv_setTarget", nil)
    end

    self.sv_riders[index] = nil
end

---@param eventPlayer? Player
---@param caller Player
function ZiplinePole:sv_toggleAttachment(eventPlayer, caller)
    local player = eventPlayer or caller
    local pId = player.id
    local char = player.character
    if self.sv_riders[pId] then
        self:sv_freeRider(pId, true)
    else
        local frac, zipDir = CalculateZiplineProgress(char.worldPosition, GetPoleEnd(self.shape), GetPoleEnd(self.sv_targetPole))
        local isReverse = zipDir:dot(char.direction) < 0
        self.sv_riders[pId] = {
            acceleration = 0,
            isReverse = isReverse,
            boosting = false,
            char = char,
            player = player
        }

        sm.event.sendToTool(
            g_ziplineInteraction, "sv_setZiplineState",
            {
                player = player,
                state = true,
                data = {
                    zipDir = zipDir,
                    isReverse = isReverse
                }
            }
        )
    end

    self.network:setClientData(self.sv_riders, 2)
    sm.effect.playEffect("Zipline - Attach", char.worldPosition)
end

---@param slider Shape
function ZiplinePole:sv_attachSlider(slider)
    local sId = slider.id
    if self.sv_riders[sId] then
        self:sv_freeRider(sId, true)
    else
        self.sv_riders[sId] = {
            acceleration = 0,
            moveDir = 0,
            boosting = false,
            shape = slider,
            int = slider.interactable
        }
    end

    self.network:setClientData(self.sv_riders, 2)
    sm.effect.playEffect("Zipline - Attach", slider.worldPosition)
end

---@param pole Interactable
---@param caller Player
function ZiplinePole:sv_attachToOtherPole(pole, caller)
    self:sv_toggleAttachment(nil, caller)
    sm.event.sendToInteractable(pole, "sv_toggleAttachment", caller)
end

---@param caller Player
function ZiplinePole:sv_boostUpdate(state, caller)
    if self.sv_riders[caller.id] == nil then return end

    self.network:setClientData(self.sv_riders, 2)
    self.sv_riders[caller.id].boosting = state
end

---@param caller Player
function ZiplinePole:sv_toggleIsReverse(args, caller)
    local pId = caller.id
    local new = not self.sv_riders[pId].isReverse
    self.sv_riders[pId].isReverse = new
    self.sv_riders[pId].acceleration = 0

    self.network:setClientData(self.sv_riders, 2)
    sm.event.sendToTool(g_ziplineInteraction, "sv_setZiplineData", { player = caller, data = { isReverse = new } })
    sm.effect.playEffect("Zipline - Attach", caller.character.worldPosition)
end



function ZiplinePole:client_onCreate()
    self.cl_riders = {}
    self.cl_targetPole = nil

    self.line = Line()
    self.line:init( 0.1, sm.color.new(0,1,0), self.shape )
end

function ZiplinePole:client_onDestroy()
    self.line:destroy()
end

function ZiplinePole:client_onFixedUpdate(dt)
    if sm.isHost then return end

    local succes, zipDir, zipDir_noZ, ziplineLength, startPos, targetPos  = self:CheckIfCanConnect(self.cl_targetPole, dt)
    if succes then
        self:UpdateRiders(zipDir, zipDir_noZ, startPos, targetPos, dt)
    end
end

function ZiplinePole:client_onUpdate(dt)
    local target = self.cl_targetPole
    if not target then return end

    if not sm.exists(target) then
        self.line:stop()
        self.cl_targetPole = nil
        return
    end

    self.line:update(GetPoleEnd(self.shape, dt), GetPoleEnd(target, dt))
end

function ZiplinePole:client_onClientDataUpdate(data, channel)
    if channel == 1 then
        self.cl_targetPole = data

        if not data then
            self.line:stop()
        end
    else
        self.cl_riders = data
    end
end

local text = "<p textShadow='false' bg='gui_keybinds_bg_orange' color='#66440C' spacing='9'>#%s%.1fm</p>"
local col_safe = sm.color.new("#00ff00")
local col_danger = sm.color.new("#ff0000")
function ZiplinePole:client_canInteract()
    if self.cl_targetPole then
        local distance = (GetPoleEnd(self.shape) - GetPoleEnd(self.cl_targetPole)):length()
        gui_setInteractionText(text:format(ColourLerp(col_safe, col_danger, distance / MAXZIPLINELENGTH):getHexStr():sub(1, 6), distance))
    end

    return false
end

local isBlockedAction = {
    [1]  = true,
    [2]  = true,
    [3]  = true,
    [4]  = true,
    [16] = true,
}
function ZiplinePole:client_onAction(action, state)
    local isRidingZipline = self:isRidingZipline()
    if isRidingZipline and action == 3 then
        self.network:sendToServer("sv_boostUpdate", state)
    end

    if not state then return false end

    if isRidingZipline then
        if action == 15 then
            local pole = DoZiplineInteractionRaycast(self.line.trigger)
            if pole then
                self.network:sendToServer("sv_attachToOtherPole", pole:getUserData().pole.interactable)
                return true
            else
                local result = CanInteract()
                if type(result) == "Interactable" then
                    if result:hasSeat() then
                        lplayer_get().character:setLockingInteractable(nil)
                        self.network:sendToServer("sv_toggleAttachment")
                    end
                elseif result then
                    self.network:sendToServer("sv_toggleIsReverse")
                    return true
                end
            end

            return false
        elseif action == 16 then
            self.network:sendToServer("sv_toggleAttachment")
        end

        return isBlockedAction[action] == true
    else
        if action == 15 then
            self.network:sendToServer("sv_toggleAttachment")
        end

        return false
    end
end




function ZiplinePole:isRidingZipline()
    local char = lplayer_get().character
    return (char.clientPublicData or {}).isRidingZipline == true
end

function ZiplinePole:CheckIfCanConnect(pole, dt)
    local startPos = GetPoleEnd(self.shape, dt)
    local targetPos = GetPoleEnd(pole, dt)
    local zipLine = targetPos - startPos
    local ziplineLength = zipLine:length()
    local zipDir = zipLine:normalize()
    local zipDir_noZ = vec3_new(zipDir.x, zipDir.y, 0):normalize()
    if ziplineLength > MAXZIPLINELENGTH or sm.physics.raycast(startPos, targetPos, nil, ZIPLINECLEARENCEFILTER) or not IsSmallerAngle(zipDir, MAXZIPLINEANGLE, zipDir_noZ) then
        return false, zipDir, zipDir_noZ, ziplineLength, startPos, targetPos
    end

    return true, zipDir, zipDir_noZ, ziplineLength, startPos, targetPos
end

function ZiplinePole:UpdateRiders(zipDir, zipDir_noZ, startPos, targetPos, dt)
    local gravityAdjustment = vec3_new(0, 0, -g_gravityStrength * dt)
    for k, data in pairs(self.sv_riders or self.cl_riders) do
        local worldPos, direction, moveDir, isReverse
        local char, shape = data.char, data.shape
        if char then
            if not sm.exists(char) then
                self:sv_freeRider(k, true)
                goto continue
            end

            if char:getLockingInteractable() ~= self.interactable then
                char:setLockingInteractable(self.interactable)
            end

            worldPos = char.worldPosition + (vec3_up * char:getHeight() * 0.5)
            direction = char.direction
            isReverse = data.isReverse
            moveDir = isReverse and -1 or 1
        elseif shape then
            if not sm.exists(shape) or shape.body:isOnLift() then
                self:sv_freeRider(k, true)
                goto continue
            end

            worldPos, direction, moveDir = shape.worldPosition, shape.right, data.int.power
            isReverse = moveDir == -1
        end

        local lineFraction, _, point = CalculateZiplineProgress(worldPos, startPos, targetPos)
        if (point - worldPos):length2() >= ZIPLINEINTERACTIONRANGESQUARED then
            self:sv_freeRider(k, true)
            goto continue
        end

        local isGoingDownhill = zipDir.z < 0 and not isReverse or zipDir.z > 0 and isReverse
        local fraction = math.acos(math.min(zipDir:dot(zipDir_noZ), 1)) / MAXZIPLINEANGLE_RAD
        local ziplineSpeed = BASEZIPLINESPEED * (1 + (isGoingDownhill and DOWNHILLMULTIPLIER or UPHILLMULTIPLIER) * fraction)
        if CanPlayerBoost(zipDir, isReverse, direction) and data.boosting then
            ziplineSpeed = ziplineSpeed * BOOSTMULTIPLIER
        end

        data.acceleration = math.min(data.acceleration + dt * ZIPLINEACCELERATIONRATE, 1)
        local dir = vec3_zero
        if (targetPos - worldPos):length2() <= ZIPLINELINEFRACTIONLIMIT and (not isReverse or moveDir == 0) then
            point = targetPos - zipDir * 0.25
        elseif (startPos - worldPos):length2() <= ZIPLINELINEFRACTIONLIMIT and (isReverse or moveDir == 0) then
            point = startPos + zipDir * 0.25
        else
            dir = zipDir * ziplineSpeed * moveDir * data.acceleration
        end

        if char then
            sm.physics.applyImpulse(char, ((point - worldPos) * 2 + dir - ( char.velocity * 0.3 )) * char.mass)
        elseif shape then
            local sBody = shape.body
            local mass = 0
            for _k, body in pairs(sBody:getCreationBodies()) do
                mass = mass + body.mass
            end

            sm.physics.applyImpulse(sBody, (((point + dir) - worldPos) * 2 - ( sBody.velocity * 0.3 ) - gravityAdjustment) * mass, true)
            sm.physics.applyTorque(sBody, (direction:cross(zipDir_noZ) + shape.at:cross(vec3_up) - sBody.angularVelocity * 0.3) * mass * dt, true)
        end

        ::continue::
    end
end