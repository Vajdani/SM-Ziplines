vec3_up      = sm.vec3.new(0,0,1)
vec3_right   = sm.vec3.new(1,0,0)
vec3_forward = sm.vec3.new(1,0,0)
vec3_zero    = sm.vec3.zero()

MAXZIPLINELENGTH = 50
MAXZIPLINEANGLE = 30
MAXZIPLINEANGLE_RAD = math.rad(MAXZIPLINEANGLE)
BASEZIPLINESPEED = 5
DOWNHILLMULTIPLIER = 1
UPHILLMULTIPLIER = -0.5
BOOSTMULTIPLIER = 1.5

ZIPLINEPOLE = sm.uuid.new("2327aad6-0a6e-480e-9c73-c11c40dfaf37")
ZIPLINESHOOTFILTER = sm.physics.filter.dynamicBody + sm.physics.filter.staticBody + sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface
ZIPLINECLEARENCEFILTER = sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface
ZIPLINEACCELERATIONRATE = 0.5



function CanInteract()
    local hit, result = sm.localPlayer.getRaycast(7.5)
    if hit then
        local shape = result:getShape()
        if shape and shape.interactable and shape.usable or result:getHarvestable() or result:getLiftData() then
            return false
        end
    end

    return true
end

--https://math.stackexchange.com/a/1905794
---@param A Vec3 The point
---@param B Vec3 First point of the line
---@param C Vec3 Second point of the line
---@return number, Vec3
function CalculateZiplineProgress(A, B, C)
    local d = (C - B):normalize()
    local v = A - B
    local t = v:dot(d)
    local P = B + d * t

    local zipDir = C - B
    return sm.util.clamp((P - B):length() / (zipDir):length(), 0, 1), zipDir:normalize()
end

local boostAngle = 0.8
function CanPlayerBoost(zipDir, isReverse, playerDir)
    local dot = zipDir:dot(playerDir)
    return zipDir.z < 0 and dot > boostAngle and not isReverse or zipDir.z > 0 and dot < -boostAngle and isReverse
end

function IsSmallerAngle(dir, angle)
    local dir_noZ = sm.vec3.new(dir.x, dir.y, 0):normalize()
    local dirAngle = math.deg(math.acos(dir_noZ:dot(dir)))
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

    return pole:getInterpolatedWorldPosition() + pole.velocity * (dt or 0) + pole:getInterpolatedUp() * 1.75
end

---@param ignore? AreaTrigger
---@return boolean, AreaTrigger
function DoZiplineInteractionRaycast(ignore)
    local start = sm.localPlayer.getRaycastStart()
    local hit, result = sm.physics.raycast(start, start + sm.localPlayer.getDirection() * 5, ignore, 8) --sm.physics.spherecast(start, start + sm.localPlayer.getDirection() * 5, 0.15, nil, 8)
    return hit, result:getAreaTrigger()
end

function BoolToNum(bool)
    return bool and 1 or 0
end

function ColourLerp(c1, c2, t)
	local r = sm.util.lerp(c1.r, c2.r, t)
	local g = sm.util.lerp(c1.g, c2.g, t)
	local b = sm.util.lerp(c1.b, c2.b, t)
	return sm.color.new(r,g,b)
end