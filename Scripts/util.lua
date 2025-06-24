vec3_up      = sm.vec3.new(0,0,1)
vec3_right   = sm.vec3.new(1,0,0)
vec3_forward = sm.vec3.new(0,1,0)
vec3_zero    = sm.vec3.zero()

MAXZIPLINELENGTH = 200 --50
MAXZIPLINEANGLE = 75 --45 --30
MAXZIPLINEANGLE_RAD = math.rad(MAXZIPLINEANGLE)
ZIPLINEACCELERATIONRATE = 0.5
ZIPLINELINEFRACTIONLIMIT = 0.25
ZIPLINELOWERLINEFRACTIONLIMIT = 0.02
ZIPLINEUPPERLINEFRACTIONLIMIT = 0.98
ZIPLINEINTERACTIONRANGE = 7.5
ZIPLINEINTERACTIONRANGESQUARED = ZIPLINEINTERACTIONRANGE^2
BASEZIPLINESPEED = 1.25 --5
DOWNHILLMULTIPLIER = 1
UPHILLMULTIPLIER = -0.5
BOOSTMULTIPLIER = 2.5

ZIPLINEPOLE = sm.uuid.new("2327aad6-0a6e-480e-9c73-c11c40dfaf37")
ZIPLINESHOOTFILTER = sm.physics.filter.dynamicBody + sm.physics.filter.staticBody + sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface
ZIPLINESHOOTFILTERTRIGGER = ZIPLINESHOOTFILTER + sm.physics.filter.areaTrigger
ZIPLINESHOOTFILTERTRIGGERCHARACTER = ZIPLINESHOOTFILTERTRIGGER + sm.physics.filter.character
ZIPLINECLEARENCEFILTER = sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface



function CanInteract()
    local hit, result = sm.localPlayer.getRaycast(ZIPLINEINTERACTIONRANGE)
    if hit then
        local shape = result:getShape()
        if shape and shape.interactable and shape.usable or result:getHarvestable() or result:getLiftData() or result:getJoint() --[[or result:getCharacter()]] then
            return shape.interactable or false
        end
    end

    return true
end

--https://math.stackexchange.com/a/1905794
---@param A Vec3 The point
---@param B Vec3 First point of the line
---@param C Vec3 Second point of the line
---@return number fraction, Vec3 direction, Vec3 point
function CalculateZiplineProgress(A, B, C)
    local zipDir = C - B
    local zipLength = zipDir:length()

    local d = (C - B):normalize()
    local v = A - B
    local t = sm.util.clamp(v:dot(d), 0, zipLength) --zipLength * ZIPLINEUPPERLINEFRACTIONLIMIT)
    local P = B + d * t

    return sm.util.clamp((P - B):length() / zipLength, 0, 1), zipDir:normalize(), P
end

local boostAngle = 0.8
function CanPlayerBoost(zipDir, isReverse, playerDir)
    if math.abs(zipDir.z) < 0.1 then
        return false
    end

    local dot = zipDir:dot(playerDir)
    return zipDir.z < 0 and dot > boostAngle and not isReverse or zipDir.z > 0 and dot < -boostAngle and isReverse
end

function IsSmallerAngle(dir, angle, noZ)
    local dirAngle = math.deg(math.acos((noZ or sm.vec3.new(dir.x, dir.y, 0):normalize()):dot(dir)))
    dirAngle = dirAngle == dirAngle and dirAngle or 0 --NaN protection
    return dirAngle < angle, dirAngle
end

---@param pole Shape
---@param dt? number
---@return Vec3
function GetPoleEnd(pole, dt)
    if not pole or not sm.exists(pole) then
        return vec3_zero
    end

    return pole:getInterpolatedWorldPosition() + pole.velocity * (dt or (1/60)) + pole:getInterpolatedUp() * 1.75
end

---@param ignore? AreaTrigger
---@return AreaTrigger?
function DoZiplineInteractionRaycast(ignore)
    local start = sm.localPlayer.getRaycastStart()
    local hit, result = sm.physics.raycast(start, start + sm.localPlayer.getDirection() * 5, ignore, ZIPLINESHOOTFILTERTRIGGER) --sm.physics.spherecast(start, start + sm.localPlayer.getDirection() * 5, 0.15, nil, 8)

    local trigger = result:getAreaTrigger()
    local userData = trigger and trigger:getUserData()
    return (userData and userData.pole) and trigger or nil
end

function ColourLerp(c1, c2, t)
	local r = sm.util.lerp(c1.r, c2.r, t)
	local g = sm.util.lerp(c1.g, c2.g, t)
	local b = sm.util.lerp(c1.b, c2.b, t)
	return sm.color.new(r,g,b)
end