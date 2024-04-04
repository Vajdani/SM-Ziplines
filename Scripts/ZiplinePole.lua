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
	self.effect:setScale(sm.vec3.new(self.thickness, self.thickness, length))
	self.effect:setRotation(rot)

    self.trigger:setWorldPosition(pos)
    self.trigger:setSize(sm.vec3.new(self.thickness, self.thickness, length * 0.5))
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
---@field progress number
---@field acceleration number
---@field isReverse boolean
---@field boosting boolean
---@field char Character
---@field player Player

---@class ZiplinePole : ShapeClass
---@field riders Rider[]
ZiplinePole = class()
ZiplinePole.connectionInput = 2^25
ZiplinePole.connectionOutput = 2^25
ZiplinePole.maxParentCount = 1
ZiplinePole.maxChildCount = 1

function ZiplinePole:server_onCreate()
    self.riders = {}

    local data = self.interactable.publicData or self.storage:load() or {}
    self:sv_updateTarget(data.target)
end

function ZiplinePole:sv_updateTarget(target)
    self.sv_targetPole = target
    self.storage:save({ target = self.sv_targetPole })
    self.network:setClientData(self.sv_targetPole)
    self:sv_freeRiders()
end

function ZiplinePole:server_onDestroy()
    self:sv_freeRiders()
end

function ZiplinePole:server_onFixedUpdate(dt)
    local child = self.interactable:getChildren()[1]
    if child and not self.sv_targetPole then
        self:sv_updateTarget(child.shape)
    end

    if not self.sv_targetPole then return end

    if not sm.exists(self.sv_targetPole) then
        self.sv_targetPole = nil
        self:sv_freeRiders()
        return
    end

    local startPos = GetPoleEnd(self.shape, dt)
    local targetPos = GetPoleEnd(self.sv_targetPole, dt)
    local zipLine = targetPos - startPos
    local zipLineLength = zipLine:length()

    if zipLineLength > MAXZIPLINELENGTH or sm.physics.raycast(startPos, targetPos, nil, ZIPLINECLEARENCEFILTER) then
        self:sv_updateTarget(nil)
    end

    local zipDir = zipLine:normalize()
    local zipDir_noZ = sm.vec3.new(zipDir.x, zipDir.y, 0):normalize()
    for k, data in pairs(self.riders) do
        data.acceleration = math.min(data.acceleration + dt * ZIPLINEACCELERATIONRATE, 1)

        local char = data.char
        if not sm.exists(char) then
            self:sv_freeRider(k)
            goto continue
        end

        if char:getLockingInteractable() ~= self.interactable then
            print("failsafe", self.interactable.id)
            char:setLockingInteractable(self.interactable)
        end

        local isReverse = data.isReverse
        local isGoingDownhill = zipDir.z < 0 and not isReverse or zipDir.z > 0 and isReverse
        local fraction = math.acos(zipDir:dot(zipDir_noZ)) / MAXZIPLINEANGLE_RAD
        local ziplineSpeed = BASEZIPLINESPEED * (1 + (isGoingDownhill and DOWNHILLMULTIPLIER * fraction or UPHILLMULTIPLIER * fraction))

        if CanPlayerBoost(zipDir, isReverse, char.direction) and data.boosting then
            ziplineSpeed = ziplineSpeed * BOOSTMULTIPLIER
        end

        if isReverse then
            data.progress = math.max(data.progress - dt * ziplineSpeed * data.acceleration / zipLineLength, 0)
        else
            data.progress = math.min(data.progress + dt * ziplineSpeed * data.acceleration / zipLineLength, 1)
        end

        local pos = sm.vec3.lerp(startPos, targetPos, sm.util.clamp(data.progress, 0.01, 0.99)) - vec3_up * 0.75
        sm.physics.applyImpulse(char, ((pos - char.worldPosition) * 2 - ( char.velocity * 0.3 )) * char.mass)

        ::continue::
    end
end

function ZiplinePole:sv_freeRiders()
    for k, data in pairs(self.riders) do
        self:sv_freeRider(k)
    end
end

function ZiplinePole:sv_freeRider(index)
    local data = self.riders[index]
    local char = data.char
    if sm.exists(char) then
        char:setLockingInteractable(nil)

        if not char:isOnGround() then
            local vel = char.velocity
            sm.physics.applyImpulse(char, sm.vec3.new(vel.x, vel.y, 0):safeNormalize(vec3_zero) * vel:length() * char.mass)
        end
    end

    sm.event.sendToTool(g_ziplineInteraction, "sv_setZiplineState", { player = data.player, state = false })
    self.riders[index] = nil
end

---@param eventPlayer? Player
---@param caller Player
function ZiplinePole:sv_toggleAttachment(eventPlayer, caller)
    local player = eventPlayer or caller
    local pId = player.id
    local char = player.character
    if self.riders[pId] then
        self:sv_freeRider(pId)
    else
        local progress, zipDir = CalculateZiplineProgress(char.worldPosition, GetPoleEnd(self.shape), GetPoleEnd(self.sv_targetPole))
        local isReverse =  zipDir:dot(char.direction) < 0
        self.riders[pId] = {
            progress = progress,
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

    sm.effect.playEffect("Zipline - Attach", char.worldPosition)
end

---@param pole Interactable
---@param caller Player
function ZiplinePole:sv_attachToOtherPole(pole, caller)
    self:sv_toggleAttachment(nil, caller)
    sm.event.sendToInteractable(pole, "sv_toggleAttachment", caller)
end

---@param caller Player
function ZiplinePole:sv_boostUpdate(state, caller)
    self.riders[caller.id].boosting = state
end

---@param caller Player
function ZiplinePole:sv_toggleIsReverse(args, caller)
    local pId = caller.id
    local new = not self.riders[pId].isReverse
    self.riders[pId].isReverse = new
    self.riders[pId].acceleration = 0

    sm.event.sendToTool(g_ziplineInteraction, "sv_setZiplineData", { player = caller, data = { isReverse = new } })
    sm.effect.playEffect("Zipline - Attach", caller.character.worldPosition)
end



function ZiplinePole:client_onCreate()
    self.cl_targetPole = nil

    self.line = Line()
    self.line:init( 0.1, sm.color.new(0,1,0), self.shape )
end

function ZiplinePole:client_onDestroy()
    self.line:destroy()
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
    self.cl_targetPole = data

    if not data then
        self.line:stop()
    end
end

local text = "<p textShadow='false' bg='gui_keybinds_bg_orange' color='#66440C' spacing='9'>#%s%.1fm</p>"
local col_safe = sm.color.new("#00ff00")
local col_danger = sm.color.new("#ff0000")
function ZiplinePole:client_canInteract()
    if self.cl_targetPole then
        local distance = (GetPoleEnd(self.shape) - GetPoleEnd(self.cl_targetPole)):length()
        sm.gui.setInteractionText(text:format(ColourLerp(col_safe, col_danger, distance / MAXZIPLINELENGTH):getHexStr():sub(1, 6), distance))
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
            local hit, pole = DoZiplineInteractionRaycast(self.line.trigger)
            if pole then
                self.network:sendToServer("sv_attachToOtherPole", pole:getUserData().pole.interactable)
            elseif CanInteract() then
                self.network:sendToServer("sv_toggleIsReverse")
            end

            return true
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
    local char = sm.localPlayer.getPlayer().character
    return (char.clientPublicData or {}).isRidingZipline == true
end