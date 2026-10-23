-- Pactblade - custom vocation for Dragon's Dogma 2 (REFramework script). TEST BUILD.
-- Needs _DragonCore 1.2.0+ (by Bloodragon).
--   * While Pactblade is active and a sword is in hand, Fighter's shield actions are off. Defend's button
--     (JobSpecialAction) fires Eldritch Blast instead: tap = Eldritch Blast, hold and release = Charged Eldritch
--     Blast. The blast leaves the left palm (Mystic Spearhand's bolt animations, Magike Sperepelote's projectile).
--   * Blast damage = the hit's magick base x Magick Bolt's attack multiplier x the passive's magick bonus x 5 / 10.
--   * Passive on all your other hits: magick part x1.5 (physical part unchanged).
-- Nothing is written into the save; Reset scripts or removing the file undoes everything.
local NAME, VERSION = "Pactblade", "3.15-test"
local DATA = "Pactblade.json"

local okDC, dcv = pcall(require, "DragonCore.version")
if not okDC or (tonumber(dcv.number) or 0) < 10200 then
    re.on_draw_ui(function()
        if imgui.tree_node(NAME .. " (NOT LOADED)") then
            imgui.text_colored("Pactblade needs _DragonCore 1.2.0 or newer.", 0xFF5050FF)
            imgui.tree_pop()
        end
    end)
    return
end
local runtime = require("DragonCore.game.runtime")
local frame = require("DragonCore.game.frame")
frame.start()

------------------------------------------------------------------------
-- tuned values (from the in-game tests)
------------------------------------------------------------------------
local JOB07_SHELLS = "AppSystem/Shell/UserData/HumanShellParamData_Job07.user"
local SKELETON_SHELLS = "AppSystem/ch/ch226/userdata/ch226003_shellparamdata.user"   -- the Skeleton Lord's waves (0)
local BLAST = {
    -- Eldritch Slash's wave (Magike Cut's shell 6): coloured like the blasts; keeps its own damage (no factor) and its
    -- full-size hit effects (noScale)
    slash = { shell = 6, noScale = true, name = "Eldritch Slash", dmgMul = 2, stagger = 5 },   -- stagger: 2.0 -> 10 (user)
    tap = { action = "Job07_MagicBindImcomplete", layer = 1, delay = 0.46, shell = 13, scale = 1.0, speed = 0.4,
            fallback = "Job07_MagicBindImcompleteFullBody", fallbackLayer = 0,   -- when the upper-body one won't start
            fx = 1.0, flash = "own", mult = 5, factor = 0.2127, name = "Eldritch Blast", stagger = 0.25 },
    charged = { action = "Job07_MagicBindComplete", layer = 0, delay = 0.30, shell = 12, scale = 1.0, speed = 2.0,
                fx = 0.5, flash = "tap", mult = 10, factor = 0.4255, name = "Eldritch Bolt", stagger = 0.5 },   -- (user: the charged blast is called Eldritch Bolt)
    -- Eldritch Burst: pressed during / right after Onslaught or Empale. The charged animation; the hit area is a
    -- Speregonne projectile (shell 13, used for nothing else) with its effects shrunk to nothing and no launch flash
    burst = { action = "Job07_MagicBindComplete", layer = 0, delay = 0.30, shell = 12, scale = 1.0, speed = 0.3,
              fx = 0.5, flash = "tap", mult = 5, factor = 0.4255, name = "Eldritch Burst", lifetime = 0.25, hidden = "launch only",
              cast = { mode = "joint", joint = "L_Hand_Palm", face = "owner" },
              range = 2.5, arc = 150, stagger = 1.0, flinchOnly = true,
              armor = 1.5,        -- seconds of hyper armour from the start
              cancelAfter = 0.1 },  -- after the burst has fired, an attack press ends the animation's long recovery
}
local DODGE = "Job04_Dodge"   -- Thief's Swift Step: the vocation button's tap (user)
local DODGE_LOCK = 0.45       -- a new dodge only after the current one has run this long (it was spammable)
-- the direction the stick points, camera-relative, nil without stick input. Worked out from the stick and the camera
-- (the game's own move direction is not updated during a dodge, so chained dodges kept the old one); which way is
-- "right" is checked against the game's move direction while walking normally
local stickSide = 1
local function stick_candidates(a)
    local ax = a.input:call("get_AxisL")
    local cam = sdk.get_primary_camera():get_GameObject():get_Transform():get_Position()
    local me = a.character:get_GameObject():get_Transform():get_Position()
    local fx, fz = me.x - cam.x, me.z - cam.z
    local len = math.sqrt(fx * fx + fz * fz)
    if len < 0.01 then return nil end
    fx, fz = fx / len, fz / len
    local function yaw_for(side)
        local rx, rz = fz * side, -fx * side
        local dx, dz = fx * ax.y + rx * ax.x, fz * ax.y + rz * ax.x
        return math.deg(math.atan(dx, dz))
    end
    return yaw_for(1), yaw_for(-1)
end
local function angle_gap(a1, a2) return math.abs(((a1 - a2) + 180) % 360 - 180) end
local function stick_yaw(a)
    local deg
    pcall(function()
        if not a.input:call("isLeverInputL") then return end
        local y1, y2 = stick_candidates(a)
        if y1 then deg = stickSide == 1 and y1 or y2 end
    end)
    return deg
end
local function face_yaw(a, deg)   -- (name kept: sets the MOVE direction only, the character doesn't turn)
    pcall(function()
        local tac = a.character["<TargetAngleCtrl>k__BackingField"]
        tac.Move["<AngleDeg>k__BackingField"] = deg
        pcall(function() tac:call("setMoveAngleDeg(System.Single)", deg) end)
    end)
end
local HOLD_SEC = 0.5          -- held longer than this = charged (user: 0.5 s, the first value again)
local COMBO_WINDOW = 0.3      -- a press in the first 0.3 s of an Onslaught / Empale swing = Eldritch Burst (user)
local PALM = "L_Hand_Palm"
local LOCK_RANGE = 30         -- the blast turns to the nearest enemy within this many metres
local MB_RATE = 1.0           -- Magick Bolt's attack multiplier (still to be measured)
local PHYS_BONUS, MAG_BONUS = 1.0, 1.5   -- user: no physical bonus, magick +50%
-- Mystic Spearhand's hand effect (Forbeding / Redouted Bolt), kept on the left arm while Pactblade is active
local GLOW = { file = "vfx/effects/character/ch07/ns/13_ch07_ns_025_00.efx", id = 25, element = 0,
               every = 2.0 }   -- renewed this often (the old one finishes a moment later)
local GLOW_FF = 0.15          -- seconds to fast-forward to the freeze moment
local GLOW_LOOP = { 2.65, 3.00 }  -- while the blast button is held: this part of the effect loops (no vibrating air)
local GLOW_LOOP_SPEED = 0.5       -- ... at half speed (user)
local GLOW_JOINTS = { "L_Arm_Lower", "L_Hand_Palm", "L_Arm_Upper", "root" }

-- the player's choices (reframework/data/Pactblade.json)
-- defaults = the look the user settled on (2026-10-21)
local cfg = { active = true, beam = false, glow = true, nox = true, glowSpeed = 0.5, freeze = true, freezeAt = 2.59, boom = 0.31,
             armTint = true, armR = 255, armG = 3, armB = 30, armBright = 5.2, blastTint = true, bind = true, warpFx = "wisps",
             noTint = { ["13/23/0"] = true, ["13/23/1"] = true, ["13/23/2"] = true,   -- see-through layers that
                      },                                                            -- cover the screen tinted (user)
             comboNoDust = true, burstWindow = 0.8, burstWindowEmpale = COMBO_WINDOW, burstWindowEmpaleAir = 0.8,   -- air Empale: as before 1.41 (user)
             burstFromEmpale = 0.5, empaleFrom = 56.6, empaleTo = 110.5,
             tuskFrom = 50, tuskTo = 91, slashFrame = 64, slashR = 255, slashG = 60, slashB = 170, slashBright = 6.0,
             slashFastFrom = 97, slashRange = 8, slashWave = "magike", slashHitRange = 28,
             slashTurn = true, slashTurnRange = 10, slashTurnCone = 70, slashTurnSpeed = 360, glowVariant = "h285g2", glowLvCharge = 4,
             chargeFull = true, chargeSpeed = 0.35, chargeEnd = 5.0,
             glowSheathed = false, armLight = false, lightLm = 800, lightRadius = 4,
             afterimage = true, afterimageSecs = 0.3,
             comboTurn = true, comboTurnSpeed = 360, comboTurnRange = 12, comboTurnCone = 70, comboDynamic = true,
             finisherHeight = -0.3, smiteSkill = "Job01_BlinkStrike",   -- (Burst Strike, user's bind)
             mistySkill = "Job01_CymbalAttack",   -- (Misty Dive's default slot: Shield Drum, the user's; rebindable)
             noxBladeR = 91, noxBladeG = 26, noxBladeB = 142, noxBladeBright = 1.0,   -- Nox look (user's sliders)
             noxMistR = 126, noxMistG = 0, noxMistB = 54, noxMistBright = 1.3, smite = {}, noxSmite = nil }   -- (user: the air finisher was too high at head + 0.4 m)
do
    local saved = json.load_file(DATA) or {}
    if type(saved.active) == "boolean" then cfg.active = saved.active end
    if type(saved.glow) == "boolean" then cfg.glow = saved.glow end
    if type(saved.nox) == "boolean" then cfg.nox = saved.nox end
    if type(saved.glowSpeed) == "number" then cfg.glowSpeed = saved.glowSpeed end
    if type(saved.freeze) == "boolean" then cfg.freeze = saved.freeze end
    if type(saved.freezeAt) == "number" then cfg.freezeAt = saved.freezeAt end
    if type(saved.boom) == "number" then cfg.boom = saved.boom end
    for _, k in ipairs({ "armR", "armG", "armB", "armBright" }) do
        if type(saved[k]) == "number" then cfg[k] = saved[k] end
    end
    if type(saved.armTint) == "boolean" then cfg.armTint = saved.armTint end
    if type(saved.blastTint) == "boolean" then cfg.blastTint = saved.blastTint end
    if type(saved.bind) == "boolean" then cfg.bind = saved.bind end
    if type(saved.comboNoDust) == "boolean" then cfg.comboNoDust = saved.comboNoDust end
    if type(saved.slashTurn) == "boolean" then cfg.slashTurn = saved.slashTurn end   -- (was not read back before 1.71)
    if type(saved.keepDay) == "boolean" then cfg.keepDay = saved.keepDay end
    if type(saved.glowVariant) == "string" then cfg.glowVariant = saved.glowVariant end
    if type(saved.smiteSkill) == "string" then cfg.smiteSkill = saved.smiteSkill end
    if type(saved.mistySkill) == "string" then cfg.mistySkill = saved.mistySkill end
    if type(saved.smite) == "table" then cfg.smite = saved.smite end
    if type(saved.noxSmite) == "table" then cfg.noxSmite = saved.noxSmite end
    for _, k in ipairs({ "brewLand", "brewPour" }) do   -- Caustic Brew's picked sounds
        if type(saved[k]) == "table" and type(saved[k].id) == "number" then cfg[k] = saved[k] end
    end
    if type(saved.chargeFull) == "boolean" then cfg.chargeFull = saved.chargeFull end
    if type(saved.chargeSpeed) == "number" then cfg.chargeSpeed = saved.chargeSpeed end
    if type(saved.chargeEnd) == "number" then cfg.chargeEnd = saved.chargeEnd end
    if type(saved.glowSheathed) == "boolean" then cfg.glowSheathed = saved.glowSheathed end
    if type(saved.glowLvCharge) == "number" then cfg.glowLvCharge = saved.glowLvCharge end
    if type(saved.armLight) == "boolean" then cfg.armLight = saved.armLight end
    if type(saved.lightLm) == "number" then cfg.lightLm = saved.lightLm end
    if type(saved.lightRadius) == "number" then cfg.lightRadius = saved.lightRadius end
    if type(saved.afterimage) == "boolean" then cfg.afterimage = saved.afterimage end
    if type(saved.afterimageSecs) == "number" then cfg.afterimageSecs = saved.afterimageSecs end
    if type(saved.comboTurn) == "boolean" then cfg.comboTurn = saved.comboTurn end
    if type(saved.comboDynamic) == "boolean" then cfg.comboDynamic = saved.comboDynamic end
    if type(saved.finisherHeight) == "number" then cfg.finisherHeight = saved.finisherHeight end
    for _, k in ipairs({ "comboTurnSpeed", "comboTurnRange", "comboTurnCone" }) do
        if type(saved[k]) == "number" then cfg[k] = saved[k] end
    end
    for _, k in ipairs({ "burstWindow", "burstWindowEmpale", "burstWindowEmpaleAir", "burstFromEmpale", "empaleFrom", "empaleTo", "tuskFrom", "tuskTo", "slashFrame", "slashR", "slashG", "slashB", "slashBright", "slashFastFrom", "slashRange", "slashWave", "slashTurnRange", "slashTurnCone", "slashTurnSpeed", "slashHitRange",
                         "noxBladeR", "noxBladeG", "noxBladeB", "noxBladeBright", "noxMistR", "noxMistG", "noxMistB", "noxMistBright" }) do
        if type(saved[k]) == "number" then cfg[k] = saved[k] end
    end
    if type(saved.noTint) == "table" then for k, v in pairs(saved.noTint) do if v == true then cfg.noTint[k] = true end end end
    if saved.warpFx == "quikfot" or saved.warpFx == "blink" or saved.warpFx == "wisps" then cfg.warpFx = saved.warpFx end
end
local glowCol
local function save_cfg()
    json.dump_file(DATA, { armRoutes = glowCol and glowCol.routes, active = cfg.active, beam = cfg.beam, glow = cfg.glow, nox = cfg.nox, glowSpeed = cfg.glowSpeed,
                           freeze = cfg.freeze, freezeAt = cfg.freezeAt, boom = cfg.boom, armTint = cfg.armTint,
                           armR = cfg.armR, armG = cfg.armG, armB = cfg.armB, armBright = cfg.armBright,
                           blastTint = cfg.blastTint, bind = cfg.bind, warpFx = cfg.warpFx,
                           noTint = cfg.noTint, comboNoDust = cfg.comboNoDust, parts = cfg.parts,
                           burstWindow = cfg.burstWindow, burstWindowEmpale = cfg.burstWindowEmpale,
                           burstWindowEmpaleAir = cfg.burstWindowEmpaleAir, burstFromEmpale = cfg.burstFromEmpale,
                           empaleFrom = cfg.empaleFrom, empaleTo = cfg.empaleTo, tuskFrom = cfg.tuskFrom, tuskTo = cfg.tuskTo,
                           slashFrame = cfg.slashFrame, slashR = cfg.slashR, slashG = cfg.slashG, slashB = cfg.slashB,
                           slashBright = cfg.slashBright, slashFastFrom = cfg.slashFastFrom,
                           slashRange = cfg.slashRange, slashWave = cfg.slashWave, slashTurn = cfg.slashTurn, slashHitRange = cfg.slashHitRange,
                           slashTurnRange = cfg.slashTurnRange, slashTurnCone = cfg.slashTurnCone, slashTurnSpeed = cfg.slashTurnSpeed,
                           keepDay = cfg.keepDay, glowVariant = cfg.glowVariant,
                           chargeFull = cfg.chargeFull, chargeSpeed = cfg.chargeSpeed, chargeEnd = cfg.chargeEnd,
                           glowSheathed = cfg.glowSheathed, glowLvCharge = cfg.glowLvCharge, armLight = cfg.armLight, lightLm = cfg.lightLm,
                           lightRadius = cfg.lightRadius, afterimage = cfg.afterimage, afterimageSecs = cfg.afterimageSecs,
                           comboTurn = cfg.comboTurn, comboTurnSpeed = cfg.comboTurnSpeed, comboTurnRange = cfg.comboTurnRange,
                           comboTurnCone = cfg.comboTurnCone, comboDynamic = cfg.comboDynamic,
                           finisherHeight = cfg.finisherHeight, brewLand = cfg.brewLand, brewPour = cfg.brewPour,
                           smiteSkill = cfg.smiteSkill, mistySkill = cfg.mistySkill, noxBladeR = cfg.noxBladeR, noxBladeG = cfg.noxBladeG,
                           noxBladeB = cfg.noxBladeB, noxBladeBright = cfg.noxBladeBright, noxMistR = cfg.noxMistR,
                           noxMistG = cfg.noxMistG, noxMistB = cfg.noxMistB, noxMistBright = cfg.noxMistBright, smite = cfg.smite,
                           noxSmite = cfg.noxSmite })
end
-- ground Empale after its Burst window (frame > cfg.empaleTo) is only its long way back to idle: dodging is fine there
local function tusk_recovering(a)   -- Tusk Toss after its Burst window (frame > cfg.tuskTo): dodging is fine
    local fr = 0
    pcall(function() fr = a.character.FullBodyLayer:call("get_Frame") end)
    return fr > cfg.tuskTo
end
local function empale_recovering(a, curA)
    if curA:find("Air") then return false end
    local fr = 0
    pcall(function() fr = a.character.FullBodyLayer:call("get_Frame") end)
    return fr > cfg.empaleTo
end

-- debug info (shown in the menu's Debug section only)
local dbg = { log = {}, hits = {}, blocked = 0, suppressed = 0, glowMethod = "A", glowJoint = "L_Arm_Lower",
              glow = "-" }
local trace = {}
-- debug files: written at most every 2 s (each write is disk I/O on the game thread - a stutter per hit / warp)
dbg.files, dbg.filesAt = {}, 0
function dbg.save(name, data) dbg.files[name] = data end
re.on_frame(function()
    if os.clock() - dbg.filesAt < 2 or next(dbg.files) == nil then return end
    dbg.filesAt = os.clock()
    for name, data in pairs(dbg.files) do pcall(json.dump_file, name, data) end
    dbg.files = {}
end)
local function note(s)
    table.insert(dbg.log, os.date("%H:%M:%S") .. "  " .. s)
    while #dbg.log > 8 do table.remove(dbg.log, 1) end
    table.insert(trace, ("%s %.2f  %s"):format(os.date("%H:%M:%S"), os.clock(), s))
    while #trace > 120 do table.remove(trace, 1) end
    dbg.save("Pactblade_trace.json", trace)
end

------------------------------------------------------------------------
-- state shared with the hooks (updated every frame)
------------------------------------------------------------------------
local live = { on = false, go = nil, am = nil, ctx = nil, avail = nil, shieldWorn = false, sc = nil }
-- while walking normally: which side matches the game's own move direction
re.on_frame(function()
    if not live.on then return end
    local a = runtime.player()
    if not a or not a:valid() then return end
    pcall(function()
        if a:current_action(0) ~= "NormalLocomotion" or not a.input:call("isLeverInputL") then return end
        local ax = a.input:call("get_AxisL")
        if math.abs(ax.x) < 0.5 then return end   -- only a clearly sideways stick tells the sides apart
        local game = a.character["<TargetAngleCtrl>k__BackingField"]:call("get_MoveAngleDeg")
        local y1, y2 = stick_candidates(a)
        if not y1 then return end
        local want = angle_gap(y1, game) <= angle_gap(y2, game) and 1 or -1
        if want ~= stickSide then stickSide = want; note("dodge: stick sides set to " .. want) end
    end)
end)
local PACK_ID = "pactblade"          -- the VSB vocation pack (reframework/data/VSB/packs/pactblade)
local forceActive = false            -- Debug: test without VSB's pick (never saved)
local ignorePick = false             -- Debug: stay off even when Pactblade is picked (crash hunting)
local function vsb_state()
    local api = rawget(_G, "VSB_API")
    local app = api and api.app
    if not app then return "missing" end
    return (app.picks and app.picks.Job01 == PACK_ID) and "picked" or "not picked"
end

;(function()   -- the VSB pick kept over a script reset
    local FILE = "Pactblade_vsb_pick.json"
    re.on_script_reset(function()
        pcall(json.dump_file, FILE, { picked = vsb_state() == "picked", at = os.time() })
    end)
    local saved = json.load_file(FILE)
    pcall(json.dump_file, FILE, {})   -- used once
    if type(saved) ~= "table" or not saved.picked or type(saved.at) ~= "number" or os.time() - saved.at > 60 then return end
    local tries = 0
    local function again()
        if tries < 0 then return end
        tries = tries + 1
        local api = rawget(_G, "VSB_API")
        local app = api and api.app
        if app and app.picks and app.set_vocation_pick then
            tries = -1
            if app.picks.Job01 == nil then
                local ok, e = pcall(app.set_vocation_pick, app, "Job01", PACK_ID)
                note(ok and "script reset: Pactblade picked in VSB again" or ("script reset: re-pick failed: " .. tostring(e)))
            end
        elseif tries > 1200 then tries = -1; note("script reset: VSB not found - Pactblade not re-picked") end
    end
    re.on_frame(function() pcall(again) end)
end)()

-- Fighter's shield actions (Defend and the rest) are refused while Pactblade is active
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method(
        "requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"), function(args)
        if not live.on or not live.am or sdk.to_int64(args[2]) ~= live.am then return end
        local ok, name = pcall(function() return sdk.to_managed_object(args[4]):call("ToString()") end)
        if ok and name and name:find("^Job01_") and (name:find("Guard") or name:find("Shield")) then
            dbg.blocked = dbg.blocked + 1
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(r) return r end)
end)

------------------------------------------------------------------------
-- Fighter kit changes while Pactblade is active
------------------------------------------------------------------------
-- core skills: Thief's Controlled Fall + Footpad on; Fighter's shield core skills off (player only)
local GRANT = { [17] = true, [18] = true, [27] = true }          -- Job04_BreakFall, Job04_KickWall, Job07 Quik Fot
local DENY = { [4] = true, [5] = true, [7] = true, [8] = true }  -- Deflect, True Deflect, Steeled Foundation, Enchanted Counter
for _, spec in ipairs({ { "app.HumanSkillContext", "isNormalSkillEnable(app.HumanNormalSkillID)", "ctx" },
                        { "app.PlayerInputProcessorDetail", "isNormalSkillEnable(app.HumanNormalSkillID)", nil },
                        { "app.HumanSkillAvailability", "isNormalSkillAvailable(app.HumanNormalSkillID)", "avail" } }) do
    pcall(function()
        local stack = {}
        sdk.hook(sdk.find_type_definition(spec[1]):get_method(spec[2]), function(args)
            local v = false
            if live.on and (not spec[3] or sdk.to_int64(args[2]) == live[spec[3]]) then
                local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
                if GRANT[id] then v = 1 elseif DENY[id] then v = 0 end
            end
            stack[#stack + 1] = v
        end, function(r)
            local v = table.remove(stack)
            if v then return sdk.to_ptr(v) end
            return r
        end)
    end)
end

-- Footpad and Controlled Fall: only the current vocation's input handler runs, so Thief's is called every frame
-- (Lenient Stagger and Exhaustion's method; if that mod already does Controlled Fall, it is left to it)
local function lse_fall()
    local f = package.loaded["_NickCore/Functions"]
    return f and f.on_frame and f.on_frame["LSE - Controlled fall"] ~= nil
end
local fall = { state = nil }
local QUIK_FOT = "Job07_MagicBindJustLeap"
local leap = { untilT = 0 }
local function unbind(target, mb)
    local ok, err = pcall(function()
        if not target then error("no bound enemy recorded") end
        local bc = target:get_field("<BindCtrl>k__BackingField")
        if not bc then bc = target:call("get_BindCtrl") end
        local mod = bc:call("get_MagicBind")
        mod:call("stop(System.Boolean)", false)
        pcall(mod.call, mod, "deleteBindEffect")
    end)
    if mb then pcall(mb.call, mb, "resetHitMagicBindInfo") end
    note(ok and "Quik Fot over: bind taken off the enemy" or ("unbind failed: " .. tostring(err)))
end
pcall(function()
    sdk.hook(sdk.find_type_definition("app.Job04BreakFall"):get_method("setMotion(System.Single)"), function(args)
        if not live.on or lse_fall() then return end
        pcall(function()
            local ch = sdk.to_managed_object(args[2])["<Character>k__BackingField"]
            if ch and ch:get_GameObject():get_address() == live.go then fall.state = "start" end
        end)
    end, function(r) return r end)
end)
re.on_frame(function()
    if not live.on then return end
    local a = runtime.player()
    if not a or not a:valid() then return end
    local d
    pcall(function() d = a.character["<InputProcessor>k__BackingField"].DetailInstances[3] end)
    if not d then dbg.thief = "Thief's input handler not found"; return end
    pcall(d.call, d, "processKickWall")
    if cfg.bind then
        local d6
        pcall(function() d6 = a.character["<InputProcessor>k__BackingField"].DetailInstances[6] end)
        if d6 then
            local ok, v = pcall(d6.call, d6, "processJustMagicBind")
            if ok and v == true then note("Quik Fot started") end
            if not ok then dbg.leap = "Quik Fot handler error: " .. tostring(v) end
        else dbg.leap = "Mystic Spearhand's input handler not found" end
        pcall(function()
            local h = a.character:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.Human"))
            local mb = h:get_field("<Job07ActionCtrl>k__BackingField"):get_field("<MagicBindCtrl>k__BackingField")
            local open = mb:call("get_IsJustMagicBindEnable")
            if open and not dbg.leapOpen then note("Quik Fot window open (press Jump)") end
            dbg.leapOpen = open
            dbg.leap = "Quik Fot window: " .. (open and "OPEN" or "closed")
            local now = os.clock()
            if open and dbg.hex_put and (a:button_pressed("Interact") or a:button_pressed("GimmickAction")) then
                local ok, e = pcall(dbg.hex_put, a, mb:call("get_MagicBindShellHitOwner"))   -- (Examine: Hex on it)
                if not ok then note("Hex failed: " .. tostring(e)) end
            end
            if open and a:button_pressed("Jump") then
                if dbg.lastKind == "burst" and now - (dbg.lastFireT or -10) < 6 and dbg.burst_step then
                    -- after a Burst bind: to the far side of the enemy (user), not Quik Fot's leap
                    dbg.burstWant = { target = mb:call("get_MagicBindShellHitOwner"), mb = mb, t = now }   -- (done in UpdateBehavior)
                else
                    leap.untilT = now + 0.3
                    leap.target = mb:call("get_MagicBindShellHitOwner")
                    leap.mb = mb
                    note("Jump in the Quik Fot window")
                end
            end
        end)
        if leap.untilT > os.clock() then
            local cur = a:current_action(0)
            if cur and tostring(cur):find("MagicBindJustLeap") then
                leap.untilT = 0
                leap.playing = os.clock()
                note("Quik Fot playing: " .. tostring(cur))
            else
                local ok = a:request_action(QUIK_FOT, 0)
                if not leap.asked then note("Quik Fot requested -> " .. tostring(ok) .. " " .. tostring(a.errors and a.errors.request_action or "")) end
                leap.asked = true
            end
        else leap.asked = nil end
        if leap.playing and (a:current_action(0) ~= QUIK_FOT or os.clock() - leap.playing > 3) then
            leap.playing = nil
            unbind(leap.target, leap.mb)
            leap.target, leap.mb = nil, nil
        end
    end
    if lse_fall() then dbg.thief = "Footpad: on | Controlled Fall: left to Lenient Stagger"; return end
    pcall(d.call, d, "processBreakFall")
    dbg.thief = "Footpad: on | Controlled Fall: on"
    if fall.state == "start" then
        fall.state = "play"
    elseif fall.state == "play" then
        fall.state = nil
        pcall(function()
            local L = a.character.FullBodyLayer   -- Thief's roll lives in Thief's motion bank (145)
            L:call("changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)",
                145, L:get_MotionID(), 0.0, 12.0, 1, 1)
        end)
        pcall(a.consume_stamina, a, 100)
        note("Controlled Fall")
    end
end)

-- Onslaught (the light attack chain) 1.5x faster; every other sped-up attack (Empale, dash / climbing / air
-- attacks, finishing moves, Blink Strike) 1.2x (user)
local FAST, FASTER_OTHER = 1.5, 1.2
local ONSLAUGHT = { Job01_AttackLeft = true, Job01_AttackRight = true, Job01_AttackAir = true }
local speeding = false
local combo = { stage = 0, lastPress = -10 }   -- Archfey Combo, in Cloudfall Strike's slot (see below)
local wisps                                     -- the warp wisps (defined further down)
local function basic_attack(name)
    if not name or not name:find("^Job01_") then return false end
    if name:find("Shield") or name:find("Guard") or name:find("Hindsight") or name:find("Cymbal") then return false end
    return name:find("Attack") ~= nil or name:find("FinishingMove") ~= nil
end
local function update_speed(a)
    local cur = a:current_action(0)
    dbg.action = cur
    if live.on and basic_attack(cur) and combo.stage == 0 then
        dbg.lastBasic = os.clock()
        local mot
        pcall(function() local L = a.character.FullBodyLayer; mot = L:get_MotionBankID() * 100000 + L:get_MotionID() end)
        if cur ~= dbg.basicName or mot ~= dbg.basicMot then   -- a new swing started
            dbg.basicName, dbg.basicMot, dbg.basicStart = cur, mot, os.clock()
        end
        local sp = ONSLAUGHT[cur] and FAST or FASTER_OTHER
        a:set_speed(sp)
        dbg.spedSeen = dbg.spedSeen or {}
        if not dbg.spedSeen[cur] then dbg.spedSeen[cur] = true; note(("speed x%.1f: %s"):format(sp, cur)) end
        speeding = true
    elseif speeding then
        dbg.basicName, dbg.basicMot = nil, nil
        a:set_speed(nil)
        speeding = false
    end
end

-- no shield: equipping one is refused while Pactblade is active (fresh equips only, never items already equipped
-- when a save loads); a shield already worn is reported in the menu
local SLOT_SUB = 1
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ItemManager"):get_method(
        "setEquip(app.ItemDefine.StorageData, app.Character, app.EquipData.SlotEnum, System.Boolean, System.Boolean)"),
        function(args)
            if not live.on then return end
            local skip = false
            pcall(function()
                if (sdk.to_int64(args[5]) & 0xFFFFFFFF) ~= SLOT_SUB then return end
                local ch = sdk.to_managed_object(args[4])
                if not ch or ch:get_GameObject():get_address() ~= live.go then return end
                local sd = sdk.to_valuetype(args[3], "app.ItemDefine.StorageData")
                if sd:get_field("_IsEquipped") then return end
                skip = true
            end)
            if skip then
                dbg.shieldRefused = (dbg.shieldRefused or 0) + 1
                note("refused to equip a shield (Pactblade)")
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(r) return r end)
end)

------------------------------------------------------------------------
-- Eldritch Blast
------------------------------------------------------------------------
local update_glow, boon_clear, colour_shell
local blasts = {}          -- { record, kind, born, ... }
local st = { phase = "idle", t0 = 0, pending = nil }
local lastFire = -100
local lastKind = nil       -- the last blast fired (tap / charged / burst)
local bindBolt = { go = nil, addr = nil, born = 0 }   -- the Forbeding Bolt riding along with the charged blast
local ourSpawn = false     -- our own projectiles are never suppressed

-- the projectile's effect size and launch flash: the shared shell settings are changed for our blast and put back
local params = {}          -- shell id -> app.ShellParam (learned from the first blast of each kind)
local restoreQueue = {}
local function restore_effects(force)
    local now = os.clock()
    for i = #restoreQueue, 1, -1 do
        local r = restoreQueue[i]
        if force or now >= r.at then
            pcall(function()
                r.eff:set_field("UseEffectScale", r.use)
                r.eff:set_field("EffectScale", r.scale)
                r.eff:set_field("StartElementID", r.start)
            end)
            table.remove(restoreQueue, i)
        end
    end
end
local function shape_effects(b)
    if b.noShape then return end
    local param = params[b.shell]
    if not param then return end
    pcall(function()
        local eff = param._ShellParameterBase.effectParam
        for _, r in ipairs(restoreQueue) do if r.eff == eff then return end end
        table.insert(restoreQueue, { at = os.clock() + 1.0, eff = eff, use = eff.UseEffectScale,
                                     scale = eff.EffectScale, start = eff.StartElementID })
        eff:set_field("EffectScale", Vector3f.new(b.fx, b.fx, b.fx))
        eff:set_field("UseEffectScale", true)
        if b.flash == "none" then eff:set_field("StartElementID", -1)
        elseif b.flash == "tap" and params[11] then
            eff:set_field("StartElementID", params[11]._ShellParameterBase.effectParam.StartElementID)
        end
    end)
end
re.on_script_reset(function()
    restore_effects(true)
    if st.armorUntil then pcall(function() local a = runtime.player(); if a then a:set_super_armor(false) end end) end
end)

local function spawn(a, node, opts)
    ourSpawn = true
    local ok, res = pcall(a.spawn_shell, a, node, opts)
    ourSpawn = false
    if not ok then return nil, tostring(res) end
    if not res then return nil, tostring(a.errors and a.errors.spawn_shell) end
    return res
end

local function spawn_blast(a, kind)
    local b = BLAST[kind]
    shape_effects(b)
    local shellId, axes = b.shell, nil
    local res, err = spawn(a, {
        type = "shell", id = "eldritch_" .. kind, shell = b.file or JOB07_SHELLS, shell_id = shellId, scale_axes = axes,
        cast = b.cast or { mode = "joint", joint = PALM, face = "crosshair", lock_range = LOCK_RANGE },
        scale = b.scale, damage_type = b.damage_type,
        speed = b.speed,
        lifetime = b.lifetime,
    })
    if not res or not res.record then return note("blast failed: " .. tostring(err)) end
    note("blast spawned: " .. kind .. " shell " .. tostring(shellId))
    res.record.startPos = res.record.pos
    table.insert(blasts, { record = res.record, kind = kind, born = os.clock() })
    if not b.noShape and res.record.param and not params[shellId] then params[shellId] = res.record.param end
    -- every effect the projectile makes is coloured (many never pass a request we see), except the ones set to keep
    -- their own colour ("Coloured effects" list; -1/8/40 and -1/8/43 by default: see-through, they cover the screen)
    local k = cfg.armBright
    local col = { math.min(1, cfg.armR / 255 * k), math.min(1, cfg.armG / 255 * k), math.min(1, cfg.armB / 255 * k), 1 }
    if cfg.blastTint then colour_shell(res.record, col, 6.0) end
end

local warmed = false
local function warm_up(a)
    if warmed then return end
    warmed = true
    for _, kind in ipairs({ "tap", "charged", "burst", "small", "wave" }) do
        local b = BLAST[kind] or { shell = kind == "wave" and 6 or 11 }   -- "small": 11's launch flash; "wave": Magike Cut
        local res = spawn(a, { type = "shell", id = "eldritch_warmup", shell = JOB07_SHELLS, shell_id = b.shell,
            cast = { mode = "owner", offset = { 0, -60, 0 } }, cosmetic = true, mute = true,
            scale = 0.01, lifetime = 0.1 })
        if res and res.record and res.record.param and not params[b.shell] then params[b.shell] = res.record.param end
    end
    note("warmed up the blasts")
end

------------------------------------------------------------------------
-- shell colouring (Skill Maker's change_efx2_color): set_Color on every effect player + setRootColor on each container
------------------------------------------------------------------------
local colourJobs = {}
local VIA_COLOR = sdk.find_type_definition("via.Color")
local function via_colour(c)
    local v = ValueType.new(VIA_COLOR)
    v:call(".ctor(via.vec4)", Vector4f.new(c[1], c[2], c[3], c[4] or 1))
    return v
end
function colour_shell(record, c, secs, everyFrame)
    -- everyFrame: the projectile's list is walked every frame (its effects get replaced while it flies - the slash
    -- wave); otherwise 5x a second and the found containers are kept coloured
    table.insert(colourJobs, { record = record, col = via_colour(c), untilT = os.clock() + secs, every = everyFrame, born = os.clock() })
end
local function shell_alive(record)
    local alive = false
    for _, part in ipairs(record.parts or {}) do
        pcall(function()
            local go = part.shell:get_GameObject()
            if go and go:call("get_Valid") ~= false and part.shell:call("get_Valid") ~= false then alive = true end
        end)
    end
    return alive
end
local function colour_container(ce, col)   -- false when the container has finished (then it is not touched)
    local finished = true
    pcall(function() finished = ce:call("get_isFinished") == true end)
    if finished then return false end
    pcall(function()
        local entries = ce.CreatedEffects._entries
        for e = 0, entries:get_size() - 1 do
            local players = entries[e] and entries[e].value
            for q = 0, (players and players._size or 0) - 1 do
                local pl = players._items[q]
                if pl then pl:set_Color(col) end
            end
        end
    end)
    pcall(function() ce:call("setRootColor(via.Color)", col) end)
    return true
end
local function colour_update()
    local now = os.clock()
    local walkAll = now >= (dbg.colourNext or 0)
    if walkAll then dbg.colourNext = now + 0.2 end
    for i = #colourJobs, 1, -1 do
        local j = colourJobs[i]
        j.done = j.done or {}
        j.conts = j.conts or {}
        if now > j.untilT or (now - (j.born or 0) > 0.5 and not shell_alive(j.record)) then   -- (0.5 s: parts still being made)
            table.remove(colourJobs, i)   -- its projectile is gone: nothing of it is touched any more
        else
            -- the containers already found (as in 1.52 - getAllPlayers misses some of the wave's players)
            for k = #j.conts, 1, -1 do
                if not colour_container(j.conts[k], j.col) then table.remove(j.conts, k) end
            end
            if j.every then j.done = {} end   -- coloured anew every frame
            if walkAll or j.every then
                for _, part in ipairs(j.record.parts or {}) do
                    pcall(function()
                        local mgr = part.shell:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
                        local list = mgr.CreatedEffectDataList
                        for k = 0, list._size - 1 do
                            local data = list._items[k]
                            local skip = false
                            pcall(function()
                                local id = data.id
                                local idstr = ("%d/%d/%d"):format(id.DataContainerIndex, id.ContainerID, id.ElementID)
                                skip = cfg.noTint[idstr] == true or (dbg.partsIds and dbg.partsIds[idstr]) == true
                                if not skip and dbg.coloured then dbg.coloured(idstr, "projectile walk", "projectile") end
                                dbg.walkSeen = dbg.walkSeen or {}
                                local r = dbg.walkSeen[idstr] or { n = 0, how = "projectile" }
                                r.n, r.last = r.n + 1, os.clock()
                                dbg.walkSeen[idstr] = r
                            end)
                            local inner = data and not skip and data.list
                            for m = 0, (inner and inner._size or 0) - 1 do
                                local ce = inner._items[m]
                                local ceAddr = ce and ce:get_address()
                                if ce and not j.done[ceAddr] then
                                    j.done[ceAddr] = true
                                    if colour_container(ce, j.col) and not j.every then
                                        pcall(function() j.conts[#j.conts + 1] = ce:add_ref() end)
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end

local function fire(a, kind)
    local b = BLAST[kind]
    if b.armor then
        a:set_super_armor(true)
        st.armorUntil = os.clock() + b.armor
    end
    local okR = a:request_action(b.action, b.layer)
    note(("fire %s: request %s on layer %d -> %s %s"):format(kind, b.action, b.layer, tostring(okR),
        tostring(a.errors and a.errors.request_action or "")))
    lastFire = os.clock()
    lastKind = kind
    dbg.lastKind, dbg.lastFireT = kind, os.clock()   -- (for code above this point in the file)
    dbg.fxRecReset = true
    st.pending = { kind = kind, asked = os.clock(), started = nil, action = b.action, layer = b.layer }
end

------------------------------------------------------------------------
-- hand glow. A: the .efx file on our own effect player, on an object kept on the arm joint (Dimension Door's way).
-- B: the character's own effect manager plays Mystic Spearhand's effect 25 with the character as parent.
------------------------------------------------------------------------
local glowState = { items = {}, next = 0, res = nil }   -- items: { kind, obj, untilT }
local function glow_clear()
    for _, it in ipairs(glowState.items) do
        pcall(function()
            if it.kind == "A" then it.obj:call("destroy(via.GameObject)", it.obj)
            else it.obj:call("finishAll") end
        end)
    end
    glowState.items = {}
    glowState.next = 0
    glowState.mode = nil
end
re.on_script_reset(glow_clear)
local function make_anchor()
    local go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)"):call(nil, "Pactblade_glow", 0)
    go = go:add_ref()
    go:call(".ctor")
    go:set_Name("Pactblade_glow")
    return go
end
local function start_A(a, charging)
    local v = cfg.glowVariant or ""
    if charging and v:find("^h%d+g%d$") then v = v:gsub("g%d$", "g" .. math.floor(cfg.glowLvCharge or 4)) end
    local path = v == "" and GLOW.file
        or ("vfx/effects/pactblade/" .. ((v:find("^pp") or v:find("^h%d+g%d$")) and "pb_arm_" or "pb_arm_no_") .. v .. ".efx")
    glowState.resCache = glowState.resCache or {}   -- (normal + charging files: no reloading between them)
    if glowState.resPath ~= path then glowState.res, glowState.resPath = glowState.resCache[path], glowState.resCache[path] and path or nil end
    if not glowState.res then
        local res = sdk.create_resource("via.effect.EffectResource", path)
        if not res and path ~= GLOW.file then   -- the pak isn't loaded (needs a game restart): the game's own file
            note("arm effect copy not found (" .. path .. ") - restart the game (pak_mods/x0004-PactbladeFx.pak loads at start)")
            path = GLOW.file
            res = sdk.create_resource("via.effect.EffectResource", path)
        end
        if not res then error("effect file not found: " .. path) end
        glowState.res, glowState.resPath = res:add_ref(), path
        glowState.resCache[path] = glowState.res
    end
    local go = make_anchor()
    local holder = glowState.res:create_holder("via.effect.EffectResourceHolder"):add_ref()
    local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
    ep:call("set_Resource", holder)
    pcall(function() ep:call("set_AutoStart", true) end)
    pcall(function() ep:call("set_PlaySpeed", cfg.glowSpeed) end)
    pcall(function() dbg.glowLooped = ep:call("get_Looped") end)
    return go, ep
end
local function ch07_index(a)
    local mgr = a.game_object:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    local conts = mgr.ExternalDataContainers
    for i = 0, conts:get_Count() - 1 do
        local ok, path = pcall(function() return tostring(conts[i].DataContainer:get_Path()) end)
        if ok and path:lower():find("ch07/13_ch07_ns") then return mgr, i end
    end
    return mgr, nil
end
local function start_B(a)
    local mgr, idx = ch07_index(a)
    if not idx then error("Mystic Spearhand's effect file is not on this character") end
    local id = sdk.create_instance("via.effect.script.EffectID")
    id.DataContainerIndex = idx; id.ContainerID = GLOW.id; id.ElementID = GLOW.element
    id.IsContainerIDOnly = false; id.IsElementIDOnly = false
    local c = mgr:call("requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)",
        id, a.game_object, -1, nil)
    if not c then error("the game returned no effect") end
    c = c:add_ref()
    pcall(function() c:call("setPlaySpeed", cfg.glowSpeed) end)
    return c
end
-- our own light on the arm (via.render.PointLight on an anchor): strength / reach from the menu, colour = the arm's
function glowState.light_update(a)
    local on = cfg.armLight and cfg.glow
    if on then
        on = false
        for _, it in ipairs(glowState.items) do if not it.hidden then on = true end end
    end
    local L = glowState.light
    if not on then
        if L then pcall(function() L.comp:call("set_Enabled", false) end) end
        return
    end
    if not L then
        local go = make_anchor()
        go:set_Name("Pactblade_armlight")
        local comp = go:call("createComponent(System.Type)", sdk.typeof("via.render.PointLight"))
        if not comp then return end
        L = { go = go, comp = comp:add_ref() }
        pcall(function() L.comp:call("set_ShadowEnable", false) end)
        glowState.light = L
    end
    pcall(function()
        local joint = a.game_object:get_Transform():getJointByName(dbg.glowJoint)
        if joint then L.go:get_Transform():set_Position(joint:get_Position()) end
    end)
    local r, g, b = cfg.armR / 255, cfg.armG / 255, cfg.armB / 255
    local gv = tostring(cfg.glowVariant or "")
    local hue = tonumber(gv:match("^ppb?(%d+)$") or gv:match("^h(%d+)g%d$") or "")
    if hue then   -- the baked arm colour's hue, full colour
        local h = (hue % 360) / 60
        local x = 1 - math.abs(h % 2 - 1)
        local t = ({ { 1, x, 0 }, { x, 1, 0 }, { 0, 1, x }, { 0, x, 1 }, { x, 0, 1 }, { 1, 0, x } })[math.floor(h) + 1]
        r, g, b = t[1], t[2], t[3]
    end
    pcall(function()
        L.comp:call("set_Color", Vector3f.new(r, g, b))
        L.comp:call("set_Intensity", cfg.lightLm + 0.0)
        L.comp:call("set_Radius", cfg.lightRadius + 0.0)
        L.comp:call("set_Enabled", true)
    end)
end
re.on_script_reset(function()
    local L = glowState.light
    if L then pcall(function() L.go:call("destroy(via.GameObject)", L.go) end) end
end)
function update_glow(a, now)
    if st.phase == "charging" then glowState.sheathUntil = now + 1.0 end   -- (and a moment after the blast)
    local shown = a:weapon_drawn() or cfg.glowSheathed or now < (glowState.sheathUntil or 0)
    if not (cfg.glow and live.on and shown) then
        if #glowState.items > 0 then glow_clear() end
        dbg.glow = "off"
        return
    end
    local joint
    pcall(function() joint = a.game_object:get_Transform():getJointByName(dbg.glowJoint) end)
    local speed = math.max(0.05, cfg.glowSpeed)
    local every = GLOW.every / speed
    if cfg.freeze then
        -- Each copy of the effect keeps its own effect time (t). Button free: one copy, fast-forwarded to the freeze
        -- moment and frozen there. Button held: the 2.56-3.00 s part (no vibrating air) loops - a relay of copies,
        -- each fast-forwarded to 2.56 s out of sight (anchor 100 m below), shown from there, ended at 3.00 s; the next
        -- one starts early enough to take over without a gap.
        local dt = now - (glowState.lastT or now)
        glowState.lastT = now
        local held = a:button_down("JobSpecialAction")
        local function speed_of(it, sp)
            it.speed = sp
            pcall(function() if it.ep then it.ep:call("set_PlaySpeed", sp) else it.obj:call("setPlaySpeed", sp) end end)
        end
        local function kill(it)
            pcall(function()
                if it.kind == "A" then it.obj:call("destroy(via.GameObject)", it.obj) else it.obj:call("finishAll") end
            end)
        end
        local function new_copy(goal)
            local ok, obj, ep = pcall(dbg.glowMethod == "A" and start_A or start_B, a, glowState.mode == "loop")
            if not ok or not obj then dbg.glow = "method " .. dbg.glowMethod .. " failed: " .. tostring(obj); return nil end
            local it = { kind = dbg.glowMethod, obj = obj, ep = ep, born = now, untilT = math.huge, t = 0, goal = goal, hidden = true }
            speed_of(it, math.max(1.0, goal / GLOW_FF))
            table.insert(glowState.items, it)
            return it
        end
        -- effect time, and keep the copies on the arm (hidden ones below the ground while fast-forwarding)
        for _, it in ipairs(glowState.items) do
            it.t = (it.t or 0) + dt * (it.speed or 0)
            if it.kind == "A" and joint then
                pcall(function()
                    local tr = it.obj:get_Transform()
                    local pos = joint:get_Position()
                    if it.hidden then pos = pos + Vector3f.new(0, -100, 0) end
                    tr:set_Position(pos)
                    tr:set_Rotation(joint:get_Rotation())
                end)
            end
        end
        if not held then
            if glowState.mode ~= "frozen" then
                glow_clear()
                glowState.mode = "frozen"
                glowState.lastT = now
            end
            local it = glowState.items[1]
            if not it then
                if new_copy(cfg.freezeAt) then dbg.glow = "fast-forwarding to the freeze moment" end
            elseif it.speed > 0 and it.t >= cfg.freezeAt then
                speed_of(it, 0.0)
                it.hidden = false
                dbg.glow = ("frozen at %.2f s"):format(cfg.freezeAt)
            end
            return
        end
        -- held
        local L1, L2, LSP = GLOW_LOOP[1], GLOW_LOOP[2], GLOW_LOOP_SPEED
        if cfg.chargeFull then L1, L2, LSP = 0.0, math.max(0.3, cfg.chargeEnd), math.max(0.05, cfg.chargeSpeed) end
        if glowState.mode ~= "loop" then
            glowState.mode = "loop"
            local it = glowState.items[1]
            if cfg.chargeFull then
                glow_clear()                 -- from the start of the effect
                glowState.mode = "loop"
                glowState.lastT = now
            elseif it and it.t >= L1 and it.t < L2 then
                it.hidden = false
                speed_of(it, LSP)  -- the frozen copy plays on into the loop
            else
                glow_clear()
                glowState.mode = "loop"      -- glow_clear resets the mode
                glowState.lastT = now
            end
        end
        for k = #glowState.items, 1, -1 do
            local it = glowState.items[k]
            if it.hidden and it.t >= L1 then
                it.hidden = false
                speed_of(it, LSP)
            elseif not it.hidden and it.t >= L2 then
                kill(it)
                table.remove(glowState.items, k)
            end
        end
        local last = glowState.items[#glowState.items]
        if not last or (not last.hidden and last.t >= L2 - GLOW_FF * LSP) then
            new_copy(L1)
        end
        dbg.glow = ("button held: looping %.2f-%.2f s (%d copies)"):format(L1, L2, #glowState.items)
        return
    end
    for i = #glowState.items, 1, -1 do
        local it = glowState.items[i]
        pcall(function()
            if it.kind == "A" and it.ep then it.ep:call("set_PlaySpeed", speed)
            elseif it.kind == "B" then it.obj:call("setPlaySpeed", speed) end
        end)
        if it.kind == "A" and joint then
            pcall(function()
                local tr = it.obj:get_Transform()
                tr:set_Position(joint:get_Position())
                tr:set_Rotation(joint:get_Rotation())
            end)
        end
        if now > it.untilT then
            pcall(function()
                if it.kind == "A" then it.obj:call("destroy(via.GameObject)", it.obj) else it.obj:call("finishAll") end
            end)
            table.remove(glowState.items, i)
        end
    end
    if now >= glowState.next then
        glowState.next = now + every
        local ok, obj, ep = pcall(dbg.glowMethod == "A" and start_A or start_B, a)
        if ok and obj then
            table.insert(glowState.items, { kind = dbg.glowMethod, obj = obj, ep = ep, untilT = now + every * 1.5 })
            dbg.glow = "method " .. dbg.glowMethod .. ": running"
        else
            dbg.glow = "method " .. dbg.glowMethod .. " failed: " .. tostring(obj)
            glowState.next = now + 5
        end
    end
end

------------------------------------------------------------------------
-- beam: copies of the Eldritch Blast projectile laid along its path (every BEAM.spacing m back to the palm), pinned
-- in place every frame, launch flash removed, harmless; all ended when the blast hits or is gone
------------------------------------------------------------------------
local BEAM = { spacing = 0.4, max = 60, scale = 1.0 }
local mathx = require("DragonCore.game.mathx")
local pieceByGo = {}       -- piece shell GameObject address -> piece
local function beam_kill(b)
    for _, pc in ipairs(b.pieces or {}) do
        for _, c in ipairs(pc.conts) do pcall(function() c:call("killAll") end) end
        pc.conts = {}
        pc.dead = true
    end
    b.beamDone = true
end
local function beam_forget(now)
    for addr, pc in pairs(pieceByGo) do
        if pc.dead and now - (pc.diedAt or now) > 6 then pieceByGo[addr] = nil end
        if pc.dead and not pc.diedAt then pc.diedAt = now end
    end
end
local function beam_update(a, now)
    beam_forget(now)
    for _, b in ipairs(blasts) do
        if b.kind == "tap" and not b.beamDone then
            local r = b.record
            b.pieces = b.pieces or {}
            -- the blast is over: hit something, gone (stopped moving), or old
            if b.hitNow or r.hit or now - b.born > 4 then beam_kill(b)
            elseif r.found and r.pos and r.rot then
                local here = r.pos
                b.beamFrom = b.beamFrom or r.startPos or here
                local moved = (here - (b.beamLast or here)):length()
                if b.beamLast and moved < 0.001 then
                    b.beamStill = (b.beamStill or 0) + 1
                    if b.beamStill > 2 then beam_kill(b) end
                else
                    b.beamStill = 0
                end
                b.beamLast = here
                -- fill from the farthest piece laid so far up to the blast's current position
                local total = (here - b.beamFrom):length()
                b.laid = b.laid or 0
                while not b.beamDone and #b.pieces < BEAM.max and (b.laid + 1) * BEAM.spacing <= total do
                    b.laid = b.laid + 1
                    local back = total - b.laid * BEAM.spacing     -- metres behind the blast
                    local target = here + mathx.rotate(Vector3f.new(0, 0, -back), r.rot)
                    local res = spawn(a, { type = "shell", id = "eldritch_beam", shell = JOB07_SHELLS,
                        shell_id = BLAST.tap.shell, cast = { mode = "previous", offset = { 0, 0, -back } },
                        cosmetic = true, mute = true, scale = BEAM.scale, speed = 0.01, lifetime = 4 }, { from = r })
                    if res and res.record then
                        table.insert(b.pieces, { record = res.record, target = target, conts = {} })
                    else
                        b.beamDone = true
                    end
                end
            end
            -- pin the pieces where they were laid
            for _, pc in ipairs(b.pieces) do
                if not pc.dead and pc.record.found then
                    for _, part in ipairs(pc.record.parts or {}) do
                        pcall(function()
                            if not pc.go then
                                pc.go = part.shell:get_GameObject():get_address()
                                pieceByGo[pc.go] = pc
                            end
                            part.shell:get_GameObject():get_Transform():set_Position(pc.target)
                        end)
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- TEST: hand glow colour. (a) the glow effect's own colour slots ("Charge", and Skill Maker's ParticleColor /
-- BaseColor / FireColor / LightningColor) + set_Color; (b) the sleeve glow = a RimLight material mode (category 8,
-- modes 1545610377 / 1704633256): its colour values in the player's MaterialInterpolationRimLight mode lists are
-- changed (Skill Maker's way for blade glows) and put back when the test is off.
------------------------------------------------------------------------
glowCol = { on = false, r = 170, g = 60, b = 255, found = "-", backup = nil,
                  routes = { rim = false, player = true, Charge = false, ParticleColor = false, BaseColor = false,
                             FireColor = false, LightningColor = false } }
do
    local saved = json.load_file(DATA) or {}
    if type(saved.armRoutes) == "table" then
        for k, v in pairs(saved.armRoutes) do
            if type(v) == "boolean" and glowCol.routes[k] ~= nil then glowCol.routes[k] = v end
        end
    end
end
local SLEEVE_MODES = { [1545610377] = true, [1704633256] = true }
local function rim_modes(a)
    local comp = a.game_object:call("getComponent(System.Type)", sdk.typeof("app.MaterialInterpolationRimLight"))
    if not comp then return nil, "no RimLight component" end
    local out, seen = {}, {}
    local function scan(list)
        for i = 0, (list and list._size or 0) - 1 do
            local md = list._items[i]
            local modes = md and md._ModeList
            for k = 0, (modes and modes._size or 0) - 1 do
                local mode = modes._items[k]
                if mode then
                    local v = mode._ModeValue
                    seen[#seen + 1] = v
                    if SLEEVE_MODES[v] then out[#out + 1] = mode end
                end
            end
        end
    end
    pcall(scan, comp.ModeDataList)
    for _, field in ipairs({ "UserDatas", "AddDatas" }) do
        pcall(function()
            local ud = comp[field]
            for i = 0, ud._size - 1 do if ud._items[i] then scan(ud._items[i]._ModeDataList) end end
        end)
    end
    return out, seen
end
local function sleeve_restore()
    if not glowCol.backup then return end
    for _, b in ipairs(glowCol.backup) do pcall(function() b.var._Value = b.orig end) end
    glowCol.backup = nil
end
local function sleeve_apply(a)
    if glowCol.backup then return end
    if os.clock() < (glowCol.retryAt or 0) then return end
    glowCol.retryAt = os.clock() + 1.0
    local modes, seen = rim_modes(a)
    if not modes then glowCol.found = tostring(seen); return end
    glowCol.backup = {}
    local n = 0
    for _, mode in ipairs(modes) do
        local mats = mode._MaterialList
        for i = 0, (mats and mats._size or 0) - 1 do
            local vars = mats._items[i] and mats._items[i]._VariableF4List
            for k = 0, (vars and vars._size or 0) - 1 do
                local var = vars._items[k]
                if var and var._IsColor then
                    local o = var._Value
                    local scale = math.max(o.x, o.y, o.z) > 1.5 and 255 or 1
                    table.insert(glowCol.backup, { var = var, orig = o })
                    local k2 = scale * cfg.armBright / 255
                    var._Value = Vector4f.new(cfg.armR * k2, cfg.armG * k2, cfg.armB * k2, o.w)
                    n = n + 1
                end
            end
        end
    end
    glowCol.found = ("%d sleeve mode(s), %d colour value(s) changed; modes on the component: %d"):format(#modes, n, #seen)
    if n == 0 then glowCol.backup = nil end   -- nothing there yet (still loading): try again in a second
    pcall(json.dump_file, "Pactblade_rimlight_modes.json", seen)
end
local function glow_colour_update(a)
    if not cfg.armTint or not live.on then sleeve_restore(); return end
    if glowCol.routes.rim then pcall(sleeve_apply, a) else sleeve_restore() end
    local k = cfg.armBright
    local r, g, b = cfg.armR / 255, cfg.armG / 255, cfg.armB / 255
    local gv = cfg.glowVariant or ""
    if gv:find("^pp") or gv:find("^h%d+g%d$") then r, g, b = 1, 1, 1 end   -- colour baked into the file: brightness only
    local col = via_colour({ math.min(1, r * k), math.min(1, g * k), math.min(1, b * k), 1 })
    for _, it in ipairs(glowState.items) do
        pcall(function()
            local ep = it.ep
            if not ep then return end
            if glowCol.routes.player then ep:set_Color(col) end
            for _, name in ipairs({ "Charge", "ParticleColor", "BaseColor", "FireColor", "LightningColor" }) do
                if glowCol.routes[name] then
                    local ex = ep:getExternParameter(name)
                    if ex then ex:set_Color(col) end
                end
            end
        end)
    end
end
re.on_script_reset(sleeve_restore)

local update_body
local lastUpdateErr = nil
frame.add("late", "Pactblade.update", function()
    local ok, err = pcall(update_body)
    if not ok and tostring(err) ~= lastUpdateErr then
        lastUpdateErr = tostring(err)
        note("UPDATE ERROR: " .. lastUpdateErr)
    end
end)
update_body = function()
    local a = runtime.player()
    local now = os.clock()
    restore_effects(false)
    for i = #blasts, 1, -1 do if now - blasts[i].born > 15 then table.remove(blasts, i) end end
    if not a or not a:valid() then
        if live.on then note("player not valid: Pactblade off") end
        live.on = false; return
    end
    live.go = a.game_object and a.game_object:get_address()
    live.am = a.action_manager and a.action_manager:get_address()
    live.vsb = vsb_state()
    live.on = ((live.vsb == "picked" and not ignorePick) or forceActive) and a:weapon_job() == 1
    -- (2.13 crash: switching staff -> sword, the warm-up ran while the weapon + its effects were being rebuilt)
    if live.on and not live.onSince then live.onSince = now elseif not live.on then live.onSince = nil end
    live.settled = live.on and now - (live.onSince or now) >= 2.0
    pcall(function() live.sc = a.character["<StatusConditionCtrl>k__BackingField"]:get_address() end)
    if live.on then pcall(boon_clear, a) end
    pcall(function()
        live.ctx = a.human["<SkillContext>k__BackingField"]:get_address()
        live.avail = a.human["<SkillAvailability>k__BackingField"]:get_address()
    end)
    live.shieldWorn = false
    pcall(function()
        local left = a.character:get_WeaponAndItemHolder():get_LeftWeapon()
        live.shieldWorn = left ~= nil and left:get_Weapon() ~= nil
    end)
    pcall(update_speed, a)
    if live.settled and not warmed then pcall(warm_up, a) end
    if live.settled or not live.on then
        pcall(update_glow, a, now)
        pcall(glowState.light_update, a)
    end
    if #colourJobs > 0 then pcall(colour_update) end
    pcall(glow_colour_update, a)
    if cfg.beam then
        local okB, errB = pcall(beam_update, a, now)
        if not okB then dbg.beamErr = tostring(errB) end
    end
    local pd = st.pending
    if pd then
        local b = BLAST[pd.kind]
        if not pd.started then
            if a:current_action(pd.layer) == pd.action then
                pd.started = now
                note("animation started: " .. pd.action)
            elseif now - pd.asked > 0.6 then
                st.pending = nil
                note(b.name .. ": the animation did not start (busy with " .. tostring(a:current_action(0)) .. ")")
            else
                -- input buffer: ask again every frame; after 0.2 s try the full-body variant, which can take over
                -- from a full-body attack
                if b.fallback and not pd.fellBack and now - pd.asked > 0.2 then
                    pd.fellBack = true
                    pd.action, pd.layer = b.fallback, b.fallbackLayer
                end
                a:request_action(pd.action, pd.layer)
            end
        elseif now - pd.started >= b.delay then
            st.pending = nil
            spawn_blast(a, pd.kind)
            if b.cancelAfter then st.recover = { from = now + b.cancelAfter, untilT = now + 2.0, action = pd.action } end
        end
    end
    if st.armorUntil and now >= st.armorUntil then
        st.armorUntil = nil
        a:set_super_armor(false)
    end
    local rc = st.recover
    if rc then
        if now > rc.untilT or a:current_action(0) ~= rc.action then
            st.recover = nil
        elseif now >= rc.from and (a:button_pressed("AttackS") or a:button_pressed("AttackL")) then
            st.recover = nil
            a:request_action("NormalLocomotion", 0)
            note("Eldritch Burst recovery cut short for an attack")
        end
    end
    if not live.on then st.phase = "idle"; return end
    -- carrying someone / something: the vocation button is the game's (throw) - no dodge / Eldritch Bolt (user bug)
    local carrying = false
    pcall(function()
        local cc = a.character:call("get_CatchController")
        if cc and cc:get_field("CaughtChara") then carrying = true end
    end)
    if not carrying then
        local cur = tostring(a:current_action(0) or "")
        for _, w in ipairs({ "Catch", "Carry", "Lift", "Hold", "Throw", "Grab", "Caught" }) do
            if cur:find(w) then carrying = true; break end
        end
    end
    if carrying then
        if st.phase ~= "idle" or st.pending then note("carrying: vocation button left to the game") end
        st.phase, st.pending = "idle", nil
        return
    end
    local down = a:button_down("JobSpecialAction")
    if a:button_pressed("JobSpecialAction") then
        note(("button pressed: phase %s, pending %s, current action %s"):format(st.phase, tostring(st.pending and st.pending.kind),
            tostring(a:current_action(0))))
    end
    if st.dodgeUntil then
        local cur = a:current_action(0)
        if st.dodgeYaw and now - (st.dodgeUntil - 0.3) < 0.1 then face_yaw(a, st.dodgeYaw) end   -- first frames
        if cur == DODGE and not st.dodgeStarted then st.dodgeStarted = true end
        if (cur == DODGE and now - (st.dodgeUntil - 0.3) >= 0.1) or now > st.dodgeUntil then
            if cur ~= DODGE then note("dodge did not start (action " .. tostring(cur) .. ")") end
            st.dodgeUntil, st.dodgeStarted = nil, nil
        elseif cur ~= DODGE then a:request_action(DODGE, 0) end
    end
    if st.phase == "idle" then
        if a:button_pressed("JobSpecialAction") and not st.pending then
            local win = cfg.burstWindow
            local inSwing = dbg.basicName and a:current_action(0) == dbg.basicName
            local ok = false
            if inSwing and dbg.basicName:find("Heavy") and not dbg.basicName:find("Air") then
                -- Empale on the ground: between two frames of its animation (user: 56.6 - 110.5)
                pcall(function()
                    local fr = a.character.FullBodyLayer:call("get_Frame")
                    ok = fr >= cfg.empaleFrom and fr <= cfg.empaleTo
                end)
            elseif inSwing then
                if dbg.basicName:find("Heavy") then win = cfg.burstWindowEmpaleAir end
                ok = now - (dbg.basicStart or -100) < win
            end
            local curT = tostring(a:current_action(0) or "")
            if not ok and curT:find("^Job01_TuskToss") then
                pcall(function()
                    local fr = a.character.FullBodyLayer:call("get_Frame")
                    ok = fr >= cfg.tuskFrom and fr <= cfg.tuskTo
                end)
            end
            if ok then fire(a, "burst")
            else st.phase = "holding"; st.t0 = now end
        end
    elseif st.phase == "holding" then
        local curA = tostring(a:current_action(0) or "")
        if not down and curA == DODGE and now - (st.dodgeT or -10) < DODGE_LOCK then
            st.phase = "idle"   -- still in the last dodge: this tap does nothing
        elseif not down and curA:find("^Job01_") and curA:find("Heavy") and not empale_recovering(a, curA) then
            st.phase = "idle"   -- no dodge out of Empale (user); only its Burst window
        elseif not down and curA:find("^Job01_TuskToss") and not tusk_recovering(a) then
            st.phase = "idle"   -- no dodge out of Tusk Toss until after its Burst window (user)
        elseif not down then
            st.phase = "idle"
            st.dodgeT = now
            st.dodgeUntil = now + 0.3   -- (re-asked until it plays)
            st.dodgeYaw = stick_yaw(a)
            if st.dodgeYaw then face_yaw(a, st.dodgeYaw) end
            a:request_action(DODGE, 0)
            note(("released after %.2f s: dodge"):format(now - st.t0))
        elseif now - st.t0 >= HOLD_SEC then
            st.phase = "charging"
            note("charging... (held " .. HOLD_SEC .. " s)")
            if dbg.rim_glow then pcall(dbg.rim_glow, a, true, 0.3) end   -- (user: a 0.3 s pulse = "charged")
        end
    elseif st.phase == "charging" then
        if not down then
            st.phase = "idle"
            fire(a, "charged")
        end
    end
end

-- the bolt animations fire Mystic Spearhand's own bolt (flinch / hold): those projectiles are blocked
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ShellManager"):get_method(
        "requestCreateShell(via.GameObject, via.vec3, via.Quaternion, app.ShellRequest.ShellCreateInfo, app.ShellParamData, app.ShellRequest.EventCreateShellSuccess, app.ShellRequest.EventBeforeShellInstantiate)"),
        function(args)
            if not live.on or ourSpawn or os.clock() - lastFire > 1.5 then return end
            local owner = sdk.to_managed_object(args[3])
            if owner and owner:get_address() == live.go then
                if (lastKind == "charged" or lastKind == "burst") and cfg.bind then
                    dbg.bindShots = (dbg.bindShots or 0) + 1
                    note("Forbeding Bolt let through (" .. (lastKind == "burst" and "Eldritch Burst" or "Eldritch Bolt") .. ")")
                    return
                end
                dbg.suppressed = dbg.suppressed + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(r) return r end)
end)

------------------------------------------------------------------------
-- explosion size: effects that our blast projectiles request (hit, hit on terrain, finish) are scaled down
------------------------------------------------------------------------
local CHARGE_CLOUD = 160   -- Mystic Spearhand's charge cloud in the common effect file (ch00, index 0)
local clouds = {}          -- { c, born }: charge clouds being kept small
local function scale_clouds()
    local now = os.clock()
    for i = #clouds, 1, -1 do
        local cl = clouds[i]
        local alive = now - cl.born < 10
        local k = (cl.hideUntil and now < cl.hideUntil) and 0.0 or (cl.k or cfg.boom)
        pcall(function()
            if cl.c:call("get_isFinished") then alive = false; return end
            cl.c:call("setUniformScale", k)
            local list = cl.c:call("getAllPlayers")
            local n = list and list:call("get_Count") or 0
            for j = 0, n - 1 do
                local pl = list:call("get_Item", j)
                local tr = pl and pl:call("get_GameObject"):get_Transform()
                if tr then tr:set_LocalScale(Vector3f.new(k, k, k)) end
            end
        end)
        if not alive then table.remove(clouds, i) end
    end
end
re.on_pre_application_entry("LateUpdateBehavior", function() if #clouds > 0 then pcall(scale_clouds) end end)
-- the blast's two see-through layers: their first 0.1 s is not shown (user; tinted they cover the screen)
local BLAST_TRIM = {}   -- (1.01 tried hiding the first 0.1 s of -1/8/40 / 43: still covered the screen)
local function trim_add(rv, secs)
    pcall(function()
        local c = sdk.to_managed_object(rv)
        if not c then return end
        local addr = c:get_address()
        for _, cl in ipairs(clouds) do
            if cl.addr == addr or (cl.c and cl.c:get_address() == addr) then
                cl.hideUntil = cl.hideUntil or (os.clock() + secs)
                return
            end
        end
        c:call("setUniformScale", 0.0)
        table.insert(clouds, { c = c:add_ref(), born = os.clock(), k = 1.0, hideUntil = os.clock() + secs, addr = addr })
    end)
end
-- blast colour: the arm glow's colour (sliders) on every effect player of the collected effects
local TINT_WINDOW = 2.0   -- seconds after a blast press in which the player's own new effects are coloured too
local tints = {}          -- { c, born }
local tintSeen = {}       -- container address -> true
local function blast_colour()
    local k = cfg.armBright
    return via_colour({ math.min(1, cfg.armR / 255 * k), math.min(1, cfg.armG / 255 * k), math.min(1, cfg.armB / 255 * k), 1 })
end
local function slash_colour()
    local k = cfg.slashBright
    return via_colour({ math.min(1, cfg.slashR / 255 * k), math.min(1, cfg.slashG / 255 * k), math.min(1, cfg.slashB / 255 * k), 1 })
end
local WHITE
local function tint_update()
    local now = os.clock()
    local col = blast_colour()
    for i = #tints, 1, -1 do
        local t = tints[i]
        if t.id and cfg.noTint[t.id] then
            WHITE = WHITE or via_colour({ 1, 1, 1, 1 })
            pcall(function() t.c:call("setRootColor(via.Color)", WHITE) end)
            pcall(function()
                local list = t.c:call("getAllPlayers")
                for j = 0, (list and list:call("get_Count") or 0) - 1 do list:call("get_Item", j):set_Color(WHITE) end
            end)
            tintSeen[t.addr or 0] = nil
            table.remove(tints, i)
            goto continue
        end
        local alive = now - t.born < 10
        pcall(function()
            if t.c:call("get_isFinished") then alive = false; return end
            local tc = t.slash and slash_colour() or col
            pcall(function() t.c:call("setRootColor(via.Color)", tc) end)
            local list = t.c:call("getAllPlayers")
            local n = list and list:call("get_Count") or 0
            for j = 0, n - 1 do
                local pl = list:call("get_Item", j)
                if pl then pl:set_Color(tc) end
            end
        end)
        if not alive then tintSeen[t.addr or 0] = nil; table.remove(tints, i) end
        ::continue::
    end
end
local function bind_follow()
    if not bindBolt.go then return end
    local now = os.clock()
    if now - bindBolt.born > 4 then bindBolt.go, bindBolt.addr = nil, nil; return end
    if lastKind == "burst" then   -- Burst: the bolt goes straight onto the nearest enemy in front (its hit area is tiny)
        if bindBolt.tgtBorn ~= bindBolt.born then
            bindBolt.tgtBorn, bindBolt.tgt = bindBolt.born, nil
            pcall(function() bindBolt.tgt = combo.pick_target(runtime.player(), 4, 100) end)
        end
        if not bindBolt.tgt or now - bindBolt.born > 0.8 then return end
        pcall(function()
            local q = bindBolt.tgt:get_GameObject():get_Transform():get_Position()
            bindBolt.go:get_Transform():set_Position(Vector3f.new(q.x, q.y + 1.0, q.z))
        end)
        return
    end
    local b
    for k = #blasts, 1, -1 do
        if blasts[k].kind == "charged" and blasts[k].born >= bindBolt.born - 0.5 then b = blasts[k]; break end
    end
    if not b or b.boltDone then return end
    local ok = pcall(function()
        local tr = b.record.parts[1].shell:get_GameObject():get_Transform()
        local btr = bindBolt.go:get_Transform()
        btr:set_Position(tr:get_Position())
        btr:set_Rotation(tr:get_Rotation())
        b.boltLast = now
    end)
    -- our blast is gone (hit or ended): the bolt stays where it was last put, right at the target
    if not ok and b.boltLast then b.boltDone = true end
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if live.on and cfg.bind then pcall(bind_follow) end
    if #tints > 0 then
        if cfg.blastTint then pcall(tint_update) else tints = {} end
    end
end)
local blast_shell_info
local function effect_id_of(args, how)
    local idstr = how
    pcall(function()
        if how == "requestEffect" or how == "requestEffectInternal" then
            local id = sdk.to_managed_object(args[3])
            idstr = ("%d/%d/%d"):format(id.DataContainerIndex, id.ContainerID, id.ElementID)
        elseif how == "requestEffectFromFsmOrSequence" or how == "requestEffectFromFsm" then
            idstr = ("fsm %d/%d"):format(sdk.to_int64(args[3]) & 0xFFFFFFFF, sdk.to_int64(args[4]) & 0xFFFFFFFF)
        end
    end)
    return idstr
end
local comboFx = { seen = {}, list = {} }
dbg.rec = { on = false, secs = 8, list = {}, info = "-", near = false, scs = {} }
function dbg.rec_add(e)
    local r = dbg.rec
    if not r.on then return end
    e.t = ("%.2f"):format(os.clock() - r.t0)
    r.list[#r.list + 1] = e
    dbg.save("Pactblade_chant_record.json", r.list)
end
-- body material requests (whole-body glows: rim light, basic ...) of the player while recording
pcall(function()
    local td = sdk.find_type_definition("app.MaterialInterpolationRequestManager")
    for _, m in ipairs(td:get_methods()) do
        local nm = m:get_name()
        local okP, pts = pcall(function() return m:get_param_types() end)
        local generic = false
        pcall(function() for _, t in ipairs(pts) do if t:get_full_name():find("!!") then generic = true end end end)
        if okP and not generic and (nm == "requestMaterialMode" or nm == "requestMaterialModeSub" or nm == "requestMIMode") then
            pcall(sdk.hook, m, function(args)
                if not dbg.rec.on then return end
                pcall(function()
                    local pl = runtime.player()
                    local go = sdk.to_managed_object(args[2]):call("get_GameObject")
                    if not pl or go:get_address() ~= pl.game_object:get_address() then return end
                    local list = ""
                    pcall(function() list = pts[3] and pts[3]:get_full_name():match("<app%.MaterialInterpolation(%w+)>") or "" end)
                    dbg.rec_add({ material = sdk.to_int64(args[3]) & 0xFFFFFFFF, category = sdk.to_int64(args[4]) & 0xFFFFFFFF,
                                  via = nm, list = list })
                end)
            end, function(r) return r end)
        end
    end
end)
local function combo_rec(args, how)
    if dbg.rec.on then
        pcall(function()
            local go = sdk.to_managed_object(args[2]):call("get_GameObject")
            local pl = runtime.player()
            if not pl or go:get_address() ~= pl.game_object:get_address() then return end
            local idd = effect_id_of(args, how)
            local e = { effect = idd, how = how }
            pcall(function()   -- which effect file set the container index points at
                local idx = tonumber(tostring(idd):match("^(%-?%d+)/"))
                if idx and idx >= 0 then
                    local mgr = pl.game_object:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
                    e.set = tostring(mgr.ExternalDataContainers[idx].DataContainer:get_Path())
                end
            end)
            dbg.rec_add(e)
        end)
    end
    if dbg.fxRecReset then dbg.fxRecReset = false; comboFx.seen, comboFx.list = {}, {}; combo.t0 = os.clock() end
    if combo.stage == 0 and os.clock() - lastFire > 4 then return end
    pcall(function()
        local go = sdk.to_managed_object(args[2]):call("get_GameObject")
        local by = go:get_address() == live.go and "player" or tostring(go:get_Name())
        local idd = effect_id_of(args, how)
        local key = combo.stage .. by .. idd
        if comboFx.seen[key] then return end
        comboFx.seen[key] = true
        table.insert(comboFx.list, { part = combo.stage, by = by, id = idd, how = how, t = ("%.2f"):format(os.clock() - (combo.t0 or 0)) })
        dbg.save("Pactblade_fx_record.json", comboFx.list)
    end)
end
local MISTY_FX = { ["13/22/0"] = true, ["13/22/3"] = true, ["13/23/1"] = true, ["13/22/15"] = true, ["13/22/10"] = true }   -- Quik Fot's own leap effects
local BLAST_DROP = {}   -- blast effects not played at all (none now; 1.01: -1/8/40 + 43 only lose their first 0.1 s)
local function blast_trim(args, how)
    if not live.on or #blasts == 0 or not (how == "requestEffect" or how == "requestEffectInternal") then return false end
    local secs = false
    pcall(function()
        local t = BLAST_TRIM[effect_id_of(args, how)]
        if not t then return end
        if blast_shell_info(sdk.to_managed_object(args[2]):call("get_GameObject"):get_address()) then secs = t end
    end)
    return secs
end
-- the blast's two see-through effects (-1/8/40, -1/8/43): tinted whole they cover the screen. Here each part of them
-- can be chosen: its emitters (emit mask bits), its colour slots (extern parameters) and its colour groups - which
-- are coloured and which are drawn at all. Applied to the real blasts and to the effect player.
local parts = { ids = { ["-1/8/40"] = true, ["-1/8/43"] = true, ["-1/10/1"] = true, ["-1/10/3"] = true, ["-1/10/6"] = true },
                live = {}, info = {}, files = {} }
-- the same two effect files sit under other numbers for the other projectile versions (13_ch07_cs_Ref.pfb, Gungnir
-- container 8): launch = cs_008_10 / 11 / 110 / 111, explosion = cs_008_30 / 31 / 130 / 131. All follow 40 / 43.
local PART_ALIAS = {}
for _, n in ipairs({ 0, 10, 40, 50, 100, 110 }) do PART_ALIAS["-1/8/" .. n] = "-1/8/40" end
for _, n in ipairs({ 3, 13, 43, 53, 103, 113 }) do PART_ALIAS["-1/8/" .. n] = "-1/8/43" end
for _, n in ipairs({ 1, 3, 6 }) do PART_ALIAS["-1/10/" .. n] = "-1/10/" .. n end   -- the Eldritch Slash wave
dbg.partsIds = PART_ALIAS
dbg.parts = parts
cfg.parts = cfg.parts or {}
do
    local saved = json.load_file(DATA) or {}
    if type(saved.parts) == "table" then
        for id, p in pairs(saved.parts) do if type(p) == "table" and parts.ids[id] then cfg.parts[id] = p end end
    end
end
local PART_DEFAULTS = {
    ["-1/8/40"] = { mode = "ours", variant = "e285" },   -- our purple copy (colour in the file: no veil)
    ["-1/8/43"] = { mode = "ours", variant = "e285" },
    ["-1/10/1"] = { mode = "ours", variant = "h285", follow = true },   -- the wave flies: our copy goes with it
    ["-1/10/3"] = { mode = "ours", variant = "h285" },
    ["-1/10/6"] = { mode = "ours", variant = "h285" },
}
local function part_cfg(id)
    local p = cfg.parts[id]
    if not p then
        local d = PART_DEFAULTS[id] or {}
        p = { mode = d.mode or "extern", variant = d.variant, follow = d.follow or false, extern = {}, groups = {}, mask = nil }
        for k, v in pairs(d.extern or {}) do p.extern[k] = v end
        cfg.parts[id] = p
    end
    p.extern, p.groups = p.extern or {}, p.groups or {}
    return p
end
-- what the effect is made of (read once per effect, from its first copy)
function parts.read(c, id)
    if parts.info[id] then return end
    local out = { players = {} }
    pcall(function()
        local list = c:call("getAllPlayers")
        for q = 0, (list and list:call("get_Count") or 0) - 1 do
            local pl = list:call("get_Item", q)
            local pi = { mask = 0, maskName = "", emitters = 0, extern = {}, groups = {}, groupNames = {} }
            pcall(function() pi.mask = pl:call("get_EmitMaskBit") end)
            pcall(function() pi.maskName = tostring(pl:call("get_MaskName")) end)
            pcall(function() pi.emitters = pl:call("get_EmitterInstanceNum") end)
            for _, getter in ipairs({ function() return pl:call("get_Resource"):call("get_ResourcePath") end,
                                      function() return pl:call("get_Resource"):call("get_Path") end,
                                      function() return pl:call("get_ResourcePath") end }) do
                if not pi.file then
                    local ok, v = pcall(getter)
                    if ok and v then pi.file = tostring(v) end
                end
            end
            pcall(function()
                local tr = pl:call("get_GameObject"):get_Transform()
                local q = tr:get_Position()
                pi.go = tostring(pl:call("get_GameObject"):get_Name())
                pi.parent = tostring(tr:call("get_Parent") and tr:call("get_Parent"):get_GameObject():get_Name())
            end)
            pcall(function()
                for i = 0, pl:call("getExternParametersCount") - 1 do
                    local ep = pl:call("getExternParameters", i)
                    pi.extern[#pi.extern + 1] = tostring(ep:call("get_Name"))
                end
            end)
            pcall(function()
                for i = 0, pl:call("getGroupParametersCount") - 1 do
                    pi.groups[#pi.groups + 1] = tostring(pl:call("getGroupParameters", i):call("get_Name"))
                end
            end)
            pcall(function()
                for i = 0, pl:call("getGroupNamesCount") - 1 do
                    pi.groupNames[#pi.groupNames + 1] = tostring(pl:call("getGroupNames", i):call("get_Name"))
                end
            end)
            out.players[#out.players + 1] = pi
        end
    end)
    parts.info[id] = out
    local all = json.load_file("Pactblade_parts.json") or {}
    all[id] = out
    pcall(json.dump_file, "Pactblade_parts.json", all)
end
-- this copy, as the settings say
local GROUP_WAYS = { "keep", "clear", "empty", "off" }
function parts.groups_off(c, way)
    if way == "clear" then pcall(function() c:call("clearGroupName") end)
    else
        pcall(function()
            local list = c:call("getAllPlayers")
            for q = 0, (list and list:call("get_Count") or 0) - 1 do
                local pl = list:call("get_Item", q)
                if way == "empty" then pl:call("setGroupNamesCount", 0)
                elseif way == "off" then pl:call("set_GroupEnabled", false) end
            end
        end)
    end
end
local function part_colour(p)
    local k = cfg.armBright * (p.strength or 1.0)
    return via_colour({ math.min(1, cfg.armR / 255 * k), math.min(1, cfg.armG / 255 * k), math.min(1, cfg.armB / 255 * k), 1 })
end
function parts.apply(c, id)
    local p = part_cfg(id)
    local col = part_colour(p)
    if p.group and p.group ~= "keep" then parts.groups_off(c, p.group) end
    pcall(function()
        local list = c:call("getAllPlayers")
        for q = 0, (list and list:call("get_Count") or 0) - 1 do
            local pl = list:call("get_Item", q)
            if p.mask then pcall(function() pl:call("set_EmitMaskBit", p.mask) end) end
            if p.mode == "whole" then
                pl:set_Color(col)
            elseif p.mode == "extern" then
                pcall(function()
                    for i = 0, pl:call("getExternParametersCount") - 1 do
                        local ep = pl:call("getExternParameters", i)
                        if p.extern[tostring(ep:call("get_Name"))] then ep:call("set_Color", col) end
                    end
                end)
            elseif p.mode == "groups" then
                pcall(function()
                    for i = 0, pl:call("getGroupParametersCount") - 1 do
                        local gp = pl:call("getGroupParameters", i)
                        if p.groups[tostring(gp:call("get_Name"))] then gp:call("set_Color", col) end
                    end
                end)
            end
        end
    end)
    if p.mode == "groups" then
        for name, on in pairs(p.groups) do
            if on then pcall(function() c:call("setGroupColor(System.String, via.Color)", name, col) end) end
        end
    end
end
-- our edited copies (pak_mods/x0002-PactbladeFx-variants.pak): each variant shrinks one layer to a tiny real mesh
-- (debris / wood chip / hook) - to find the layer that covers the screen. 40's all have its light + blur at 0.
local OUR_VARIANTS = {
    ["-1/8/40"] = {
                    { "v0", "light + blur off only" }, { "v1", "+ spiral 1 off" }, { "v2", "+ shockwave off" },
                    { "v3", "+ magic shape off" }, { "v4", "+ cone off" }, { "v5", "+ spiral 2 off" },
                    { "v6", "+ ALL five shapes off" }, { "t1", "blast colour baked into the file", true },
                    { "c285", "purple (baked)", true }, { "c300", "pink-purple (baked)", true }, { "c315", "pink (baked)", true },
                    { "d285", "purple + light", true }, { "d300", "pink-purple + light", true }, { "d315", "pink + light", true },
                    { "e285", "purple, all", true }, { "e300", "pink-purple, all", true }, { "e315", "pink, all", true } },
    ["-1/8/43"] = {
                    { "w0", "unchanged copy" }, { "w1", "heat haze 1 off" }, { "w2", "heat haze 2 off" },
                    { "w3", "both heat hazes off" }, { "t1", "blast colour baked into the file", true },
                    { "t2", "baked colour, no rock / snow / ice debris (x0006 pak)", true },
                    { "c285", "purple (baked, no debris)", true }, { "c300", "pink-purple (baked, no debris)", true },
                    { "c315", "pink (baked, no debris)", true },
                    { "d285", "purple", true }, { "d300", "pink-purple", true }, { "d315", "pink", true },
                    { "e285", "purple, all", true }, { "e300", "pink-purple, all", true }, { "e315", "pink, all", true } },
    ["-1/10/1"] = { { "h285", "purple", true }, { "h300", "pink-purple", true }, { "h315", "pink", true } },
    ["-1/10/3"] = { { "h285", "purple", true }, { "h300", "pink-purple", true }, { "h315", "pink", true } },
    ["-1/10/6"] = { { "h285", "purple", true }, { "h300", "pink-purple", true }, { "h315", "pink", true } },
}
local OUR_FILES = setmetatable({}, { __index = function(_, id)
    local vs = OUR_VARIANTS[id]
    if not vs then return nil end
    local p = cfg.parts and cfg.parts[id]
    local v = (p and p.variant) or vs[1][1]
    -- 3.15 fog test (user: Eldritch Bolt's lingering fog 70 % smaller): one explosion layer at 30 % per test copy
    -- (pak_mods/x0007-PactbladeFx-fogtest.pak: pb_43_e<hue>f<layer>)
    if id == "-1/8/43" and dbg.fogLayer and tostring(v):match("^e%d+$") then v = v .. "f" .. dbg.fogLayer end
    local tail = id:match("^%-1/8/(%d+)$") or id:gsub("^%-1/", ""):gsub("/", "_")   -- 40 / 43, or 10_1 / 10_3 / 10_6
    return ("vfx/effects/pactblade/pb_%s_%s.efx"):format(tail, v)
end })
parts.ours = {}
function parts.play_ours(id, at, rot, creator)
    local path = OUR_FILES[id]
    if not path then return false end
    parts.res = parts.res or {}
    if not parts.res[path] then
        local r = sdk.create_resource("via.effect.EffectResource", path)
        if not r then note("our effect file not found: " .. path); return false end
        parts.res[path] = r:add_ref()
    end
    local go = make_anchor()
    local tr = go:get_Transform()
    tr:set_Position(at)
    if rot then tr:set_Rotation(rot) end
    local holder = parts.res[path]:create_holder("via.effect.EffectResourceHolder"):add_ref()
    local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
    ep:call("set_Resource", holder)
    pcall(function() ep:call("set_AutoStart", true) end)
    local baked = path:find("_x%d+%.efx$") ~= nil or path:find("_e%d+f%d+%.efx$") ~= nil   -- (the layer test copies: baked purple)
    for _, v in ipairs(OUR_VARIANTS[id] or {}) do
        if path:find("_" .. v[1] .. ".efx", 1, true) and v[3] then baked = true end
    end
    local follow = creator ~= nil and part_cfg(id).follow == true
    pcall(function() if creator then tr:set_LocalScale(creator:get_Transform():call("get_Scale")) end end)
    table.insert(parts.ours, { go = go, ep = ep, creator = creator, untilT = os.clock() + (follow and 30.0 or 3.0), id = id,
                               baked = baked, follow = follow })
    return true
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if #parts.ours == 0 then return end
    local now = os.clock()
    local col = blast_colour()
    for i = #parts.ours, 1, -1 do
        local o = parts.ours[i]
        if now > o.untilT then
            pcall(function() o.go:call("destroy(via.GameObject)", o.go) end)
            table.remove(parts.ours, i)
        else
            pcall(function()
                if o.creator and (o.follow or part_cfg(o.id).follow) then
                    local alive = false
                    pcall(function() alive = o.creator:call("get_Valid") ~= false and o.creator:get_Transform() ~= nil end)
                    if not alive then
                        if o.untilT > now + 0.3 then o.untilT = now + 0.3 end   -- the wave is gone: ours ends with it
                        return
                    end
                    if o.id == "-1/10/1" and not o.killed then   -- the wave ends where its look ends (or at the distance limit)
                        local st = 0
                        pcall(function() st = o.ep:call("get_State") & 0xFFFFFFFF end)
                        local em = -1
                        pcall(function() em = o.ep:call("get_EmitterInstanceNum") end)
                        local here = o.creator:get_Transform():get_Position()
                        o.from = o.from or here
                        o.born2 = o.born2 or now
                        local dist = (here - o.from):length()
                        if st == 2 then o.ran = true end
                        if em and em > 0 then o.seenEmit = true end
                        o.noEmit = (o.seenEmit and em == 0) and (o.noEmit or 0) + 1 or 0
                        if (o.ran and (st == 0 or st == 3 or st == 4 or st == 5)) or o.noEmit >= 3 or dist >= (cfg.slashHitRange or 28) then
                            o.killed = true
                            pcall(function()
                                local sh = o.creator:call("getComponent(System.Type)", sdk.typeof("app.Shell"))
                                local mc = o.creator:call("getComponent(System.Type)", sdk.typeof("app.ShellAdditionalJob07SubNormalAttackShell"))
                                local ow = sh and sh:get_field("<Owner>k__BackingField")
                                if mc and ow and ow:get_address() == live.go then
                                    dbg.slashKilled = dbg.slashKilled or {}
                                    dbg.slashKilled[o.creator:get_address()] = now + 0.5   -- (its end effect is dropped)
                                    sh:call("set_RequestKill", true)
                                    note(("Eldritch Slash: wave ended at %.1f m (state %d, emitters %d)"):format(dist, st, em or -1))
                                end
                            end)
                        end
                    end
                    local ctr, tr = o.creator:get_Transform(), o.go:get_Transform()
                    tr:set_Position(ctr:get_Position())
                    tr:set_Rotation(ctr:get_Rotation())
                    pcall(function() tr:set_LocalScale(ctr:call("get_Scale")) end)
                end
            end)
            if cfg.blastTint and not o.baked then pcall(function() o.ep:set_Color(part_colour(part_cfg(o.id))) end) end
        end
    end
end)
function parts.add(rv, id)
    pcall(function()
        local c = sdk.to_managed_object(rv)
        if not c then return end
        local addr = c:get_address()
        for _, e in ipairs(parts.live) do if e.addr == addr then return end end
        c = c:add_ref()
        parts.read(c, id)
        if part_cfg(id).mode == "hidden" and parts.files[id] then c:call("killAll"); return end   -- not played at all
        if part_cfg(id).mode == "ours" and OUR_FILES[id] then
            local at, rot, creator
            pcall(function()
                creator = c:get_field("Creator")
                if creator then creator = creator:add_ref() end
                local tr = creator:get_Transform()
                at, rot = tr:get_Position(), tr:get_Rotation()
            end)
            if at and parts.play_ours(id, at, rot, creator) then
                c:call("killAll")
                note("effect " .. id .. ": our edited copy plays instead (" .. tostring(OUR_FILES[id]) .. ")")
                return
            end
        end
        parts.apply(c, id)
        table.insert(parts.live, { c = c, id = id, born = os.clock(), addr = addr })
    end)
end
function parts.wanted(args, how)
    if not live.on or #blasts == 0 or not (how == "requestEffect" or how == "requestEffectInternal") then return false end
    local id = false
    pcall(function()
        local idstr = PART_ALIAS[effect_id_of(args, how)]
        if not idstr then return end
        if blast_shell_info(sdk.to_managed_object(args[2]):call("get_GameObject"):get_address()) then id = idstr end
    end)
    return id
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if #parts.live == 0 then return end
    local now = os.clock()
    for i = #parts.live, 1, -1 do
        local e = parts.live[i]
        local dead = now - e.born > 10
        pcall(function() if e.c:call("get_isFinished") then dead = true end end)
        if not dead and not parts.files[e.id] then
            pcall(function()
                local list = e.c:call("getAllPlayers")
                local paths = {}
                for q = 0, (list and list:call("get_Count") or 0) - 1 do
                    local pl = list:call("get_Item", q)
                    local ready = true
                    pcall(function() ready = pl:call("get_ReadyResource") end)
                    local path
                    pcall(function() path = pl:call("get_ResourcePath") end)
                    if ready and path and tostring(path) ~= "" then paths[#paths + 1] = tostring(path) end
                end
                if #paths > 0 then
                    parts.files[e.id] = paths
                    note("effect " .. e.id .. " plays " .. table.concat(paths, ", "))
                    pcall(json.dump_file, "Pactblade_parts_files.json", parts.files)
                end
            end)
        end
        if dead then table.remove(parts.live, i) else parts.apply(e.c, e.id) end
    end
end)
pcall(function()
    local td = sdk.find_type_definition("app.WwiseContainerApp")
    for _, m in ipairs(td:get_methods()) do
        local name = m:get_name()
        if name == "trigger" or name == "triggerLogLess" or name == "triggerWithSyncSpace" then
            sdk.hook(m, function(args)
                if dbg.rec.on then
                    pcall(function()
                        local pl = runtime.player()
                        local cgo = sdk.to_managed_object(args[2]):get_GameObject()
                        if not pl then return end
                        local objName
                        if cgo:get_address() ~= pl.game_object:get_address() then
                            if not dbg.rec.near then return end
                            local p1, p2 = cgo:get_Transform():get_Position(), pl.game_object:get_Transform():get_Position()
                            local dx, dy, dz = p1.x - p2.x, p1.y - p2.y, p1.z - p2.z
                            if dx * dx + dy * dy + dz * dz > 100 then return end
                            objName = tostring(cgo:get_Name())
                        end
                        local id
                        pcall(function() id = sdk.to_managed_object(args[3]):call("get_TriggerId") end)
                        if not id then id = sdk.to_int64(args[3]) & 0xFFFFFFFF end
                        dbg.rec_add({ sound = id, via = name, obj = objName })
                    end)
                end
                if not live.on then return end
                if combo.stage == 0 and os.clock() - (combo.endT or -100) > 3 then return end
                pcall(function()
                    local id
                    pcall(function() id = sdk.to_managed_object(args[3]):call("get_TriggerId") end)
                    if not id then id = sdk.to_int64(args[3]) & 0xFFFFFFFF end
                    local key = "snd" .. combo.stage .. tostring(id)
                    if comboFx.seen[key] then return end
                    comboFx.seen[key] = true
                    table.insert(comboFx.list, { part = combo.stage, sound = id, via = name,
                        warpCue = combo.cueingSnd == true, t = ("%.2f"):format(os.clock() - (combo.t0 or 0)) })
                    dbg.save("Pactblade_fx_record.json", comboFx.list)
                end)
            end, function(r) return r end)
        end
    end
end)
local function combo_dust(args, how)
    if dbg.slashKilled and next(dbg.slashKilled) then   -- an Eldritch Slash wave we ended: no end / hit effect there
        local drop = false
        pcall(function()
            local addr = sdk.to_managed_object(args[2]):call("get_GameObject"):get_address()
            local untilT = dbg.slashKilled[addr]
            if untilT then
                if os.clock() < untilT then drop = true else dbg.slashKilled[addr] = nil end
            end
        end)
        if drop then return true end
    end
    if live.on and #blasts > 0 and (how == "requestEffect" or how == "requestEffectInternal") then
        local drop = false
        pcall(function()
            if not BLAST_DROP[effect_id_of(args, how)] then return end
            drop = blast_shell_info(sdk.to_managed_object(args[2]):call("get_GameObject"):get_address()) ~= nil
        end)
        if drop then return true end
    end
    if live.on and combo.mistyUntil and os.clock() < combo.mistyUntil and not combo.cueing
       and (how == "requestEffect" or how == "requestEffectInternal") then
        local kill = false
        pcall(function()
            if sdk.to_managed_object(args[2]):call("get_GameObject"):get_address() ~= live.go then return end
            kill = MISTY_FX[effect_id_of(args, how)] == true
        end)
        if kill then return true end
    end
    if not live.on or combo.stage == 0 or combo.cueing then return false end
    local rush = combo.stage == 2 or combo.stage == 3
    if not ((cfg.comboNoDust and rush) or dbg.comboNoFxAll) then return false end
    local yes = false
    pcall(function()
        local addr = sdk.to_managed_object(args[2]):call("get_GameObject"):get_address()
        yes = addr == live.go
        if not yes and dbg.comboNoSwordFx then
            local sw = combo.sword_go and combo.sword_go()   -- held_sword_go is defined further down
            yes = sw ~= nil and sw:get_address() == addr
        end
    end)
    return yes
end
local function tint_wanted(args, how)
    if not (live.on and cfg.blastTint) then return false end
    local tint, mine = false, false
    pcall(function()
        if ourSpawn then tint = true; return end
        local mgr = sdk.to_managed_object(args[2])
        local goAddr = mgr:call("get_GameObject"):get_address()
        if goAddr == live.go then tint = os.clock() - lastFire < TINT_WINDOW; mine = true
        elseif #blasts > 0 and blast_shell_info(goAddr) then tint = true
        elseif os.clock() - lastFire < 6 or os.clock() - (dbg.slashT or -10) < 6 then
            local go = mgr:call("get_GameObject")
            local sh = go:call("getComponent(System.Type)", sdk.typeof("app.Shell"))
            local ow = sh and sh:get_field("<Owner>k__BackingField")
            tint = ow ~= nil and ow:get_address() == live.go
            if tint and (lastKind == "charged" or lastKind == "burst") and cfg.bind and bindBolt.addr ~= goAddr and not dbg.noBindCapture then
                bindBolt.go, bindBolt.addr, bindBolt.born = go:add_ref(), goAddr, os.clock()
            end
        end
    end)
    if not tint then return false end
    local idstr = effect_id_of(args, how)
    if cfg.noTint[idstr] or dbg.partsIds[idstr] then return false end
    -- the character's own effects: only the blast animation's (Mystic Spearhand's effect file = data container 13)
    -- and the charge cloud (0/160) - not water splashes, footsteps, dust or sword trails played in those 2 s
    if mine and not (idstr:find("^13/") or idstr:find("^0/160/")) then return false end
    -- the slash's wave (it fired last, within 6 s): its own colour
    -- (1.56-1.63: the slash's wave had its own colour here - back to the blasts' colour, user)
    return idstr
end
local tintRecent = {}   -- idstr -> { n, last, how }: what was coloured lately (menu list)
local colouredLog = {}
function dbg.coloured(idstr, how, by)
    local key = idstr .. "|" .. tostring(how)
    if colouredLog[key] then return end
    colouredLog[key] = true
    local all = json.load_file("Pactblade_coloured.json") or {}
    all[#all + 1] = { id = idstr, how = how, by = by, t = os.date("%H:%M:%S") }
    pcall(json.dump_file, "Pactblade_coloured.json", all)
end
local function tint_note(idstr, how)
    if dbg.coloured then dbg.coloured(idstr, how, "requested") end
    local r = tintRecent[idstr] or { n = 0, how = how }
    r.n, r.last = r.n + 1, os.clock()
    tintRecent[idstr] = r
end
local function tint_add(rv, how, idstr)
    pcall(function()
        local c = sdk.to_managed_object(rv)
        if not c then return end
        local addr = c:get_address()
        if tintSeen[addr] then return end
        tintSeen[addr] = true
        local isSlash = type(idstr) == "table" and idstr.slash
        if type(idstr) == "table" then idstr = idstr.id end
        idstr = type(idstr) == "string" and idstr or how
        tint_note(idstr, how)
        table.insert(tints, { c = c:add_ref(), born = os.clock(), addr = addr, id = idstr, slash = isSlash })
        dbg.tinted = (dbg.tinted or 0) + 1
        dbg.tintBy = dbg.tintBy or {}
        dbg.tintBy[how] = (dbg.tintBy[how] or 0) + 1
    end)
end
function blast_shell_info(goAddr)
    for _, b in ipairs(blasts) do
        for _, p in ipairs(b.record.parts or {}) do
            local ok, a2 = pcall(function() return p.shell:get_GameObject():get_address() end)
            if ok and a2 == goAddr then return b end
        end
    end
    return nil
end
local function hit_elements(shellId)
    local param = params[shellId]
    if not param then return nil end
    local out = {}
    pcall(function()
        local e = param._ShellParameterBase.effectParam
        for _, f in ipairs({ "HitElementID", "HitAddElementID", "HitTerrainElementID", "HitTerrainAddElementID", "FinishElementID" }) do
            local v = e[f]
            if v and v >= 0 then out[v] = true end
        end
    end)
    return out
end
pcall(function()
    local td = sdk.find_type_definition("via.effect.script.ObjectEffectManager2")
    for _, m in ipairs(td:get_methods()) do
        local okP, pt = pcall(function() return m:get_param_types() end)
        if m:get_name() == "requestEffect" and okP and pt[1] and pt[1]:get_full_name() == "via.effect.script.EffectID" then
            local stack, tstack, rstack = {}, {}, {}
            sdk.hook(m, function(args)
                local want = false
                if live.on and next(pieceByGo) then
                    pcall(function()
                        local mgr = sdk.to_managed_object(args[2])
                        local pc = pieceByGo[mgr:call("get_GameObject"):get_address()]
                        if pc then
                            local id = sdk.to_managed_object(args[3])
                            local flight = -2
                            pcall(function() flight = params[BLAST.tap.shell]._ShellParameterBase.effectParam.ShellElementID end)
                            want = (pc.dead or id.ElementID ~= flight) and "kill" or pc
                        end
                    end)
                end
                if not want and live.on and #blasts > 0 then
                    pcall(function()
                        local mgr = sdk.to_managed_object(args[2])
                        local b = blast_shell_info(mgr:call("get_GameObject"):get_address())
                        if b then
                            local idh = sdk.to_managed_object(args[3])
                            local hits = hit_elements(BLAST[b.kind].shell)
                            if hits and hits[idh.ElementID] then b.hitNow = true end
                        end
                        if b and BLAST[b.kind].hidden then
                            local id = sdk.to_managed_object(args[3])
                            local start = -2
                            pcall(function() start = params[BLAST[b.kind].shell]._ShellParameterBase.effectParam.StartElementID end)
                            if id.ElementID ~= start then want = "kill" end
                        end
                    end)
                end
                -- the Forbeding Bolt that rides along with the charged blast: its own flight / launch visuals hidden
                -- (the bind effect on the enemy stays)
                if not want and live.on and cfg.bind and (lastKind == "charged" or lastKind == "burst") and os.clock() - lastFire < 6 then
                    pcall(function()
                        local mgr = sdk.to_managed_object(args[2])
                        local go = mgr:call("get_GameObject")
                        local addr = go:get_address()
                        if addr == live.go or blast_shell_info(addr) then return end
                        local sh = go:call("getComponent(System.Type)", sdk.typeof("app.Shell"))
                        local ow = sh and sh:get_field("<Owner>k__BackingField")
                        if ow and ow:get_address() == live.go then
                            want = "kill"
                            if not (bindBolt.go and bindBolt.addr == addr) then
                                bindBolt.go, bindBolt.addr, bindBolt.born = go:add_ref(), addr, os.clock()
                            end
                        end
                    end)
                end
                if not want and live.on and cfg.boom < 0.999 then
                    pcall(function()
                        local mgr = sdk.to_managed_object(args[2])
                        local goAddr = mgr:call("get_GameObject"):get_address()
                        if goAddr == live.go then
                            local id = sdk.to_managed_object(args[3])
                            if id.DataContainerIndex == 0 and id.ContainerID == CHARGE_CLOUD then want = "scale" end
                            return
                        end
                        if #blasts == 0 then return end
                        local b = blast_shell_info(goAddr)
                        if b then
                            local id = sdk.to_managed_object(args[3])
                            local hits = not BLAST[b.kind].noScale and hit_elements(BLAST[b.kind].shell)
                            if hits and hits[id.ElementID] then want = "scale" end
                        end
                    end)
                end
                stack[#stack + 1] = want
                combo_rec(args, "requestEffect")
                if dbg.md_seen then pcall(dbg.md_seen, args, "requestEffect") end
                if not want and combo_dust(args, "requestEffect") then
                    want = "kill"
                    local idd = effect_id_of(args, "requestEffect")
                    if not combo.dustSeen then combo.dustSeen = {} end
                    if not combo.dustSeen[idd] then combo.dustSeen[idd] = true; note("combo: switched off effect " .. idd) end
                end
                stack[#stack] = want
                tstack[#tstack + 1] = want ~= "kill" and tint_wanted(args, "requestEffect")
                rstack[#rstack + 1] = want ~= "kill" and parts.wanted(args, "requestEffect")
            end, function(rv)
                local tid = table.remove(tstack)
                if tid then tint_add(rv, "requestEffect", tid) end
                local trimS = table.remove(rstack)
                local want = table.remove(stack)
                if want then
                    pcall(function()
                        local c = sdk.to_managed_object(rv)
                        if not c then return end
                        if want == "kill" then c:call("killAll"); dbg.hidden = (dbg.hidden or 0) + 1; return end
                        if type(want) == "table" then table.insert(want.conts, c:add_ref()); return end
                        if cfg.boom < 0.05 then c:call("finishAll")
                        else
                            c:call("setUniformScale", cfg.boom)
                            table.insert(clouds, { c = c:add_ref(), born = os.clock() })
                        end
                        dbg.booms = (dbg.booms or 0) + 1
                    end)
                end
                if trimS then parts.add(rv, trimS) end
                return rv
            end)
        end
    end
end)

pcall(function()
    local td = sdk.find_type_definition("via.effect.script.ObjectEffectManager2")
    local NAMES = { requestEffectInternal = true, requestEffectFromFsmOrSequence = true, requestEffectFromFsm = true,
                    requestEffectParamFromFsm = true, requestEffectParamAllElementsFromFsm = true }
    for _, m in ipairs(td:get_methods()) do
        local name = m:get_name()
        local okR, rt = pcall(function() return m:get_return_type():get_full_name() end)
        if NAMES[name] and okR and rt == "via.effect.script.CreatedEffectContainer" then
            local stack, rst, mst = {}, {}, {}
            sdk.hook(m, function(args)
                combo_rec(args, name)
                if dbg.md_seen then pcall(dbg.md_seen, args, name) end
                local mdf = false
                if dbg.md_fx then pcall(function() mdf = dbg.md_fx(args, effect_id_of(args, name)) end) end
                mst[#mst + 1] = mdf
                if combo_dust(args, name) then
                    local idd = effect_id_of(args, name)
                    if not combo.dustSeen then combo.dustSeen = {} end
                    if not combo.dustSeen[idd] then combo.dustSeen[idd] = true; note("combo: switched off effect " .. idd) end
                    stack[#stack + 1] = "kill"
                    rst[#rst + 1] = false
                    return
                end
                stack[#stack + 1] = tint_wanted(args, name)
                rst[#rst + 1] = parts.wanted(args, name)
            end, function(rv)
                local mdf = table.remove(mst)
                local tid = table.remove(stack)   -- (all three stacks popped every time: 2.91 returned before these
                local trimS = table.remove(rst)   -- two, so every later effect got another one's colour / kill)
                if mdf then pcall(dbg.md_fx_play, rv, mdf); return rv end   -- (Misty Dive: our copy instead)
                if tid == "kill" then
                    pcall(function() local c = sdk.to_managed_object(rv); if c then c:call("killAll") end end)
                    return rv
                elseif tid then tint_add(rv, name, tid) end
                if trimS then parts.add(rv, trimS) end
                return rv
            end)
        end
    end
end)

------------------------------------------------------------------------
-- test dummies: DLC enemies that stand still (AI decision tree paused, reactions still play); killable, their hits
-- are marked "(dummy)" in the hit log. Spawned with DragonCore's summon; found afterwards in the
-- enemy list by type near the spawn point.
------------------------------------------------------------------------
local DUMMIES = {
    { name = "Beorcan Warrior (DLC bandit)", path = "AppSystem/ch/ch230/prefab/ch230004_05.pfb", tag = "ch230004" },
    { name = "Beorcan Fighter (DLC bandit)", path = "AppSystem/ch/ch230/prefab/ch230004_01.pfb", tag = "ch230004" },
    { name = "Cyclops", path = "AppSystem/ch/ch250/prefab/ch250000_00.pfb", tag = "ch250000" },
    { name = "Chimera", path = "AppSystem/ch/ch254/prefab/ch254000_00.pfb", tag = "ch254000" },
}
local dummy = { wanted = {}, set = {}, hits = {}, count = 0, status = "-" }   -- set: chara address -> { chara, paused }
local function dummy_spawn(d)
    local a = runtime.player()
    if not a or not a:valid() then return end
    local ok = a:summon({ summon = d.path, count = 1, duration = 3600, hostile = true, at = "front", distance = 4 })
    local before = {}
    pcall(function()
        local list = sdk.get_managed_singleton("app.EnemyManager")._EnemyList
        for i = 0, list._size - 1 do
            local e = list._items[i]
            if e and e._Chara then before[e._Chara:get_address()] = true end
        end
    end)
    local at
    pcall(function()
        local tr = a.game_object:get_Transform()
        at = tr:get_Position() + require("DragonCore.game.mathx").rotate(Vector3f.new(0, 0, 4), tr:get_Rotation())
    end)
    table.insert(dummy.wanted, { tag = d.tag, untilT = os.clock() + 20, before = before, at = at })
    dummy.status = ok and ("spawning " .. d.name .. "...") or ("spawn failed: " .. tostring(a.errors and a.errors.summon))
end
local dumped = {}
local function pause_ai(chara)
    local go = chara:get_GameObject()
    local n = 0
    local comps = go:call("get_Components")
    local list = {}
    for i = 0, comps:get_size() - 1 do
        pcall(function()
            local c = comps[i]
            local td = c:get_type_definition()
            local tn = td:get_full_name()
            local okT, isTree = pcall(td.is_a, td, "via.behaviortree.BehaviorTree")
            isTree = okT and isTree
            local okM, isFsm = pcall(td.is_a, td, "via.motion.MotionFsm2")
            local isMotion = (okM and isFsm) or tn:find("Motion") ~= nil
            list[#list + 1] = tn .. (isTree and (isMotion and "  [tree, animation: left running]" or "  [tree: PAUSED]") or "")
            if tn == "app.AIDecisionMaker" then
                c:call("set_Enabled", false); n = n + 1
                list[#list] = list[#list] .. "  [SWITCHED OFF]"
            end
        end)
    end
    -- components of each dummy once, for choosing exactly what to pause
    if not dumped[chara:get_address()] then
        dumped[chara:get_address()] = true
        pcall(json.dump_file, "Pactblade_dummy_components.json", list)
    end
    return n
end
local function dummy_update()
    if #dummy.wanted == 0 and dummy.count == 0 then return end
    local now = os.clock()
    local mgr = sdk.get_managed_singleton("app.EnemyManager")
    local list = mgr and mgr._EnemyList
    local items, size = list and list._items, list and list._size or 0
    for i = 0, size - 1 do
        local e = items[i]
        local ch = e and e._Chara
        if ch then
            local addr = ch:get_address()
            local d = dummy.set[addr]
            if not d and #dummy.wanted > 0 then
                local okP, pos = pcall(function() return ch:get_GameObject():get_Transform():get_Position() end)
                for k, w in ipairs(dummy.wanted) do
                    local near = okP and w.at and (pos - w.at):length() < 6
                    if near and not w.before[addr] then
                        d = { chara = ch:add_ref(), seen = now }
                        pcall(function() dummy.hits[ch["<Hit>k__BackingField"]:get_address()] = true end)
                        dummy.set[addr] = d
                        dummy.count = dummy.count + 1
                        table.remove(dummy.wanted, k)
                        break
                    end
                end
            end
            -- pause its AI a moment after it appears (once its parts are set up), and keep it paused
            if d and now - d.seen > 3.0 then
                local okP, n = pcall(pause_ai, ch)
                if okP and not d.paused then d.paused = n; dummy.status = ("dummy ready (%d AI part(s) paused)"):format(n) end
            end
        end
    end
    for k = #dummy.wanted, 1, -1 do if now > dummy.wanted[k].untilT then table.remove(dummy.wanted, k) end end
end
re.on_pre_application_entry("UpdateBehavior", function() pcall(dummy_update) end)
local function is_dummy_hit(info)
    if dummy.count == 0 then return false end
    local ok, hc = pcall(function() return info:get_DamageOwnerHitController() end)
    return ok and hc and dummy.hits[hc:get_address()] == true
end
local function is_dummy(go)
    if dummy.count == 0 or not go then return false end
    local ok, ch = pcall(function() return go:call("getComponent(System.Type)", sdk.typeof("app.Character")) end)
    return ok and ch and dummy.set[ch:get_address()] ~= nil
end


------------------------------------------------------------------------
-- debug: the game's damage math for the player's hits -> reframework/data/Pactblade_calc.json
-- app.PlayerDamageCalculator.calcMagicAttack / calcPhysicsAttack wrap calcAttack(4 floats) and calcDamage(5 floats)
------------------------------------------------------------------------
local calc = { rows = {}, scope = nil, humanAddr = nil }
local function calc_row(r)
    r.t = os.date("%H:%M:%S")
    table.insert(calc.rows, r)
    while #calc.rows > 80 do table.remove(calc.rows, 1) end
    dbg.save("Pactblade_calc.json", calc.rows)
end
local function mine(this)
    local ok, h = pcall(function() return sdk.to_managed_object(this).Human end)
    return ok and h and live.go and h:get_GameObject():get_address() == live.go
end
pcall(function()
    local td = sdk.find_type_definition("app.PlayerDamageCalculator")
    for _, spec in ipairs({ { "calcMagicAttack", "magick" }, { "calcPhysicsAttack", "physical" } }) do
        local m = td:get_method(spec[1] .. "(app.HitController.DamageInfo, app.PlayerAttackParameter, app.PlayerDamageCalculator.SpecialAttackFactor)")
        sdk.hook(m, function(args)
            if mine(args[2]) then calc.scope = spec[2] end
        end, function(r) calc.scope = nil; return r end)
    end
    local function floats(args, n)
        local out = {}
        for i = 1, n do
            local ok, v = pcall(sdk.to_float, args[2 + i])
            out[i] = ok and math.floor(v * 1000 + 0.5) / 1000 or "?"
        end
        return out
    end
    for _, spec in ipairs({ { "calcAttack(System.Single, System.Single, System.Single, System.Single)", "calcAttack", 4 },
                            { "calcDamage(System.Single, System.Single, System.Single, System.Single, System.Single)", "calcDamage", 5 } }) do
        local m = td:get_method(spec[1])
        local stack = {}
        sdk.hook(m, function(args)
            local rec = false
            if mine(args[2]) then rec = { fn = spec[2], part = calc.scope or "?", args = floats(args, spec[3]) } end
            stack[#stack + 1] = rec
        end, function(r)
            local rec = table.remove(stack)
            if rec then
                local ok, v = pcall(sdk.to_float, r)
                rec.result = ok and math.floor(v * 1000 + 0.5) / 1000 or "?"
                calc_row(rec)
            end
            return r
        end)
    end
end)

------------------------------------------------------------------------
-- holy magick sword: while Pactblade is active the sword in hand gets Magick equal to its Strength (like a duospear,
-- whose Strength and Magick are always equal) and the Holy element like The Exalted (_Element 4, _ElementStore 100). Written into the weapon's data
-- (app.ItemWeaponParam, shared by every copy of that weapon, as Stalwart Nox does) and put back when Pactblade is off,
-- another weapon is drawn, or on script reset. Nothing goes into the save.
------------------------------------------------------------------------
local swordMod = nil   -- { param, id, mag, el, store }
local HOLY, HOLY_STORE = 4, 100
local ELEMENT_CHOICES = { { "Holy", 4 }, { "Fire", 1 }, { "Ice", 2 }, { "Thunder", 3 }, { "none", 0 } }
local swordEl = { pick = 4 }   -- index into ELEMENT_CHOICES: Thunder (damage, swing trail and sounds; user's choice)
local function sword_element() return ELEMENT_CHOICES[swordEl.pick][2] end
local function refresh_equipment(itemId)
    local im = sdk.get_managed_singleton("app.ItemManager")
    if not im then return end
    if itemId then
        pcall(function()
            local members = im:call("getStorageMembers")
            for i = 0, members:call("get_Count") - 1 do
                local cid = members:call("get_Item", i)
                local list = im:call("getStorageMasterList(app.CharacterID)", cid)
                local ed = im:call("getEquipData(app.CharacterID)", cid)
                local data = ed and ed:get_field("Data")
                if list and data then
                    for j = 0, list:call("get_Count") - 1 do
                        local md = list:call("get_Item", j)
                        local sd = md and md:get_field("_Param")
                        if sd and sd:get_field("_ItemId") == itemId and sd:get_field("_IsEquipped") then
                            pcall(data.call, data, "updateEnhanceEquip(app.ItemDefine.StorageData)", sd)
                            dbg.swordRefresh = (dbg.swordRefresh or 0) + 1
                        end
                    end
                end
            end
        end)
    end
    pcall(function() im:call("applyEquipDataForCharacter()") end)
end
local function sword_restore()
    if not swordMod then return end
    pcall(function()
        swordMod.param._MagicAttack = swordMod.mag
        swordMod.param._Element = swordMod.el
        swordMod.param._ElementStore = swordMod.store
    end)
    local itemId = swordMod.itemId
    swordMod = nil
    refresh_equipment(itemId)
end
-- the weapon in my right hand, read from the weapon slot's own field. (CRASH 2026-10-24 00:03, Pactblade -> Mystic
-- Spearhand -> Pactblade: WeaponElementController.getWeapon threw inside the game ~180 times in 2 s while the vocation
-- changed, crash 14 s later.) Nothing is called on the game here; nil while the slot is switching or empty.
function dbg.right_weapon()
    local w, why = nil, "?"
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        local p = cm and cm["<ManualPlayer>k__BackingField"]
        local holder = p and p:get_WeaponAndItemHolder()
        local slot = holder and holder:get_RightWeapon()
        if not slot then why = "no slot"; return end
        local prep = slot:get_field("IsStartPrepare")
        if prep == true then why = "switching"; return end
        w = slot:get_field("<Weapon>k__BackingField")
        if not w then   -- (the weapon component on the slot's object)
            local go = slot:get_field("<Object>k__BackingField")
            w = go and go:call("getComponent(System.Type)", sdk.typeof("app.Weapon"))
        end
        why = w and "ok" or "empty slot"
    end)
    if why ~= dbg.rwWhy then dbg.rwWhy = why; note("right-hand weapon: " .. why) end
    return w
end
local function held_weapon() return dbg.right_weapon() end
local function held_weapon_id()
    local w = held_weapon()
    return w and w.ID or nil
end
local heldEl = nil   -- { weapon, el }: the sword object whose element we changed
local function held_restore()
    if not heldEl then return end
    pcall(function() heldEl.weapon.ElementType = heldEl.el end)
    heldEl = nil
end
local function held_apply()
    local w = held_weapon()
    if not w then return end
    if heldEl and heldEl.weapon:get_address() ~= w:get_address() then held_restore() end
    if not heldEl then heldEl = { weapon = w:add_ref(), el = w.ElementType } end
    if w.ElementType ~= sword_element() then
        w.ElementType = sword_element()
        dbg.heldEl = ("sword object element: %s -> %s"):format(tostring(heldEl.el), ELEMENT_CHOICES[swordEl.pick][1])
    end
end
local lastSword = 0
local function sword_update()
    if os.clock() - lastSword < 0.5 then return end
    lastSword = os.clock()
    if not live.on then sword_restore(); held_restore(); return end
    pcall(held_apply)
    if swordEl.dirty and swordMod then
        swordEl.dirty = false
        refresh_equipment(swordMod.itemId)
    end
    local id = held_weapon_id()
    if not id then return end
    if swordMod and swordMod.id == id then
        -- keep it applied (another mod or the game could have reset the value)
        pcall(function()
            if swordMod.param._MagicAttack ~= swordMod.param._PhysicalAttack or swordMod.param._Element ~= sword_element() then
                swordMod.param._MagicAttack = swordMod.param._PhysicalAttack
                swordMod.param._Element = sword_element()
                swordMod.param._ElementStore = HOLY_STORE
                refresh_equipment(swordMod.itemId)
            end
        end)
        return
    end
    sword_restore()
    local im = sdk.get_managed_singleton("app.ItemManager")
    local ok, param = pcall(function() return im:call("getItemData(app.WeaponID)", id) end)
    if not ok or not param then return end
    swordMod = { param = param:add_ref(), id = id, itemId = param._Id, mag = param._MagicAttack, el = param._Element,
                 store = param._ElementStore }
    param._MagicAttack = param._PhysicalAttack
    param._Element = sword_element()
    param._ElementStore = HOLY_STORE
    dbg.sword = ("sword: Strength %s -> Magick %s (was %s), Holy %s (was element %s)"):format(tostring(param._PhysicalAttack),
        tostring(param._MagicAttack), tostring(swordMod.mag), tostring(HOLY_STORE), tostring(swordMod.el))
    refresh_equipment(swordMod.itemId)
end
re.on_frame(function() pcall(sword_update) end)
re.on_script_reset(function() sword_restore(); held_restore() end)

------------------------------------------------------------------------
-- no boons: Fire / Ice / Thunder enchant (StatusConditionEnum 15 / 16 / 17) can't be put on you while Pactblade is
-- active, and one already on you is cured when Pactblade becomes active
------------------------------------------------------------------------
local BOONS = { [15] = "fire_boon", [16] = "ice_boon", [17] = "thunder_boon" }
pcall(function()
    sdk.hook(sdk.find_type_definition("app.StatusConditionCtrl"):get_method(
        "reqStatusConditionApplyCore(app.StatusConditionDef.StatusConditionEnum, app.HitController.DamageInfo, app.StatusConditionDef.RequestInfo, System.Boolean)"),
        function(args)
            if not live.on or not live.sc or sdk.to_int64(args[2]) ~= live.sc then return end
            if BOONS[sdk.to_int64(args[3]) & 0xFFFFFFFF] then
                dbg.boons = (dbg.boons or 0) + 1
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(r) return r end)
end)
local boonCheck = 0
function boon_clear(a)
    if os.clock() - boonCheck < 1.0 then return end
    boonCheck = os.clock()
    local st = require("DragonCore.game.statuses")
    for _, kind in pairs(BOONS) do
        pcall(function()
            if a:status_active(kind) then st.cure(a.character, kind); note("removed " .. kind .. " (Pactblade)") end
        end)
    end
end

-- damage element: the sword keeps its element for sounds / behaviour (e.g. Fire), the hit's element is swapped when
-- the game writes it (CharacterDamageCalculator.setElemntTypeOnEnchant) - Holy by default
local dmgEl = { pick = 2, names = { "Holy (not working yet)", "same as the sword" } }
pcall(function()
    sdk.hook(sdk.find_type_definition("app.CharacterDamageCalculator"):get_method(
        "setElemntTypeOnEnchant(app.AttackUserData.ElementType, app.HitController.DamageInfo)"), function(args)
        if not live.on or dmgEl.pick ~= 1 then return end
        local ok, mine = pcall(function()
            local h = sdk.to_managed_object(args[2]).Human
            return h and h:get_GameObject():get_address() == live.go
        end)
        if ok and mine then
            dbg.elSwaps = (dbg.elSwaps or 0) + 1
            dbg.elFrom = sdk.to_int64(args[3]) & 0xFFFFFFFF
            args[3] = sdk.to_ptr(4)
        end
    end, function(r) return r end)
end)

pcall(function()
    local td = sdk.find_type_definition("app.PlayerDamageCalculator")
    local stack = {}
    sdk.hook(td:get_method("getElementTypeByEnchant(app.HitController.DamageInfo)"), function(args)
        local mineNow = false
        if live.on and dmgEl.pick == 1 then
            pcall(function()
                local h = sdk.to_managed_object(args[2]).Human
                mineNow = h and h:get_GameObject():get_address() == live.go
            end)
        end
        stack[#stack + 1] = mineNow
    end, function(r)
        if not table.remove(stack) then return r end
        local v = sdk.to_int64(r)
        if (v & 0xFF) == 0 then return r end              -- no element: leave it
        dbg.elReads = (dbg.elReads or 0) + 1
        return sdk.to_ptr((v & 0xFFFFFFFF) | (4 << 32))   -- HasValue kept, value = Holy
    end)
end)

-- recorder: effects and blade-glow modes requested on the sword in hand (to find the element's own visuals)
local swordFx = { rows = {}, ours = false }
local function sword_fx_row(r)
    r.t = os.date("%H:%M:%S")
    r.swordEl = ELEMENT_CHOICES[swordEl.pick][1]
    table.insert(swordFx.rows, r)
    while #swordFx.rows > 80 do table.remove(swordFx.rows, 1) end
    dbg.save("Pactblade_sword_fx.json", swordFx.rows)
end
local function held_sword_go()
    local w = held_weapon()
    return w and w:get_GameObject() or nil
end
pcall(function()
    local td = sdk.find_type_definition("via.effect.script.ObjectEffectManager2")
    for _, m in ipairs(td:get_methods()) do
        local okP, pt = pcall(function() return m:get_param_types() end)
        if m:get_name() == "requestEffect" and okP and pt[1] and pt[1]:get_full_name() == "via.effect.script.EffectID" then
            sdk.hook(m, function(args)
                if not live.on then return end
                pcall(function()
                    local go = held_sword_go()
                    local mgr = sdk.to_managed_object(args[2])
                    if not go or mgr:call("get_GameObject"):get_address() ~= go:get_address() then return end
                    local id = sdk.to_managed_object(args[3])
                    sword_fx_row({ what = "effect", id = ("%s/%s/%s"):format(id.DataContainerIndex, id.ContainerID, id.ElementID),
                                   ours = noxStarting == true })
                    if noxStarting ~= true then thread.get_hook_storage().pbKillSword = true end
                end)
            end, function(r)
                local st5 = thread.get_hook_storage()
                if st5.pbKillSword then
                    st5.pbKillSword = nil
                    pcall(function() local c = sdk.to_managed_object(r); if c then c:call("killAll"); dbg.swordFxKilled = (dbg.swordFxKilled or 0) + 1 end end)
                end
                return r
            end)
        end
    end
end)
for _, tname in ipairs({ "app.MaterialInterpolation", "app.MaterialInterpolationEnchant" }) do pcall(function()
    local td = sdk.find_type_definition(tname)
    for _, m in ipairs(td:get_methods()) do
        if m:get_name() == "requestMaterialModeSub" or m:get_name() == "requestMaterialMode" then
            sdk.hook(m, function(args)
                if not live.on or not dbg.noxGlowMode then return end   -- (3.03: game glow requests left alone)
                pcall(function()
                    local go = held_sword_go()
                    local mi = sdk.to_managed_object(args[2])
                    if not go or mi:get_GameObject():get_address() ~= go:get_address() then return end
                    sword_fx_row({ what = "blade glow " .. m:get_name(), mode = sdk.to_int64(args[3]) & 0xFFFFFFFF,
                                   ours = noxStarting == true })
                    if noxStarting ~= true then thread.get_hook_storage().pbSkipGlow = true; noxGlowAgain = true end
                end)
                if thread.get_hook_storage().pbSkipGlow then
                    dbg.swordGlowBlocked = (dbg.swordGlowBlocked or 0) + 1
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end, function(r)
                local st6 = thread.get_hook_storage()
                if st6.pbSkipGlow then st6.pbSkipGlow = nil; return sdk.to_ptr(0) end
                return r
            end)
        end
    end
end) end

------------------------------------------------------------------------
-- damage: blast = Magick Bolt formula x 5 / 10; passive on everything else
------------------------------------------------------------------------
local function blast_of(attacker)
    if not attacker then return nil end
    local addr = attacker:get_address()
    for _, b in ipairs(blasts) do
        for _, p in ipairs(b.record.parts or {}) do
            local ok, hc = pcall(function() return p.shell["<HitCtrl>k__BackingField"] end)
            if ok and hc and hc:get_address() == addr then return b end
        end
    end
    return nil
end
-- Mystic Spearhand's own Forbeding Bolt fired by the charged animation: a shell owned by the player, not ours
local function is_bind_bolt(attacker)
    if not (cfg.bind and (lastKind == "charged" or lastKind == "burst") and os.clock() - lastFire < 6) or not attacker then return false end
    local yes = false
    pcall(function()
        local go = attacker:get_GameObject()
        if go:get_address() == live.go then return end
        local sh = go:call("getComponent(System.Type)", sdk.typeof("app.Shell"))
        local ow = sh and sh:get_field("<Owner>k__BackingField")
        yes = ow ~= nil and ow:get_address() == live.go
    end)
    return yes
end
local function blast_kind_of(attacker)
    local b = blast_of(attacker)
    if b then b.hitNow = true end
    return b and b.kind or nil
end

pcall(function()
    sdk.hook(sdk.find_type_definition("app.HitController"):get_method("calcDamageValue(app.HitController.DamageInfo)"),
        function(args)
            local s = thread.get_hook_storage()
            s.pbInfo, s.pbKind = nil, nil
            if not live.go then return end
            local info = sdk.to_managed_object(args[3])
            local owner = info and info["<AttackOwnerObject>k__BackingField"]
            if not owner or owner:get_address() ~= live.go then return end
            s.pbInfo = info
            if dbg.smite and dbg.smite.stage == 2 and dbg.smite_hit then
                pcall(function()
                    local hc = info:get_AttackHitController()
                    if hc and hc:get_GameObject():get_address() == live.go then dbg.smite_hit(info) end
                end)
            end
            local okK, kind = pcall(blast_kind_of, info:get_AttackHitController())
            s.pbKind = okK and kind or nil

            if not s.pbKind and is_bind_bolt(info:get_AttackHitController()) then s.pbKind = "bind" end
            if combo.stage == 4 and not combo.finalHit then combo.finalHit = true; note("final strike hit") end
            if combo.stage == 1 and not combo.target then
                pcall(function()
                    local v = info["<DamageGameObject>k__BackingField"]
                    local ch = v and v:call("getComponent(System.Type)", sdk.typeof("app.Character"))
                    if ch then combo.target = ch:add_ref(); note("combo target: " .. tostring(v:get_Name())) end
                end)
            end
            if s.pbKind == "burst" then
                s.pbOutside = false
                pcall(function()
                    local b = BLAST.burst
                    local tr = owner:get_Transform()
                    local victim = info["<DamageGameObject>k__BackingField"]
                    local d = victim:get_Transform():get_Position() - tr:get_Position()
                    d.y = 0
                    local dist = d:length()
                    local fwd = require("DragonCore.game.mathx").rotate(Vector3f.new(0, 0, 1), tr:get_Rotation())
                    fwd.y = 0
                    local cosang = dist > 0.01 and (d:normalized():dot(fwd:normalized())) or 1
                    if dist > b.range or cosang < math.cos(math.rad(b.arc / 2)) then s.pbOutside = true end
                end)
            end
        end, function(r)
            local s = thread.get_hook_storage()
            local info, kind = s.pbInfo, s.pbKind
            s.pbInfo, s.pbKind = nil, nil
            local outside = s.pbOutside
            s.pbOutside = nil
            if not info then return r end
            pcall(function()
                local phys = (info.SlashDamage or 0) + (info.ShootDamage or 0)
                local mag = (info.MagicDamage or 0) + (info.EnchantDamage or 0)
                local before = info.Damage
                local data = info["<AttackUserData>k__BackingField"]
                local ELEMENTS = { [0] = "none", "Fire", "Ice", "Thunder", "Holy" }
                local el = data and data:get_field("_ElementType")
                local row = { kind = kind or "hit", before = before, phys = phys, mag = mag,
                              rate = data and data:get_field("ActionRate") or 0,
                              magic = tostring(info.IsMagicAttack), element = ELEMENTS[tonumber(el) or -1] or tostring(el) }
                pcall(function() row.element = row.element .. " | hit element " .. tostring(info:call("get_ElementType")) end)
                pcall(function() row.swordEl = ELEMENT_CHOICES[swordEl.pick][1] end)
                pcall(function()
                    row.attack = tostring(data:get_field("Name"))
                    row.stagger = info.DamageReaction                     -- stagger / knock power dealt
                    row.staggerBase, row.staggerAction = data:get_field("DmgReactionValue"), data:get_field("ActionDmgReactionValue")
                    row.staggerRate = data:get_field("DmgReactionRate")
                    row.reaction = tostring(info.DamageType) .. " / lv " .. tostring(info.DmgReactionLv)
                    row.reactionTypes = ("%s, lean %s, blown %s"):format(tostring(data:get_field("DamageType")),
                        tostring(data:get_field("DamageTypeLean")), tostring(data:get_field("DamageTypeBlown")))
                    row.pushBack = ("z %.2f, y %.2f"):format(info.HitBackZ or 0, info.HitBackY or 0)
                    row.staminaDamage = info.StaminaDamage
                end)
                row.enchant = info.EnchantDamage
                row.elemental = info.NonMagicElementDamage
                if kind == "bind" then
                    info.Damage = 1
                    row.kind = "Forbeding Bolt"
                    note("Forbeding Bolt hit")
                elseif kind == "burst" and outside then
                    info.Damage = 0
                    row.kind = "burst (outside the arc)"
                elseif kind and live.on and BLAST[kind].factor then
                    local base = mag > 0 and mag or (phys + mag)
                    info.Damage = base * (info.DamageRate or 1) * BLAST[kind].factor
                elseif live.on and phys + mag > 0 then
                    info.Damage = before * (phys * PHYS_BONUS + mag * MAG_BONUS) / (phys + mag)
                end
                if kind and live.on and BLAST[kind] and BLAST[kind].dmgMul then info.Damage = info.Damage * BLAST[kind].dmgMul end
                if dbg.hex_mul then info.Damage = info.Damage * dbg.hex_mul(info) end   -- (Hex: -10 % defence)
                row.after = info.Damage
                if is_dummy_hit(info) or is_dummy(info["<DamageGameObject>k__BackingField"]) then
                    row.kind = row.kind .. " (dummy)"
                end
                row.t = os.date("%H:%M:%S")
                table.insert(dbg.hits, row)
                while #dbg.hits > 5 do table.remove(dbg.hits, 1) end
                dbg.hitFile = dbg.hitFile or {}
                table.insert(dbg.hitFile, row)
                while #dbg.hitFile > 40 do table.remove(dbg.hitFile, 1) end
                dbg.save("Pactblade_hits.json", dbg.hitFile)
            end)
            return r
        end)
end)

------------------------------------------------------------------------
-- Nox look on the sword in hand (ported from Stalwart Nox 1.6): the Frost Boon's shimmer (effect 25) on the
-- sword's own effect manager, tinted purple, and the blade's enchant glow coloured through Enchant_Color1/2.
-- Started/stopped inside the game's update step (starting it at the end of the frame detached the body).
------------------------------------------------------------------------
local NOX = { shimmer = 25, tint = { 126 / 255, 0, 54 / 255, 1 }, bright = 1.3,
              glowMode = 2834278566, bladeColor = { 91 / 255, 26 / 255, 142 / 255, 1 },
              boosted = false, boostGlow = 2.5 }   -- (boost: Eldritch Smite's second part - the blade glow only)
dbg.NOX = NOX
local NOX_REQ = "requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)"
local GLOW_SUB = "requestMaterialModeSub(System.UInt32, System.Int32, System.Int32, System.Boolean, System.Boolean)"
local GLOW_FINISH = "finishMaterialMode(System.UInt32, System.Int32, System.Int32)"
local noxPlaying = nil     -- { addr, go, cont, glowComp }
local nox_start
noxStarting = false        -- global on purpose: read by the recorder defined later
noxGlowAgain = false       -- global: set by the recorder when it blocked a game glow request
-- 3.06: the blade glow without the glow MODE (it crashed weapon switches): the mode's only own value (dump 3.05, mode
-- 2834278566, material 2180083513) = float var hash 2797575560 0 -> 0.15, written directly with the colour
NOX.glowVar, NOX.glowRate = 2797575560, 0.15
NOX.GETF = "getMaterialFloat(System.UInt32, System.UInt32)"
NOX.SETF = "setMaterialFloat(System.UInt32, System.UInt32, System.Single)"
dbg.noxGlowMode = false    -- 3.03 crash test (3.02 crash in MaterialInterpolation 1.5 s after the sword's glow mode was
                           -- finished at setDirectAndDestroyOld): no enchant glow MODE on the sword, game glow requests
                           -- not blocked. Shimmer + blade colour stay. Menu: Nox look settings.
local function comp_of(go, t)
    local ok, c = pcall(function() return go:call("getComponent(System.Type)", sdk.typeof(t)) end)
    return ok and c or nil
end
local function held_sword()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local p = cm and cm["<ManualPlayer>k__BackingField"]
    if not p then return nil end
    local sword = dbg.right_weapon()   -- (not getWeapon: it throws inside the game during a vocation change)
    if not sword then return nil end
    local go = sword:get_GameObject()
    return sword, go, comp_of(go, "via.effect.script.ObjectEffectManager2")
end
-- user (crash after ~5 switches, every round): our shimmer plays on the sword OUTSIDE the game's enchant system, so
-- nobody stopped it when the game deleted the sword -> an effect left on a deleted parent (the EffectManager crash
-- rule). Now it is killed the moment the game starts changing / clearing a weapon slot of mine, while the sword is
-- still there (hooks below, after nox_stop).
local function nox_stop()
    if not noxPlaying then return end
    pcall(function() if noxPlaying.cont and not noxPlaying.cont:call("get_isFinished") then noxPlaying.cont:call("finishAll()") end end)
    pcall(function() if noxPlaying.glowComp then noxPlaying.glowComp:call(GLOW_FINISH, NOX.glowMode, -1, -1) end end)
    noxPlaying = nil
end
-- 3.04: what the blade glow mode (NOX.glowMode) sets, read from the sword's MaterialInterpolationEnchant by FIELDS only
-- (ModeDataList -> _ModeList -> the mode whose _ModeValue = glowMode -> _MaterialList -> variables) -> data/Pactblade_glow_mode.json
function dbg.glow_mode_dump(go)
    if dbg.glowDumped then return end
    local mi = comp_of(go, "app.MaterialInterpolationEnchant")
    if not mi then return end
    dbg.glowDumped = true
    local function val(v, depth)
        if depth > 6 or v == nil then return v == nil and nil or "..." end
        local tv = type(v)
        if tv == "number" or tv == "boolean" or tv == "string" then return v end
        if tv == "userdata" then
            local out = {}
            local ok = pcall(function()
                local td = v:get_type_definition()
                out._type = td:get_full_name()
                if out._type:find("List`1") then
                    out.items = {}
                    for k = 0, math.min(v:get_field("_size") - 1, 40) do out.items[#out.items + 1] = val(v:get_field("_items")[k], depth + 1) end
                    return
                end
                if out._type == "System.String" then out = v:ToString(); return end
                while td and td:get_full_name() ~= "System.Object" do
                    for _, f in ipairs(td:get_fields()) do
                        if not f:is_static() then
                            local okf, fv = pcall(f.get_data, f, v)
                            if okf then
                                if type(fv) == "userdata" and fv.x ~= nil then out[f:get_name()] = { fv.x, fv.y, fv.z, fv.w }
                                else out[f:get_name()] = val(fv, depth + 1) end
                            end
                        end
                    end
                    td = td:get_parent_type()
                end
            end)
            if not ok then return "?" end
            return out
        end
        return tostring(v)
    end
    local out = { want = NOX.glowMode, modes = {} }
    local function scan(mdl, where)   -- a List<ModeData>
        pcall(function()
            for a = 0, mdl:get_field("_size") - 1 do
                local ml = mdl:get_field("_items")[a]:get_field("_ModeList")
                for b = 0, ml:get_field("_size") - 1 do
                    local mode = ml:get_field("_items")[b]
                    local mv = mode:get_field("_ModeValue")
                    out.modes[#out.modes + 1] = where .. ":" .. tostring(mv)
                    if mv == NOX.glowMode and not out.mode then out.mode = val(mode, 0); out.from = where end
                end
            end
        end)
    end
    scan(mi:get_field("ModeDataList"), "own")
    for _, lf in ipairs({ "UserDatas", "AddDatas" }) do   -- (the modes come from the game's data files)
        pcall(function()
            local l = mi:get_field(lf)
            for k = 0, l:get_field("_size") - 1 do
                local ud = l:get_field("_items")[k]
                scan(ud:get_field("_ModeDataList"), lf .. k)
            end
        end)
    end
    pcall(function() out.default = val(mi:get_field("_DefaultModeData"), 0) end)
    pcall(json.dump_file, "Pactblade_glow_mode.json", out)
    note(("blade glow mode read: %d modes, ours %s"):format(#out.modes, out.mode and "found" or "NOT found"))
end
function nox_start(go, mgr)
    pcall(dbg.glow_mode_dump, go)
    noxStarting = true
    local cont
    pcall(function()
        local eid = sdk.create_instance("via.effect.script.EffectID")
        eid.DataContainerIndex = -1; eid.ContainerID = 0; eid.ElementID = NOX.shimmer
        eid.IsContainerIDOnly = false; eid.IsElementIDOnly = false
        local c = mgr:call(NOX_REQ, eid, go, -1, nil)
        if c then cont = c:add_ref() end
    end)
    local glowComp
    local mi = comp_of(go, "app.MaterialInterpolationEnchant")
    if dbg.noxGlowMode and mi and pcall(function() mi:call(GLOW_SUB, NOX.glowMode, -1, -1, false, false) end) then glowComp = mi:add_ref() end
    noxPlaying = { addr = go:get_address(), go = go, cont = cont, glowComp = glowComp, orig = {} }
    noxStarting = false
end
;(function()   -- the weapon slots of mine: before any change / clear, our sword look goes (killAll: gone this frame)
    local function my_slot(slot)
        local mine = false
        pcall(function()
            local p = sdk.get_managed_singleton("app.CharacterManager")["<ManualPlayer>k__BackingField"]
            local h = p:get_WeaponAndItemHolder()
            local addr = slot:get_address()
            for _, g in ipairs({ "get_RightWeapon", "get_LeftWeapon" }) do
                local sl = h:call(g)
                if sl and sl:get_address() == addr then mine = true end
            end
        end)
        return mine
    end
    local function before_change(why)
        dbg.noxHoldUntil = os.clock() + 1.0
        if not noxPlaying then return end
        pcall(function() if noxPlaying.cont then noxPlaying.cont:call("killAll") end end)
        pcall(function() if noxPlaying.glowComp then noxPlaying.glowComp:call(GLOW_FINISH, NOX.glowMode, -1, -1) end end)
        noxPlaying = nil
        dbg.noxDropBlade = true
        dbg.noxStops = (dbg.noxStops or 0) + 1
        note("Nox look stopped before the weapon change (" .. why .. ")")
    end
    local WANT = { clear = true, release = true, equipPrepared = true, createWeapon = true, requestEquipWeapon = true,
                   prepareWeapon = true, changeWeapon = true, setDirectAndDestroyOld = true, onStartPreparing = true,
                   cancelPreparing = true }
    local n = 0
    for _, tn in ipairs({ "app.WeaponAndItemHolder.Slot", "app.WeaponAndItemHolder.WeaponSlot" }) do
        local td = sdk.find_type_definition(tn)
        for _, m in ipairs(td and td:get_methods() or {}) do
            local name = m:get_name()
            if WANT[name] then
                local ok = pcall(sdk.hook, m, function(args)
                    pcall(function()
                        if noxPlaying == nil and os.clock() < (dbg.noxHoldUntil or 0) then return end
                        if my_slot(sdk.to_managed_object(args[2])) then before_change(name) end
                    end)
                end, function(r) return r end)
                if ok then n = n + 1 end
            end
        end
    end
    dbg.noxSlotHooks = n
end)()
local colorType = sdk.find_type_definition("via.Color")
local function make_color(r, g, b, a)
    local c = ValueType.new(colorType)
    c:call(".ctor(via.vec4)", Vector4f.new(r, g, b, a))
    return c
end
-- the boost (Eldritch Smite's second part): the blade glow gets brighter (user: the mist stays as it is)
function dbg.nox_boost(on) NOX.boosted = on end
-- which Nox look shows: the smite's (user's sliders for the skill) while it boosts, else the everyday one
if not cfg.noxSmite then   -- (once: the values set so far were meant for the skill; everyday goes back to the defaults)
    cfg.noxSmite = { bladeR = cfg.noxBladeR, bladeG = cfg.noxBladeG, bladeB = cfg.noxBladeB, bladeBright = cfg.noxBladeBright,
                     mistR = cfg.noxMistR, mistG = cfg.noxMistG, mistB = cfg.noxMistB, mistBright = cfg.noxMistBright }
    cfg.noxBladeR, cfg.noxBladeG, cfg.noxBladeB, cfg.noxBladeBright = 91, 26, 142, 1.0
    cfg.noxMistR, cfg.noxMistG, cfg.noxMistB, cfg.noxMistBright = 126, 0, 54, 1.3
    pcall(save_cfg)
end
function dbg.nox_look()
    local t = NOX.boosted and cfg.noxSmite
    if t then return t.bladeR, t.bladeG, t.bladeB, t.bladeBright, t.mistR, t.mistG, t.mistB, t.mistBright end
    return cfg.noxBladeR, cfg.noxBladeG, cfg.noxBladeB, cfg.noxBladeBright, cfg.noxMistR, cfg.noxMistG, cfg.noxMistB, cfg.noxMistBright
end
local function nox_tint()
    local np = noxPlaying
    if not np or not np.cont then return end
    for _, cont in ipairs({ np.cont }) do pcall(function()
        local entries = cont.CreatedEffects._entries
        for i = 0, entries:get_size() - 1 do
            local list = entries[i] and entries[i].value
            if list then
                for j = 0, list._size - 1 do
                    local effect = list._items[j]
                    if effect and effect:get_Valid() then
                        local key = tostring(effect:get_address())
                        pcall(function()
                            if not np.orig[key] then
                                local c = effect:get_Color()
                                np.orig[key] = { c:call("get_r"), c:call("get_g"), c:call("get_b"), c:call("get_a") }
                            end
                            local o = np.orig[key]
                            if o[4] == 0 or (o[1] + o[2] + o[3]) == 0 then return end
                            local _, _, _, _, mr, mg, mb, mbr = dbg.nox_look()
                            local mist = { mr / 255, mg / 255, mb / 255 }
                            local function ch(k) return math.min(1, (o[k] / 255) * mist[k] * mbr) end
                            effect:set_Color(make_color(ch(1), ch(2), ch(3), o[4] / 255))
                        end)
                    end
                end
            end
        end
    end) end
end
re.on_pre_application_entry("UpdateBehavior", function()
    pcall(function()
        local sword, go, mgr = held_sword()
        dbg.heldAddr = go and go:get_address() or nil   -- (user: crash after ~5 weapon switches - only THIS sword is touched)
        local want = cfg.nox and live.on and sword ~= nil and mgr ~= nil and sword:get_IsDrawed()
        if not want then
            if noxPlaying and noxPlaying.addr ~= dbg.heldAddr then   -- its sword is gone (switch): forgotten, not touched
                noxPlaying = nil
                dbg.noxDropBlade = true
            else nox_stop() end   -- (the same sword, sheathed / Nox off: put back properly)
            return
        end
        if noxPlaying and noxPlaying.addr ~= go:get_address() then
            noxPlaying = nil   -- (the old sword may be gone already: nothing of it is touched - the game cleans up)
            dbg.noxDropBlade = true
        end
        if dbg.noxSword ~= go:get_address() then dbg.noxSword, dbg.noxSwordT = go:get_address(), os.clock() end
        if not noxPlaying and os.clock() - (dbg.noxSwordT or 0) >= 1.5 and os.clock() >= (dbg.noxHoldUntil or 0) then nox_start(go, mgr) end   -- (a new sword settles first)
        -- the game tried to put its element glow on the blade (blocked): set the Nox glow again so it stays the last one
        if noxGlowAgain and noxPlaying and noxPlaying.glowComp then
            noxGlowAgain = false
            noxStarting = true
            pcall(function() noxPlaying.glowComp:call(GLOW_SUB, NOX.glowMode, -1, -1, false, false) end)
            noxStarting = false
            dbg.noxGlowAgain = (dbg.noxGlowAgain or 0) + 1
        end
        nox_tint()
    end)
end)
-- blade glow colour: Enchant_Color1 (main) / Enchant_Color2 (lighter highlight), written right before rendering;
-- kept for 2 s after sheathing while the glow fades, then the material's own colours come back
local nameHash = sdk.find_type_definition("app.StringExtension"):get_method("hash(System.String)")
local SET4 = "setMaterialFloat4(System.UInt32, System.UInt32, via.Float4)"
local blade, fadeUntil = nil, 0
local function blade_restore()
    if not blade then return end
    pcall(function()
        for _, e in ipairs(blade.entries) do
            if e.float then blade.mesh:call(NOX.SETF, e.m, e.v, e.orig)
            else blade.mesh:call(SET4, e.m, e.v, Vector4f.new(e.orig[1], e.orig[2], e.orig[3], e.orig[4])) end
        end
    end)
    blade = nil
end
re.on_pre_application_entry("BeginRendering", function()
    if dbg.noxDropBlade then dbg.noxDropBlade = nil; blade = nil end   -- (sword changed: the old blade is not restored)
    if blade and blade.addr ~= dbg.heldAddr then blade = nil end   -- (its sword left my hand: never touched again)
    local active = noxPlaying ~= nil and (noxPlaying.glowComp ~= nil or not dbg.noxGlowMode) and noxPlaying.addr == dbg.heldAddr
    if active then fadeUntil = os.clock() + 2.0 end
    if not active and os.clock() > fadeUntil then blade_restore(); return end
    pcall(function()
        local mesh = active and comp_of(noxPlaying.go, "via.render.Mesh") or (blade and blade.mesh)
        if not mesh then return end
        if not blade or blade.mesh ~= mesh then
            blade_restore()
            local entries = {}
            for m = 0, mesh:get_MaterialNum() - 1 do
                for _, name in ipairs({ "Enchant_Color1", "Enchant_Color2" }) do
                    pcall(function()
                        local v = mesh:getMaterialVariableIndex(m, nameHash:call(nil, name))
                        if v == nil or v >= 65535 then return end   -- (this material has no such slot)
                        local f = mesh:getMaterialFloat4(m, v)
                        entries[#entries + 1] = { m = m, v = v, second = name == "Enchant_Color2", orig = { f.x, f.y, f.z, f.w } }
                    end)
                end
            end
            for m = 0, mesh:get_MaterialNum() - 1 do   -- (3.06) the glow mode's one value, set directly (no mode)
                pcall(function()
                    local v = mesh:getMaterialVariableIndex(m, NOX.glowVar)
                    if v == nil or v >= 65535 then return end
                    local f = mesh:call(NOX.GETF, m, v)
                    entries[#entries + 1] = { m = m, v = v, float = true, orig = f }
                end)
            end
            blade = { mesh = mesh:add_ref(), entries = entries, addr = noxPlaying.addr }
        end
        local br, bg, bb, bbr = dbg.nox_look()   -- (everyday, or the smite's look while it boosts)
        local c = { br / 255, bg / 255, bb / 255, 1 }
        local k = (NOX.boosted and NOX.boostGlow or 1) * bbr   -- (Eldritch Smite: brighter)
        for _, e in ipairs(blade.entries) do
            if e.float then mesh:call(NOX.SETF, e.m, e.v, NOX.glowRate)
            else
                local r, g, b = c[1] * k, c[2] * k, c[3] * k
                if e.second then r, g, b = (c[1] + 1) / 2 * k, (c[2] + 1) / 2 * k, (c[3] + 1) / 2 * k end
                mesh:call(SET4, e.m, e.v, Vector4f.new(r, g, b, c[4]))
            end
        end
    end)
end)
re.on_script_reset(function() blade_restore(); pcall(nox_stop) end)

-- stagger (knockdown) power of each blast kind: BLAST[kind].stagger x the game's value (from calcDamageReaction)
pcall(function()
    sdk.hook(sdk.find_type_definition("app.HitController"):get_method("calcDamageReaction(app.HitController.DamageInfo)"),
        function(args)
            local s = thread.get_hook_storage()
            s.pbBurst = nil
            if not live.on or #blasts == 0 then return end
            pcall(function()
                local info = sdk.to_managed_object(args[3])
                local b = blast_of(info:get_AttackHitController())
                if b and BLAST[b.kind].stagger then s.pbBurst = info; s.pbStagger = BLAST[b.kind].stagger end
            end)
        end, function(r)
            local s = thread.get_hook_storage()
            local info = s.pbBurst
            s.pbBurst = nil
            if info then pcall(function() info.DamageReaction = info.DamageReaction * (s.pbStagger or 1) end) end
            return r
        end)
end)

-- Eldritch Burst only makes enemies flinch: a heavier reaction the game picks (knocked down, blown away, launched,
-- slammed, quake, heavy hitback) becomes Hitback_M (app.AttackUserData.DamageTypeEnum values)
local FLINCH = 6                                   -- Hitback_M
local HEAVIER = { [3] = true, [4] = true }         -- Quake_S / Quake_L
for v = 7, 19 do HEAVIER[v] = true end             -- Hitback_L .. Blown_L
HEAVIER[22] = true                                 -- FlashFlood
pcall(function()
    sdk.hook(sdk.find_type_definition("app.HitController"):get_method("getReactionDamageType(app.HitController.DamageInfo)"),
        function(args)
            local s2 = thread.get_hook_storage()
            s2.pbCap = nil
            if not live.on or #blasts == 0 then return end
            pcall(function()
                local info = sdk.to_managed_object(args[3])
                local b = blast_of(info:get_AttackHitController())
                if b and BLAST[b.kind].flinchOnly then s2.pbCap = info end
            end)
        end, function(r)
            local s2 = thread.get_hook_storage()
            local info = s2.pbCap
            s2.pbCap = nil
            if not info then return r end
            local v = sdk.to_int64(r) & 0xFFFFFFFF
            if not HEAVIER[v] then return r end
            pcall(function() info.DamageType, info.DamageActType, info.OverwriteBlownType = FLINCH, FLINCH, FLINCH end)
            dbg.capped = (dbg.capped or 0) + 1
            return sdk.to_ptr(FLINCH)
        end)
end)

------------------------------------------------------------------------
-- menu
------------------------------------------------------------------------
;(function()   -- Archfey Combo + warp wisps: its own function, so its locals don't count against the main chunk's 200
------------------------------------------------------------------------
-- Archfey Combo (user's name): Cloudfall Strike's slot plays this while Pactblade is active (user's design):
--   Job02_StartFlightShot 0-71.6 -> warp to the target's left or right side -> Job01_RushAttack 34-67 -> warp
--   behind it -> Job01_RushAttackFinish 25-54 -> warp in front of it above its head -> Job01_EndRisingLunge to its
--   end (the game's landing follows). Target = the first enemy the opening hits; no hit = it ends after the opening.
--   Each warp: Blink Behind's cues (Skydragon's Fangtooth takeoff here, its arrival there).
------------------------------------------------------------------------
local COMBO = {
    { action = "Job02_StartFlightShot", from = 0.0, to = 71.6 },
    { action = "Job01_RushAttack", from = 34.0, to = 67.0, warp = "side" },
    { action = "Job01_RushAttackFinish", from = 25.0, to = 54.0, warp = "behind" },
    { action = "Job01_EndRisingLunge", from = 0.0, warp = "head" },
}
local COMBO_STAMINA = 250
local WARP_GAP = 1.2         -- metres between the target's body and us
local HEAD_ABOVE = 0.4       -- metres above the target's head for the falling strike
local HEAD_GAP = 0.6         -- ... and this close in front of its body
local CUES = {
    -- Quik Fot (recorded: takeoff 13/22/0 + 13/22/3 and its whoosh; arrival 13/23/1, 13/22/15, 13/22/10)
    quikfot = { depart_efx = { { 13, 22, 0 }, { 13, 22, 3 } }, depart_snd = { 1781269347 },   -- (4087819823, 4052369681 loop)
                arrive_efx = { { 13, 23, 1 }, { 13, 22, 15 }, { 13, 22, 10 } }, arrive_snd = { 1863385021 } },   -- (1840818767 loops)
    -- Blink Behind (Skydragon's Fangtooth takeoff / arrival)
    blink = { depart_efx = { { 14, 7, 10 } }, depart_snd = { 1717783091 },
              arrive_efx = { { 14, 7, 11 }, { 13, 0, 10 } }, arrive_snd = { 2823464530 } },
}
local CUE_SECS = 1.0
local ourReq = false
local cueLive = {}

local function flat_dir(x, z)
    local len = math.sqrt(x * x + z * z)
    if len < 0.0001 then return nil end
    return x / len, z / len, len
end
local function forward_of(q) return 2 * (q.x * q.z + q.w * q.y), 1 - 2 * (q.x * q.x + q.y * q.y) end
local function yaw_rotation(dx, dz)
    local yaw = math.atan(dx, dz)
    return Quaternion.new(math.cos(yaw / 2), 0, math.sin(yaw / 2), 0)
end
local function is_alive(chara)
    if not chara then return false end
    local ok, valid = pcall(chara.get_Valid, chara)
    if not ok or not valid then return false end
    local okH, hp = pcall(function() return chara:get_Hit():get_Hp() end)
    if okH and type(hp) == "number" then return hp > 0 end
    return true
end
local function components_of(go, typeName)
    local found = {}
    local ok, comps = pcall(function() return go:call("get_Components") end)
    if not ok or not comps then return found end
    for _, c in ipairs(comps:get_elements()) do
        local td = c:get_type_definition()
        while td do
            if td:get_full_name() == typeName then found[#found + 1] = c; break end
            td = td:get_parent_type()
        end
    end
    return found
end

-- cues (Blink Behind's way): effects faded out with finishAll after CUE_SECS, sounds from the player's containers
local function cue_efx(a, ids, pos, rot)
    for _, mgr in ipairs(components_of(a.character:get_GameObject(), "via.effect.script.ObjectEffectManager2")) do
        combo.cueing = true
        local ok, res = pcall(function()
            local id = sdk.create_instance("via.effect.script.EffectID")
            id.DataContainerIndex, id.ContainerID, id.ElementID = ids[1], ids[2], ids[3]
            id.IsContainerIDOnly, id.IsElementIDOnly = false, false
            return mgr:call("requestEffect(via.effect.script.EffectID, via.vec3, via.Quaternion, via.GameObject, System.String, via.effect.script.EffectManager.WwiseTriggerInfo)",
                id, pos, rot, nil, "root", nil)
        end)
        combo.cueing = false
        if ok and res then
            pcall(function()
                local c = res:add_ref()
                cueLive[#cueLive + 1] = { c = c, untilT = os.clock() + CUE_SECS }
                local idstr = ("%d/%d/%d"):format(ids[1], ids[2], ids[3])
                if cfg.blastTint and not cfg.noTint[idstr] and not tintSeen[c:get_address()] then
                    tintSeen[c:get_address()] = true
                    tint_note(idstr, "warp cue")
                    table.insert(tints, { c = c, born = os.clock(), addr = c:get_address(), id = idstr })
                end
            end)
            return true
        end
    end
    return false
end
local function cue_sound(a, triggerId)
    local go = a.character:get_GameObject()
    for _, sc in ipairs(components_of(go, "soundlib.SoundContainer")) do
        local ok, done = pcall(function()
            for _, info in pairs(sc._TriggerInfoList._items) do
                if info and info._TriggerId == triggerId then
                    local req = sc:call("createRequestInfo(soundlib.SoundTriggerInfo, via.GameObject, via.GameObject, System.UInt32, System.Boolean, System.Boolean, System.UInt32, via.simplewwise.CallbackType, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>)",
                        info, go, go, info._OffsetJointHash, false, false, 0, 0, nil, nil, nil, nil)
                    if req then
                        req = req:add_ref()
                        req["<Container>k__BackingField"] = sc
                        sc:call("trigger(soundlib.SoundManager.RequestInfo)", req)
                        return true
                    end
                end
            end
            return false
        end)
        if ok and done then return true end
    end
    return false
end
combo.cue_sound = cue_sound   -- (the cast test, outside this function, plays sounds with it)
-- a looping sound started with cue_sound stops only when told: SoundContainer.stopTriggered(id, object, fade ms)
function combo.stop_sound(a, triggerId, fadeMs)
    local go = a.character:get_GameObject()
    for _, sc in ipairs(components_of(go, "soundlib.SoundContainer")) do
        pcall(function() sc:call("stopTriggered(System.UInt32, via.GameObject, System.UInt32)", triggerId, go, fadeMs or 300) end)
    end
end
local function cues(a, efx, snd, pos, rot)
    for _, ids in ipairs(efx) do cue_efx(a, ids, pos, rot) end
    if dbg.noWarpSounds then return end
    combo.cueingSnd = true
    for _, id in ipairs(snd) do cue_sound(a, id) end
    combo.cueingSnd = false
end
re.on_frame(function()
    if #cueLive == 0 then return end
    local now = os.clock()
    for i = #cueLive, 1, -1 do
        if now >= cueLive[i].untilT then
            local c = cueLive[i].c
            for _, m in ipairs({ "finishAll", "finish", "killAll", "kill" }) do
                if pcall(function() c:call(m .. "()") end) then break end
            end
            table.remove(cueLive, i)
        end
    end
end)

-- terrain checks with _SharedCore's raycast (Blink Behind), when installed
local castOk, shared = pcall(require, "_SharedCore/Functions")
local cast_ray = castOk and type(shared) == "table" and shared.cast_ray or nil
local function nearest_hit(from, to, radius)
    if not cast_ray then return nil end
    local ok, best, bestD = pcall(function()
        local best, bestD
        for _, r in ipairs(cast_ray(from, to, 2, 0, radius or 0.05, 0) or {}) do
            local p = r[2]
            if p then
                p = Vector3f.new(p.x, p.y, p.z)
                local dx, dy, dz = p.x - from.x, p.y - from.y, p.z - from.z
                local d = dx * dx + dy * dy + dz * dz
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
        return best, bestD
    end)
    if not ok or not best then return nil end
    return best, math.sqrt(bestD)
end

local function face(a, dx, dz)
    pcall(function()
        local tac = a.character["<TargetAngleCtrl>k__BackingField"]
        local deg = math.deg(math.atan(dx, dz))
        tac.Front["<AngleDeg>k__BackingField"] = deg
        tac.Move["<AngleDeg>k__BackingField"] = deg
    end)
end

-- the spot next to the target for this part; nil + why when there is none
local function warp_spot(a, how, forced)
    local t = combo.target
    local tTr = t:get_GameObject():get_Transform()
    local tPos = tTr:get_Position()
    local pPos = a.character:get_GameObject():get_Transform():get_Position()
    local fx, fz = flat_dir(forward_of(tTr:get_Rotation()))
    if not fx then fx, fz = flat_dir(pPos.x - tPos.x, pPos.z - tPos.z) end
    if not fx then fx, fz = 0, 1 end
    local radius = 0.5
    pcall(function()
        local r = t["<CharaController>k__BackingField"]:call("get_Radius")
        if type(r) == "number" and r > 0 and r < 10 then radius = r end
    end)
    local dirs
    if forced then dirs = forced
    elseif how == "side" then
        local sgn = math.random() < 0.5 and 1 or -1
        dirs = { { fz * sgn, -fx * sgn }, { -fz * sgn, fx * sgn } }   -- one side, else the other
    elseif how == "behind" then dirs = { { -fx, -fz } }
    else dirs = { { fx, fz } } end
    local want = radius + (how == "head" and HEAD_GAP or WARP_GAP)
    local chest = Vector3f.new(tPos.x, tPos.y + 1.0, tPos.z)
    for _, d in ipairs(dirs) do
        local dist = want
        local _, hitD = nearest_hit(chest, Vector3f.new(chest.x + d[1] * want, chest.y, chest.z + d[2] * want), 0.4)
        if hitD then dist = hitD - 0.5 end
        if dist >= radius + 0.3 then
            local dest = Vector3f.new(tPos.x + d[1] * dist, tPos.y, tPos.z + d[2] * dist)
            if how == "head" then
                local headY = tPos.y + 1.7
                pcall(function()
                    for _, jn in ipairs({ "Head", "head", "Neck", "neck" }) do
                        local j = tTr:getJointByName(jn)
                        if j then headY = j:get_Position().y; return end
                    end
                end)
                dest.y = headY + cfg.finisherHeight   -- (was HEAD_ABOVE 0.4)
            else
                local g = nearest_hit(Vector3f.new(dest.x, tPos.y + 1.8, dest.z), Vector3f.new(dest.x, tPos.y - 3.0, dest.z), 0.05)
                if g and math.abs(g.y - tPos.y) < 2.5 then dest.y = g.y end
            end
            return dest, yaw_rotation(tPos.x - dest.x, tPos.z - dest.z), (tPos.x - dest.x), (tPos.z - dest.z), d.name
        end
    end
    return nil, "wall next to the target"
end

local hiddenMeshes = {}
local function meshes_of(go, out)
    for _, m in ipairs(components_of(go, "via.render.Mesh")) do out[#out + 1] = m end
    pcall(function()
        local c = go:get_Transform():call("get_Child")
        while c do
            meshes_of(c:get_GameObject(), out)
            c = c:call("get_Next")
        end
    end)
    return out
end
local function sword_shown(on)
    if on then
        for _, m in ipairs(hiddenMeshes) do pcall(function() m:call("set_Enabled", true) end) end
        hiddenMeshes = {}
        return
    end
    pcall(function()
        local go = held_sword_go()
        if not go then return end
        for _, m in ipairs(meshes_of(go, {})) do
            local en = true
            pcall(function() en = m:call("get_Enabled") end)
            if en then
                m:call("set_Enabled", false)
                local known = false
                for _, h in ipairs(hiddenMeshes) do if h == m then known = true end end
                if not known then hiddenMeshes[#hiddenMeshes + 1] = m:add_ref() end
            end
        end
    end)
end
local function combo_end(why)
    if combo.stage ~= 0 then
        combo.endT = os.clock()
        if combo.stage == 4 then
            combo.result = { text = combo.finalHit and "Archfey Combo: final strike HIT" or "Archfey Combo: final strike MISSED",
                             ok = combo.finalHit == true, t = os.clock() }
        else
            combo.result = { text = ("Archfey Combo stopped in part %d: %s"):format(combo.stage, tostring(why)), ok = false, t = os.clock() }
        end
    end
    if combo.stage == 4 and not combo.finalHit then note("final strike MISSED") end
    if combo.stage ~= 0 then note("combo ended: " .. why) end
    if combo.swordHidden then combo.swordWait = os.clock() end   -- shown again once the Archer animation is over
    combo.stage, combo.target, combo.reapply, combo.stick = 0, nil, nil, nil
end
local function combo_request(a, name)
    ourReq = true
    local ok = a:request_action(name, 0)
    ourReq = false
    return ok
end
local function motion_key(L)
    return L:call("get_MotionBankID") * 100000 + L:call("get_MotionID")
end
-- the enemy's four sides (unit directions from it), and the one we are on now
local SIDE_OPP = { front = "back", back = "front", left = "right", right = "left" }
local function enemy_sides(a)
    local tTr = combo.target:get_GameObject():get_Transform()
    local tPos = tTr:get_Position()
    local pPos = a.character:get_GameObject():get_Transform():get_Position()
    local fx, fz = flat_dir(forward_of(tTr:get_Rotation()))
    if not fx then fx, fz = 0, 1 end
    local sides = { front = { fx, fz }, back = { -fx, -fz }, right = { fz, -fx }, left = { -fz, fx } }
    local cur, best = "front", -2
    local dx, dz = flat_dir(pPos.x - tPos.x, pPos.z - tPos.z)
    if dx then
        for name, d in pairs(sides) do
            local dot = d[1] * dx + d[2] * dz
            if dot > best then cur, best = name, dot end
        end
    end
    return sides, cur
end
-- nk = the part about to start (2 / 3 / 4): which sides to try, in order
local function dynamic_spot(a, nk)
    local sides, cur = enemy_sides(a)
    combo.used = combo.used or {}
    local order = {}
    if nk == 2 then
        combo.used = { [cur] = true }
        order[1] = SIDE_OPP[cur]
        local perp = (cur == "front" or cur == "back") and { "left", "right" } or { "front", "back" }
        if math.random() < 0.5 then perp[1], perp[2] = perp[2], perp[1] end
        order[2], order[3] = perp[1], perp[2]
    elseif nk == 3 then
        local free = {}
        for _, n in ipairs({ "back", "front", "left", "right" }) do if not combo.used[n] then free[#free + 1] = n end end
        if free[1] ~= "back" and #free >= 2 and math.random() < 0.5 then free[1], free[2] = free[2], free[1] end
        order = free
    else
        for _, n in ipairs({ "back", "front", "left", "right" }) do if not combo.used[n] then order[#order + 1] = n end end
        for _, n in ipairs({ "back", "front", "left", "right" }) do if combo.used[n] and n ~= cur then order[#order + 1] = n end end
    end
    local forced = {}
    for _, n in ipairs(order) do forced[#forced + 1] = { sides[n][1], sides[n][2], name = n } end
    local dest, rot, dx, dz, name = warp_spot(a, nk == 4 and "head" or "side", forced)
    if dest then
        combo.used[name] = true
        note(("warp to part %d: from the enemy's %s to its %s"):format(nk, cur, name))
    end
    return dest, rot, dx, dz
end
local function combo_stage(a, k)
    local part = COMBO[k]
    combo.stage, combo.asked, combo.started, combo.framed = k, os.clock(), nil, false
    if k == 4 then combo.stick, combo.finalHit = nil, false end
    if part.action:find("^Job02_") then sword_shown(false); combo.swordHidden = true; combo.swordWait = nil
    elseif combo.swordHidden then sword_shown(true); combo.swordHidden = false end
    pcall(function() combo.prevMot = motion_key(a.character.FullBodyLayer) end)
    combo_request(a, part.action)
    note(("combo %d: %s (frames %.1f-%s)"):format(k, part.action, part.from, part.to and ("%.1f"):format(part.to) or "end"))
end

local function combo_update(a)
    local now = os.clock()
    if combo.want then
        combo.want = false
        if combo.stage == 0 then
            combo.target = nil
            combo.t0 = now
            comboFx.seen, comboFx.list = {}, {}
            pcall(a.consume_stamina, a, COMBO_STAMINA)
            combo.aim, combo.aimT, combo.used = nil, now, nil
            if cfg.comboTurn and combo.pick_target then
                local ok, t, d = pcall(combo.pick_target, a, cfg.comboTurnRange, cfg.comboTurnCone)
                if ok and t then combo.aim = t:add_ref(); note(("Archfey Combo: turning to an enemy %.1f m away"):format(d)) end
            end
            combo_stage(a, 1)
        end
    end
    if combo.swordWait then
        local cur0 = tostring(a:current_action(0) or "")
        -- user: 1.5 s after the combo stops (the sword takes that long to fly back into the hand)
        local waited = now - combo.swordWait
        if waited >= 1.5 then   -- user: 1.5 s, no waiting for the Archer animation
            sword_shown(true)
            combo.swordHidden, combo.swordWait = false, nil
        else sword_shown(false) end
    end
    if combo.stage == 0 then return end
    local tr = a.character:get_GameObject():get_Transform()
    if combo.reapply then   -- the character controller can put us back for a frame or two after a warp
        tr:set_Position(combo.reapply.dest)
        tr:set_Rotation(combo.reapply.rot)
        face(a, combo.reapply.dx, combo.reapply.dz)
        combo.reapply.n = combo.reapply.n - 1
        if combo.reapply.n <= 0 then combo.reapply = nil end
    end
    if combo.swordHidden then sword_shown(false) end
    if combo.stage == 1 and combo.aim and not combo.target and combo.turn_to then   -- the opening: toward the enemy
        local dt = math.min(now - (combo.aimT or now), 0.1)
        combo.aimT = now
        pcall(combo.turn_to, a, combo.aim, dt, cfg.comboTurnSpeed)
    end
    if combo.target and not combo.reapply and (combo.stage == 1 or (combo.stage == 4 and not combo.finalHit)) then
        pcall(function()
            local t = combo.target:get_GameObject():get_Transform():get_Position()
            local p = tr:get_Position()
            if not combo.stick then
                combo.stick = { x = p.x - t.x, z = p.z - t.z }
                note(("part %d: staying %.1f m from the target"):format(combo.stage, math.sqrt(combo.stick.x ^ 2 + combo.stick.z ^ 2)))
            end
            tr:set_Position(Vector3f.new(t.x + combo.stick.x, p.y, t.z + combo.stick.z))
            local dx, dz = -combo.stick.x, -combo.stick.z
            if dx * dx + dz * dz > 0.0001 then
                tr:set_Rotation(yaw_rotation(dx, dz))
                face(a, dx, dz)
            end
        end)
    end
    local part = COMBO[combo.stage]
    local cur = a:current_action(0)
    if not combo.started then
        if cur == part.action then combo.started = now
        elseif now - combo.asked > 0.4 then return combo_end(part.action .. " did not start (now " .. tostring(cur) .. ")")
        else combo_request(a, part.action); return end
    end
    if cur ~= part.action then
        if not part.to then return combo_end("done") end
        return combo_end("interrupted by " .. tostring(cur))
    end
    local L = a.character.FullBodyLayer
    if motion_key(L) == combo.prevMot and now - combo.started < 0.25 then return end   -- not on the new animation yet
    local fr = L:call("get_Frame")
    if not combo.framed then
        combo.framed = true
        if part.from > 0 and fr < part.from then L:call("set_Frame", part.from); return end
    end
    if part.to and fr >= part.to then
        if combo.stage == 1 and not combo.target then
            pcall(function() combo_request(a, a:is_grounded() == false and "WaitToFall" or "NormalLocomotion") end)
            return combo_end("the opening hit nothing")
        end
        if not is_alive(combo.target) then return combo_end("target gone") end
        local nk = combo.stage + 1
        local dest, rot, dx, dz
        if cfg.comboDynamic then dest, rot, dx, dz = dynamic_spot(a, nk)
        else dest, rot, dx, dz = warp_spot(a, COMBO[nk].warp) end
        if not dest then return combo_end("no spot: " .. tostring(rot)) end
        local useWisps = cfg.warpFx == "wisps" and not dbg.comboNoWisps
        local CUE = CUES[cfg.warpFx] or CUES.quikfot
        if useWisps then
            CUE = CUES.quikfot
            local ok, err = pcall(wisps.burst, a, false)
            if not ok then note("warp wisps: " .. tostring(err)) end
        end
        if dbg.ai then pcall(dbg.ai.warp, a) end
        cues(a, useWisps and {} or CUE.depart_efx, CUE.depart_snd, tr:get_Position(), tr:get_Rotation())
        tr:set_Position(dest)
        tr:set_Rotation(rot)
        pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end)
        face(a, dx, dz)
        combo.reapply = { dest = dest, rot = rot, dx = dx, dz = dz, n = 2 }
        cues(a, useWisps and {} or CUE.arrive_efx, CUE.arrive_snd, dest, rot)
        if useWisps then pcall(wisps.burst, a, true) end
        combo_stage(a, nk)
    end
end
re.on_pre_application_entry("UpdateBehavior", function()
    if combo.stage == 0 and not combo.want and not combo.swordWait then return end
    local a = runtime.player()
    if not a or not a:valid() or not live.on then combo.want = false; combo_end("Pactblade off"); return end
    local ok, err = pcall(combo_update, a)
    if not ok then combo_end("error: " .. tostring(err)) end
end)

-- Cloudfall Strike (Job01_RisingLunge) pressed while Pactblade is active: the combo instead
local RISING_ID = 2
pcall(function()
    for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if f:is_static() and f:get_name() == "Job01_RisingLunge" then RISING_ID = f:get_data(nil) & 0xFFFFFFFF end
    end
end)
pcall(function()
    local SIG = "processCustomSkill(app.HumanCustomSkillID, System.UInt64, app.LockOnController.Option, System.Boolean, System.Boolean, System.Boolean, app.LocomotionSpeedTypeEnum, System.Boolean)"
    sdk.hook(sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method(SIG), function(args)
        if not live.on then return end
        local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
        if id ~= RISING_ID then return end
        local now = os.clock()
        if combo.stage == 0 and now - combo.lastPress > 0.6 then
            local can = false
            pcall(function()
                local track = runtime.player().character:get_Human().Track
                can = track.All or track.Skill
            end)
            if can then
                combo.lastPress = now
                combo.want = true
                note("Cloudfall Strike pressed: Archfey Combo")
            end
        end
        return sdk.PreHookResult.SKIP_ORIGINAL   -- the vanilla skill never plays (also not queued for later)
    end, function(r) return r end)
end)
-- Misty Step = Quik Fot after the bind: its own leap effects are switched off (combo_dust) and the warp wisps play
-- where we leave and on us where we land (Quik Fot's sounds stay)
local misty = { started = nil }
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if not live.on or cfg.warpFx ~= "wisps" or (misty.started and os.clock() - misty.started < 1.0) then return end
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if name ~= "Job07_MagicBindJustLeap" then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                misty.started, misty.seen, misty.done = os.clock(), false, false
                combo.mistyUntil = os.clock() + 2.0
                local a = runtime.player()
                if a then pcall(wisps.burst, a, false) end
                if a and dbg.ai then pcall(dbg.ai.warp, a) end
                note("Misty Step: wisps")
            end)
        end, function(r) return r end)
end)
re.on_pre_application_entry("UpdateBehavior", function()
    if not misty.started or misty.done then return end
    local a = runtime.player()
    if not a or not a:valid() then misty.done = true; return end
    local cur = a:current_action(0)
    if cur == "Job07_MagicBindJustLeap" then misty.seen = true; return end
    if misty.seen or os.clock() - misty.started > 2.0 then
        misty.done = true
        if misty.seen then pcall(wisps.burst, a, true) end
    end
end)

-- any other way the vanilla Cloudward / Cloudfall starts (a queued press...) is turned into the combo too
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if ourReq or not live.on then return end
            -- during the combo's opening: Kite Arrow's own follow-up (the kick-off jump after a hit) is refused, so the
            -- opening plays on to its end frame and the combo warps
            if combo.stage == 1 then
                local skipF = false
                pcall(function()
                    local name = sdk.to_managed_object(args[4]):ToString()
                    if not name:find("^Job02_") or name == "Job02_StartFlightShot" then return end
                    if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                    skipF = true
                    if combo.refused ~= name then combo.refused = name; note("Kite Arrow follow-up refused: " .. name) end
                end)
                if skipF then return sdk.PreHookResult.SKIP_ORIGINAL end
                return
            end
            if combo.stage ~= 0 then return end
            local skip = false
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if not name:find("^Job01_RisingLunge") or name == "Job01_RisingLungeLanding" then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                skip = true
                if os.clock() - combo.lastPress > 0.6 then
                    combo.lastPress = os.clock()
                    combo.want = true
                    note("vanilla " .. name .. " requested: combo instead")
                end
            end)
            if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r) return r end)
end)

------------------------------------------------------------------------
-- TEST: our own warp look - enchantment wisps (weapon effect element 20, Dimension Door's way: they only show when a
-- weapon's own effect manager plays them, so a hidden Stalwart Sword is spawned once as the "donor") on the body:
-- feet and hips (butt / groin). "Show on me now" keeps them on for a look.
------------------------------------------------------------------------
wisps = { on = false, items = {}, donor = nil, joints = nil, info = "-", element = 30, useDonor = false, from = "-",
                layerNames = {}, layers = 0 }
local WISP_POINTS = {   -- user: feet and butt / groin are enough (also wisps.POINTS, for the menu)
    { key = "feet", name = "feet", find = { "L_Foot", "R_Foot", "L_Leg_Foot", "R_Leg_Foot", "L_Ankle", "R_Ankle" } },
    { key = "hips", name = "butt and groin", find = { "Hip", "Pelvis", "Waist", "C_Hip" } },
}
wisps.POINTS = WISP_POINTS
cfg.wispPts = cfg.wispPts or { feet = true, hips = true }
cfg.wispSize, cfg.wispMode, cfg.wispFreeze, cfg.wispA, cfg.wispB, cfg.wispSpeed = 1.0, "loop", 1.0, 0.0, 5.0, 1.0
cfg.wispTint, cfg.wispLayers, cfg.warpWispSecs = true, {}, 0.5   -- user: 0.5 s
cfg.wispElement = 30   -- user: 30 looks best
local WISP_KEYS = { "wispElement", "wispSize", "wispMode", "wispFreeze", "wispA", "wispB", "wispSpeed", "wispTint", "warpWispSecs" }
do
    local saved = json.load_file(DATA) or {}
    if type(saved.wispPts) == "table" then
        for k, v in pairs(saved.wispPts) do if type(v) == "boolean" then cfg.wispPts[k] = v end end
    end
    for _, k in ipairs(WISP_KEYS) do
        if saved[k] ~= nil and type(saved[k]) == type(cfg[k]) then cfg[k] = saved[k] end
    end
    wisps.element = cfg.wispElement
    if type(saved.wispLayers) == "table" then
        for k, v in pairs(saved.wispLayers) do if type(v) == "boolean" then cfg.wispLayers[tonumber(k) or k] = v end end
    end
end
do
    local save0 = save_cfg
    save_cfg = function()
        save0()
        local d = json.load_file(DATA) or {}
        d.wispPts = cfg.wispPts
        for _, k in ipairs(WISP_KEYS) do d[k] = cfg[k] end
        local L = {}
        for k, v in pairs(cfg.wispLayers) do L[tostring(k)] = v end
        d.wispLayers = L
        json.dump_file(DATA, d)
    end
end

local DONOR_WEAPON = 3368873434   -- app.WeaponID of the Stalwart Sword (wp00_009)
function wisps.donor_mgr(a)
    local dn = wisps.donor
    if dn then
        local alive = false
        pcall(function() alive = dn.go:get_Name() ~= nil end)
        if alive then return dn.mgr end
        wisps.donor = nil
    end
    local owner = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)"):call(nil, "Pactblade_wisp_donor", 0):add_ref()
    owner:call(".ctor"); owner:set_Name("Pactblade_wisp_donor")
    local pos = a.character:get_GameObject():get_Transform():get_Position()
    owner:get_Transform():set_Position(Vector3f.new(pos.x, pos.y - 50, pos.z))    -- out of sight
    local em = sdk.get_managed_singleton("app.EquipmentManager")
    em:call("requestInstantiate(app.WeaponID, via.Component, System.Action`1<app.PrefabInstantiateResults>, System.Func`2<app.PrefabInstantiateArgs.DummyArg2,System.Boolean>)",
        DONOR_WEAPON, owner:get_Transform(), nil, nil)
    -- our copy = the child of our owner object (never the Stalwart Sword in someone's hand)
    local child = owner:get_Transform():call("get_Child")
    local go = child and child:get_GameObject()
    if not go then wisps.info = "donor sword did not spawn"; return nil end
    go = go:add_ref()
    pcall(function() go:call("set_DrawSelf", false) end)
    local mgr = go:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    if not mgr then wisps.info = "donor sword has no effect manager"; return nil end
    wisps.donor = { go = go, mgr = mgr:add_ref(), owner = owner }
    wisps.info = "donor sword ready"
    return wisps.donor.mgr
end

local function make_anchor(name)
    local go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)"):call(nil, name, 0)
    go = go:add_ref()
    go:call(".ctor")
    go:set_Name(name)
    return go
end

-- user: use the enchanted sword's own (hidden) wisps -> the held sword's effect manager plays element 20 on our
-- anchor (our sword-effect blocker lets it through via noxStarting); the donor sword only when there is none
wisps.swapped = {}
function wisps.play_on(a, go)
    local function req(mgr)
        local eid = sdk.create_instance("via.effect.script.EffectID")
        eid.DataContainerIndex = -1; eid.ContainerID = 0; eid.ElementID = wisps.element
        eid.IsContainerIDOnly = false; eid.IsElementIDOnly = false
        return mgr:call("requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)",
            eid, go, -1, nil)
    end
    local c
    local sw = held_sword_go()
    local smgr = sw and sw:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    if smgr and not wisps.useDonor then
        noxStarting = true
        local ok, r = pcall(req, smgr)
        noxStarting = false
        if ok then c = r end
        wisps.from = "the sword in hand"
    end
    if not c then
        local mgr = wisps.donor_mgr(a)
        if not mgr then return nil end
        c = req(mgr)
        wisps.from = "the hidden donor sword"
    end
    if not c then return nil end
    return c:add_ref()
end
-- our file into the sword's wisp players (also retried each frame for a moment: players can come a frame later)
function wisps.swap(c)   -- (name kept) the sword's wisps in our colour through their own colour parameters
    local v = part_cfg("-1/8/40").variant
    local hue = part_cfg("-1/8/40").mode == "ours" and tonumber(tostring(v or ""):match("^e(%d+)$") or "")
    if not hue then return end
    local h = hue / 60
    local x = 1 - math.abs(h % 2 - 1)
    local rgb = ({ { 1, x, 0 }, { x, 1, 0 }, { 0, 1, x }, { 0, x, 1 }, { x, 0, 1 }, { 1, 0, x } })[math.floor(h) % 6 + 1]
    wisps.paramCol = wisps.paramCol or {}
    wisps.paramCol[hue] = wisps.paramCol[hue] or via_colour({ rgb[1], rgb[2], rgb[3], 1 })
    local col = wisps.paramCol[hue]
    local done = 0
    pcall(function()
        local list = c:call("getAllPlayers")
        for q = 0, (list and list:call("get_Count") or 0) - 1 do
            local pl = list:call("get_Item", q)
            for _, name in ipairs({ "BaseColor", "FireColor" }) do
                pcall(function()
                    local xp = pl:call("getExternParameter", name)
                    if xp then xp:call("set_Color", col); done = done + 1 end
                end)
            end
        end
    end)
    if done > 0 then
        wisps.swapped[c:get_address()] = true
        if not wisps.swapNoted then wisps.swapNoted = true; note(("warp wisps: coloured through %d colour parameter(s)"):format(done)) end
    end
end

-- the player's joints, found by name once (all names saved to data/Pactblade_joints.json)
function wisps.find_joints(a)
    if wisps.joints then return wisps.joints end
    local tr = a.character:get_GameObject():get_Transform()
    local names, byName = {}, {}
    pcall(function()
        for _, j in ipairs(tr:call("get_Joints"):get_elements()) do
            local n = j:call("get_Name")
            names[#names + 1] = n
            byName[n] = j
        end
    end)
    pcall(json.dump_file, "Pactblade_joints.json", names)
    local out = {}
    for _, pt in ipairs(WISP_POINTS) do
        out[pt.key] = {}
        local wantTwo = pt.key == "feet" or pt.key == "shoulders"
        for _, n in ipairs(pt.find) do
            if byName[n] then
                table.insert(out[pt.key], byName[n])
                if not wantTwo or #out[pt.key] >= 2 then break end
            end
        end
    end
    wisps.joints = out
    return out
end

function wisps.clear()
    for _, slot in ipairs(wisps.items) do
        for _, cp in ipairs(slot.copies or {}) do
            pcall(function() cp.c:call("killAll") end)
            pcall(function() cp.go:call("destroy(via.GameObject)", cp.go) end)
        end
    end
    wisps.items = {}
end

-- effect player (like the hand glow's): each copy keeps its own effect time; hidden copies (100 m down) are
-- fast-forwarded to where they should start. normal = plays at a speed; freeze = stopped at a moment;
-- loop = only the A-B part, a relay of copies so there is no gap
local WISP_FF = 0.15
local function wisp_speed(cp, sp)
    cp.speed = sp
    pcall(function() cp.c:call("setPlaySpeed", sp) end)
end
local function wisp_copy(a, slot, goal)
    local go = make_anchor("Pactblade_wisp")
    local cp = { go = go, t = 0, hidden = goal > 0, goal = goal }
    local ok, c = pcall(wisps.play_on, a, go)
    if not ok or not c then pcall(function() go:call("destroy(via.GameObject)", go) end); return nil end
    cp.c = c
    wisp_speed(cp, goal > 0 and math.max(1.0, goal / WISP_FF) or cfg.wispSpeed)
    table.insert(slot.copies, cp)
    return cp
end
local function wisp_kill(slot, k)
    local cp = slot.copies[k]
    pcall(function() cp.c:call("killAll") end)
    pcall(function() cp.go:call("destroy(via.GameObject)", cp.go) end)
    table.remove(slot.copies, k)
end

function wisps.update(a)
    local js = wisps.find_joints(a)
    local tr = a.character:get_GameObject():get_Transform()
    local rot = tr:get_Rotation()
    local now = os.clock()
    local dt = now - (wisps.lastT or now)
    wisps.lastT = now
    -- (re)build when the points or the player settings changed
    local want = {}
    for _, pt in ipairs(WISP_POINTS) do
        if cfg.wispPts[pt.key] then
            for _, j in ipairs(js[pt.key] or {}) do want[#want + 1] = { pt = pt, j = j } end
        end
    end
    local sig = ("%d:%s:%.2f:%.2f:%.2f:%.2f:%d"):format(#want, cfg.wispMode, cfg.wispFreeze, cfg.wispA, cfg.wispB, cfg.wispSpeed, wisps.element)
    for _, w in ipairs(want) do sig = sig .. w.pt.key end
    if sig ~= wisps.sig then
        wisps.clear()
        wisps.sig = sig
        for _, w in ipairs(want) do table.insert(wisps.items, { pt = w.pt, j = w.j, copies = {} }) end
    end
    local col = blast_colour()
    local n, shownT, layers = 0, nil, 0
    for _, slot in ipairs(wisps.items) do
        pcall(function()
            for _, cp in ipairs(slot.copies) do cp.t = cp.t + dt * (cp.speed or 0) end
            local mode = cfg.wispMode
            if mode == "normal" then
                local cp = slot.copies[1]
                local dead = not cp
                if cp then pcall(function() dead = cp.c:call("get_isFinished") end) end
                if dead then
                    if cp then wisp_kill(slot, 1) end
                    wisp_copy(a, slot, 0)
                end
            elseif mode == "freeze" then
                local cp = slot.copies[1]
                if not cp then wisp_copy(a, slot, cfg.wispFreeze)
                elseif cp.speed > 0 and cp.t >= cfg.wispFreeze then wisp_speed(cp, 0); cp.hidden = false end
            else   -- loop A-B
                local A, B = math.min(cfg.wispA, cfg.wispB - 0.05), cfg.wispB
                for k = #slot.copies, 1, -1 do
                    local cp = slot.copies[k]
                    if cp.hidden and cp.t >= A then cp.hidden = false; wisp_speed(cp, cfg.wispSpeed)
                    elseif not cp.hidden and cp.t >= B then wisp_kill(slot, k) end
                end
                local last = slot.copies[#slot.copies]
                if not last or (not last.hidden and last.t >= B - WISP_FF * cfg.wispSpeed) then wisp_copy(a, slot, A) end
            end
            -- place the copies on the body (hidden ones below the ground) and colour the chosen layers
            local p = slot.j:get_Position()
            if slot.pt.back then   -- behind the back: away from the character's facing
                local fx, fz = forward_of(rot)
                p = Vector3f.new(p.x - fx * slot.pt.back, p.y, p.z - fz * slot.pt.back)
            end
            for _, cp in ipairs(slot.copies) do
                local t2 = cp.go:get_Transform()
                t2:set_Position(cp.hidden and Vector3f.new(p.x, p.y - 100, p.z) or p)
                t2:set_Rotation(rot)
                t2:set_LocalScale(Vector3f.new(cfg.wispSize, cfg.wispSize, cfg.wispSize))
                if not cp.hidden then
                    n = n + 1
                    shownT = shownT or cp.t
                end
                if cfg.wispTint then
                    pcall(function()
                        local list = cp.c:call("getAllPlayers")
                        local cnt = list and list:call("get_Count") or 0
                        layers = math.max(layers, cnt)
                        for q = 0, cnt - 1 do
                            local pl = list:call("get_Item", q)
                            if pl and cfg.wispLayers[q + 1] ~= false then pl:set_Color(col) end
                            if pl and not wisps.layerNames[q + 1] then
                                pcall(function() wisps.layerNames[q + 1] = pl:call("get_Resource"):call("get_ResourcePath") end)
                                wisps.layerNames[q + 1] = wisps.layerNames[q + 1] or "?"
                            end
                        end
                    end)
                end
            end
        end)
    end
    wisps.layers = layers
    local miss = {}
    for _, pt in ipairs(WISP_POINTS) do
        if cfg.wispPts[pt.key] and #(js[pt.key] or {}) == 0 then miss[#miss + 1] = pt.name end
    end
    wisps.now = shownT
    wisps.info = ("%d wisps showing (from %s)%s"):format(n, wisps.from, #miss > 0 and (" | no joint found for: " .. table.concat(miss, ", ")) or "")
end

-- the warp look: a burst of wisps on the chosen points for warpWispSecs, then faded out (finishAll). follow = they
-- stay on the body (arrival), else they stay where we were (departure). Uses the effect player's settings: starts at
-- A (loop) / the frozen moment (freeze) / 0 (normal), at its speed
wisps.bursts = {}
local function wisp_layers_colour(c, col)
    pcall(function()
        local list = c:call("getAllPlayers")
        for q = 0, (list and list:call("get_Count") or 0) - 1 do
            local pl = list:call("get_Item", q)
            if pl and cfg.wispLayers[q + 1] ~= false then pl:set_Color(col) end
        end
    end)
end
function wisps.burst(a, follow)
    local js = wisps.find_joints(a)
    local goal = (cfg.wispMode == "loop" and cfg.wispA) or (cfg.wispMode == "freeze" and cfg.wispFreeze) or 0
    local now = os.clock()
    for _, pt in ipairs(WISP_POINTS) do
        if cfg.wispPts[pt.key] then
            for _, j in ipairs(js[pt.key] or {}) do
                local go = make_anchor("Pactblade_warpwisp")
                local ok, c = pcall(wisps.play_on, a, go)
                if ok and c then
                    local b = { go = go, c = c, t = 0, hidden = goal > 0, goal = goal, j = j, follow = follow, born = now,
                                pos = j:get_Position(), untilT = now + cfg.warpWispSecs + (goal > 0 and WISP_FF or 0) }
                    wisp_speed(b, goal > 0 and math.max(1.0, goal / WISP_FF) or cfg.wispSpeed)
                    table.insert(wisps.bursts, b)
                else
                    pcall(function() go:call("destroy(via.GameObject)", go) end)
                end
            end
        end
    end
end
function wisps.update_bursts(a)
    local now = os.clock()
    local dt = now - (wisps.burstT or now)
    wisps.burstT = now
    local col = blast_colour()
    for k = #wisps.bursts, 1, -1 do
        local b = wisps.bursts[k]
        b.t = b.t + dt * (b.speed or 0)
        if b.hidden and b.t >= b.goal then
            b.hidden = false
            wisp_speed(b, cfg.wispMode == "freeze" and 0 or cfg.wispSpeed)
        end
        if not b.ending and now >= b.untilT then
            b.ending = now
            wisp_speed(b, math.max(cfg.wispSpeed, 0.5))   -- a frozen one has to run to fade out
            pcall(function() b.c:call("finishAll") end)
        end
        if b.ending and now - b.ending > 2 then
            pcall(function() b.go:call("destroy(via.GameObject)", b.go) end)
            table.remove(wisps.bursts, k)
        else
            pcall(function()
                local p = b.follow and b.j:get_Position() or b.pos
                local t2 = b.go:get_Transform()
                t2:set_Position(b.hidden and Vector3f.new(p.x, p.y - 100, p.z) or p)
                t2:set_LocalScale(Vector3f.new(cfg.wispSize, cfg.wispSize, cfg.wispSize))
                wisps.swap(b.c)   -- every frame (the game may set them back)
                if cfg.wispTint and not wisps.swapped[b.c:get_address()] then wisp_layers_colour(b.c, col) end
            end)
        end
    end
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if #wisps.bursts > 0 then
        local a0 = runtime.player()
        if a0 and a0:valid() then pcall(wisps.update_bursts, a0) end
    end
    if not wisps.on then
        if #wisps.items > 0 then wisps.clear(); wisps.sig = nil end
        return
    end
    local a = runtime.player()
    if not a or not a:valid() then return end
    local ok, err = pcall(wisps.update, a)
    if not ok then wisps.info = "error: " .. tostring(err) end
end)
re.on_script_reset(function()
    wisps.clear()
    pcall(function() if wisps.donor then wisps.donor.owner:call("destroy(via.GameObject)", wisps.donor.owner) end end)
end)




------------------------------------------------------------------------
-- Eldritch Slash (user's design): Hindsight Sweep's slot plays Warrior's Job05_CrescentSlashNormal (frames 0-97)
-- and, at cfg.slashFrame, fires Magike Cut's wave (Mystic Spearhand's shell 6) from the sword hand, aimed like the
-- blasts (crosshair + lock-on), coloured with the blast colour. Super armour while it plays (user).
------------------------------------------------------------------------
local SLASH = { action = "Job05_CrescentSlashNormal", to = 97, shell = 6, stamina = 150, range = 8 }
local slash = { on = false, lastPress = -10, waves = {}, rangeBase = {} }
combo.slash = slash
local function slash_end(why)
    if slash.on then note("Eldritch Slash ended: " .. why) end
    slash.on = false
    if slash.fast then
        slash.fast = false
        pcall(function() local a = runtime.player(); if a then a:set_speed(nil) end end)
    end
    if slash.armor then
        slash.armor = false
        pcall(function() local a = runtime.player(); if a then a:set_super_armor(false) end end)
    end
end
local function slash_lifetime()
    if SLASH.baseDur then return SLASH.baseDur * 5 end   -- 5x as far (user)
    note("Eldritch Slash: wave flight time not measured yet - normal distance this time")
    return nil
end
local function slash_learn(rec)
    if SLASH.baseLife or not rec then return end
    pcall(function()
        local p = rec.param or (rec.parts and rec.parts[1] and rec.parts[1].shell:get_ShellParameter())
        local b = p._ShellParameterBase and p._ShellParameterBase.ShellBaseParam or p.ShellBaseParam
        note(("Eldritch Slash: wave UseLifeTime %s, LifeTime %s"):format(tostring(b.UseLifeTime), tostring(b.LifeTime)))
        if b.LifeTime and b.LifeTime > 0 then SLASH.baseLife = b.LifeTime end
    end)
end
-- the nearest living enemy within cfg.slashTurnRange m and cfg.slashTurnCone degrees of where the character faces
local function slash_pick_target(a, range, cone, gap)
    range, cone, gap = range or cfg.slashTurnRange, cone or cfg.slashTurnCone, gap or 4
    local tr = a.character:get_GameObject():get_Transform()
    local p = tr:get_Position()
    local fx, fz = flat_dir(forward_of(tr:get_Rotation()))
    if not fx then return nil end
    local list = sdk.get_managed_singleton("app.EnemyManager")._EnemyList
    local best, bestD
    for i = 0, list._size - 1 do
        pcall(function()
            local ch = list._items[i]._Chara
            if not is_alive(ch) then return end
            local q = ch:get_GameObject():get_Transform():get_Position()
            local dx, dz, d = flat_dir(q.x - p.x, q.z - p.z)
            if not dx or d > range or math.abs(q.y - p.y) > gap then return end
            if math.deg(math.acos(math.max(-1, math.min(1, dx * fx + dz * fz)))) > cone then return end
            if not bestD or d < bestD then best, bestD = ch, d end
        end)
    end
    return best, bestD
end
-- turns at most cfg.slashTurnSpeed degrees a second toward the target (slight tracking until the wave fires)
local function slash_turn(a, dt)
    local t = slash.target
    if not t or not is_alive(t) then return end
    local tr = a.character:get_GameObject():get_Transform()
    local p, q = tr:get_Position(), t:get_GameObject():get_Transform():get_Position()
    local tx, tz = flat_dir(q.x - p.x, q.z - p.z)
    local fx, fz = flat_dir(forward_of(tr:get_Rotation()))
    if not tx or not fx then return end
    local gap = math.atan(tx * fz - tz * fx, fx * tx + fz * tz)   -- yaw (atan(x, z)) still to turn
    local step = math.rad(cfg.slashTurnSpeed) * dt
    if math.abs(gap) > step then gap = gap > 0 and step or -step end
    local yaw = math.atan(fx, fz) + gap
    local dx, dz = math.sin(yaw), math.cos(yaw)
    tr:set_Rotation(yaw_rotation(dx, dz))
    face(a, dx, dz)
end
-- the same for the Archfey Combo opening (combo_update is defined above these: it reaches them through combo)
combo.pick_target = slash_pick_target
function combo.turn_to(a, t, dt, speed)
    if not t or not is_alive(t) then return end
    local tr = a.character:get_GameObject():get_Transform()
    local p, q = tr:get_Position(), t:get_GameObject():get_Transform():get_Position()
    local tx, tz = flat_dir(q.x - p.x, q.z - p.z)
    local fx, fz = flat_dir(forward_of(tr:get_Rotation()))
    if not tx or not fx then return end
    local gap = math.atan(tx * fz - tz * fx, fx * tx + fz * tz)
    local step = math.rad(speed) * dt
    if math.abs(gap) > step then gap = gap > 0 and step or -step end
    local yaw = math.atan(fx, fz) + gap
    local dx, dz = math.sin(yaw), math.cos(yaw)
    tr:set_Rotation(yaw_rotation(dx, dz))
    face(a, dx, dz)
end
local function slash_update(a)
    local now = os.clock()
    if slash.want then
        slash.want = false
        if not slash.on and combo.stage == 0 then
            pcall(a.consume_stamina, a, SLASH.stamina)
            slash.on, slash.asked, slash.started, slash.fired = true, now, nil, false
            pcall(function() a:set_super_armor(true); slash.armor = true end)
            pcall(function() slash.prevMot = motion_key(a.character.FullBodyLayer) end)
            combo_request(a, SLASH.action)
            slash.target, slash.lastT = nil, now
            if cfg.slashTurn then
                local ok, t, d = pcall(slash_pick_target, a)
                if ok and t then slash.target = t:add_ref(); note(("Eldritch Slash: turning to an enemy %.1f m away"):format(d)) end
            end
            note("Eldritch Slash")
        end
    end
    if not slash.on then return end
    local cur = a:current_action(0)
    if not slash.started then
        if cur == SLASH.action then slash.started = now
        elseif now - slash.asked > 0.4 then return slash_end("did not start (now " .. tostring(cur) .. ")")
        else combo_request(a, SLASH.action); return end
    end
    if cur ~= SLASH.action then
        if slash.fast and tostring(cur or ""):find("^Job05_") then   -- the recovery is its own action: keep it fast
            pcall(function() a:set_speed(1.2) end)
            pcall(function() a.character.FullBodyLayer:call("set_Speed", 1.2) end)
            return
        end
        return slash_end((slash.fired and "done" or "interrupted") .. " (next action " .. tostring(cur) .. ")")
    end
    local L = a.character.FullBodyLayer
    if motion_key(L) == slash.prevMot and now - slash.started < 0.25 then return end   -- not on the new animation yet
    local fr = L:call("get_Frame")
    local dt = now - (slash.lastT or now); slash.lastT = now
    if slash.target and fr < cfg.slashFrame then pcall(slash_turn, a, math.min(dt, 0.1)) end
    if fr >= cfg.slashFastFrom then
        if not slash.fast then note(("Eldritch Slash: 1.2x from frame %.1f"):format(fr)) end
        slash.fast = true
        pcall(function() a:set_speed(1.2) end)   -- every frame (user: the recovery 1.2x)
        pcall(function() L:call("set_Speed", 1.2) end)
    end
    if not slash.fired and fr >= cfg.slashFrame then
        slash.fired = true
        dbg.slashT = os.clock()
        local skel = false   -- (1.66 Skeleton Lord wave: only dust + a shockwave without its own effect files)
        local res, err = spawn(a, {
            type = "shell", id = "eldritch_slash",
            shell = skel and SKELETON_SHELLS or JOB07_SHELLS, shell_id = skel and 0 or SLASH.shell,
            cast = { mode = "owner", offset = { 0, 1.2, 1.3 }, face = "owner" },
            scale_axes = { 1, 2, 1 },                      -- 2x taller (user)
            -- (range: what ends its flight is still being looked for - data/Pactblade_wave_params.json)
        })
        if res and res.record then
            slash.rec = res.record
            -- Magike Cut's wave counts as a blast (coloured like them); the Skeleton Lord's keeps its own look
            if not skel then table.insert(blasts, { record = res.record, kind = "slash", born = os.clock() }) end
            slash.waveBorn, slash.waveMeasure, slash.waveDumped, slash.rangeSet = os.clock(), false, false, false
            note(("Eldritch Slash: wave at frame %.1f"):format(fr))
            if cfg.blastTint and not skel then   -- the blasts' colour, exactly as they get it
                local k = cfg.armBright
                colour_shell(res.record, { math.min(1, cfg.armR / 255 * k), math.min(1, cfg.armG / 255 * k), math.min(1, cfg.armB / 255 * k), 1 }, 6.0)
            end
        else note("Eldritch Slash: wave failed: " .. tostring(err)) end
    end
    -- (no cut at SLASH.to: the recovery after it plays out, sped up from cfg.slashFastFrom; ends with the animation)
end
-- the wave's own built-in effect (the shell's ShellEffectContainer) in the slash colour, every frame while it flies
local function wave_meshes(rec)
    local out = {}
    for _, part in ipairs(rec.parts or {}) do
        pcall(function()
            local go = part.shell:get_GameObject()
            for _, m in ipairs(meshes_of(go, {})) do out[#out + 1] = m end
        end)
    end
    return out
end
local function wave_mesh_dump(meshes)
    if SLASH.meshDumped or #meshes == 0 then return end
    SLASH.meshDumped = true
    local all = {}
    for _, m in ipairs(meshes) do
        local md = { materials = {} }
        pcall(function() md.go = tostring(m:get_GameObject():get_Name()) end)
        pcall(function()
            for i = 0, m:call("get_MaterialNum") - 1 do
                local mat = { name = tostring(m:call("getMaterialName", i)), vars = {} }
                for v = 0, m:call("getMaterialVariableNum", i) - 1 do
                    local vr = { name = tostring(m:call("getMaterialVariableName", i, v)), type = m:call("getMaterialVariableType", i, v) }
                    pcall(function()
                        local f = m:call("getMaterialFloat4(System.UInt32, System.UInt32)", i, v)
                        vr.value = { f.x, f.y, f.z, f.w }
                    end)
                    mat.vars[#mat.vars + 1] = vr
                end
                md.materials[#md.materials + 1] = mat
            end
        end)
        all[#all + 1] = md
    end
    pcall(json.dump_file, "Pactblade_wave_mesh.json", all)
    note(("Eldritch Slash: wave has %d mesh(es) - materials written to data/Pactblade_wave_mesh.json"):format(#meshes))
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    local rec = slash.rec
    if not rec then return end
    local now = os.clock()
    if false then   -- (1.59-1.60 flight measurement: ended at once, gave 0.01 s - off)
        local alive = false
        pcall(function()
            local go = rec.parts[1].shell:get_GameObject()
            alive = go ~= nil and go:call("get_Valid") ~= false and rec.parts[1].shell:call("get_Valid") ~= false
        end)
        if not alive then
            slash.waveMeasure = false
            SLASH.baseDur = now - slash.waveBorn
            note(("Eldritch Slash: the wave flies %.2f s normally - next ones fly 5x that"):format(SLASH.baseDur))
        end
    end
    if now - (dbg.slashT or -10) > 30 then slash.rec = nil; return end
    if false then   -- (its own colour on the child effect player: off)
        local col = slash_colour()
        for _, part in ipairs(rec.parts or {}) do
            pcall(function()
                local ch = part.shell:get_GameObject():get_Transform():call("get_Child")
                while ch do
                    pcall(function()
                        local ep = ch:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer"))
                        if ep then ep:set_Color(col) end
                    end)
                    ch = ch:call("get_Next")
                end
            end)
        end
    end
    -- range: remember which wave shells are ours (the update() hook below scales their range)
    if not slash.rangeSet then
        pcall(function()
            local comp = rec.parts[1].shell:get_GameObject():call("getComponent(System.Type)", sdk.typeof("app.ShellAdditionalJob07SubNormalAttackShell"))
            if not comp then return end
            slash.waves[comp:get_address()] = os.clock()
            slash.rangeSet = true
        end)
    end
    for k, t in pairs(slash.waves) do if now - t > 30 then slash.waves[k] = nil end end
    local meshes = wave_meshes(rec)
    wave_mesh_dump(meshes)
    if true then return end   -- (mesh colouring + the TEST dumps below: off)
    local col = slash_colour and slash_colour()
    if not col then return end
    -- the wave's mesh: every colour value of its materials in the slash colour (alpha kept)
    local k = cfg.slashBright
    for _, m in ipairs(meshes) do
        pcall(function()
            for i = 0, m:call("get_MaterialNum") - 1 do
                for v = 0, m:call("getMaterialVariableNum", i) - 1 do
                    local name = tostring(m:call("getMaterialVariableName", i, v)):lower()
                    if name:find("color") or name:find("colour") then
                        pcall(function()
                            local f = m:call("getMaterialFloat4(System.UInt32, System.UInt32)", i, v)
                            m:call("setMaterialFloat(System.UInt32, System.UInt32, via.Float4)", i, v,
                                Vector4f.new(cfg.slashR / 255 * k, cfg.slashG / 255 * k, cfg.slashB / 255 * k, f.w))
                        end)
                    end
                end
            end
        end)
    end
    for _, part in ipairs(rec.parts or {}) do
        pcall(function()
            local c = part.shell:get_field("<ShellEffectContainer>k__BackingField")
            if not c then return end
            pcall(function() c:call("setRootColor(via.Color)", col) end)
            local list = c:call("getAllPlayers")
            for q = 0, (list and list:call("get_Count") or 0) - 1 do list:call("get_Item", q):set_Color(col) end
        end)
    end
end)
re.on_pre_application_entry("UpdateBehavior", function()
    if not slash.on and not slash.want then return end
    local a = runtime.player()
    if not a or not a:valid() or not live.on then slash.want = false; slash_end("Pactblade off"); return end
    local ok, err = pcall(slash_update, a)
    if not ok then slash_end("error: " .. tostring(err)) end
end)

pcall(function()
    local scaled = {}
    sdk.hook(sdk.find_type_definition("app.ShellAdditionalJob07SubNormalAttackShell"):get_method("update()"), function(args)
        local this = sdk.to_managed_object(args[2])
        if not this or not slash.waves[this:get_address()] then return end
        local prm = this:get_field("<DetailParam>k__BackingField")
        if not prm then return end
        local key = prm:get_address()
        if not slash.rangeBase[key] then
            slash.rangeBase[key] = prm:get_field("DefaultRangeDist")
            note(("Eldritch Slash: wave range %.1f m normally, x%.1f now"):format(slash.rangeBase[key], cfg.slashRange))
        end
        prm:set_field("DefaultRangeDist", slash.rangeBase[key] * cfg.slashRange)
        scaled[#scaled + 1] = prm
    end, function(r)
        while #scaled > 0 do
            local prm = table.remove(scaled)
            pcall(function() prm:set_field("DefaultRangeDist", slash.rangeBase[prm:get_address()]) end)
        end
        return r
    end)
end)

-- (Misty Dive) a spot above an enemy's head, a bit toward us, facing it; and the combo's warp look + move to a spot
function combo.dive_spot(a, t, above, back)
    local tTr = t:get_GameObject():get_Transform()
    local tPos = tTr:get_Position()
    local pPos = a.character:get_GameObject():get_Transform():get_Position()
    local dx, dz = flat_dir(pPos.x - tPos.x, pPos.z - tPos.z)
    if not dx then dx, dz = 0, 1 end
    local headY
    pcall(function()   -- the highest joint with "head" in its name (big monsters name theirs differently)
        local joints = tTr:call("get_Joints")
        for k = 0, joints:call("get_Length") - 1 do
            local j = joints:call("Get", k)
            local nm = tostring(j:call("get_Name")):lower()
            if nm:find("head") then   -- (only joints on the creature: helper points can sit far away)
                local jp = j:get_Position()
                local near = math.abs(jp.x - tPos.x) < 6 and math.abs(jp.z - tPos.z) < 6 and jp.y > tPos.y and jp.y < tPos.y + 15
                if near and (not headY or jp.y > headY) then headY = jp.y end
            end
        end
    end)
    if not headY then   -- else the creature's own height
        pcall(function() local h = t["<CharaController>k__BackingField"]:call("get_Height"); if h and h > 0.5 then headY = tPos.y + h end end)
    end
    headY = headY or tPos.y + 1.7
    local dest = Vector3f.new(tPos.x + dx * back, headY + above, tPos.z + dz * back)
    return dest, yaw_rotation(-dx, -dz), -dx, -dz   -- (facing the enemy as seen from where I was)
end
function combo.warp_to(a, dest, rot, dx, dz)
    local tr = a.character:get_GameObject():get_Transform()
    local useWisps = cfg.warpFx == "wisps" and not dbg.comboNoWisps
    local CUE = CUES[cfg.warpFx] or CUES.quikfot
    if useWisps then
        CUE = CUES.quikfot
        pcall(wisps.burst, a, false)
    end
    if dbg.ai then pcall(dbg.ai.warp, a) end
    cues(a, useWisps and {} or CUE.depart_efx, CUE.depart_snd, tr:get_Position(), tr:get_Rotation())
    tr:set_Position(dest)
    tr:set_Rotation(rot)
    pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end)
    face(a, dx, dz)
    cues(a, useWisps and {} or CUE.arrive_efx, CUE.arrive_snd, dest, rot)
    if useWisps then pcall(wisps.burst, a, true) end
end
combo.face = face
combo.yaw = yaw_rotation   -- (3.10: for the Burst step, outside this function)

-- Hindsight Sweep (Job01_HindsightSlash) pressed while Pactblade is active: Eldritch Slash instead
local HINDSIGHT_ID = -1
pcall(function()
    for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if f:is_static() and f:get_name() == "Job01_HindsightSlash" then HINDSIGHT_ID = f:get_data(nil) & 0xFFFFFFFF end
    end
end)
pcall(function()
    local SIG = "processCustomSkill(app.HumanCustomSkillID, System.UInt64, app.LockOnController.Option, System.Boolean, System.Boolean, System.Boolean, app.LocomotionSpeedTypeEnum, System.Boolean)"
    sdk.hook(sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method(SIG), function(args)
        if not live.on then return end
        local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
        if id ~= HINDSIGHT_ID then return end
        local now = os.clock()
        if not slash.on and combo.stage == 0 and now - slash.lastPress > 0.6 then
            local can = false
            pcall(function()
                local track = runtime.player().character:get_Human().Track
                can = track.All or track.Skill
            end)
            if can then slash.lastPress = now; slash.want = true end
        end
        return sdk.PreHookResult.SKIP_ORIGINAL   -- the vanilla skill never plays
    end, function(r) return r end)
end)
-- the vanilla Hindsight Sweep started any other way (a queued press...) becomes Eldritch Slash too
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if ourReq or not live.on or slash.on then return end
            local skip = false
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if not name:find("^Job01_HindsightSlash") then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                skip = true
                if os.clock() - slash.lastPress > 0.6 then slash.lastPress = os.clock(); slash.want = true end
            end)
            if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r) return r end)
end)

end)()

re.on_frame(function()
    local r = combo.result
    if not r or os.clock() - r.t > 4 then return end
    pcall(function()
        local col = r.ok and 0xFF40FF40 or 0xFF4040FF   -- ABGR: green / red
        draw.text(r.text, 60, 220, 0xFF000000)
        draw.text(r.text, 59, 219, col)
    end)
end)

-- time skip to `hour`:00 where the player stands (app.TimeSkipManager.requestPlayerWarp, as Nick's Devtools do)
function dbg.day_skip(hour)
    local tm, ts = sdk.get_managed_singleton("app.TimeManager"), sdk.get_managed_singleton("app.TimeSkipManager")
    local tr = runtime.player().character:get_GameObject():get_Transform()
    local h, d = tm:get_InGameHour(), tm:get_InGameDay()
    if h >= hour then d = d + 1 end
    ts:call("requestPlayerWarp", hour, 0, d, tr:get_UniversalPosition(), tr:get_Rotation(), nil, true, true)
    note(("time skip: %d:00 -> %d:00"):format(h, hour))
end
-- keep it daytime: once it gets dark (19:00-4:59), skip to 10:00 - not while a Pactblade skill plays
re.on_frame(function()
    if not cfg.keepDay then return end
    local now = os.clock()
    if now - (dbg.dayCheck or 0) < 5 then return end
    dbg.dayCheck = now
    pcall(function()
        if combo.stage ~= 0 or (combo.slash and combo.slash.on) then return end
        local h = sdk.get_managed_singleton("app.TimeManager"):get_InGameHour()
        if (h >= 19 or h < 5) and now - (dbg.daySkipped or -100) > 30 then
            dbg.daySkipped = now
            dbg.day_skip(10)
        end
    end)
end)
local ai = { secs = 0.3, log = {}, nextOk = 0 }
dbg.ai = ai   -- (the warps, inside the combo function, reach it through dbg)
local function ai_note(sx) table.insert(ai.log, 1, sx); while #ai.log > 8 do table.remove(ai.log) end; note("afterimage: " .. sx) end
function ai.handler(a)
    return a.character:get_Human()["<Job07ActionCtrl>k__BackingField"]["<AfterImageHandler>k__BackingField"]
end
function ai.inspect(a)
    local h = ai.handler(a)
    local inst = h:call("get_Instance")
    if not inst then ai_note("inspect: no clone"); return end
    local out = {}
    for _, g in ipairs({ "get_InProcess", "get_Appeared" }) do out[#out + 1] = "handler." .. g:sub(5) .. "=" .. tostring(h:call(g)) end
    for _, g in ipairs({ "get_Status", "get_NextStatus" }) do
        local ok, v = pcall(inst.call, inst, g)
        out[#out + 1] = g:sub(5) .. "=" .. tostring(ok and v)
    end
    pcall(function()
        local go = inst:get_GameObject()
        out[#out + 1] = "draw=" .. tostring(go:call("get_DrawSelf"))
        local d = (go:get_Transform():get_Position() - a.character:get_GameObject():get_Transform():get_Position()):length()
        out[#out + 1] = ("%.1f m from me"):format(d)
        if ai.spot then out[#out + 1] = ("%.1f m from the spot"):format((go:get_Transform():get_Position() - ai.spot):length()) end
    end)
    ai_note("inspect: " .. table.concat(out, " "))
end
ai.fx = 3   -- which Mirage Dance effects: 1 = element 0, 2 = element 20, 3 = both, 4 = none
ai.FX = { { 0 }, { 20 }, { 0, 20 }, {} }
ai.src = 1
ai.anchors = {}
function ai.play_ours(cgo, el, hue)
    local path = ("vfx/effects/pactblade/pb_ai%02d_h%d.efx"):format(el, hue)
    ai.res = ai.res or {}
    if ai.res[path] == nil then
        local r = sdk.create_resource("via.effect.EffectResource", path)
        ai.res[path] = r and r:add_ref() or false
    end
    if not ai.res[path] then return "copy not found (restart the game for the pak)" end
    local go = make_anchor()
    go:set_Name("Pactblade_afterimage_fx")
    local tr = go:get_Transform()
    tr:call("set_Parent", cgo:get_Transform())
    tr:set_LocalPosition(Vector3f.new(0, 0, 0))
    local holder = ai.res[path]:create_holder("via.effect.EffectResourceHolder"):add_ref()
    local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
    ep:call("set_Resource", holder)
    pcall(function() ep:call("set_AutoStart", true) end)
    table.insert(ai.anchors, { go = go, ep = ep })
    return "ours"
end
function ai.play_fx(a, cgo)
    local p40 = part_cfg("-1/8/40")
    local hue = p40.mode == "ours" and tonumber(tostring(p40.variant or ""):match("^e(%d+)$") or "")
    local mine = {}
    if hue and ai.src ~= 2 then
        for _, el in ipairs(ai.FX[ai.fx] or {}) do mine[#mine + 1] = el .. ":" .. ai.play_ours(cgo, el, hue) end
        if ai.src == 1 then return "aura " .. table.concat(mine, " ") end
    end
    local mgr = a.game_object:call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    local conts = mgr.ExternalDataContainers
    local idx
    for i = 0, conts:get_Count() - 1 do
        local ok, path = pcall(function() return tostring(conts[i].DataContainer:get_Path()) end)
        if ok and path:lower():find("ch07/13_ch07_cs") then idx = i end
    end
    if not idx then return "Mystic Spearhand's cs effects are not on this character" end
    local got = {}
    for _, el in ipairs(ai.FX[ai.fx] or {}) do
        local id = sdk.create_instance("via.effect.script.EffectID")
        id.DataContainerIndex = idx; id.ContainerID = 10; id.ElementID = el
        id.IsContainerIDOnly = false; id.IsElementIDOnly = false
        local ok, c = pcall(mgr.call, mgr, "requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)",
            id, cgo, -1, nil)
        got[#got + 1] = ("%d:%s"):format(el, tostring(ok and c ~= nil))
        if ok and c then ai.conts = ai.conts or {}; table.insert(ai.conts, c:add_ref()) end
    end
    return "effects " .. table.concat(got, " ") .. (#mine > 0 and (" + ours " .. table.concat(mine, " ")) or "")
end
function ai.snapshot(a)
    local snap = {}
    local tr = a.character:get_GameObject():get_Transform()
    local joints = tr:call("get_Joints")
    for k = 0, (joints and joints:call("get_Length") or 0) - 1 do
        pcall(function()
            local j = joints:call("Get", k)
            snap[#snap + 1] = { name = j:call("get_Name"), pos = j:call("get_LocalPosition"), rot = j:call("get_LocalRotation") }
        end)
    end
    return snap
end
function ai.apply_pose(inst)
    if ai.poseOf ~= ai.snap then   -- a new pose: its joints on the clone, looked up once
        local ctr = inst:get_GameObject():get_Transform()
        ai.cj, ai.pose, ai.poseOf = ai.cj or {}, {}, ai.snap
        for _, e in ipairs(ai.snap or {}) do
            local j = ai.cj[e.name]
            if j == nil then
                local okJ, jj = pcall(ctr.call, ctr, "getJointByName", e.name)
                j = okJ and jj or false
                ai.cj[e.name] = j
            end
            if j then ai.pose[#ai.pose + 1] = { j = j, pos = e.pos, rot = e.rot } end
        end
    end
    for _, e in ipairs(ai.pose or {}) do
        pcall(e.j.call, e.j, "set_LocalPosition", e.pos)
        pcall(e.j.call, e.j, "set_LocalRotation", e.rot)
    end
end
function ai.meshes(go, out, depth)
    out = out or {}
    pcall(function()
        local m = go:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
        if m then out[#out + 1] = m end
    end)
    if (depth or 0) < 4 then
        pcall(function()
            local ch = go:get_Transform():call("get_Child")
            while ch do
                ai.meshes(ch:get_GameObject(), out, (depth or 0) + 1)
                ch = ch:call("get_Next")
            end
        end)
    end
    return out
end
function ai.hsv(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    if mx <= 0 then return 0, 0, 0 end
    local s0, h = (mx - mn) / mx, 0
    if mx > mn then
        if mx == r then h = (g - b) / (mx - mn) elseif mx == g then h = 2 + (b - r) / (mx - mn) else h = 4 + (r - g) / (mx - mn) end
        h = (h * 60 + 360) % 360
    end
    return h, s0, mx
end
function ai.rgb(h, s0, v)
    local c = v * s0
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local t = ({ { c, x, 0 }, { x, c, 0 }, { 0, c, x }, { 0, x, c }, { x, 0, c }, { c, 0, x } })[math.floor(h / 60) % 6 + 1]
    return t[1] + m, t[2] + m, t[3] + m
end
-- the clone's teal material colours: found once (0.3 s in), then kept in the picker's hue right before rendering
ai.GHOST = { { name = "RimLight_Emissive_Color_A", rgb = { 0.118, 0.235, 1.0 } },
             { name = "RimLight_Emissive_Color_B", rgb = { 0.235, 1.0, 0.784 } } }
function ai.find_colours(inst)
    local found = {}
    for _, g in ipairs(ai.GHOST) do g.h, g.s, g.v = ai.hsv(g.rgb[1], g.rgb[2], g.rgb[3]); g.hash = g.hash or nameHash:call(nil, g.name) end
    for _, mesh in ipairs(ai.meshes(inst:get_GameObject())) do
        pcall(function()
            for i = 0, mesh:call("get_MaterialNum") - 1 do
                for _, g in ipairs(ai.GHOST) do
                    pcall(function()
                        local v = mesh:call("getMaterialVariableIndex", i, g.hash)
                        if v ~= nil and v < 65535 then
                            found[#found + 1] = { mesh = mesh:add_ref(), m = i, v = v, w = 1.0, s = g.s, val = g.v }
                        end
                    end)
                end
            end
        end)
    end
    return found
end
re.on_pre_application_entry("BeginRendering", function()
    if not ai.t0 or not ai.colours then return end
    local p40 = part_cfg("-1/8/40")
    local hue = p40.mode == "ours" and tonumber(tostring(p40.variant or ""):match("^e(%d+)$") or "")
    if not hue then return end
    for _, e in ipairs(ai.colours) do
        pcall(function()
            local r, g, b = ai.rgb(hue, e.s, e.val)
            e.mesh:call("setMaterialFloat4(System.UInt32, System.UInt32, via.Float4)", e.m, e.v, Vector4f.new(r, g, b, e.w))
        end)
    end
end)
-- a warp starts (before the player is moved): the afterimage here, in this pose
function ai.warp(a)
    if not cfg.afterimage then return end
    ai.secs = cfg.afterimageSecs
    if ai.t0 and ai.inst and ai.step and ai.step >= 1 then   -- still showing: it moves to this warp's spot + pose
        local tr = a.character:get_GameObject():get_Transform()
        ai.spot, ai.rot, ai.snap, ai.t0 = tr:get_Position(), tr:get_Rotation(), ai.snapshot(a), os.clock()
        return
    end
    ai.spawn(a)
end
function ai.spawn(a)
    local now = os.clock()
    local h = ai.handler(a)
    if ai.t0 or now < ai.nextOk or h:call("get_InProcess") then ai_note("not now: the last one is still running (wait a few seconds)"); return end
    local inst = h:call("get_Instance")
    if not inst then ai_note("no clone"); return end
    local tr = a.character:get_GameObject():get_Transform()
    ai.spot, ai.rot = tr:get_Position(), tr:get_Rotation()
    local okI, eI = pcall(h.call, h, "init(System.Boolean)", false)
    local info = sdk.create_instance("app.CloneCharacter.StartInformation"):add_ref()
    pcall(function() info:call(".ctor") end)
    info:call("set_Position", tr:get_UniversalPosition())
    info:call("set_Rotation", ai.rot)
    local okS, eS = pcall(h.call, h, "start(app.CloneCharacter.StartInformation)", info)
    ai.snap, ai.cj, ai.conts, ai.colours, ai.poseOf = ai.snapshot(a), nil, nil, nil, nil
    ai.inst, ai.t0, ai.step = inst, now, 0
    ai_note(("spawn: init %s / start %s"):format(tostring(okI and true or eI), tostring(okS and true or eS)))
end
-- after the game's own late update: the clone stays on the spot (no following), frozen in our pose, ghost look asked
re.on_application_entry("LateUpdateBehavior", function()
    if ai.dying then
        local t = os.clock()
        for k = #ai.dying, 1, -1 do
            local an = ai.dying[k]
            if t >= an.dieAt then
                pcall(function() an.go:call("destroy(via.GameObject)", an.go) end)
                table.remove(ai.dying, k)
            end
        end
    end
    if not ai.t0 then return end
    local inst, now = ai.inst, os.clock()
    pcall(function()
        inst:set_field("RootMoveScale", 0.0)
        local tr = inst:get_GameObject():get_Transform()
        tr:set_Position(ai.spot)
        tr:set_Rotation(ai.rot)
    end)
    pcall(ai.apply_pose, inst)
    if ai.step == 0 then
        ai.step = 1
        local r = {}
        for _, f in ipairs({ "requestStartEffect()", "requestBodyEffect()" }) do
            local ok, e = pcall(inst.call, inst, f)
            r[#r + 1] = f .. " " .. tostring(ok and true or e)
        end
        local okM, eM = pcall(function()
            local cat = inst:get_field("Basic")
            local none = ValueType.new(sdk.find_type_definition("System.Nullable`1<System.UInt32>"))
            inst:call("requestMaterialMode(app.MaterialInterpolationRequestManager.RequestListCategory, System.Nullable`1<System.UInt32>)", cat, none)
            ai.cat = cat
        end)
        r[#r + 1] = "material mode (Basic = " .. tostring(ai.cat) .. ") " .. tostring(okM and true or eM)
        if not ai.dumped then
            ai.dumped = true
            pcall(function()
                local out = { Basic = tostring(inst:get_field("Basic")), settings = {} }
                local arr = inst:get_field("_MaterialInterpolationSettings")
                for k = 0, (arr and arr:call("get_Length") or 0) - 1 do
                    local st = arr:call("Get", k)
                    local e = { category = tostring(st:get_field("_Category")), userdatas = {} }
                    local uds = st:get_field("_MaterialInterpolationUserDatas")
                    for q = 0, (uds and uds:call("get_Length") or 0) - 1 do
                        local ud = uds:call("Get", q)
                        local path
                        pcall(function() path = ud:call("get_Path") end)
                        if not path then pcall(function() path = ud:call("ToString") end) end
                        e.userdatas[#e.userdatas + 1] = tostring(path)
                    end
                    out.settings[#out.settings + 1] = e
                end
                json.dump_file("Pactblade_afterimage_materials.json", out)
            end)
        end
        local okC, cC = pcall(ai.find_colours, inst)
        if okC then ai.colours = cC; r[#r + 1] = ("ghost colour in %d material(s)"):format(#cC) else r[#r + 1] = "colours failed: " .. tostring(cC) end
        local okP, eP = pcall(function() inst:call("get_Motion"):call("set_Enabled", false) end)
        r[#r + 1] = ("pose: %d joints, motion off %s"):format(#(ai.snap or {}), tostring(okP and true or eP))
        local a1 = runtime.player()
        if a1 then
            local okE, eE = pcall(ai.play_fx, a1, inst:get_GameObject())
            r[#r + 1] = tostring(okE and eE or ("effects failed: " .. tostring(eE)))
        end
        ai_note(table.concat(r, " / "))
    elseif ai.step == 1 and now - ai.t0 > 0.3 then
        ai.step = 2
        local a1 = runtime.player()
        if a1 then pcall(ai.inspect, a1) end

    end
    if now - ai.t0 >= ai.secs then
        local a1 = runtime.player()
        pcall(function() inst:call("get_Motion"):call("set_Enabled", true) end)   -- (the clone is reused)
        for _, c in ipairs(ai.conts or {}) do pcall(function() c:call("finishAll") end) end
        local fin
        pcall(function() fin = sdk.find_type_definition("via.effect.PlayerAction"):get_field("Finish"):get_data(nil) end)
        for _, an in ipairs(ai.anchors) do
            pcall(function() if fin ~= nil then an.ep:call("set_Action", fin) end end)
            an.dieAt = now + 2.0
            ai.dying = ai.dying or {}
            table.insert(ai.dying, an)
        end
        ai.anchors = {}
        local okF = pcall(function() ai.handler(a1):call("finish") end)
        ai_note("ended (finish " .. tostring(okF) .. ")")
        ai.t0, ai.nextOk = nil, now + 0.3
    end
end)


re.on_frame(function()
    local r = dbg.rec
    if not r.on then return end
    pcall(function()
        local L = runtime.player().character.FullBodyLayer
        local key = L:call("get_MotionBankID") .. "/" .. L:call("get_MotionID")
        if key ~= r.lastMotion then
            r.lastMotion = key
            local nm
            pcall(function() nm = tostring(runtime.player():current_action(0)) end)
            dbg.rec_add({ motion = key, frame = L:call("get_Frame"), action = nm })
        end
    end)
    if os.clock() - r.t0 >= r.secs then
        r.on = false
        pcall(json.dump_file, "Pactblade_chant_record.json", r.list)
        r.info = ("done: %d entries -> data/Pactblade_chant_record.json"):format(#r.list)
    else
        r.info = ("recording... %.1f s left (%d entries)"):format(r.secs - (os.clock() - r.t0), #r.list)
    end
end)

local castT = { secs = 3.0, info = "-", BANK = 9112, PATH = "animation/ch/ch00/motlist/ch00_006_atk.motlist",
                CHANGE = "changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)" }
dbg.castT = castT
function castT.bank(a)
    local mo = a.character:get_Motion()
    for i = 0, mo:getDynamicMotionBankCount() - 1 do
        local b = mo:getDynamicMotionBank(i)
        if b and b:get_BankID() == castT.BANK then return true end
    end
    local holder = sdk.create_resource("via.motion.MotionListResource", castT.PATH):add_ref()
        :create_holder("via.motion.MotionListResourceHolder"):add_ref()
    local n = mo:getDynamicMotionBankCount()
    mo:setDynamicMotionBankCount(n + 1)
    local bank = sdk.create_instance("via.motion.DynamicMotionBank"):add_ref()
    bank:set_MotionList(holder)
    bank:set_OverwriteBankID(true)
    bank:set_BankID(castT.BANK)
    mo:setDynamicMotionBank(n, bank)
    return false
end
function castT.ready(a)
    local info = sdk.create_instance("via.motion.MotionInfo", true)
    return a.character:get_Motion():call("getMotionInfo(System.UInt32, System.UInt32, via.motion.MotionInfo)", castT.BANK, 712, info)
end
function castT.play(a, id, interp)
    a.character:get_Motion():getLayer(0):call(castT.CHANGE, castT.BANK, id, 0.0, interp or 8.0, 1, 1)
end
function castT.fsm(a, on)
    pcall(function()
        if on then
            local fsm = a.character:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
            if fsm then fsm:call("set_Paused", true); castT.paused = fsm:add_ref() end
        elseif castT.paused then castT.paused:call("set_Paused", false); castT.paused = nil end
    end)
end
-- one effect from a Mage effect set (by path) on the player
-- the anchor in front of the chest the chant circle sits on (a Mage's is on the staff): follows the player while chanting
castT.frontDist, castT.frontHeight, castT.frontTilt, castT.frontSide = 0.65, 0.0, 90, 0.47   -- from the head (user's spot)
castT.frontScale = 0.6   -- (user: 60 % of its size)
function castT.front(a)
    local tr = a.character:get_GameObject():get_Transform()
    local rot = tr:get_Rotation()
    local fwd = rot * Vector3f.new(0, 0, 1)
    if not castT.anchor then
        castT.anchor = make_anchor()
        castT.anchor:set_Name("Pactblade_cast_circle")
    end
    local h = math.rad(castT.frontTilt) / 2   -- tilted around its own sideways axis: upright, facing forward
    local q = Quaternion.new(math.cos(h), math.sin(h), 0, 0)
    local r = Quaternion.new(rot.w * q.w - rot.x * q.x - rot.y * q.y - rot.z * q.z, rot.w * q.x + rot.x * q.w + rot.y * q.z - rot.z * q.y,
                             rot.w * q.y - rot.x * q.z + rot.y * q.w + rot.z * q.x, rot.w * q.z + rot.x * q.y - rot.y * q.x + rot.z * q.w)
    local base = tr:get_Position() + Vector3f.new(0, 1.6, 0)
    pcall(function() local hj = tr:call("getJointByName", "Head"); if hj then base = hj:get_Position() end end)
    local at = castT.anchor:get_Transform()
    local len = math.sqrt(fwd.x * fwd.x + fwd.z * fwd.z)
    local fx, fz = len > 0.001 and fwd.x / len or 0, len > 0.001 and fwd.z / len or 1
    -- (the character's right is (-fz, fx) of its flat forward: 2.46 had it the other way round)
    at:set_Position(base + Vector3f.new(fx * castT.frontDist - fz * castT.frontSide, castT.frontHeight, fz * castT.frontDist + fx * castT.frontSide))
    at:set_Rotation(r)
    at:set_LocalScale(Vector3f.new(castT.frontScale, castT.frontScale, castT.frontScale))
    return castT.anchor
end
-- which element / parts of the file show: the game's player's mask, groups and extern parameters onto our copy
function castT.copy_look(src, ep)
    if not src then return end
    local got = {}
    pcall(function() ep:call("set_EmitMaskBit", src:call("get_EmitMaskBit")); got[#got + 1] = "mask " .. tostring(src:call("get_EmitMaskBit")) end)
    pcall(function() local m = src:call("get_MaskName"); if m and tostring(m) ~= "" then ep:call("set_MaskName", m); got[#got + 1] = "name " .. tostring(m) end end)
    pcall(function() ep:call("set_GroupEnabled", src:call("get_GroupEnabled")) end)
    for _, kind in ipairs({ "GroupNames", "GroupParameters", "ExternParameters" }) do
        pcall(function()
            local n = src:call("get" .. kind .. "Count")
            if not n or n == 0 then return end
            ep:call("set" .. kind .. "Count", n)
            for q = 0, n - 1 do ep:call("set" .. kind, q, src:call("get" .. kind, q)) end
            got[#got + 1] = ("%d %s"):format(n, kind)
        end)
    end
    castT.lookInfo = table.concat(got, ", ")
end
-- the game's circle -> the same effect file(s) on our own effect players on the anchor; the game's copy is killed
function castT.move_front(a)
    for k = #(castT.frontPending or {}), 1, -1 do
        local e = castT.frontPending[k]
        local done = false
        local okM, errM = pcall(function()
            local list = e.c:call("getAllPlayers")
            local paths = {}
            e.src = {}
            local n = list and list:call("get_Count") or 0
            for q = 0, n - 1 do
                local pl = list:call("get_Item", q)
                local path
                for _, getter in ipairs({ function() return pl:call("get_Resource"):call("get_ResourcePath") end,
                                          function() return pl:call("get_ResourcePath") end }) do
                    if not path then
                        local ok, v = pcall(getter)
                        if ok and v and tostring(v) ~= "" then path = tostring(v) end
                    end
                end
                if path then paths[#paths + 1] = path; e.src = e.src or {}; e.src[#paths] = pl:add_ref() end
            end
            castT.frontInfo = ("%d effect player(s), %d file(s)"):format(n, #paths)
            if #paths == 0 then return end
            local go = castT.front(a)
            castT.res = castT.res or {}
            for pi, path in ipairs(paths) do
                if castT.res[path] == nil then
                    local r = sdk.create_resource("via.effect.EffectResource", path)
                    castT.res[path] = r and r:add_ref() or false
                end
                if castT.res[path] then
                    local child = make_anchor()   -- (one EffectPlayer per game object)
                    child:set_Name("Pactblade_cast_fx")
                    local ctr = child:get_Transform()
                    ctr:call("set_Parent", go:get_Transform())
                    ctr:set_LocalPosition(Vector3f.new(0, 0, 0))
                    ctr:set_LocalRotation(Quaternion.new(1, 0, 0, 0))
                    castT.frontGos = castT.frontGos or {}
                    table.insert(castT.frontGos, child)
                    local ep = child:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
                    ep:call("set_Resource", castT.res[path]:create_holder("via.effect.EffectResourceHolder"):add_ref())
                    castT.copy_look(e.src and e.src[pi], ep)
                    pcall(function() ep:call("set_AutoStart", true) end)
                    castT.frontPlayers = castT.frontPlayers or {}
                    table.insert(castT.frontPlayers, ep)
                end
            end
            e.c:call("killAll")
            castT.moved = (castT.moved or 0) + 1
            castT.frontInfo = ("moved %d effect(s) in front; last: %s"):format(castT.moved, paths[1]:match("([^/]+)$") or paths[1])
            done = true
        end)
        if not okM then castT.frontInfo = "move failed: " .. tostring(errM); done = true end
        if done then table.remove(castT.frontPending, k)
        elseif os.clock() - e.t > 0.5 then
            table.remove(castT.frontPending, k)
            castT.frontInfo = "an effect could not be moved (" .. tostring(castT.frontInfo) .. ")"
        end
    end
end
function castT.drop_front()   -- our players fade out, then our anchor goes (2 s later)
    castT.frontPending = nil
    if not castT.anchor then return end
    pcall(function()
        local fin = sdk.find_type_definition("via.effect.PlayerAction"):get_field("Finish"):get_data(nil)
        for _, ep in ipairs(castT.frontPlayers or {}) do pcall(function() ep:call("set_Action", fin) end) end
    end)
    castT.frontPlayers = nil
    local t = os.clock() + 2.0
    castT.dying = castT.dying or {}
    for _, child in ipairs(castT.frontGos or {}) do table.insert(castT.dying, { go = child, t = t }) end   -- (children first)
    table.insert(castT.dying, { go = castT.anchor, t = t + 0.1 })
    castT.frontGos, castT.anchor = nil, nil
end
re.on_frame(function()
    for k = #(castT.dying or {}), 1, -1 do
        local d = castT.dying[k]
        if os.clock() >= d.t then pcall(function() d.go:call("destroy(via.GameObject)", d.go) end); table.remove(castT.dying, k) end
    end
end)
re.on_script_reset(function()
    for _, child in ipairs(castT.frontGos or {}) do pcall(function() child:call("destroy(via.GameObject)", child) end) end
    if castT.anchor then local o = castT.anchor; pcall(function() o:call("destroy(via.GameObject)", o) end) end
    for _, d in ipairs(castT.dying or {}) do pcall(function() d.go:call("destroy(via.GameObject)", d.go) end) end
end)
function castT.fx(a, set, cont, el, front)
    local mgr = a.character:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    local conts, idx = mgr.ExternalDataContainers, nil
    for i = 0, conts:get_Count() - 1 do
        local ok, path = pcall(function() return tostring(conts[i].DataContainer:get_Path()) end)
        if ok and path:lower():find(set, 1, true) then idx = i end
    end
    if not idx then return set .. " not on this character" end
    local id = sdk.create_instance("via.effect.script.EffectID")
    id.DataContainerIndex = idx; id.ContainerID = cont; id.ElementID = el
    id.IsContainerIDOnly = false; id.IsElementIDOnly = false
    local c = mgr:call("requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)",
        id, a.character:get_GameObject(), -1, nil)
    if c then
        castT.conts = castT.conts or {}
        table.insert(castT.conts, c:add_ref())
        if front then   -- moved in front of the chest as soon as its files are known (castT.move_front)
            castT.frontPending = castT.frontPending or {}
            table.insert(castT.frontPending, { c = c:add_ref(), t = os.clock() })
        end
    end
    return c and "ok" or "no effect"
end
castT.STEPS = {
    { t = 0.0, fx = { { "ch03/13_ch03_ns", 0, 40, true }, { "ch03/13_ch03_cs", 0, 104, true } }, snd = 2921097576, motion = 710 },
    { t = 0.2, snd = 3366100101, loop = true },
    { t = 0.4, fx = { { "ch03/13_ch03_cs", 0, 304, true } }, motion = 712 },   -- (true: in front of the chest)
}
castT.LOOP = 3366100101   -- the chant loop (a looping sound: triggered once, stopped at the release)
castT.STOP = 2605810471   -- the sound that ends the chant (user found it in the recorded cast: 2.16)
-- sheathing during the chant: the chant ends (no release)
function castT.cancel(a, why)
    if not castT.t0 then return end
    castT.onRelease = nil
    for _, c in ipairs(castT.conts or {}) do pcall(function() c:call("finishAll") end) end
    castT.drop_front()
    if combo.cue_sound then pcall(combo.cue_sound, a, castT.STOP) end
    castT.fsm(a, false)
    castT.t0, castT.released = nil, false
    castT.info = "cancelled: " .. tostring(why)
    if castT.onEnd then local f = castT.onEnd; castT.onEnd = nil; pcall(f, a) end
end
function castT.start(a)
    if castT.t0 then return end
    castT.bank(a)
    if not castT.ready(a) then castT.info = "animations loading - press again in a moment"; return end
    castT.t0, castT.step, castT.conts, castT.log, castT.moved, castT.cancelWith = os.clock(), 1, {}, {}, 0, nil
    castT.fsm(a, true)
end
re.on_pre_application_entry("UpdateBehavior", function()
    if not castT.t0 then return end
    local a = runtime.player()
    if not a then return end
    local t = os.clock() - castT.t0
    if a:button_pressed("Sheathe") then castT.cancel(a, "sheathe pressed"); return end   -- (user: sheathing cancels)
    pcall(function()
        while castT.STEPS[castT.step] and t >= castT.STEPS[castT.step].t do
            local st = castT.STEPS[castT.step]
            if st.motion then pcall(castT.play, a, st.motion) end
            for _, f in ipairs(st.fx or {}) do
                local ok, r = pcall(castT.fx, a, f[1], f[2], f[3], f[4])
                castT.log[#castT.log + 1] = ("fx %s %d/%d: %s"):format(f[1], f[2], f[3], tostring(ok and r or r))
            end
            if st.snd and combo.cue_sound and (not st.loop or castT.loopOn) then
                local ok, r = pcall(combo.cue_sound, a, st.snd)
                castT.log[#castT.log + 1] = ("sound %d: %s"):format(st.snd, tostring(ok and r or r))
            end
            castT.step = castT.step + 1
        end
        if castT.frontPending and #castT.frontPending > 0 then pcall(castT.move_front, a) end
        if castT.anchor then pcall(castT.front, a) end   -- the circle stays in front
        -- keep the chant looping
        local L = a.character:get_Motion():getLayer(0)
        if t < castT.secs and t > 0.4 and (L:get_MotionBankID() ~= castT.BANK or L:get_MotionID() ~= 712) then castT.play(a, 712, 6.0) end
        if t >= castT.secs and not castT.released then   -- ready flash + chime, release motion
            castT.released = true
            for _, f in ipairs({ { "ch03/13_ch03_ns", 0, 41, true }, { "ch03/13_ch03_cs", 0, 3, true } }) do pcall(castT.fx, a, f[1], f[2], f[3], f[4]) end
            if combo.cue_sound then pcall(combo.cue_sound, a, 3990051307) end
            if combo.cue_sound then pcall(combo.cue_sound, a, castT.STOP) end
            castT.play(a, 750, 6.0)
            if castT.onRelease then local f = castT.onRelease; castT.onRelease = nil; pcall(f, a) end
        end
        if t >= castT.secs + 0.9 then
            for _, c in ipairs(castT.conts or {}) do pcall(function() c:call("finishAll") end) end
            castT.drop_front()
            if combo.cue_sound then pcall(combo.cue_sound, a, castT.STOP) end   -- (in case the release was skipped)
            castT.fsm(a, false)
            castT.ourReq = true
            pcall(function() a:request_action("NormalLocomotion", 0) end)
            castT.ourReq = false
            castT.t0, castT.released = nil, false
            castT.info = table.concat(castT.log, " | ")
            if castT.onEnd then local f = castT.onEnd; castT.onEnd = nil; pcall(f, a) end
        end
    end)
end)

------------------------------------------------------------------------
-- TASHA'S CAUSTIC BREW (user's skill, in Full Moon Slash's slot)
--   The recorded Mage chant (castT, 3 s). At the release the green acid (our pb_acid_v3 effect, 8 copies over 15 m)
--   pours forward from 1 m ahead, a splash sound at every splash. The damage: every 0.3 s the enemies inside the
--   acid's strip take a little damage (HitManager.directDamage) and poison build-up (own meter: 100 = poisoned).
------------------------------------------------------------------------
;(function()
local sk = { castSecs = 3.0, ahead = 1.0, lingerSecs = 5.0, halfWidth = 1.25, tickSecs = 0.3, tickDmg = 72, poisonPts = 35, stagger = false,
             file = "pactblade/pb_acid_v3", info = "-", lastPress = -10, hitCount = 0, meters = {}, poisonQ = {} }
dbg.brew = sk   -- (the menu reaches it through dbg)

-- the look: our acid effect on anchors, a wave of 8 copies 1.9 m apart, 0.07 s after each other
local acidRes, acidLive = nil, {}
local function acid_at(pos, rot)
    if acidRes == nil then
        local r = sdk.create_resource("via.effect.EffectResource", "vfx/effects/" .. sk.file .. ".efx")
        acidRes = r and r:add_ref() or false
    end
    if not acidRes then sk.info = "acid effect not found (restart the game for the effect pak)"; return nil end
    local go = make_anchor()
    go:set_Name("Pactblade_acid")
    local tr = go:get_Transform()
    tr:set_Position(pos)
    tr:set_Rotation(rot)
    local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
    ep:call("set_Resource", acidRes:create_holder("via.effect.EffectResourceHolder"):add_ref())
    pcall(function() ep:call("set_AutoStart", true) end)
    table.insert(acidLive, { go = go, dieAt = os.clock() + 6 })
    return go
end
re.on_frame(function()
    local w = sk.wave
    if w then
        local due = math.floor((os.clock() - w.t0) / 0.07) + 1
        while w.n < math.min(due, 8) do
            w.n = w.n + 1
            local d = sk.ahead + (w.n - 1) * 1.9
            local g = acid_at(Vector3f.new(w.pos.x + w.fx * d, w.pos.y, w.pos.z + w.fz * d), w.rot)
            if g then pcall(sk.play, sk.splashSnd(), g:get_Transform():get_Position(), "splash") end
        end
        if w.n >= 8 then sk.wave = nil end
    end
    for k = #acidLive, 1, -1 do
        if os.clock() > acidLive[k].dieAt then
            pcall(function() acidLive[k].go:call("destroy(via.GameObject)", acidLive[k].go) end)
            table.remove(acidLive, k)
        end
    end
end)

-- sounds: my own (combo.cue_sound, the chant's way) or the acid monster's (its projectile sound set, loaded by the game)
-- a trigger's info in a container: its own list, or the trigger lists of the sound sets loaded into it
local function find_info(c, id)
    local found
    pcall(function()
        local l = c._TriggerInfoList
        for k = 0, l._size - 1 do if l._items[k] and l._items[k]._TriggerId == id then found = l._items[k]; return end end
    end)
    if found then return found end
    pcall(function()
        local L = c["<AllTriggerInfoListData>k__BackingField"]
        for k = 0, L._size - 1 do
            local items = L._items[k] and L._items[k]._TriggerInfoList
            for q = 0, (items and items._size or 0) - 1 do
                if items._items[q] and items._items[q]._TriggerId == id then found = items._items[q]; return end
            end
        end
    end)
    return found
end
local REQ_INFO = "createRequestInfo(soundlib.SoundTriggerInfo, via.GameObject, via.GameObject, System.UInt32, System.Boolean, System.Boolean, System.UInt32, via.simplewwise.CallbackType, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>)"
-- a trigger played as cue_sound plays mine: a request made from its info, sent through the container
local request_play
dbg.snd_find_info = find_info
function request_play(c, info, go)
    local req = c:call(REQ_INFO, info, go, go, info._OffsetJointHash, false, false, 0, 0, nil, nil, nil, nil)
    if not req then return "no request" end
    req = req:add_ref()
    req["<Container>k__BackingField"] = c
    c:call("trigger(soundlib.SoundManager.RequestInfo)", req)
    return "asked"
end
-- the acid monster's projectile sound set (its trigger lists + banks: ch254001_fx, ch221000_fx)
dbg.snd_request = request_play
sk.SOUNDSET = "Sound/Resource/EM/ch254001/Containers/shl_ch254001_fx_ContainerListData.user"
sk.SPLASH = { src = "monster", id = 3870869112, label = "monster splash (random: B 02 / 06 / 08 / 10)" }
sk.pool, sk.poolNext = {}, 1
local function sound_set()
    if sk.soundSet == nil then
        local ud = sdk.create_userdata("soundlib.SoundContainerListData", sk.SOUNDSET)
        sk.soundSet = ud and ud:add_ref() or false
    end
    return sk.soundSet or nil
end
local function pool_clear()
    for _, e in ipairs(sk.pool) do local o = e.go; pcall(function() o:call("destroy(via.GameObject)", o) end) end
    sk.pool, sk.poolNext = {}, 1
end
-- the set into my own container (once per character) and 8 fresh sound objects of ours, one per splash (made anew for every cast:
-- nothing old is touched after a scene change)
function sk.prepare_sounds(a)
    local set = sound_set()
    if not set then sk.sndInfo = "the monster's sound set was not found"; return end
    local go = a.character:get_GameObject()
    if sk.soundsFor ~= go:get_address() then
        for _, c in ipairs(go:call("get_Components"):get_elements()) do
            if c:get_type_definition():get_full_name() == "app.WwiseContainerApp" then
                c:call("loadContainableUserData", set)
                sk.soundsFor = go:get_address()
                break
            end
        end
    end
    pool_clear()
    local at = go:get_Transform():get_Position()
    for k = 1, 8 do
        local o = make_anchor()
        o:set_Name("Pactblade_sound")
        o:get_Transform():set_Position(at)
        local c = o:call("createComponent(System.Type)", sdk.typeof("app.WwiseContainerApp")):add_ref()
        pcall(function() c._UserDataList:call("Add", set) end)
        pcall(c.call, c, "loadContainableUserData", set)
        sk.pool[k] = { go = o, c = c }
    end
end
-- one sound of the set at a spot: the next sound object goes there and plays it (else from my own container)
local function play_at_spot(a, id, pos)
    local e = sk.pool[sk.poolNext]
    sk.poolNext = sk.poolNext % math.max(1, #sk.pool) + 1
    if e and pos then
        local info = find_info(e.c, id)
        if info then
            e.go:get_Transform():set_Position(pos)
            return "at the spot: " .. request_play(e.c, info, e.go)
        end
    end
    local go = a.character:get_GameObject()
    for _, c in ipairs(go:call("get_Components"):get_elements()) do
        if c:get_type_definition():get_full_name() == "app.WwiseContainerApp" then
            local info = find_info(c, id)
            if info then return "from me: " .. request_play(c, info, go) end
        end
    end
    return "not loaded yet (the sounds load when the chant starts)"
end
re.on_script_reset(pool_clear)
function sk.play(snd, pos, what)
    if not snd then sk.sndInfo = "no " .. (what or "") .. " sound picked"; return end
    local a = runtime.player()
    if not a then return end
    local r
    if snd.src == "player" then
        r = tostring(combo.cue_sound(a, snd.id))
    else
        if #sk.pool == 0 then pcall(sk.prepare_sounds, a) end
        local ok, rr = pcall(play_at_spot, a, snd.id, pos)
        r = tostring(rr)
    end
    sk.sndInfo = ("%s %d (%s): %s"):format(what or "sound", snd.id, snd.label or snd.src, r)
end
-- picked: { src = "player" | "monster" | "obj" | "vase", id, label } (saved: the container itself is never kept)
local function saved_pick(c) return c and type(c.id) == "number" and { src = c.src or "obj", id = c.id, label = c.label } or nil end
sk.releaseSnd, sk.pourSnd = saved_pick(cfg.brewLand), saved_pick(cfg.brewPour)
if not sk.pourSnd or sk.pourSnd.src == "vase" then sk.pourSnd = sk.SPLASH end   -- (the vase's sound: pottery, not a splash)
function sk.splashSnd() return sk.pourSnd end
-- every sound of the last recording, once each
function sk.candidates()
    local out, seen = {}, {}
    for _, e in ipairs(dbg.rec.list) do
        if e.sound then
            local key = (e.obj or "player") .. "/" .. e.sound
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = { src = e.obj and "obj" or "player", id = e.sound, label = (e.obj or "me") .. " " .. e.sound }
            end
        end
    end
    return out
end

function sk.poison_value()
    if sk.poison ~= nil then return sk.poison end
    sk.poison = false
    pcall(function()
        for _, f in ipairs(sdk.find_type_definition("app.StatusConditionDef.StatusConditionEnum"):get_fields()) do
            if f:is_static() and f:get_name() == "Poison" then sk.poison = f:get_data(nil) end
        end
    end)
    return sk.poison
end
local APPLY_STATUS = "reqStatusConditionApplyCore(app.StatusConditionDef.StatusConditionEnum, app.HitController.DamageInfo, app.StatusConditionDef.RequestInfo, System.Boolean)"
-- the damage: enemies in the acid's strip (from 1 m ahead to where the wave has got, sk.halfWidth to each side,
-- 2.5 m up / down) take sk.tickDmg and sk.poisonPts on their poison meter - called every sk.tickSecs while the acid lies
function sk.tick(a)
    local ar = sk.area
    local reach = math.min(sk.ahead + 7 * 1.9 + 1.0, sk.ahead + (os.clock() - ar.t0) / 0.07 * 1.9 + 1.0)   -- the wave's front
    local list = sdk.get_managed_singleton("app.EnemyManager")._EnemyList
    local hm = sdk.get_managed_singleton("app.HitManager")
    local me, myHit = a.character:get_GameObject(), a.character["<Hit>k__BackingField"]
    for k = 0, list._size - 1 do
        pcall(function()
            local ch = list._items[k] and list._items[k]._Chara
            local hit = ch and ch["<Hit>k__BackingField"]
            if not hit or hit:get_Hp() <= 0 then return end
            local p = (ch.Hip or ch["<Transform>k__BackingField"]):get_Position()
            local dx, dz = p.x - ar.pos.x, p.z - ar.pos.z
            local along, side = dx * ar.fx + dz * ar.fz, math.abs(dx * ar.fz - dz * ar.fx)
            if along < sk.ahead - 1.0 or along > reach or side > sk.halfWidth or math.abs(p.y - ar.pos.y) > 2.5 then return end
            local info = sdk.create_instance("app.HitController.DamageInfo"):add_ref()
            info.Damage = sk.tickDmg
            if sk.stagger and not ar.staggered[ch:get_address()] then   -- (test) one flinch per enemy
                ar.staggered[ch:get_address()] = true
                info.DamageType, info.DamageActType, info.IsDirectDamageEnableAllDamageType = 6, 6, true   -- Hitback_M
            end
            local ok = pcall(hm.call, hm, "directDamage", info, hit, me, false, myHit)
            if not ok then hm:call("directDamage", info, hit, nil, false, nil) end
            sk.hitCount = sk.hitCount + 1
            local key, now = ch:get_address(), os.clock()
            local m = sk.meters[key]
            if not m or now - m.at > 10 then m = { value = 0 } end
            m.value, m.at = m.value + sk.poisonPts, now
            if m.value >= 100 then m.value = 0; sk.poisonQ[#sk.poisonQ + 1] = ch:add_ref() end
            sk.meters[key] = m
        end)
    end
end
-- the chant is over: the acid pours and starts to hurt
function sk.release(a)
    local tr = a.character:get_GameObject():get_Transform()
    local pos, rot = tr:get_Position(), tr:get_Rotation()
    local fwd = rot * Vector3f.new(0, 0, 1)
    local len = math.sqrt(fwd.x * fwd.x + fwd.z * fwd.z)
    local fx, fz = len > 0.001 and fwd.x / len or 0, len > 0.001 and fwd.z / len or 1
    local yaw = math.atan(fx, fz)
    pcall(sk.play, sk.releaseSnd, nil, "release")
    sk.area = { pos = pos, fx = fx, fz = fz, t0 = os.clock(), nextT = os.clock() + 0.25, staggered = {} }
    sk.info = "acid out"
    sk.wave = { pos = pos, rot = Quaternion.new(math.cos(yaw / 2), 0, math.sin(yaw / 2), 0), fx = fx, fz = fz, t0 = os.clock(), n = 0 }
    sk.stage, sk.t0 = "pour", os.clock()
end
function sk.finish(why)
    sk.stage, sk.on, sk.wave, sk.area = nil, false, nil, nil
    if why then sk.info = why end
end
re.on_application_entry("LateUpdateBehavior", function()
    for k = #sk.poisonQ, 1, -1 do   -- poison, asked outside the damage calculation
        local ch = table.remove(sk.poisonQ, k)
        pcall(function()
            if ch:get_IsDead() then return end
            local req = sdk.create_instance("app.StatusConditionDef.RequestInfo"):add_ref()
            ch["<StatusConditionCtrl>k__BackingField"]:call(APPLY_STATUS, sk.poison_value(), nil, req, false)
            sk.poisoned = (sk.poisoned or 0) + 1
            sk.ourPoison[ch:get_address()] = os.clock()
        end)
    end
    if sk.area and os.clock() >= sk.area.nextT then
        sk.area.nextT = os.clock() + sk.tickSecs
        local a = runtime.player()
        if a then
            local okT, eT = pcall(sk.tick, a)
            if not okT then sk.info = "damage failed: " .. tostring(eT) end
        end
    end
    if sk.stage == "pour" and os.clock() - sk.t0 >= sk.lingerSecs then
        sk.finish(("done: %d hit(s) on enemies, %d poisoned"):format(sk.hitCount, sk.poisoned or 0))
    end
end)
-- the press: the chant starts as soon as its animations are loaded (first time: a moment)
re.on_pre_application_entry("UpdateBehavior", function()
    if not sk.want then return end
    local a = runtime.player()
    if not a or not live.on then sk.want = false; return end
    if castT.t0 or combo.stage ~= 0 then return end
    castT.secs = sk.castSecs
    local okS, eS = pcall(castT.start, a)
    if okS and castT.t0 then
        sk.want, sk.on, sk.stage, sk.hitCount, sk.poisoned = false, true, "cast", 0, 0
        pcall(sk.prepare_sounds, a)   -- (loaded by the release, 3 s later)
        castT.onRelease = sk.release
        castT.onEnd = function() if sk.stage == "cast" then sk.finish("the chant ended without a release") end end
        sk.info = "chanting"
    elseif os.clock() - sk.wantT > 2.5 then
        sk.want = false
        sk.info = "could not start: " .. tostring(okS and castT.info or eS)
    end
end)
re.on_script_reset(function() sk.finish() end)
-- our poison hurts sk.poisonMul x as much: the game's poison ticks on enemies Caustic Brew poisoned
sk.ourPoison, sk.poisonMul, sk.poisonTicks = {}, 2.0, 0
pcall(function()
    sdk.hook(sdk.find_type_definition("app.StatusConditionActionSlipDamage"):get_method("setDirectDamage(System.Single, System.Boolean, app.StatusConditionInfo)"),
        function(args)
            if sk.poisonMul == 1 or next(sk.ourPoison) == nil then return end
            pcall(function()
                local act = sdk.to_managed_object(args[2])
                local ch = act["<OwnerCharacter>k__BackingField"]
                local at = ch and sk.ourPoison[ch:get_address()]
                if not at then return end
                if os.clock() - at > 120 then sk.ourPoison[ch:get_address()] = nil; return end
                if (act.ActionParam._ElementType or 0) ~= 0 then return end   -- (burning: fire)
                args[3] = sdk.float_to_ptr(sdk.to_float(args[3]) * sk.poisonMul)
                sk.poisonTicks = sk.poisonTicks + 1
            end)
        end, function(r) return r end)
end)
local FULLMOON_ID = -1
pcall(function()
    for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if f:is_static() and f:get_name() == "Job01_FullMoonSlash" then FULLMOON_ID = f:get_data(nil) & 0xFFFFFFFF end
    end
end)
function sk.press()
    local now = os.clock()
    if sk.on or sk.want or now - sk.lastPress < 0.6 then return end
    local can = false
    pcall(function()
        local track = runtime.player().character:get_Human().Track
        can = track.All or track.Skill
    end)
    if can then sk.lastPress, sk.want, sk.wantT = now, true, now end
end
pcall(function()
    local SIG = "processCustomSkill(app.HumanCustomSkillID, System.UInt64, app.LockOnController.Option, System.Boolean, System.Boolean, System.Boolean, app.LocomotionSpeedTypeEnum, System.Boolean)"
    sdk.hook(sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method(SIG), function(args)
        if not live.on then return end
        if (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= FULLMOON_ID then return end
        sk.press()
        return sdk.PreHookResult.SKIP_ORIGINAL   -- the vanilla skill never plays
    end, function(r) return r end)
end)
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if not live.on then return end
            local skip = false
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if not name:find("^Job01_FullMoonSlash") then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                skip = true
                sk.press()
            end)
            if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r) return r end)
end)
end)()

------------------------------------------------------------------------
-- ELDRITCH SMITE (user's skill): Warrior's short-range heavy attack (0 - 66.6) into Arc of Obliteration's end (from 50,
-- 1.5x from 150, back to normal locomotion at 347). In Burst Strike's slot (Job01_BlinkStrike), rebindable from the menu.
------------------------------------------------------------------------
;(function()
local sm = { info = "-", lastPress = -10, fast = 1.5,
             PARTS = { { action = "Job05_ShortRangeHeavyAttack", from = 0.0, to = 66.6 },
                       { action = "Job05_ArcOfObliterationEnd", from = 50.0, fastFrom = 150.0, to = 347.0 } } }
sm.blend = 12   -- frames of crossfade into a part's start frame
local CHANGE = "changeMotion(System.UInt32, System.UInt32, System.Single, System.Single, via.motion.InterpolationMode, via.motion.InterpolationCurve)"
dbg.smite = sm
-- the skill ids (app.HumanCustomSkillID) by name and the other way round
local IDS, NAMES = {}, {}
pcall(function()
    for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if f:is_static() then
            local ok, v = pcall(f.get_data, f, nil)
            if ok and type(v) == "number" then IDS[f:get_name()] = v & 0xFFFFFFFF; NAMES[v & 0xFFFFFFFF] = f:get_name() end
        end
    end
end)
local function request(a, name)
    sm.ourReq = true
    local ok = a:request_action(name, 0)
    sm.ourReq = false
    return ok
end
local function mkey(L) return L:call("get_MotionBankID") * 100000 + L:call("get_MotionID") end
sm.boomScale, sm.boomFx = 1.5, "-1/8/43"   -- (user: 60 % of 2.5)
sm.lightOn, sm.lightUntil, sm.lightLm, sm.lightRadius = true, 132, 562, 3.0   -- (user's values, 2026-10-23)
sm.lookAfter = 0.3   -- (user: the smite look from 0.3 s into the first animation; the light follows the look)
sm.lookUntil = 86    -- (user: ... until about frame 86 of the second animation)
sm.lookExtra = 0.2   -- (user: and 0.2 s longer)
sm.downType, sm.downPower = 15, 100   -- (user: every enemy knocked down: Slam_L, stagger x100)
sm.chargeDelay = -0.2  -- s from the smite look's start; minus = sooner, down to the smite's start (user: a bit sooner)
local function my_smite_hit(info)
    if not sm.stage or not live.on then return false end
    local hc = info:get_AttackHitController()
    return hc ~= nil and hc:get_GameObject():get_address() == live.go
end
pcall(function()
    sdk.hook(sdk.find_type_definition("app.HitController"):get_method("getReactionDamageType(app.HitController.DamageInfo)"),
        function(args)
            local st = thread.get_hook_storage()
            st.smDown = nil
            if not sm.stage then return end
            pcall(function()
                local info = sdk.to_managed_object(args[3])
                if my_smite_hit(info) then st.smDown = info end
            end)
        end, function(r)
            local st = thread.get_hook_storage()
            local info = st.smDown
            st.smDown = nil
            if not info then return r end
            pcall(function() info.DamageType, info.DamageActType, info.OverwriteBlownType = sm.downType, sm.downType, sm.downType end)
            sm.downs = (sm.downs or 0) + 1
            return sdk.to_ptr(sm.downType)
        end)
end)
pcall(function()
    sdk.hook(sdk.find_type_definition("app.HitController"):get_method("calcDamageReaction(app.HitController.DamageInfo)"),
        function(args)
            local st = thread.get_hook_storage()
            st.smPow = nil
            if not sm.stage then return end
            pcall(function()
                local info = sdk.to_managed_object(args[3])
                if my_smite_hit(info) then st.smPow = info end
            end)
        end, function(r)
            local st = thread.get_hook_storage()
            local info = st.smPow
            st.smPow = nil
            if info then pcall(function() info.DamageReaction = info.DamageReaction * sm.downPower end) end
            return r
        end)
end)
-- Mystic Spearhand's whole-body charge look: its RimLight material mode, recoloured
sm.RIM = { mode = 1704633256, cat = 8, secs = 1.0 }   -- (user: a ~1 s pulse, just a signal)
local RIM_REQ = "requestMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
local RIM_FIN = "finishMaterialMode(System.UInt32, app.MaterialInterpolationRequestManager.RequestListCategory, System.Int32, System.Int32)"
local function pick_hue()
    local gv = tostring(cfg.glowVariant or "")
    return tonumber(gv:match("^ppb?(%d+)$") or gv:match("^h(%d+)g%d$") or "") or 285
end
function dbg.rim_glow(a, on, secs)
    local go = a.character:get_GameObject()
    local mgr = go:call("getComponent(System.Type)", sdk.typeof("app.MaterialInterpolationRequestManager"))
    if not mgr then return end
    if on then
        mgr:call(RIM_REQ, sm.RIM.mode, sm.RIM.cat, -1, -1)
        sm.rimOn, sm.rimOffAt = true, os.clock() + (secs or sm.RIM.secs)   -- (a pulse: off again by itself)
        -- its colour slots in my meshes (looked up anew each time: equipment changes)
        sm.rimEntries = {}
        for _, mesh in ipairs(dbg.ai.meshes(go)) do
            pcall(function()
                for m = 0, mesh:call("get_MaterialNum") - 1 do
                    for _, nm in ipairs({ "RimLight_Emissive_Color_A", "RimLight_Emissive_Color_B" }) do
                        pcall(function()
                            local v = mesh:call("getMaterialVariableIndex", m, nameHash:call(nil, nm))
                            if v == nil or v >= 65535 then return end
                            mesh:call("getMaterialFloat4(System.UInt32, System.UInt32)", m, v)   -- (3.07: only slots that read)
                            sm.rimEntries[#sm.rimEntries + 1] = { mesh = mesh:add_ref(), m = m, v = v }
                        end)
                    end
                end
            end)
        end
    elseif sm.rimOn then
        mgr:call(RIM_FIN, sm.RIM.mode, sm.RIM.cat, -1, -1)
        sm.rimOn = false
    end
end
-- my rim-light colour slots (equipment changes: looked up anew each time) and their colour turned to a hue
function dbg.rim_entries(go)
    local out = {}
    for _, mesh in ipairs(dbg.ai.meshes(go)) do
        pcall(function()
            for m = 0, mesh:call("get_MaterialNum") - 1 do
                for _, nm in ipairs({ "RimLight_Emissive_Color_A", "RimLight_Emissive_Color_B" }) do
                    pcall(function()
                        local v = mesh:call("getMaterialVariableIndex", m, nameHash:call(nil, nm))
                        if v == nil or v >= 65535 then return end
                        mesh:call("getMaterialFloat4(System.UInt32, System.UInt32)", m, v)   -- (3.07: only slots that read)
                        out[#out + 1] = { mesh = mesh:add_ref(), m = m, v = v }
                    end)
                end
            end
        end)
    end
    return out
end
function dbg.rim_paint(entries, hue)
    for i = #entries, 1, -1 do   -- (a slot that fails is dropped, never read again)
        local e = entries[i]
        local ok = pcall(function()
            local f = e.mesh:call("getMaterialFloat4(System.UInt32, System.UInt32)", e.m, e.v)
            local h, s0, v = dbg.ai.hsv(f.x, f.y, f.z)
            if v <= 0.001 or s0 < 0.2 or (h > 250 and h < 330) then return end   -- (dark / white / already ours)
            local r, g, b = dbg.ai.rgb(hue, s0, v)
            e.mesh:call("setMaterialFloat4(System.UInt32, System.UInt32, via.Float4)", e.m, e.v, Vector4f.new(r, g, b, f.w))
        end)
        if not ok then table.remove(entries, i) end
    end
end
re.on_pre_application_entry("BeginRendering", function()
    if sm.rimOffAt and os.clock() >= sm.rimOffAt then
        sm.rimOffAt = nil
        local a = runtime.player()
        if a then pcall(dbg.rim_glow, a, false) end
    end
    if not sm.rimOn or not sm.rimEntries then return end
    local hue = pick_hue()
    for i = #sm.rimEntries, 1, -1 do   -- the game's teal, turned to our hue (its own strength kept)
        local e = sm.rimEntries[i]
        local ok = pcall(function()
            local f = e.mesh:call("getMaterialFloat4(System.UInt32, System.UInt32)", e.m, e.v)
            local h, s0, v = dbg.ai.hsv(f.x, f.y, f.z)
            if v <= 0.001 then return end
            local r, g, b = dbg.ai.rgb(hue, s0, v)
            e.mesh:call("setMaterialFloat4(System.UInt32, System.UInt32, via.Float4)", e.m, e.v, Vector4f.new(r, g, b, f.w))
        end)
        if not ok then table.remove(sm.rimEntries, i) end
    end
end)
-- our own sounds (x0005-PactbladeSounds.pak): loaded into my sound container once per character
-- (2.66 diagnosis: our banks load fine; through a container list nothing joins my container, but our trigger list loaded
-- DIRECTLY does: lists 40 -> 41 - and the sounds played. So both lists are loaded directly.)
sm.SND = { lists = { { "soundlib.SoundBankListData", "Sound/Resource/pactblade/pactblade_fx_BankListData.user", load = true },
                     { "soundlib.SoundTriggerInfoListData", "Sound/Resource/pactblade/pactblade_fx_TriggerInfoListData.user", load = true } },
           charge = 199459528, hit = 3434957627 }
local function my_container(a)
    for _, c in ipairs(a.character:get_GameObject():call("get_Components"):get_elements()) do
        if c:get_type_definition():get_full_name() == "app.WwiseContainerApp" then return c end
    end
end
sm.my_container = my_container   -- (the menu's diagnosis uses it)
function sm.load_sounds(a)
    local go = a.character:get_GameObject()
    local c = my_container(a)
    -- loaded = our charge trigger really is in my container (the game rebuilds it, e.g. when a save loads - 2.70)
    if c and dbg.snd_find_info and dbg.snd_find_info(c, sm.SND.charge) then sm.soundsFor = go:get_address(); return end
    if not c then sm.sndInfo = "no sound container (?)"; return end
    sm.sets = sm.sets or {}
    local got = {}
    for _, l in ipairs(sm.SND.lists) do
        if not sm.sets[l[2]] then
            local ud = sdk.create_userdata(l[1], l[2])
            if ud then sm.sets[l[2]] = ud:add_ref() end
        end
        if sm.sets[l[2]] then
            if l.load then
                -- (still in its list of sets after the game rebuilt the container -> the load would be skipped)
                pcall(function() c._UserDataList:call("Remove", sm.sets[l[2]]) end)
                c:call("loadContainableUserData", sm.sets[l[2]])
            end
            got[#got + 1] = l[2]:match("([^/]+)$")
        end
    end
    local inIt = dbg.snd_find_info and dbg.snd_find_info(c, sm.SND.charge) ~= nil
    if inIt then sm.soundsFor = go:get_address() end
    sm.loadInfo = #got < #sm.SND.lists and "our sound files were NOT found"
        or (inIt and "our sounds are in my sound container" or "loaded, but our sounds did not join my container (retried every 5 s)")
end
-- loaded early (once Pactblade is on), so the first smite already has them (the first play after loading can be silent)
re.on_frame(function()   -- (checked every 5 s: back in if the game threw them out)
    if not live.on or os.clock() < (sm.nextLoadTry or 0) then return end
    sm.nextLoadTry = os.clock() + 5
    local a = runtime.player()
    if a then pcall(sm.load_sounds, a) end
end)
function sm.sound(a, id, what)
    pcall(sm.load_sounds, a)
    local c = my_container(a)
    local info = c and dbg.snd_find_info and dbg.snd_find_info(c, id)
    if not info then
        local lists, ours = -1, false
        pcall(function()
            local L = c["<AllTriggerInfoListData>k__BackingField"]
            lists = L._size
        end)
        sm.sndInfo = ("%s sound: not in my container yet (%s; %d trigger lists in it)"):format(what, tostring(sm.loadInfo), lists)
        return
    end
    local ok, r = pcall(dbg.snd_request, c, info, a.character:get_GameObject())
    sm.sndInfo = what .. " sound: " .. tostring(ok and r or r)
end
-- the blade's light: our point light on the held sword (switched on / off, never destroyed while the script runs)
function sm.light(on)
    if not on then
        if sm.L then pcall(function() sm.L.comp:call("set_Enabled", false) end) end
        return
    end
    if not sm.L then
        local go = make_anchor()
        go:set_Name("Pactblade_smite_light")
        local comp = go:call("createComponent(System.Type)", sdk.typeof("via.render.PointLight"))
        if not comp then return end
        sm.L = { go = go, comp = comp:add_ref() }
        pcall(function() sm.L.comp:call("set_ShadowEnable", false) end)
    end
    pcall(function()
        local _, sgo = held_sword()
        if sgo then sm.L.go:get_Transform():set_Position(sgo:get_Transform():get_Position()) end
        local r, g, b = dbg.nox_look()
        local mx = math.max(r, g, b, 1)
        sm.L.comp:call("set_Color", Vector3f.new(r / mx, g / mx, b / mx))
        sm.L.comp:call("set_Intensity", sm.lightLm + 0.0)
        sm.L.comp:call("set_Radius", sm.lightRadius + 0.0)
        sm.L.comp:call("set_Enabled", true)
    end)
end
re.on_script_reset(function() if sm.L then local o = sm.L.go; pcall(function() o:call("destroy(via.GameObject)", o) end) end end)
-- the saved settings (cfg.smite) <-> sm / NOX
sm.KEYS = { "fast", "blend", "boomScale", "boomFx", "lightOn", "lightUntil", "lightLm", "lightRadius", "chargeDelay" }
for _, k in ipairs(sm.KEYS) do if cfg.smite and cfg.smite[k] ~= nil then sm[k] = cfg.smite[k] end end
if cfg.smite and type(cfg.smite.boostGlow) == "number" then dbg.NOX.boostGlow = cfg.smite.boostGlow end
if cfg.smite and not cfg.smite.cdSooner then sm.chargeDelay = -0.2; cfg.smite.cdSooner = true end   -- (once: user, sooner)
if not (cfg.smite and cfg.smite.userSet) then   -- once: the user's screenshot values (2.59 may have saved the old defaults)
    sm.fast, sm.blend, sm.boomScale, sm.boomFx = 1.5, 12, 1.5, "-1/8/43"
    sm.lightOn, sm.lightUntil, sm.lightLm, sm.lightRadius = true, 132, 562, 3.0
    dbg.NOX.boostGlow = 2.5
    cfg.smite = cfg.smite or {}
    cfg.smite.userSet = true
    pcall(function() for _, k in ipairs(sm.KEYS) do cfg.smite[k] = sm[k] end; cfg.smite.boostGlow = 2.5; save_cfg() end)
end
function sm.save()
    cfg.smite = cfg.smite or {}
    for _, k in ipairs(sm.KEYS) do cfg.smite[k] = sm[k] end
    cfg.smite.boostGlow = dbg.NOX.boostGlow
    save_cfg()
end
-- Mystic Spearhand's charge-complete body effect (ch07 ns 25/50) on the player, its "Charge" colour in the picker's hue
local function pick_rgb()
    local gv = tostring(cfg.glowVariant or "")
    local hue = tonumber(gv:match("^ppb?(%d+)$") or gv:match("^h(%d+)g%d$") or "") or 285
    local h = (hue % 360) / 60
    local x = 1 - math.abs(h % 2 - 1)
    local t = ({ { 1, x, 0 }, { x, 1, 0 }, { 0, 1, x }, { 0, x, 1 }, { x, 0, 1 }, { 1, 0, x } })[math.floor(h) + 1]
    return t[1], t[2], t[3]
end
sm.chargeFx = {}   -- { c, untilT }
function dbg.charge_fx(a)
    local mgr = a.character:get_GameObject():call("getComponent(System.Type)", sdk.typeof("via.effect.script.ObjectEffectManager2"))
    local conts, idx = mgr.ExternalDataContainers, nil
    for i = 0, conts:get_Count() - 1 do
        local ok, path = pcall(function() return tostring(conts[i].DataContainer:get_Path()) end)
        if ok and path:lower():find("ch07/13_ch07_ns", 1, true) then idx = i end
    end
    if not idx then sm.info = "Mystic Spearhand's effects are not on this character"; return end
    local id = sdk.create_instance("via.effect.script.EffectID")
    id.DataContainerIndex = idx; id.ContainerID = 25; id.ElementID = 50
    id.IsContainerIDOnly = false; id.IsElementIDOnly = false
    local c = mgr:call("requestEffect(via.effect.script.EffectID, via.GameObject, System.Int32, via.effect.script.EffectManager.WwiseTriggerInfo)",
        id, a.character:get_GameObject(), -1, nil)
    if c then table.insert(sm.chargeFx, { c = c:add_ref(), untilT = os.clock() + 4 }) end
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if #sm.chargeFx == 0 then return end
    local r, g, b = pick_rgb()
    local col
    for k = #sm.chargeFx, 1, -1 do
        local e = sm.chargeFx[k]
        local done = os.clock() > e.untilT
        pcall(function() if e.c:call("get_isFinished") then done = true end end)
        if done then table.remove(sm.chargeFx, k)
        else
            pcall(function()
                col = col or via_colour({ r, g, b, 1 })
                local list = e.c:call("getAllPlayers")
                for q = 0, (list and list:call("get_Count") or 0) - 1 do
                    local pl = list:call("get_Item", q)
                    local ex = pl:getExternParameter("Charge")
                    if ex then ex:set_Color(col); sm.chargeColoured = true end
                end
            end)
        end
    end
end)
-- the big explosion where the strike landed (asked from the damage hook, made on the next late update)
function sm.on_hit(info)
    if sm.stage ~= 2 or sm.boomed then return end
    -- (any hit counts - an enemy, a crate, a barrel; the slam into bare ground is no hit, so nothing plays then: user)
    sm.boomed = true
    sm.hitFrame = sm.frame
    local v = info["<DamageGameObject>k__BackingField"]
    local p = v:get_Transform():get_Position()
    sm.boomAt = Vector3f.new(p.x, p.y + 1.0, p.z)
end
dbg.smite_hit = function(info) pcall(sm.on_hit, info) end
re.on_application_entry("LateUpdateBehavior", function()
    if not sm.boomAt then return end
    local at = sm.boomAt
    sm.boomAt = nil
    local ok, e = pcall(function()
        local a = runtime.player()
        local rot = a.character:get_GameObject():get_Transform():get_Rotation()
        pcall(sm.sound, a, sm.SND.hit, "hit")   -- (user's own explosion sound)
        if parts.play_ours(sm.boomFx, at, rot) then
            local o = parts.ours[#parts.ours]
            o.go:get_Transform():set_LocalScale(Vector3f.new(sm.boomScale, sm.boomScale, sm.boomScale))
        end
    end)
    sm.info = ok and "hit: explosion" or ("explosion failed: " .. tostring(e))
end)
local function finish(a, why)
    pcall(dbg.nox_boost, false)
    if a then pcall(dbg.rim_glow, a, false) end
    pcall(sm.light, false)
    if a then pcall(function() a.character.FullBodyLayer:call("set_Speed", 1.0) end) end
    sm.stage, sm.fastOn = nil, false
    sm.info = why
    note("Eldritch Smite: " .. tostring(why))
end
local function stage(a, k)
    sm.stage, sm.asked, sm.started, sm.framed, sm.fastOn = k, os.clock(), nil, false, false
    if k == 1 then sm.boomed, sm.looked, sm.lookEndAt, sm.chargeAt, sm.chargeSet = false, false, nil, nil, false; pcall(sm.load_sounds, a) end
    if k == 2 then
        if not dbg.NOX.boosted then pcall(dbg.nox_boost, true) end   -- (on since 0.3 s into part 1)
        pcall(dbg.rim_glow, a, true)   -- (user: Mystic Spearhand's whole-body charge look, our colour)
    end
    pcall(function() sm.prevMot = mkey(a.character.FullBodyLayer) end)
    pcall(function() a.character.FullBodyLayer:call("set_Speed", 1.0) end)
    request(a, sm.PARTS[k].action)
end
local function update(a)
    local now = os.clock()
    if sm.want then
        sm.want = false
        if not sm.stage then stage(a, 1); sm.info = "smiting" end
    end
    if not sm.stage then return end
    local part = sm.PARTS[sm.stage]
    local cur = a:current_action(0)
    if not sm.started then
        if cur == part.action then sm.started = now
        elseif now - sm.asked > 0.4 then return finish(a, part.action .. " did not start (now " .. tostring(cur) .. ")")
        else request(a, part.action); return end
    end
    if cur ~= part.action then return finish(a, "interrupted by " .. tostring(cur)) end
    if sm.stage == 1 and not sm.looked and now - sm.started >= sm.lookAfter then   -- the smite look from 0.3 s
        sm.looked = true
        pcall(dbg.nox_boost, true)
    end
    if sm.stage == 1 and not sm.chargeSet then   -- the charge sound: from the look's start, + / - the delay
        sm.chargeSet = true
        sm.chargeAt = sm.started + sm.lookAfter + math.max(-sm.lookAfter, sm.chargeDelay)
    end
    if sm.chargeAt and now >= sm.chargeAt then
        sm.chargeAt = nil
        pcall(sm.sound, a, sm.SND.charge, "charge")   -- (user's own charge sound)
    end
    pcall(sm.light, sm.lightOn and dbg.NOX.boosted)   -- the blade lights the area as long as the look is on
    local L = a.character.FullBodyLayer
    if mkey(L) == sm.prevMot and now - sm.started < 0.25 then return end   -- not on the new animation yet
    local fr = L:call("get_Frame")
    if not sm.framed then
        sm.framed = true
        if part.from > 0 and fr < part.from then   -- crossfade into the start frame (no jump)
            local ok = pcall(L.call, L, CHANGE, L:call("get_MotionBankID"), L:call("get_MotionID"), part.from, sm.blend, 1, 1)
            if not ok then L:call("set_Frame", part.from) end
            return
        end
    end
    if sm.stage == 2 then
        sm.frame = fr
        if fr >= sm.lookUntil and dbg.NOX.boosted and not sm.lookEndAt then sm.lookEndAt = now + sm.lookExtra end
        if sm.lookEndAt and now >= sm.lookEndAt and dbg.NOX.boosted then pcall(dbg.nox_boost, false); pcall(sm.light, false) end
    end
    if part.fastFrom and fr >= part.fastFrom and not sm.fastOn then   -- (user: only 270 - 347 faster)
        sm.fastOn = true
        L:call("set_Speed", sm.fast)
    end
    if fr >= part.to then
        if sm.PARTS[sm.stage + 1] then return stage(a, sm.stage + 1) end
        pcall(function() L:call("set_Speed", 1.0) end)
        request(a, a:is_grounded() == false and "WaitToFall" or "NormalLocomotion")
        return finish(a, "done")
    end
end
re.on_pre_application_entry("UpdateBehavior", function()
    if not sm.stage and not sm.want then return end
    local a = runtime.player()
    if not a or not a:valid() or not live.on then sm.want = false; if sm.stage then finish(a, "Pactblade off") end; return end
    local ok, err = pcall(update, a)
    if not ok then finish(a, "error: " .. tostring(err)) end
end)
re.on_script_reset(function() if sm.stage then pcall(function() runtime.player().character.FullBodyLayer:call("set_Speed", 1.0) end) end end)
function sm.press()
    local now = os.clock()
    if sm.stage or sm.want or now - sm.lastPress < 0.6 or combo.stage ~= 0 or castT.t0 then return end
    local can = false
    pcall(function()
        local track = runtime.player().character:get_Human().Track
        can = track.All or track.Skill
    end)
    if can then sm.lastPress, sm.want = now, true end
end
-- the press of the bound skill (or, while binding, whichever skill is pressed next becomes the slot)
pcall(function()
    local SIG = "processCustomSkill(app.HumanCustomSkillID, System.UInt64, app.LockOnController.Option, System.Boolean, System.Boolean, System.Boolean, app.LocomotionSpeedTypeEnum, System.Boolean)"
    sdk.hook(sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method(SIG), function(args)
        if not live.on then return end
        local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
        if sm.binding then
            sm.binding = false
            if NAMES[id] then cfg.smiteSkill = NAMES[id]; save_cfg(); sm.info = "now in " .. NAMES[id] .. "'s slot" end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        if id ~= IDS[cfg.smiteSkill] then return end
        sm.press()
        return sdk.PreHookResult.SKIP_ORIGINAL   -- the vanilla skill never plays
    end, function(r) return r end)
end)
-- the vanilla skill started any other way (a queued press ...) becomes the smite too - not the combo's own requests
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if not live.on or sm.ourReq or combo.stage ~= 0 or not cfg.smiteSkill then return end
            local skip = false
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if name:sub(1, #cfg.smiteSkill) ~= cfg.smiteSkill then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                skip = true
                sm.press()
            end)
            if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r) return r end)
end)
end)()

------------------------------------------------------------------------
-- MISTY DIVE (user's skill): warp above the enemy in front, fall into the air Empale (Job01_HeavyAttackAir)
------------------------------------------------------------------------
;(function()
local md = { info = "-", lastPress = -10, above = 1.8, back = 0.0, range = 20, cone = 90, ACTION = "Job01_HeavyAttackAir",   -- (user: lower)
             -- (user: the same preparing jump as Mystic Spearhand's skill - recorded: Job07_SkyDive, motions 170/1100 prepare
             -- (with its start effects + sound), 170/1101 = the teleport (sound 2823464530), 170/1102 the landing)
             PREP = "Job07_SkyDive", PREP_BANK = 170, WARP_MOTION = 1101, prepMax = 0.6, warpSound = 2823464530,
             -- (user: use the WHOLE SkyDive - its own targeting + teleport - and only swap the strike after the teleport)
             mode = "ours", afterTeleport = 0.05, lockWarp = true }   -- (user: from scratch - SkyDive's targeting finds nothing for a Fighter)
dbg.misty = md
local IDS, NAMES = {}, {}
pcall(function()
    for _, f in ipairs(sdk.find_type_definition("app.HumanCustomSkillID"):get_fields()) do
        if f:is_static() then
            local ok, v = pcall(f.get_data, f, nil)
            if ok and type(v) == "number" then IDS[f:get_name()] = v & 0xFFFFFFFF; NAMES[v & 0xFFFFFFFF] = f:get_name() end
        end
    end
end)
local function request(a, name)
    md.ourReq = true
    local ok = a:request_action(name, 0)
    md.ourReq = false
    return ok
end
-- alive = HP above 0 (is_alive() turned every enemy down here); unreadable HP counts as alive
function md.alive(ch)
    if not ch then return false end
    local hp
    pcall(function() hp = ch["<Hit>k__BackingField"]:get_Hp() end)
    if type(hp) ~= "number" then pcall(function() hp = ch:get_Hit():get_Hp() end) end
    return type(hp) ~= "number" or hp > 0
end
-- Misty Dive's own pick (camera or facing - user aims with the camera)
function md.pick(a)
    local best, bestD, bestS, why
    pcall(function()
        local tr = a.character:get_GameObject():get_Transform()
        local p = tr:get_Position()
        local dirs = {}
        pcall(function()
            local c = sdk.get_primary_camera():get_GameObject():get_Transform():get_Position()
            local x, z = p.x - c.x, p.z - c.z
            local l = math.sqrt(x * x + z * z)
            if l > 0.05 then dirs[#dirs + 1] = { x / l, z / l } end
        end)
        local f = tr:get_Rotation() * Vector3f.new(0, 0, 1)
        local fl = math.sqrt(f.x * f.x + f.z * f.z)
        if fl > 0.001 then dirs[#dirs + 1] = { f.x / fl, f.z / fl } end
        local list = sdk.get_managed_singleton("app.EnemyManager")._EnemyList
        local n, nAlive = 0, 0
        for k = 0, list._size - 1 do
            pcall(function()
                local ch = list._items[k]._Chara
                n = n + 1
                if not md.alive(ch) then return end
                nAlive = nAlive + 1
                local q = ch:get_GameObject():get_Transform():get_Position()
                local dx, dz = q.x - p.x, q.z - p.z
                local d = math.sqrt(dx * dx + dz * dz)
                if d > md.range or math.abs(q.y - p.y) > 15 then return end   -- (standing on a Cyclops)
                local ang = 0
                if d > 3 then   -- (close by / on top of it: any direction)
                    ang = 180
                    for _, v in ipairs(dirs) do
                        ang = math.min(ang, math.deg(math.acos(math.max(-1, math.min(1, (dx * v[1] + dz * v[2]) / d)))))
                    end
                end
                if ang > md.cone then return end
                local sc = d * (1 + ang / 90)
                if not bestS or sc < bestS then best, bestD, bestS = ch, d, sc end
            end)
        end
        why = ("%d enemies listed, %d alive"):format(n, nAlive)
    end)
    return best, bestD, why
end
-- why nobody was picked: the nearest enemy and what ruled it out (user: dummies sometimes not targeted)
function md.why(a)
    local out = "no enemies listed"
    pcall(function()
        local tr = a.character:get_GameObject():get_Transform()
        local p = tr:get_Position()
        local f = tr:get_Rotation() * Vector3f.new(0, 0, 1)
        local fl = math.sqrt(f.x * f.x + f.z * f.z)
        local list = sdk.get_managed_singleton("app.EnemyManager")._EnemyList
        local bestD
        for k = 0, list._size - 1 do
            pcall(function()
                local ch = list._items[k]._Chara
                local q = ch:get_GameObject():get_Transform():get_Position()
                local dx, dz = q.x - p.x, q.z - p.z
                local d = math.sqrt(dx * dx + dz * dz)
                if bestD and d >= bestD then return end
                bestD = d
                local ang = d > 0.01 and fl > 0.001 and math.deg(math.acos(math.max(-1, math.min(1, (dx * f.x + dz * f.z) / (d * fl))))) or 0
                local alive = true
                pcall(function() alive = ch["<Hit>k__BackingField"]:get_Hp() > 0 end)
                out = ("nearest enemy %.1f m, %.0f deg to the side, %.1f m height gap, %s"):format(d, ang, q.y - p.y, alive and "alive" or "not alive")
            end)
        end
    end)
    return out
end
-- the dive itself: where to, the warp (+ SkyDive's teleport sound), the air Empale
local function dive(a)
    local tr = a.character:get_GameObject():get_Transform()
    local t, d
    if md.target and md.alive(md.target) then   -- the one picked at the press (on the ground)
        t = md.target
        pcall(function()
            local p, q = tr:get_Position(), t:get_GameObject():get_Transform():get_Position()
            d = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
        end)
    else
        pcall(function() t, d = md.pick(a) end)
    end
    local dest, rot, dx, dz
    if t then
        dest, rot, dx, dz = combo.dive_spot(a, t, md.above, md.back)
        md.info = ("diving onto an enemy %.1f m away"):format(d or 0)
    else   -- nobody in front: 3 m ahead, up in the air
        local p = tr:get_Position()
        local f = tr:get_Rotation() * Vector3f.new(0, 0, 1)
        local len = math.sqrt(f.x * f.x + f.z * f.z)
        local fx, fz = len > 0.001 and f.x / len or 0, len > 0.001 and f.z / len or 1
        dest, rot, dx, dz = Vector3f.new(p.x + fx * 3, p.y + md.above + 1.5, p.z + fz * 3), tr:get_Rotation(), fx, fz
        md.info = "no enemy in front: dove ahead (" .. md.why(a) .. ")"
    end
    combo.warp_to(a, dest, rot, dx, dz)   -- (its CharaController warp also clears SkyDive's jump speed)
    if combo.cue_sound then pcall(combo.cue_sound, a, md.warpSound) end
    md.stage, md.asked, md.started, md.hold = "dive", os.clock(), nil, { dest = dest, rot = rot, dx = dx, dz = dz, n = 3, always = true }
    md.steppedOff = nil
    md.lockXZ = { dest.x, dest.z, warp = md.lockWarp, top = dest.y + 2, head = t and dest.y - md.above or nil }   -- straight down from there, never up
    md.push = 0
    note("Misty Dive: " .. md.info)
    request(a, md.ACTION)
end
-- first Mystic Spearhand's preparing jump (its own action: its start effects + sound come with it)
local function start(a)
    md.seenDive = {}
    md.stage, md.prepT, md.prepStarted, md.teleportAt, md.lockXZ = "prep", os.clock(), nil, nil, nil
    md.target = nil   -- (SkyDive's own targeting finds nothing for a Fighter: our pick, used at its teleport)
    local t, d, why = md.pick(a)
    if t then
        md.target = t:add_ref()
        note(("Misty Dive press: enemy %.1f m away picked"):format(d or 0))
    else
        note("Misty Dive press: nobody picked (" .. tostring(why) .. "; " .. md.why(a) .. ")")
    end
    pcall(function()   -- the way I face at the press: the dive goes that way (user: sometimes it fell backwards)
        local tr = a.character:get_GameObject():get_Transform()
        local f = tr:get_Rotation() * Vector3f.new(0, 0, 1)
        local len = math.sqrt(f.x * f.x + f.z * f.z)
        md.face = len > 0.001 and { f.x / len, f.z / len, tr:get_Rotation() } or nil
    end)
    request(a, md.PREP)
end
local function update(a)
    local now = os.clock()
    if md.want then
        md.want = false
        if not md.stage then local ok, e = pcall(start, a); if not ok then md.info = "failed: " .. tostring(e); md.stage = nil end end
    end
    if not md.stage then return end
    if md.stage == "prep" then   -- until SkyDive reaches its teleport (motion 1101), then our warp + dive
        local cur = tostring(a:current_action(0) or "")
        if cur == md.PREP then md.prepStarted = md.prepStarted or now end
        local teleport = false
        pcall(function()
            local L = a.character.FullBodyLayer
            teleport = L:call("get_MotionBankID") == md.PREP_BANK and L:call("get_MotionID") == md.WARP_MOTION
        end)
        if md.mode == "msp" and md.prepStarted then
            -- SkyDive teleports by itself; a moment after its teleport its strike becomes the air Empale
            if teleport and not md.teleportAt then md.teleportAt = now end
            if md.teleportAt and now - md.teleportAt >= md.afterTeleport then
                -- no leftover speed from SkyDive's jump, and facing the way I faced at the press (held a few frames)
                local tr = a.character:get_GameObject():get_Transform()
                local onTarget = false
                if md.target then   -- above the enemy in front, facing it (SkyDive put us above ourselves)
                    pcall(function()
                        local dest, rot, dx, dz = combo.dive_spot(a, md.target, md.above, md.back)
                        tr:set_Position(dest)
                        tr:set_Rotation(rot)
                        md.face = { dx / math.max(0.001, math.sqrt(dx * dx + dz * dz)), dz / math.max(0.001, math.sqrt(dx * dx + dz * dz)), rot }
                        md.hold = { dest = dest, rot = rot, dx = dx, dz = dz, n = 3, always = true }
                        onTarget = true
                    end)
                end
                pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end)
                if md.face and not onTarget then
                    tr:set_Rotation(md.face[3])
                    pcall(combo.face, a, md.face[1], md.face[2])
                    md.hold = { dest = tr:get_Position(), rot = md.face[3], dx = md.face[1], dz = md.face[2], n = 4, keepPos = true }
                end
                md.stage, md.asked, md.started, md.teleportAt = "dive", now, nil, nil
                local p0 = tr:get_Position()
                md.lockXZ = { p0.x, p0.z }   -- (user: straight down - no sideways drift with the stick / momentum)
                md.info = onTarget and "SkyDive's teleport, moved above the enemy, the air Empale" or "SkyDive's teleport (no enemy), the air Empale"
                note("Misty Dive: " .. md.info)
                request(a, md.ACTION)
            elseif now - md.prepStarted > 2.0 then md.stage = nil; md.info = "SkyDive never teleported" end
            return
        end
        -- (user: 200 m up - SkyDive's upward push comes in its teleport's first frame, after a warp in that frame:
        -- our warp waits md.afterTeleport too, and the speed is cleared on every hold frame)
        if teleport and not md.teleportAt then md.teleportAt = now end
        local due = md.teleportAt and now - md.teleportAt >= md.afterTeleport
        if due or (md.prepStarted and now - md.prepStarted > md.prepMax) or (not md.prepStarted and now - md.prepT > 0.4) then
            md.teleportAt = nil
            local ok, e = pcall(dive, a)
            if not ok then md.info = "failed: " .. tostring(e); md.stage = nil end
        elseif not md.prepStarted then request(a, md.PREP) end
        return
    end
    if md.lockXZ then   -- straight down: only the height changes until the dive is over
        pcall(function()
            local tr = a.character:get_GameObject():get_Transform()
            local p = tr:get_Position()
            local L = md.lockXZ
            local push = math.sqrt((p.x - L[1]) ^ 2 + (p.z - L[2]) ^ 2)
            md.push = math.max(md.push or 0, push)
            if not L.y0 then L.y0, L.t0 = p.y, now end
            if L.warp and not L.checked and now - L.t0 >= 0.3 then   -- the fall goes on with the controller warp?
                L.checked = true
                if p.y > L.y0 - 0.05 then L.warp = false; note("Misty Dive: the controller lock stopped the fall - dropped") end
            end
            local y = p.y
            if L.top and y > L.top then   -- (user: from under the ground it threw me ~2 km up)
                y = L.top
                if not L.capped then L.capped = true; note("Misty Dive: pushed upward - held at the dive spot's height") end
            end
            if push > 0.001 or y ~= p.y then
                tr:set_Position(Vector3f.new(L[1], y, L[2]))
                if y ~= p.y then pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end) end
                if L.warp then pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end) end
            end
            if now - L.t0 > 3 then md.lockXZ = nil end   -- (never held for long)
            if L.head and y <= L.head + 0.3 then md.lockXZ = nil end   -- at its head: free (no standing on it)
        end)
    end
    local h = md.hold   -- the character controller can put us back for a frame or two after a warp
    if h and h.n > 0 then
        h.n = h.n - 1
        local tr = a.character:get_GameObject():get_Transform()
        if (h.always or not md.started) and not h.keepPos then
            tr:set_Position(h.dest)
            pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end)   -- (no speed kept)
        end
        tr:set_Rotation(h.rot)
        pcall(combo.face, a, h.dx, h.dz)
    end
    local cur = tostring(a:current_action(0) or "")
    if not md.started then
        if cur == md.ACTION then md.started = now
        elseif now - md.asked > 0.5 then   -- (never left hanging in the air: the game's fall)
            md.stage, md.lockXZ = nil, nil
            md.info = md.ACTION .. " did not start (now " .. cur .. ") - falling"
            pcall(function() a.character["<CharaController>k__BackingField"]:call("warp") end)
            request(a, "WaitToFall")
        else request(a, md.ACTION) end
        return
    end
    if md.started and not md.steppedOff and now - md.started > 2.5 and cur == md.ACTION then
        md.steppedOff = true   -- (still falling after 2.5 s = standing on something, e.g. the enemy's head)
        pcall(function()
            local tr = a.character:get_GameObject():get_Transform()
            local p = tr:get_Position()
            local bx, bz = -(md.hold and md.hold.dx or 0), -(md.hold and md.hold.dz or 1)
            local l = math.max(0.001, math.sqrt(bx * bx + bz * bz))
            md.lockXZ = nil
            tr:set_Position(Vector3f.new(p.x + bx / l * 1.5, p.y, p.z + bz / l * 1.5))
            a.character["<CharaController>k__BackingField"]:call("warp")
        end)
        note("Misty Dive: still in the air after 2.5 s - stepped off (1.5 m back)")
    end
    if not cur:find("^Job01_HeavyAttackAir") then   -- (its landing is part of it; then it is over)
        md.stage, md.lockXZ = nil, nil
        note(("Misty Dive: over (the game pushed me sideways up to %.2f m a frame)"):format(md.push or 0))
    end
end
re.on_pre_application_entry("UpdateBehavior", function()
    if not md.stage and not md.want then return end
    local a = runtime.player()
    if not a or not a:valid() or not live.on then md.want, md.stage = false, nil; return end
    local ok, err = pcall(update, a)
    if not ok then md.stage = nil; md.info = "error: " .. tostring(err) end
end)
re.on_application_entry("LateUpdateBehavior", function()   -- (the lock again after the game moved us this frame)
    if not md.lockXZ then return end
    pcall(function()
        local tr = runtime.player().character:get_GameObject():get_Transform()
        local p = tr:get_Position()
        tr:set_Position(Vector3f.new(md.lockXZ[1], md.lockXZ.top and math.min(p.y, md.lockXZ.top) or p.y, md.lockXZ[2]))
        if md.lockXZ.warp then pcall(function() runtime.player().character["<CharaController>k__BackingField"]:call("warp") end) end
    end)
end)
md.FX = { ["14/7/10"] = "sd10", ["14/7/11"] = "sd11", ["14/7/20"] = "sd20", ["14/7/21"] = "sd21", ["13/0/10"] = "sdns10", ["0/15/0"] = "sdex" }   -- (2.95: as a Fighter SkyDive plays 14/7/10 + 14/7/11)   -- SkyDive's teal on me (0/15/0 = the skill-start flash ch00/atk/13_ch00_EX_000_00, inverted layers: baked with the opposite hue)
md.fxOn, md.fxs, md.res = true, {}, {}
function md.hue()   -- the colour picked under Look (285 / 300 / 315); nil = the game's colours
    local p40 = part_cfg("-1/8/40")
    local h = p40.mode == "ours" and tonumber(tostring(p40.variant or ""):match("^e(%d+)$") or "")
    return (h == 285 or h == 300 or h == 315) and h or nil
end
function md.busy() return md.stage ~= nil or md.want or os.clock() - (md.lastBusy or -10) < 1.5 end
function dbg.md_seen(args, how)   -- (diagnosis 2.94; off unless md.logFx)
    if not md.logFx or not md.busy() then return end
    local go = sdk.to_managed_object(args[2]):call("get_GameObject")
    if go:get_address() ~= live.go then return end
    local idd = effect_id_of(args, how)
    md.seenDive = md.seenDive or {}
    local key = tostring(idd) .. " " .. how
    if md.seenDive[key] then return end
    md.seenDive[key] = true
    note(("Misty Dive fx: %s via %s%s"):format(tostring(idd), how, md.FX[idd] and " (ours replaces it)" or ""))
end
-- the teal material colours on these meshes: { "<object> / <material> / <variable> hue h" ... }
function md.teal_of(go, label, out, dump)
    for _, mesh in ipairs(dbg.ai.meshes(go)) do
        pcall(function()
            local gname = tostring(mesh:get_GameObject():get_Name())
            for i = 0, mesh:call("get_MaterialNum") - 1 do
                local mname = tostring(mesh:call("getMaterialName", i))
                for v = 0, mesh:call("getMaterialVariableNum", i) - 1 do
                    pcall(function()
                        local name = tostring(mesh:call("getMaterialVariableName", i, v))
                        local f = mesh:call("getMaterialFloat4(System.UInt32, System.UInt32)", i, v)
                        local h, s0, mx = dbg.ai.hsv(f.x, f.y, f.z)
                        if s0 > 0.35 and mx > 0.02 and h >= 150 and h <= 230 then
                            out[name] = (out[name] or 0) + 1
                            dump[#dump + 1] = { who = label, go = gname, material = mname, var = name, value = { f.x, f.y, f.z, f.w } }
                        end
                    end)
                end
            end
        end)
    end
end
function md.teal_dump()
    local dump = {}
    for _, who in ipairs({ "me", "clone" }) do
        local out = {}
        pcall(function()
            local go
            if who == "me" then go = runtime.player().character:get_GameObject()
            else
                local inst = dbg.ai.handler(runtime.player()):call("get_Instance")
                go = inst and inst:get_GameObject()
            end
            if go then md.teal_of(go, who, out, dump) end
        end)
        local names = {}
        for k, n in pairs(out) do names[#names + 1] = k .. " x" .. n end
        table.sort(names)
        note(("Misty Dive teal on %s: %s"):format(who, #names > 0 and table.concat(names, ", ") or "none"))
    end
    pcall(json.dump_file, "Pactblade_misty_teal.json", dump)
end
function dbg.md_fx(args, idd)
    if not md.fxOn or not md.FX[idd] or not md.busy() then return false end
    local hue = md.hue()
    if not hue then return false end
    local go = sdk.to_managed_object(args[2]):call("get_GameObject")
    if go:get_address() ~= live.go then return false end
    return ("vfx/effects/pactblade/pb_%s_h%d.efx"):format(md.FX[idd], hue)
end
function dbg.md_fx_play(rv, path)
    local c = sdk.to_managed_object(rv)
    if not c then return end
    if not md.res[path] then
        local r = sdk.create_resource("via.effect.EffectResource", path)
        if not r then
            c = nil
            if not md.fxMissing then md.fxMissing = true; note("Misty Dive: our effect copy not found (" .. path .. ") - restart the game for the pak") end
            return
        end
        md.res[path] = r:add_ref()
    end
    local ptr = runtime.player().character:get_GameObject():get_Transform()
    local go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)"):call(nil, "Pactblade_md_fx", 0)
    go = go:add_ref()
    go:call(".ctor")
    go:set_Name("Pactblade_md_fx")
    local tr = go:get_Transform()
    tr:set_Position(ptr:get_Position())
    tr:set_Rotation(ptr:get_Rotation())
    local holder = md.res[path]:create_holder("via.effect.EffectResourceHolder"):add_ref()
    local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
    ep:call("set_Resource", holder)
    pcall(function() ep:call("set_AutoStart", true) end)
    pcall(function()   -- which parts the game switches on (emitters / groups) - NOT its colour / group parameters:
        -- those carry the game's teal, copied only when its player was ready that frame (user: randomly teal again)
        local list = c:call("getAllPlayers")
        local src = list and list:call("get_Count") > 0 and list:call("get_Item", 0)
        if not src then return end
        pcall(function() ep:call("set_EmitMaskBit", src:call("get_EmitMaskBit")) end)
        pcall(function() local m = src:call("get_MaskName"); if m and tostring(m) ~= "" then ep:call("set_MaskName", m) end end)
        pcall(function() ep:call("set_GroupEnabled", src:call("get_GroupEnabled")) end)
        pcall(function()
            local n = src:call("getGroupNamesCount")
            if not n or n == 0 then return end
            ep:call("setGroupNamesCount", n)
            for q = 0, n - 1 do ep:call("setGroupNames", q, src:call("getGroupNames", q)) end
        end)
    end)
    c:call("killAll")
    note("Misty Dive: our copy plays (" .. path:match("([^/]+)$") .. ")")
    md.fxs[#md.fxs + 1] = { go = go, ep = ep, untilT = os.clock() + 4 }
    md.fxN = (md.fxN or 0) + 1
end
re.on_pre_application_entry("LateUpdateBehavior", function()
    if md.stage then md.lastBusy = os.clock() end
    if #md.fxs > 0 then   -- our copies go with me; gone after 4 s
        local now = os.clock()
        local ptr
        pcall(function() ptr = runtime.player().character:get_GameObject():get_Transform() end)
        for i = #md.fxs, 1, -1 do
            local o = md.fxs[i]
            if now > o.untilT or not ptr then
                pcall(function() o.go:call("destroy(via.GameObject)", o.go) end)
                table.remove(md.fxs, i)
            else
                pcall(function()
                    local tr = o.go:get_Transform()
                    tr:set_Position(ptr:get_Position())
                    tr:set_Rotation(ptr:get_Rotation())
                end)
            end
        end
    end
end)
re.on_pre_application_entry("BeginRendering", function()   -- my body glow (SkyDive's rim light) in our colour
    if md.tealAt and os.clock() >= md.tealAt then md.tealAt = nil; pcall(md.teal_dump) end
    if not md.fxOn or not md.busy() or not dbg.rim_paint then md.rim = nil; return end
    local hue = md.hue()
    if not hue then return end
    if not md.rim then
        pcall(function() md.rim = dbg.rim_entries(runtime.player().character:get_GameObject()) end)
        md.rim = md.rim or {}
    end
    dbg.rim_paint(md.rim, hue)
end)
md.finish = "always"   -- (user: blocking it didn't work - left to the game) the air Empale's execution: "staggered" (staggered + standing only), "always", "never"
md.STAG = { "damage", "stagger", "flinch", "knockback", "stun", "hitback", "shock", "stumble" }
md.DOWN = { "down", "blown", "lie", "lying", "slam", "fall", "crawl", "getup", "standup", "rise", "air", "dead", "die" }
function md.target_state(ch)
    local nm = "?"
    pcall(function() local e = ch:get_ActionManager().CurrentActionList[0]; nm = tostring(e and e.Name or "?") end)
    local l = nm:lower()
    local function any(words) for _, w in ipairs(words) do if l:find(w, 1, true) then return true end end return false end
    return any(md.STAG) and not any(md.DOWN), nm
end
pcall(function()
    sdk.hook(sdk.find_type_definition("app.HumanCatchProcessor"):get_method("processFinishingMove(app.HitController.DamageInfo, app.Character)"),
        function(args)
            local st = thread.get_hook_storage()
            st.mdBlock = nil
            if md.stage ~= "dive" or md.finish == "always" then return end
            local block
            pcall(function()
                local info = sdk.to_managed_object(args[3])
                local hc = info:get_AttackHitController()
                local me = runtime.player().character:get_GameObject()
                if not hc or hc:get_GameObject():get_address() ~= me:get_address() then return end
                local ch = sdk.to_managed_object(args[4])
                local ok, nm = true, "-"
                if md.finish == "never" then ok = false elseif ch then ok, nm = md.target_state(ch) end
                block = not ok
                note(("Misty Dive: execution check - enemy action %s -> %s"):format(nm, ok and "allowed" or "blocked"))
            end)
            if block then st.mdBlock = true; return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r)
            local st = thread.get_hook_storage()
            if st.mdBlock then st.mdBlock = nil; return sdk.to_ptr(0) end   -- (null: no finishing move)
            return r
        end)
    md.finishHook = true
end)
function md.press()
    local now = os.clock()
    if md.stage or md.want or now - md.lastPress < 0.6 or combo.stage ~= 0 or castT.t0 then return end
    local can = false
    pcall(function()
        local track = runtime.player().character:get_Human().Track
        can = track.All or track.Skill
    end)
    if can then md.lastPress, md.want = now, true end
end
-- (user: the slot is a shield skill and there is no shield) - the game asks HumanSkillAvailability whether a skill can be
-- used (a shield skill needs a shield); for MY character and Misty Dive's slot the answer is yes while Pactblade is on
for _, mname in ipairs({ "isCustomSkillAvailable(app.HumanCustomSkillID)", "isCustomSkillAvailableWithoutItemCondition(app.HumanCustomSkillID)" }) do
    pcall(function()
        sdk.hook(sdk.find_type_definition("app.HumanSkillAvailability"):get_method(mname), function(args)
            local st = thread.get_hook_storage()
            st.mdYes = nil
            if not live.on or not cfg.mistySkill then return end
            -- (while binding any skill may come through, so a shield skill can be picked without a shield)
            if not md.binding and (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= IDS[cfg.mistySkill] then return end
            pcall(function()
                local ch = sdk.to_managed_object(args[2]).Chara
                if ch and ch:get_GameObject():get_address() == live.go then st.mdYes = true end
            end)
        end, function(r)
            local st = thread.get_hook_storage()
            if st.mdYes then st.mdYes = nil; md.allowed = (md.allowed or 0) + 1; return sdk.to_ptr(1) end
            return r
        end)
    end)
end
pcall(function()
    local SIG = "processCustomSkill(app.HumanCustomSkillID, System.UInt64, app.LockOnController.Option, System.Boolean, System.Boolean, System.Boolean, app.LocomotionSpeedTypeEnum, System.Boolean)"
    sdk.hook(sdk.find_type_definition("app.PlayerInputProcessorDetail"):get_method(SIG), function(args)
        if not live.on then return end
        local id = sdk.to_int64(args[3]) & 0xFFFFFFFF
        if md.binding then
            md.binding = false
            if NAMES[id] then cfg.mistySkill = NAMES[id]; save_cfg(); md.info = "now in " .. NAMES[id] .. "'s slot" end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        if id ~= IDS[cfg.mistySkill] then return end
        md.press()
        return sdk.PreHookResult.SKIP_ORIGINAL   -- the vanilla skill never plays
    end, function(r) return r end)
end)
pcall(function()
    sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
        function(args)
            if not live.on or md.ourReq or combo.stage ~= 0 or not cfg.mistySkill then return end
            local skip = false
            pcall(function()
                local name = sdk.to_managed_object(args[4]):ToString()
                if name:sub(1, #cfg.mistySkill) ~= cfg.mistySkill then return end
                if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                skip = true
                md.press()
            end)
            if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
        end, function(r) return r end)
end)
end)()

-- the colour of everything recoloured in files (blast launch + explosion, Eldritch Slash wave, warp wisps, arm effect)
local COLOURS = { { 285, "purple" }, { 300, "pink-purple" }, { 315, "pink" }, { false, "the game's colours (no recolour)" } }
local function current_hue()
    local p40 = part_cfg("-1/8/40")
    return p40.mode == "ours" and tonumber(tostring(p40.variant or ""):match("^e(%d+)$") or "") or false
end
local function set_colour(hue)
    for _, id in ipairs({ "-1/8/40", "-1/8/43", "-1/10/1", "-1/10/3", "-1/10/6" }) do
        local pc = part_cfg(id)
        local v = hue and ((id:find("^%-1/10/") and "h" or "e") .. hue) or nil
        pc.mode, pc.variant, pc.follow = hue and "ours" or "whole", v, id == "-1/10/1"
    end
    local lv = tonumber(tostring(cfg.glowVariant or ""):match("g(%d)$") or "") or 2
    cfg.glowVariant = hue and ("h%dg%d"):format(hue, lv) or "dis"   -- the arm without its cloud, game colour
    cfg.blastTint, cfg.armTint = hue and true or false, hue and true or false
    glowState.res = nil; glow_clear(); sleeve_restore(); save_cfg()
end
-- purple look (user): dropdowns, buttons, sliders, section headers
local THEME = { { 7, 0xFF4A1E5C }, { 8, 0xFF6A2C84 }, { 9, 0xFF8A3AAA }, { 21, 0xFF6A2C84 }, { 22, 0xFF8A3AAA },
                { 23, 0xFFA048C8 }, { 24, 0xFF5A2470 }, { 25, 0xFF7A3296 }, { 26, 0xFF9A40BE }, { 19, 0xFFE07AFF },
                { 20, 0xFFF0A0FF }, { 18, 0xFFE07AFF } }   -- FrameBg x3, Button x3, Header x3, SliderGrab x2, CheckMark
local TITLE = 0xFFFFB4F0   -- light purple (ABGR)
local function title(t) imgui.text_colored(t, TITLE) end
-- HEX (user): Examine (Circle) puts Hex on the enemy in front for 15 s: an X of Frost Boon shimmer (Dimension Door's
-- frame effect, in the Nox mist colour) on it, -10 % defence (every hit on it x 1/0.9), killing it gives 15 % HP back.
-- One target: a new Hex takes it off the old one. Also here: the Burst bind's far-side step (dbg.burst_step).
;(function()
    local hex = { secs = 15, defence = 0.10, heal = 0.15, over = 0.6, scale = 1.0, roll = 45, freezeAt = 0.8,
                  copies = 2, col = { 255, 255, 255 }, bright = 2, half = 0.6, side = 0.0, dots = false,   -- (half: 3.12 dots - each line runs ~1.1 m from its anchor along its own up)
                  info = "-", anchors = {},
                  res = nil, behind = 1.8, pts = nil }
    dbg.hex = hex
    local SHIMMER = "vfx/effects/weapon/wp00/009/13_wp00_009_enchant_25.efx"   -- (Dimension Door's door frame)
    local OURS = "vfx/effects/pactblade/pb_hexx_b%d.efx"   -- (our solid pink copies, brightness 1-3)
    local function clear()
        for _, an in ipairs(hex.anchors) do pcall(function() an.go:call("destroy(via.GameObject)", an.go) end) end
        hex.anchors = {}
        hex.target, hex.go = nil, nil
    end
    re.on_script_reset(clear)
    local function anchor()
        local want = OURS:format(hex.bright)
        if hex.resPath ~= want then hex.res, hex.resPath = nil, want end
        if not hex.res then
            local r = sdk.create_resource("via.effect.EffectResource", want)
            if not r then
                if not hex.noOurs then hex.noOurs = true; note("Hex: our pink X file not loaded (restart the game for the pak) - the game's shimmer") end
                r = sdk.create_resource("via.effect.EffectResource", SHIMMER)
            end
            if not r then return nil end
            hex.res = r:add_ref()
        end
        local go = sdk.find_type_definition("via.GameObject"):get_method("create(System.String, via.Folder)"):call(nil, "Pactblade_hex", 0)
        go = go:add_ref()
        go:call(".ctor")
        go:set_Name("Pactblade_hex")
        local holder = hex.res:create_holder("via.effect.EffectResourceHolder"):add_ref()
        local ep = go:call("createComponent(System.Type)", sdk.typeof("via.effect.EffectPlayer")):add_ref()
        ep:call("set_Resource", holder)
        pcall(function() ep:call("set_AutoStart", true) end)
        return { go = go, ep = ep }
    end
    local function hp_of(ch)
        local hp
        pcall(function() hp = ch["<Hit>k__BackingField"]:get_Hp() end)
        return hp
    end
    function hex.put(a, t)
        if hex.target and hex.target:get_address() ~= t:get_address() then clear() end
        hex.target, hex.go = t:add_ref(), t:get_GameObject():add_ref()
        hex.untilT = os.clock() + hex.secs
        hex.build()
        hex.headAt, hex.placedNote = nil, nil
        hex.info = ("on %s for %.0f s"):format(tostring(t:get_GameObject():get_Name()), hex.secs)
        note("Hex: " .. hex.info .. " (" .. #hex.anchors .. " shimmer points)")
    end
    dbg.hex_put = hex.put
    function hex.build()   -- the two lines (x copies), playing from 0 until hex.freezeAt, then frozen
        for _, an in ipairs(hex.anchors) do pcall(function() an.go:call("destroy(via.GameObject)", an.go) end) end
        hex.anchors = {}
        for i = 1, 2 * hex.copies do
            local an = anchor()
            if an then an.line = i % 2 == 1 and 1 or -1; hex.anchors[#hex.anchors + 1] = an end
        end
        hex.born, hex.frozen = os.clock(), false
    end
    -- the top of the creature: its highest "head" joint (as Misty Dive's spot), every 0.3 s; else feet + 1.7
    local function head_y(q)
        local now = os.clock()
        if hex.headAt and now - hex.headAt < 0.3 and hex.headY then return hex.headY end
        hex.headAt = now
        local y
        pcall(function()
            local joints = hex.go:get_Transform():call("get_Joints")
            for k = 0, joints:call("get_Length") - 1 do
                local j = joints:call("Get", k)
                if tostring(j:call("get_Name")):lower():find("head") then
                    local jp = j:get_Position()
                    if math.abs(jp.x - q.x) < 6 and math.abs(jp.z - q.z) < 6 and jp.y > q.y and jp.y < q.y + 15 and (not y or jp.y > y) then y = jp.y end
                end
            end
        end)
        hex.headY, hex.headFound = y or q.y + 1.7, y ~= nil
        return hex.headY
    end
    -- the X: two diagonals through the enemy's chest, turned to the camera, following it
    re.on_pre_application_entry("LateUpdateBehavior", function()
        if not hex.target then return end
        local now = os.clock()
        local hp = hp_of(hex.target)
        if hp and hp <= 0 then   -- killed while hexed: 15 % HP back
            pcall(function()
                local hc = runtime.player().character["<Hit>k__BackingField"]
                local before = hc:get_Hp()
                local amount = hc:get_OriginalMaxHp() * hex.heal
                hc:call("recoverHp(System.Single, System.Boolean, System.Int32, System.Boolean)", amount, false, 0, false)
                note(("Hex: the target died - HP %.0f -> %.0f (+%.0f)"):format(before, hc:get_Hp(), amount))
            end)
            hex.info = "target killed: HP restored"
            clear()
            return
        end
        if now > (hex.untilT or 0) or not live.on then hex.info = "ended"; clear(); return end
        pcall(function()
            local tr = hex.go:get_Transform()
            local q = tr:get_Position()
            local hy = head_y(q)
            -- big creatures get a bigger X (user: tiny on the Cyclops): x1 up to 1.8 m tall, at most x4
            local big = math.max(1, math.min(4, (hy - q.y) / 1.8))
            local sc = hex.scale * big
            local c = Vector3f.new(q.x, hy + hex.over * big, q.z)   -- above the head
            if not hex.placedNote then
                hex.placedNote = true
                note(("Hex X: feet %.1f, head %.1f (%s), size x%.1f, centre %.1f m up"):format(q.y, hy, hex.headFound and "head joint" or "no head joint: feet + 1.7", big, c.y - q.y))
            end
            local cam = sdk.get_primary_camera():get_GameObject():get_Transform():get_Position()
            local fx, fz = c.x - cam.x, c.z - cam.z
            local l = math.max(0.001, math.sqrt(fx * fx + fz * fz))
            fx, fz = fx / l, fz / l
            -- facing the camera (yaw), each line rolled +-roll about the view axis
            local yaw = math.atan(-fx, -fz)
            local qy = Quaternion.new(math.cos(yaw / 2), 0, math.sin(yaw / 2), 0)
            local col = via_colour({ hex.col[1] / 255, hex.col[2] / 255, hex.col[3] / 255, 1 })
            if not hex.frozen and now - (hex.born or now) >= hex.freezeAt then   -- the chosen frame: stop there
                hex.frozen = true
                for _, an in ipairs(hex.anchors) do pcall(function() an.ep:call("set_PlaySpeed", 0.0) end) end
            end
            local pts = {}
            hex.pts = { c = c, lines = pts }
            local rx, rz = -fz, fx   -- (right, seen from the camera)
            for _, an in ipairs(hex.anchors) do
                local r = math.rad(hex.roll) * an.line
                local qr = Quaternion.new(math.cos(r / 2), 0, 0, math.sin(r / 2))
                local atr = an.go:get_Transform()
                local q = qy * qr
                local dir = q * Vector3f.new(0, 1, 0)   -- the line's own up
                local off = hex.half * sc
                local sd = hex.side * an.line            -- (the two lines pushed apart / together sideways)
                local at = Vector3f.new(c.x - dir.x * off + rx * sd, c.y - dir.y * off, c.z - dir.z * off + rz * sd)
                atr:set_Position(at)
                atr:set_Rotation(q)
                pts[#pts + 1] = { at, Vector3f.new(at.x + dir.x, at.y + dir.y, at.z + dir.z) }
                atr:set_LocalScale(Vector3f.new(sc, sc, sc))
                pcall(function() an.ep:set_Color(col) end)
            end
        end)
    end)
    -- -10 % defence: every hit on the hexed enemy (mine go through the damage hook above; others here)
    function dbg.hex_mul(info)
        if not hex.go then return 1 end
        local v = info["<DamageGameObject>k__BackingField"]
        if v and v:get_address() == hex.go:get_address() then return 1 / (1 - hex.defence) end
        return 1
    end
    pcall(function()
        sdk.hook(sdk.find_type_definition("app.HitController"):get_method("calcDamageValue(app.HitController.DamageInfo)"),
            function(args)
                local st = thread.get_hook_storage()
                st.hexInfo = nil
                if not hex.go then return end
                pcall(function()
                    local info = sdk.to_managed_object(args[3])
                    local owner = info["<AttackOwnerObject>k__BackingField"]
                    if owner and owner:get_address() == live.go then return end   -- (mine: the hook above)
                    local v = info["<DamageGameObject>k__BackingField"]
                    if v and v:get_address() == hex.go:get_address() then st.hexInfo = info end
                end)
            end, function(r)
                local st = thread.get_hook_storage()
                local info = st.hexInfo
                st.hexInfo = nil
                if info then pcall(function() info.Damage = info.Damage / (1 - hex.defence) end) end
                return r
            end)
    end)
    re.on_frame(function()   -- debug dots for placing the X
        if not hex.dots or not hex.target or not hex.pts then return end
        pcall(function()
            local function dot(v, col, r)
                local sp = draw.world_to_screen(v)
                if sp then draw.filled_circle(sp.x, sp.y, r, col, 12) end
            end
            dot(hex.pts.c, 0xFF00FF00, 7)
            for _, l in ipairs(hex.pts.lines) do dot(l[1], 0xFF0000FF, 6); dot(l[2], 0xFFFF8000, 5) end
        end)
    end)
    pcall(function()   -- no jump right after the Burst step (the same Jump press)
        sdk.hook(sdk.find_type_definition("app.ActionManager"):get_method("requestActionCore(app.ActionManager.Priority, System.String, System.UInt32)"),
            function(args)
                if os.clock() > (dbg.noJumpUntil or 0) then return end
                local skip = false
                pcall(function()
                    local name = sdk.to_managed_object(args[4]):ToString()
                    if not name:find("Jump") then return end
                    if sdk.to_managed_object(args[2]):get_GameObject():get_address() ~= live.go then return end
                    skip = true
                    note("Burst step: jump refused (" .. name .. ")")
                end)
                if skip then return sdk.PreHookResult.SKIP_ORIGINAL end
            end, function(r) return r end)
    end)
    re.on_pre_application_entry("UpdateBehavior", function()   -- the Burst step, at the same point as the combo's warps
        local w = dbg.burstWant
        if not w then return end
        dbg.burstWant = nil
        if os.clock() - w.t > 0.5 then return end
        local a = runtime.player()
        if not a or not a:valid() then return end
        dbg.noJumpUntil = os.clock() + 0.4
        local ok, e = pcall(dbg.burst_step, a, w.target, w.mb)
        note(ok and "Misty Step (Burst): to the far side of the enemy" or ("Burst step failed: " .. tostring(e)))
        pcall(function()   -- the same Jump press may have started a jump: no jump after the step
            local cur = tostring(a:current_action(0) or "")
            if cur:find("Jump") then a:request_action("NormalLocomotion", 0); note("Burst step: jump " .. cur .. " stopped") end
        end)
    end)
    -- the Burst bind's step: to the far side of the bound enemy, facing it (combo's warp: wisps, afterimage, sounds)
    function dbg.burst_step(a, target, mb)
        local tr = a.character:get_GameObject():get_Transform()
        local p = tr:get_Position()
        local q = target:get_GameObject():get_Transform():get_Position()
        local dx, dz = q.x - p.x, q.z - p.z
        local l = math.sqrt(dx * dx + dz * dz)
        if l < 0.01 then dx, dz, l = 0, 1, 1 end
        dx, dz = dx / l, dz / l
        local back = hex.behind
        pcall(function() local r = target["<CharaController>k__BackingField"]:call("get_Radius"); if r and r + 1.0 > back then back = r + 1.0 end end)
        local dest = Vector3f.new(q.x + dx * back, q.y, q.z + dz * back)
        combo.warp_to(a, dest, combo.yaw(-dx, -dz), -dx, -dz)
        unbind(target, mb)
    end
end)()

re.on_draw_ui(function()
    if not imgui.tree_node(NAME .. " " .. VERSION) then return end
    for _, c in ipairs(THEME) do imgui.push_style_color(c[1], c[2]) end
    local ok, err = pcall(function()
    local ch
    if live.vsb == "missing" then
        imgui.text_colored("VocationAndSkillBuilder (VSB) is not loaded: Pactblade is picked in VSB's menu.", 0xFF40C0FF)
    elseif live.vsb ~= "picked" then
        imgui.text("Pactblade is not picked: VocationAndSkillBuilder -> Vocations -> Fighter: pick Pactblade.")
    else
        imgui.text(live.on and "Pactblade is ACTIVE (sword in hand)." or "Pactblade is picked - active with a sword in hand.")
    end
    if live.on and live.shieldWorn then
        imgui.text_colored("Pactblade can't use a shield: take yours off (it can't be equipped while active).", 0xFF40C0FF)
    end

    title("Look")
    local hue = current_hue()
    local ci = #COLOURS
    for k, c in ipairs(COLOURS) do if c[1] == hue then ci = k end end
    local cl = {}
    for k, c in ipairs(COLOURS) do cl[k] = c[2] end
    local chc, cn = imgui.combo("Colour (blasts, Eldritch Slash, warps, arm)", ci, cl)
    if chc then set_colour(COLOURS[cn][1]); hue = COLOURS[cn][1] end
    ch, cfg.glow = imgui.checkbox("Arm effect", cfg.glow)
    if ch then save_cfg() end
    if cfg.glow then
        local v = tostring(cfg.glowVariant or "")
        local ahue, lv = tonumber(v:match("^h(%d+)g") or ""), tonumber(v:match("g(%d)$") or "") or 2
        if ahue then
            local c1, c2
            c1, lv = imgui.slider_int("   glow strength", lv, 1, 4)
            if c1 then cfg.glowVariant = ("h%dg%d"):format(ahue, lv); glowState.res = nil; glow_clear(); save_cfg() end
            c2, cfg.glowLvCharge = imgui.slider_int("   glow strength while charging", math.floor(cfg.glowLvCharge or 4), 1, 4)
            if c2 then glow_clear(); save_cfg() end
        end
        ch, cfg.glowSheathed = imgui.checkbox("   also while the sword is sheathed (always when charging)", cfg.glowSheathed)
        if ch then save_cfg() end
    end
    ch, cfg.nox = imgui.checkbox("Nox sword look", cfg.nox)
    local chg
    chg, dbg.noxGlowMode = imgui.checkbox("  blade glow mode (3.03 crash test: off)", dbg.noxGlowMode)
    if ch then save_cfg() end
    if cfg.nox and imgui.tree_node("Nox look settings (blade glow + mist)") then
        local SL = { { "blade glow: red", "R", 255 }, { "blade glow: green", "G", 255 }, { "blade glow: blue", "B", 255 },
                     { "blade glow: brightness", "Bright", 8 } }
        local any = false
        local function block(title, get, set, tag)
            imgui.text(title)
            for _, part in ipairs({ "blade", "mist" }) do
                for _, sl in ipairs(SL) do
                    local label = sl[1]:gsub("^blade glow", part == "blade" and "blade glow" or "mist")
                    local maxv = (part == "mist" and sl[2] == "Bright") and 4 or sl[3]
                    local v = get(part, sl[2])
                    local chn, nv = imgui.slider_float(label .. "##" .. tag, v, 0, maxv, sl[2] == "Bright" and "%.2f" or "%.0f")
                    if chn then set(part, sl[2], nv); any = true end
                end
            end
        end
        block("everyday look:", function(part, k) return cfg["nox" .. (part == "blade" and "Blade" or "Mist") .. k] end,
              function(part, k, v) cfg["nox" .. (part == "blade" and "Blade" or "Mist") .. k] = v end, "day")
        if imgui.button("everyday look: back to the defaults") then
            cfg.noxBladeR, cfg.noxBladeG, cfg.noxBladeB, cfg.noxBladeBright = 91, 26, 142, 1.0
            cfg.noxMistR, cfg.noxMistG, cfg.noxMistB, cfg.noxMistBright = 126, 0, 54, 1.3
            any = true
        end
        block("during Eldritch Smite (part 2):", function(part, k) return cfg.noxSmite[part .. k] end,
              function(part, k, v) cfg.noxSmite[part .. k] = v end, "smite")
        if any then save_cfg() end
        imgui.tree_pop()
    end

    title("Skills")
    imgui.text("   Vocation button: tap = dodge, hold = Eldritch Bolt, right after Onslaught / Empale = Eldritch Burst")
    ch, cfg.bind = imgui.checkbox("Eldritch Bolt binds - Misty Step (Quik Fot) with Jump", cfg.bind)
    if ch then save_cfg() end
    local WARP_LOOKS = { "wisps", "quikfot", "blink" }
    local wfi = 1
    for k, v in ipairs(WARP_LOOKS) do if v == cfg.warpFx then wfi = k end end
    local chw, wfn = imgui.combo("Warp look (Archfey Combo / Misty Step)", wfi, { "Wisps", "Quik Fot", "Blink Behind (Skydragon's Fangtooth)" })
    if chw then cfg.warpFx = WARP_LOOKS[wfn]; save_cfg() end
    if cfg.warpFx == "wisps" then
        ch, cfg.warpWispSecs = imgui.slider_float("   wisps last (s)", cfg.warpWispSecs, 0.2, 3.0, "%.2f")
        if ch then save_cfg() end
    end
    ch, cfg.afterimage = imgui.checkbox("Afterimage where a warp starts (Mystic Spearhand's ghost, our colour)", cfg.afterimage)
    if ch then save_cfg() end
    if cfg.afterimage then
        ch, cfg.afterimageSecs = imgui.slider_float("   afterimage lasts (s)", cfg.afterimageSecs, 0.1, 2.0, "%.2f")
        if ch then save_cfg() end
    end

    if imgui.tree_node("Advanced") then
        title("Arm effect")
        ch, cfg.freezeAt = imgui.slider_float("   frozen at (s)", cfg.freezeAt, 0.05, 3.0, "%.2f")
        if ch then glow_clear(); save_cfg() end
        ch, cfg.chargeFull = imgui.checkbox("   while charging: the whole effect from the start (looped)", cfg.chargeFull)
        if ch then glow_clear(); save_cfg() end
        if cfg.chargeFull then
            local c1, c2
            c1, cfg.chargeSpeed = imgui.slider_float("      charging play speed", cfg.chargeSpeed, 0.1, 2.0, "%.2f")
            c2, cfg.chargeEnd = imgui.slider_float("      loop back after (s of the effect)", cfg.chargeEnd, 0.5, 6.0, "%.2f")
            if c1 or c2 then save_cfg() end
        end
        title("Runtime colour (the effects not recoloured in files)")
        ch, cfg.armTint = imgui.checkbox("   arm", cfg.armTint)
        if ch then sleeve_restore(); save_cfg() end
        imgui.same_line()
        ch, cfg.blastTint = imgui.checkbox("   blasts", cfg.blastTint)
        if ch then save_cfg() end
        if cfg.armTint or cfg.blastTint then
            local cr, cg, cb, cbr
            cr, cfg.armR = imgui.slider_int("      red", cfg.armR, 0, 255)
            cg, cfg.armG = imgui.slider_int("      green", cfg.armG, 0, 255)
            cb, cfg.armB = imgui.slider_int("      blue", cfg.armB, 0, 255)
            cbr, cfg.armBright = imgui.slider_float("      brightness", cfg.armBright, 1.0, 8.0, "%.1f")
            if cr or cg or cb or cbr then sleeve_restore(); save_cfg() end
        end
        ch, cfg.boom = imgui.slider_float("   blast cloud size (0 = none)", cfg.boom, 0.0, 1.0, "%.2f")
        if ch then save_cfg() end
        ch, cfg.comboNoDust = imgui.checkbox("   no dust from the Archfey Combo's Rush parts", cfg.comboNoDust)
        if ch then save_cfg() end
        title("Archfey Combo")
        ch, cfg.comboDynamic = imgui.checkbox("   warps go around the enemy (opposite, then the free sides; off = fixed spots)", cfg.comboDynamic)
        if ch then save_cfg() end
        ch, cfg.finisherHeight = imgui.slider_float("   air finisher height (m above / below its head)", cfg.finisherHeight, -1.5, 1.5, "%.2f")
        if ch then save_cfg() end
        ch, cfg.comboTurn = imgui.checkbox("   opening: turn toward a nearby enemy", cfg.comboTurn)
        if ch then save_cfg() end
        if cfg.comboTurn then
            local c1, c2
            c1, cfg.comboTurnSpeed = imgui.slider_float("      turn speed (degrees a second)", cfg.comboTurnSpeed, 30, 1440, "%.0f")
            c2, cfg.comboTurnRange = imgui.slider_float("      enemy within (m)", cfg.comboTurnRange, 2, 30, "%.1f")
            if c1 or c2 then save_cfg() end
        end
        title("Eldritch Burst window (vocation button during each swing)")
        local w1, w2, w3
        w1, cfg.burstWindow = imgui.slider_float("   Onslaught: s from the start", cfg.burstWindow, 0.05, 1.5, "%.2f")
        local w2a, w2b
        w2a, cfg.empaleFrom = imgui.slider_float("   Empale (ground): from frame", cfg.empaleFrom, 0, 200, "%.1f")
        w2b, cfg.empaleTo = imgui.slider_float("   Empale (ground): to frame (dodge after it)", cfg.empaleTo, 0, 250, "%.1f")
        if w2a or w2b then w2 = true end
        local t1, t2
        t1, cfg.tuskFrom = imgui.slider_float("   Tusk Toss: from frame", cfg.tuskFrom, 0, 200, "%.1f")
        t2, cfg.tuskTo = imgui.slider_float("   Tusk Toss: to frame", cfg.tuskTo, 0, 250, "%.1f")
        if t1 or t2 then w2 = true end
        w3, cfg.burstWindowEmpaleAir = imgui.slider_float("   Empale (in the air): s from the start", cfg.burstWindowEmpaleAir, 0.05, 1.5, "%.2f")
        if w1 or w2 or w3 then save_cfg() end
        title("Eldritch Slash")
        ch, cfg.slashFrame = imgui.slider_float("   wave fires at frame", cfg.slashFrame, 0, 97, "%.1f")
        if ch then save_cfg() end
        ch, cfg.slashRange = imgui.slider_float("   wave range (x Magike Cut's)", cfg.slashRange, 1, 20, "%.1f")
        if ch then save_cfg() end
        ch, cfg.slashHitRange = imgui.slider_float("   wave ends after (m) - set it to where the wave fades", cfg.slashHitRange or 28, 5, 70, "%.0f")
        if ch then save_cfg() end
        ch, cfg.slashFastFrom = imgui.slider_float("   1.2x speed from frame (the recovery)", cfg.slashFastFrom, 0, 350, "%.1f")
        if ch then save_cfg() end
        ch, cfg.slashTurn = imgui.checkbox("   turn toward a nearby enemy before the wave", cfg.slashTurn)
        if ch then save_cfg() end
        if cfg.slashTurn then
            local c1, c2, c3
            c1, cfg.slashTurnRange = imgui.slider_float("      enemy within (m)", cfg.slashTurnRange, 2, 30, "%.1f")
            c2, cfg.slashTurnCone = imgui.slider_float("      and within (degrees of where you face)", cfg.slashTurnCone, 10, 180, "%.0f")
            c3, cfg.slashTurnSpeed = imgui.slider_float("      turn speed (degrees a second)", cfg.slashTurnSpeed, 30, 1440, "%.0f")
            if c1 or c2 or c3 then save_cfg() end
        end
        imgui.tree_pop()
    end

    if imgui.tree_node("Eldritch Bolt fog test (which layer is the fog)") then
        local FOG = { false, 6, 7, 11, 12, 13, 14, 23, 24, 25, 26, 27 }
        local NAMES = { "none (normal explosion)", "6 i0", "7 ig0", "11 ky0", "12 sk0", "13 sm", "14 ss", "23 mkky", "24 mtb", "25 miky", "26 mky", "27 msk" }
        local cur = 1
        for k, v in ipairs(FOG) do if v == dbg.fogLayer or (not v and not dbg.fogLayer) then cur = k end end
        local chf
        chf, cur = imgui.combo("layer at 30 % (then fire an Eldritch Bolt)", cur, NAMES)
        if chf then dbg.fogLayer = FOG[cur] or nil end
        imgui.text("Tell Claude which one makes the fog smaller.")
        imgui.tree_pop()
    end
    if imgui.tree_node("Skill settings") then
        if imgui.tree_node("Eldritch Smite") then
            local sm, chm = dbg.smite, nil
            imgui.text(("slot: %s   |   %s"):format(tostring(cfg.smiteSkill), sm.info))
            if imgui.button(sm.binding and "press the skill now...##sm" or "put it in the next skill I press##sm") then sm.binding = true end
            chm, sm.fast = imgui.slider_float("speed from frame 150", sm.fast, 1, 3, "%.2f")
            chm, sm.blend = imgui.slider_float("blend into Arc of Obliteration (frames)", sm.blend, 0, 30, "%.0f")
            chm, dbg.NOX.boostGlow = imgui.slider_float("blade glow while smiting (x)", dbg.NOX.boostGlow, 1, 6, "%.1f")
            chm, sm.boomScale = imgui.slider_float("hit explosion size (x)", sm.boomScale, 0.5, 6, "%.1f")
            local downs = { 15, 12 }
            local dpick = sm.downType == 12 and 2 or 1
            chm, dpick = imgui.combo("knocks enemies", dpick, { "slammed to the ground (Slam_L)", "knocked down (Hitdown_L)" })
            if chm then sm.downType = downs[dpick] end
            chm, sm.downPower = imgui.slider_float("stagger power x (big enemies go down past their limit)", sm.downPower, 1, 500, "%.0f")
            chm, sm.lightOn = imgui.checkbox("the blade lights the area during the smite", sm.lightOn)
            chm, sm.lightLm = imgui.slider_float("blade light strength", sm.lightLm, 100, 10000, "%.0f")
            chm, sm.lightRadius = imgui.slider_float("blade light reach (m)", sm.lightRadius, 1, 15, "%.1f")
            chm, sm.chargeDelay = imgui.slider_float("charge sound vs the sword lighting up (s, minus = sooner)", sm.chargeDelay, -0.3, 1.5, "%.2f")
            local sig = ("%s|%s|%s|%s|%s|%s|%s|%s|%s"):format(sm.fast, sm.blend, sm.boomScale, tostring(sm.lightOn), sm.lightUntil, sm.lightLm, sm.lightRadius, dbg.NOX.boostGlow, sm.chargeDelay)
            if sig ~= sm.lastSig then sm.lastSig, sm.dirtyAt = sig, os.clock() end
            if sm.dirtyAt and os.clock() - sm.dirtyAt > 1.5 then sm.dirtyAt = nil; sm.save() end   -- (saved by itself)
            imgui.tree_pop()
        end
        if imgui.tree_node("Tasha's Caustic Brew") then
            local sk, chb = dbg.brew, nil
            imgui.text(sk.info)
            chb, sk.tickSecs = imgui.slider_float("acid hits every (s)", sk.tickSecs, 0.1, 1.0, "%.2f")
            chb, sk.tickDmg = imgui.slider_float("damage per acid hit", sk.tickDmg, 0, 2000, "%.0f")
            chb, sk.poisonPts = imgui.slider_float("poison build-up per acid hit (100 = poisoned)", sk.poisonPts, 0, 100, "%.0f")
            chb, sk.poisonMul = imgui.slider_float("poison damage x (our poison only)", sk.poisonMul, 1, 5, "%.1f")
            chb, sk.lingerSecs = imgui.slider_float("acid lasts (s)", sk.lingerSecs, 1, 10, "%.1f")
            chb, sk.halfWidth = imgui.slider_float("acid strip: half width (m)", sk.halfWidth, 0.5, 4, "%.2f")
            imgui.tree_pop()
        end
        if imgui.tree_node("Hex") then
            local hx, chx = dbg.hex, nil
            imgui.text("Examine (Circle) in the bind window (after Eldritch Bolt / Burst): Hex on the bound enemy | " .. hx.info)
            chx, hx.secs = imgui.slider_float("lasts (s)##hex", hx.secs, 3, 60, "%.0f")
            chx, hx.defence = imgui.slider_float("defence lowered by##hex", hx.defence, 0, 0.5, "%.2f")
            chx, hx.heal = imgui.slider_float("HP back on a kill (of max)##hex", hx.heal, 0, 0.5, "%.2f")
            if imgui.button("Hex the enemy in front (test)##hex") then
                pcall(function() local a = runtime.player(); dbg.hex_put(a, dbg.misty.pick(a)) end)
            end
            local rebuild = false
            chx, hx.freezeAt = imgui.slider_float("freeze at (s) - the X is replayed to this frame##hex", hx.freezeAt, 0, 4, "%.2f")
            rebuild = rebuild or chx
            chx, hx.copies = imgui.slider_int("copies per line (more = more solid)##hex", hx.copies, 1, 4)
            rebuild = rebuild or chx
            if rebuild and hx.target then hx.build() end
            chx, hx.roll = imgui.slider_float("line angle (deg)##hex", hx.roll, 0, 90, "%.0f")
            chx, hx.scale = imgui.slider_float("X size##hex", hx.scale, 0.2, 4, "%.2f")
            chx, hx.over = imgui.slider_float("X above the head (m)##hex", hx.over, -2, 4, "%.2f")
            chx, hx.dots = imgui.checkbox("show placement dots (green = X centre, red = line anchor, blue = 1 m along the line)##hex", hx.dots)
            chx, hx.half = imgui.slider_float("move each line along itself##hex", hx.half, -4, 4, "%.2f")
            chx, hx.side = imgui.slider_float("move the lines apart / together##hex", hx.side, -3, 3, "%.2f")
            chx, hx.bright = imgui.slider_int("X brightness (our pink file 1-3)##hex", hx.bright, 1, 3)
            if chx and hx.target then hx.build() end
            imgui.text("colour tint (255/255/255 = the file's own pink):")
            chx, hx.col[1] = imgui.slider_int("X red##hex", hx.col[1], 0, 255)
            chx, hx.col[2] = imgui.slider_int("X green##hex", hx.col[2], 0, 255)
            chx, hx.col[3] = imgui.slider_int("X blue##hex", hx.col[3], 0, 255)
            chx, hx.behind = imgui.slider_float("Burst step: behind the enemy (m)##hex", hx.behind, 0.8, 5, "%.1f")
            imgui.tree_pop()
        end
        if imgui.tree_node("Misty Dive") then
            local md, chd = dbg.misty, nil
            imgui.text(("slot: %s   |   %s   |   no-shield checks answered: %d"):format(tostring(cfg.mistySkill), md.info, md.allowed or 0))
            if imgui.button(md.binding and "press the skill now...##md" or "put it in the next skill I press##md") then md.binding = true end
            local mpick = md.mode == "ours" and 2 or 1
            chd, mpick = imgui.combo("teleport", mpick, { "SkyDive's teleport, then moved above the enemy", "ours (above the enemy in front)" })
            if chd then md.mode = mpick == 2 and "ours" or "msp" end
            chd, md.afterTeleport = imgui.slider_float("air Empale after SkyDive's teleport (s)", md.afterTeleport, 0, 0.5, "%.2f")
            chd, md.above = imgui.slider_float("height above the enemy's head (m)", md.above, 0.5, 6, "%.1f")
            chd, md.back = imgui.slider_float("toward me from the enemy (m)", md.back, 0, 4, "%.1f")
            chd, md.lockWarp = imgui.checkbox("straight down: hold the character controller too", md.lockWarp)
            chd, md.fxOn = imgui.checkbox(("our colour on its effects + body glow (%d copies played)"):format(md.fxN or 0), md.fxOn)
            local FIN = { "staggered", "always", "never" }
            local fpick = md.finish == "always" and 2 or md.finish == "never" and 3 or 1
            chd, fpick = imgui.combo("execution animation" .. (md.finishHook and "" or " (hook failed)"), fpick,
                { "only on a staggered, standing enemy", "whenever the game does it", "never" })
            if chd then md.finish = FIN[fpick] end
            chd, md.range = imgui.slider_float("finds enemies up to (m)", md.range, 3, 40, "%.0f")
            imgui.tree_pop()
        end
        imgui.tree_pop()
    end
    if imgui.tree_node("Debug") then
        imgui.text(("%s | button: %s | action: %s"):format(live.on and "ACTIVE" or "off", st.phase, tostring(dbg.action)))
        imgui.text(("Archfey Combo: part %d%s | %s | Forbeding Bolts: %d"):format(combo.stage,
            combo.target and " (target set)" or "", tostring(dbg.leap or "Quik Fot: -"), dbg.bindShots or 0))
        if combo.slash then imgui.text("Eldritch Slash: " .. (combo.slash.on and "playing" or "-")) end
        if combo.result then
            imgui.text_colored("Last " .. combo.result.text, combo.result.ok and 0xFF40FF40 or 0xFF4040FF)
        end
        imgui.text(tostring(dbg.thief or "Footpad / Controlled Fall: -"))
        imgui.text(("Test dummies: %d | %s"):format(dummy.count, dummy.status))
        for _, d in ipairs(DUMMIES) do
            if imgui.button("Spawn " .. d.name) then require("DragonCore.game.actor_fx").defer(function() dummy_spawn(d) end) end
            imgui.same_line()
        end
        if imgui.button("Remove all dummies") then
            require("DragonCore.game.summons").request_remove_all()
            dummy.set, dummy.hits, dummy.count, dummy.wanted, dummy.status = {}, {}, 0, {}, "removed"
        end
        local okH, hr = pcall(function() return sdk.get_managed_singleton("app.TimeManager"):get_InGameHour() end)
        imgui.text(("Time of day: %s:00"):format(okH and tostring(hr) or "?"))
        if imgui.button("Skip to daytime (10:00)") then
            local okS, e2 = pcall(dbg.day_skip, 10)
            if not okS then note("time skip failed: " .. tostring(e2)) end
        end
        imgui.same_line()
        ch, cfg.keepDay = imgui.checkbox("keep it daytime", cfg.keepDay == true)
        if ch then save_cfg() end
        -- the Recorder: my effects / sounds / animations (+ nearby objects' sounds) -> Caustic Brew's sound picks
        if imgui.tree_node("Recorder (my effects + sounds + animations, works with any weapon)") then
            local chr
            chr, dbg.rec.secs = imgui.slider_float("seconds", dbg.rec.secs, 2, 30, "%.0f")
            if imgui.button(dbg.rec.on and "recording..." or "record now") and not dbg.rec.on then
                dbg.rec.list, dbg.rec.t0, dbg.rec.lastMotion, dbg.rec.on, dbg.rec.scs = {}, os.clock(), nil, true, {}
            end
            local chn
            chn, dbg.rec.near = imgui.checkbox("also sounds of objects within 10 m (barrels, vases, water ...)", dbg.rec.near)
            imgui.text(dbg.rec.info)
            imgui.tree_pop()
        end
        imgui.text("Last hits (before -> after | physical, magick):")
        for i = #dbg.hits, 1, -1 do
            local h = dbg.hits[i]
            imgui.text(("  %-8s %.0f -> %.0f | physical %.0f, magick %.0f, elemental %.0f | x%.2f"):format(
                h.kind, h.before or 0, h.after or 0, h.phys, h.mag, h.elemental or 0, h.rate or 0))
        end
        for i = #dbg.log, 1, -1 do imgui.text(dbg.log[i]) end
        imgui.tree_pop()
    end
    end)
    imgui.pop_style_color(#THEME)
    if not ok then imgui.text_colored("menu error: " .. tostring(err), 0xFF4040FF) end
    imgui.tree_pop()
end)
