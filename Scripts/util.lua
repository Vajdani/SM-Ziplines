vec3_up      = sm.vec3.new(0,0,1)
vec3_right   = sm.vec3.new(1,0,0)
vec3_forward = sm.vec3.new(1,0,0)

MAXZIPLINELENGTH = 50
MAXZIPLINEANGLE = 30
MAXZIPLINEANGLE_RAD = math.rad(MAXZIPLINEANGLE)
BASEZIPLINESPEED = 2
DOWNHILLMULTIPLIER = 1
UPHILLMULTIPLIER = -0.5
BOOSTMULTIPLIER = 0.25

ZIPLINEPOLE = sm.uuid.new("2327aad6-0a6e-480e-9c73-c11c40dfaf37")
ZIPLINESHOOTFILTER = sm.physics.filter.dynamicBody + sm.physics.filter.staticBody + sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface
ZIPLINECLEARENCEFILTER = sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface



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
    return dirAngle < angle, dirAngle
end

---@param pole Shape
---@param dt? number
---@return Vec3
function GetPoleEnd(pole, dt)
    return pole:getInterpolatedWorldPosition() + pole.velocity * (dt or 0) + pole:getInterpolatedUp() * 1.75
end