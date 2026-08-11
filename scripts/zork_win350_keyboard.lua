-- NES Zork I — keyboard injection aiming for the full 350-point ending.
--
-- Uses zork_cmd_inject.lua (Enter on title → INPUT_MODE_KB). Adaptive loops for
-- troll/thief combat, sand digging, and post-fight healing. Auto-dismisses
-- read_char / [MORE] via inject.tick().
--
-- Walkthrough basis: Stanley Dunigan optimized FAQ (DogeCandy), with combat
-- handling patterned on zork_troll_keyboard.lua.
--
-- Run (ROM already built to C:\Mesen\ROMs\neszork.nes):
--   C:\Mesen\Mesen.exe C:\Mesen\ROMs\neszork.nes E:\GemmaProjects\NESZork1\scripts\zork_win350_keyboard.lua
--
-- Headless:
--   C:\Mesen\Mesen.exe --testrunner C:\Mesen\ROMs\neszork.nes E:\GemmaProjects\NESZork1\scripts\zork_win350_keyboard.lua

local inject = dofile("E:/GemmaProjects/NESZork1/scripts/zork_cmd_inject.lua")
local labels = inject.load_labels("E:/GemmaProjects/NESZork1/build/neszork.lbl")
inject.set_settle(70)

local ppu = emu.memType.nesPpuDebug
local cpu = emu.memType.nesMemory

local MAX_ATTACKS = 40
local MAX_DIGS = 12
local MAX_WAITS = 25
local MAX_EGG_WAITS = 12  -- turns for thief to open the jewel-encrusted egg
local TIMEOUT_FRAMES = 60 * 60 * 45  -- 45 minutes worst case

local phase = "run"
local step_i = 1
local attacks = 0
local digs = 0
local waits = 0
local start_frame = nil
local prev_screen = ""
local finished = false
local fail_reason = nil

local function reseed_rng(tag)
  local addr = labels["z_rng"]
  if not addr then return end
  local t = os.time() or 0
  local c = math.floor((os.clock() or 0) * 1000000)
  local lo = (t + c + (step_i * 17)) % 256
  local hi = math.floor(t / 256 + c / 257 + step_i) % 256
  if lo == 0 and hi == 0 then lo = 1 end
  emu.write(addr, lo, cpu)
  emu.write(addr + 1, hi, cpu)
  emu.log(string.format("reseed z_rng=$%04X (%s)", lo + hi * 256, tag or "?"))
end

local function read_screen()
  local t = {}
  for row = 0, 29 do
    for col = 0, 31 do
      local tile = emu.read(0x2000 + row * 32 + col, ppu)
      if tile >= 32 and tile < 127 then
        t[#t + 1] = string.char(tile)
      else
        t[#t + 1] = " "
      end
    end
    t[#t + 1] = "\n"
  end
  return table.concat(t):upper()
end

local function screen_has(screen, patterns)
  for _, pat in ipairs(patterns) do
    if screen:find(pat, 1, true) then
      return pat
    end
  end
  return nil
end

-- Only unambiguous death banners — never the dark-room warning
-- "YOU ARE LIKELY TO BE EATEN BY A GRUE".
local DEAD_YOU = {
  "****  YOU HAVE DIED  ****",
  "YOU HAVE DIED",
  "WALKED INTO THE SLAVERING",
  "SLAVERING FANGS OF A LURKING",
}

local TROLL_DEAD = {
  "TROLL DIES",
  "BLACK FOG",
  "CARCASS HAS DISAPPEARED",
  "BREATHES HIS LAST",
  "CAN'T SEE ANY TROLL",
  "CAN'T SEE THE TROLL",
  "WHAT TROLL",
}

local THIEF_DEAD = {
  "THIEF IS DEAD",
  "THIEF DIES",
  "THE THIEF DIES",
  "VANQUISH THE THIEF",
  "KILLED THE THIEF",
  "BREATHES HIS LAST",
  "BODY OF A THIEF",
  "CAN'T SEE ANY THIEF",
  "CAN'T SEE THE THIEF",
  "WHAT THIEF",
}

local HEALED_OK = {
  "YOU ARE IN PERFECT HEALTH",
  "PERFECT HEALTH",
}

local SCARAB_OK = {
  "SCARAB",
  "A BEAUTIFUL JEWELED SCARAB",
  "JEWELED SCARAB",
}

-- Ordered script. Strings = command queues. Tables = special phases.
local SCRIPT = {
  -- Into house + GUE with egg
  -- Behind House: OPEN WINDOW + W enters Kitchen; second W → Living Room.
  {
    "N", "N", "U", "TAKE EGG", "D", "S", "E", "OPEN WINDOW", "W", "W",
    "TAKE LAMP", "MOVE RUG", "OPEN TRAP", "DROP EGG", "D", "TURN ON LAMP",
  },
  -- Painting run
  -- Gallery → Studio → Kitchen; one W to Living Room (a second W overshoots
  -- into Strange Passage, which is west of the Living Room toward Cyclops).
  {
    "S", "E", "TAKE PAINTING", "N", "U", "W",
    "TAKE SWORD", "TAKE EGG", "OPEN CASE", "PUT PAINTING IN CASE",
  },
  -- Attic: Living Room → E Kitchen → U Attic; return D W to Living Room.
  -- Keep lamp on (attic/cellar dark). Grab knife explicitly (thief weapon).
  {
    "TURN ON LAMP", "E", "U",
    "TAKE KNIFE", "TAKE ROPE", "TAKE ALL",
    "D", "W", "OPEN TRAP", "D", "N",
  },
  { kind = "fight", foe = "troll", weapon = "SWORD", dead = TROLL_DEAD },
  -- Dome / temple / coffin / sceptre
  -- Drop sword here (treasure — thief loves it). Nasty knife is the thief weapon.
  {
    "DROP SWORD", "E", "E", "SE", "E",
    "TIE ROPE TO RAILING", "D",
    "TURN OFF LAMP", "TAKE TORCH", "S", "DROP LAMP",
    "E", "TAKE COFFIN", "OPEN COFFIN", "TAKE SCEPTRE", "W",
  },
  -- Feed thief (egg FIRST so he can open it → clockwork canary), bounce out.
  -- Hold coffin+sceptre for mid-fight distraction (give → stab → give → stab).
  -- Stash the nasty knife while we WAIT so he can't steal it.
  {
    "TEMPLE",
    "GIVE EGG TO THIEF",
    "GIVE TORCH TO THIEF",
    "TEMPLE",
    "DROP KNIFE",
  },
  { kind = "egg_wait" },
  {
    "TAKE KNIFE",
    "TAKE LAMP", "TURN ON LAMP", "TEMPLE",
  },
  {
    kind = "fight",
    foe = "thief",
    weapon = "KNIFE",
    alt_weapons = { "KNIFE", "STILETTO" },
    distract = { "COFFIN", "SCEPTRE" },
    dead = THIEF_DEAD,
  },
  -- Safe to WAIT-heal now: thief is dead and can't steal the knife.
  { kind = "heal" },
  -- Loot treasure room + maze coins → case
  -- Take torch BEFORE extinguishing the lamp — treasure room is dark otherwise.
  {
    "TAKE TORCH", "TURN OFF LAMP", "DROP KNIFE",
    "TAKE CHALICE", "TAKE EGG", "TAKE SCEPTRE",
    "D", "ODYSSEUS", "E", "E",
    "TAKE CANARY",
    "PUT EGG IN CASE", "PUT CANARY IN CASE", "PUT SCEPTRE IN CASE", "PUT CHALICE IN CASE",
    "DROP LAMP", "OPEN TRAP", "W",
    "NW", "S", "W", "D", "TAKE BAG",
    "N", "W", "S", "E", "S", "U",
    "PUT BAG IN CASE",
    "W", "U",
  },
  -- Troll+thief both dead: skip long WAIT heals.
  { kind = "heal", bosses_dead = true },
  {
    "TAKE COFFIN", "D", "E", "E",
    "PUT COFFIN IN CASE",
  },
  -- Garlic, loud room, dam
  {
    "E", "OPEN SACK", "TAKE GARLIC", "W",
    "D", "N", "E", "E", "E",
    "ECHO", "TAKE BAR",
    "U", "E", "N", "TAKE MATCHBOOK", "N",
    "TAKE WRENCH", "TAKE SCREWDRIVER", "PUSH YELLOW BUTTON",
    "S", "S", "TURN BOLT WITH WRENCH", "DROP WRENCH",
    "S", "SW", "S",
    "DROP SCREWDRIVER", "DROP BAR", "DROP GARLIC",
  },
  -- Hades exorcism (ivory torch is always flaming — drop it before the descent).
  -- Light candles BEFORE going down; Entrance to Hades is dark without them.
  -- Ringing the bell usually drops/extinguishes candles — pick up and relight.
  -- Keep candles lit until the torch is recovered upstairs.
  {
    "SE", "E", "D",
    "S", "DROP TORCH", "TAKE BELL", "S", "TAKE CANDLES", "TAKE BOOK",
    "LIGHT MATCH", "LIGHT CANDLES WITH MATCH",
    "D", "D",
    "RING BELL",
    "TAKE CANDLES", "LIGHT MATCH", "LIGHT CANDLES WITH MATCH",
    "READ BOOK",
    "S", "TAKE SKULL",
    "N", "U", "N",
    "TAKE TORCH",
    "DROP BOOK", "DROP CANDLES", "DROP MATCHBOOK",
    "TOUCH MIRROR",
    "E", "S", "TAKE TRIDENT", "S", "TAKE PUMP", "S", "TAKE TRUNK",
    "S", "SW", "S", "S",
    "DROP PUMP",
    "W", "W", "S", "U",
    "PUT TRIDENT IN CASE", "PUT TRUNK IN CASE", "PUT SKULL IN CASE",
  },
  -- Coal mine / diamond
  -- Torch is an open flame — must be IN THE BASKET before Gas Room.
  -- Lit lamp is OK; lit torch/candles are not.
  {
    "TAKE LAMP", "D", "N", "E", "E", "S", "S",
    "TAKE GARLIC", "TAKE SCREWDRIVER",
    "S", "S", "TOUCH MIRROR",
    "N", "W", "N", "W", "N",
    "DROP GARLIC",
    "E",
    "PUT TORCH IN BASKET",
    "PUT SCREWDRIVER IN BASKET",
    "TURN ON LAMP",
    "N", "D",
    "E", "NE", "SE", "SW", "D", "D", "S", "TAKE COAL",
    "N", "U", "U", "N", "E", "S", "N", "U", "S",
    "PUT COAL IN BASKET", "LOWER BASKET",
    "N", "D", "E", "NE", "SE", "SW", "D", "D", "W",
    "DROP LAMP", "W",
    "TAKE COAL", "TAKE TORCH", "TAKE SCREWDRIVER",
    "S", "OPEN LID", "PUT COAL IN MACHINE", "CLOSE LID",
    "TURN SWITCH WITH SCREWDRIVER", "DROP SCREWDRIVER",
    "OPEN LID", "TAKE DIAMOND",
    "N", "PUT DIAMOND IN BASKET", "PUT TORCH IN BASKET",
    "E", "TAKE LAMP", "E", "U", "U", "N", "E", "S", "N",
    "TAKE BRACELET", "U", "S",
    "RAISE BASKET", "TAKE DIAMOND", "TAKE TORCH",
    "DROP LAMP", "W", "TAKE JADE",
    "S", "E", "S", "E", "S", "TOUCH MIRROR",
    "N", "N",
    "TAKE BAR",
    "W", "W", "S", "U",
    "PUT BAR IN CASE", "PUT JADE IN CASE", "PUT DIAMOND IN CASE", "PUT BRACELET IN CASE",
  },
  -- Outdoor: boat, scarab, rainbow, bauble
  {
    "TAKE CANARY", "TAKE SCEPTRE",
    "D", "N", "E", "E", "S", "S", "TAKE PUMP",
    "E", "U", "E", "D",
    "INFLATE BOAT WITH PUMP", "DROP PUMP",
    "PUT SCEPTRE IN BOAT", "ENTER BOAT", "LAUNCH",
    "TAKE SCEPTRE",
    "WAIT", "WAIT", "WAIT", "WAIT", "WAIT", "WAIT",
    "TAKE BUOY", "E",
    "EXIT", "OPEN BUOY", "TAKE EMERALD", "DROP BUOY",
    "TAKE SHOVEL", "NE",
  },
  { kind = "dig" },
  {
    "TAKE SCARAB", "DROP SHOVEL",
    "SW", "S", "S",
    "WAVE SCEPTRE", "W", "W",
    "TAKE GOLD",
    "SW", "U", "U", "NW", "W", "N", "N",
    "WIND CANARY", "TAKE BAUBLE",
    "S", "E", "W", "W",
    "PUT ALL IN CASE",
    "SCORE",
  },
  { kind = "check_score" },
  -- Finish into barrow (optional but nice)
  {
    "TAKE MAP", "READ MAP",
    "E", "E", "N", "W", "SW", "ENTER",
  },
  { kind = "done" },
}

local function enqueue(list)
  inject.enqueue(list)
end

local function begin_step()
  local s = SCRIPT[step_i]
  if not s then
    phase = "done"
    return
  end
  if type(s[1]) == "string" or (s.kind == nil and s[1] ~= nil) then
    -- plain command list (array part)
    local cmds = {}
    for _, c in ipairs(s) do
      if type(c) == "string" then cmds[#cmds + 1] = c end
    end
    emu.log(string.format("STEP %d/%d: queue %d cmds", step_i, #SCRIPT, #cmds))
    enqueue(cmds)
    phase = "queue"
  elseif s.kind == "fight" then
    emu.log(string.format("STEP %d: fight %s with %s", step_i, s.foe, s.weapon))
    reseed_rng(s.foe)
    attacks = 0
    s._wpn_i = 1
    s._distract_i = 1
    s._next_distract = (s.distract ~= nil)
    prev_screen = read_screen()
    phase = "fight"
  elseif s.kind == "heal" then
    emu.log(string.format("STEP %d: heal waits", step_i))
    waits = 0
    enqueue({ "DIAGNOSE" })
    phase = "heal"
  elseif s.kind == "egg_wait" then
    emu.log(string.format("STEP %d: wait for thief to open egg", step_i))
    waits = 0
    phase = "egg_wait"
  elseif s.kind == "dig" then
    emu.log(string.format("STEP %d: dig sand", step_i))
    digs = 0
    phase = "dig"
  elseif s.kind == "check_score" then
    emu.log(string.format("STEP %d: verify score", step_i))
    phase = "check_score"
  elseif s.kind == "done" then
    phase = "done"
  else
    fail_reason = "unknown step kind at " .. tostring(step_i)
    phase = "fail"
  end
end

local function advance()
  step_i = step_i + 1
  begin_step()
end

local function fail(msg)
  fail_reason = msg
  phase = "fail"
  emu.log("WIN350 FAIL: " .. msg)
  emu.displayMessage("zork", "350 FAIL")
end

local function pass(msg)
  finished = true
  phase = "done"
  emu.log("WIN350 PASS: " .. (msg or "350 points"))
  emu.displayMessage("zork", "350 PASS")
end

begin_step()

emu.addEventCallback(function()
  local st = emu.getState()
  local frame = st["frameCount"] or 0
  if not start_frame then start_frame = frame end

  if finished or phase == "fail" then
    return
  end

  if frame - start_frame > TIMEOUT_FRAMES then
    fail("timeout")
    return
  end

  local p = inject.tick()
  local screen = nil

  -- Global death detect when idle between commands
  if p == "idle" or p == "wait_prompt" then
    screen = read_screen()
    if screen_has(screen, DEAD_YOU) then
      fail("player died")
      return
    end
  end

  if phase == "queue" and p == "idle" then
    advance()
    return
  end

  if phase == "fight" and p == "idle" then
    screen = screen or read_screen()
    local sdef = SCRIPT[step_i]
    local dead = screen_has(screen, sdef.dead)
    if dead then
      emu.log(string.format("  %s defeated (%s) after %d attacks", sdef.foe, dead, attacks))
      advance()
      return
    end

    -- Thief: if we knock the stiletto away, grab it before he recovers it.
    if sdef.foe == "thief" then
      if sdef._stile_pending then
        sdef._stile_pending = false
        if screen:find("TAKEN", 1, true) then
          emu.log("  got stiletto — he stays unarmed")
          sdef.weapon = "STILETTO"
        end
        -- fall through to next action this idle
      elseif (not sdef._stile_done)
          and screen:find("UNARMED", 1, true)
          and not screen:find("RETRIEVES HIS STILETTO", 1, true) then
        sdef._stile_done = true
        sdef._stile_pending = true
        emu.log("  thief disarmed — TAKE STILETTO")
        enqueue({ "TAKE STILETTO" })
        return
      end
    end

    if screen:find("YOU DON'T HAVE THAT", 1, true)
        or screen:find("DON'T HAVE THE", 1, true) then
      -- Distract give may fail if item already gone; fall through to weapon/alts.
      if sdef.distract and sdef._distract_i and sdef._distract_i <= #sdef.distract + 1 then
        -- ignore; try attack path below after bumping distract index
        if sdef._next_distract then
          emu.log("  distract give failed — skip to attack")
          sdef._next_distract = false
        end
      end
      if not sdef._wpn_i then sdef._wpn_i = 1 end
      local list = sdef.alt_weapons or { sdef.weapon }
      local next_i = sdef._wpn_i + 1
      if next_i > #list then
        fail(string.format("%s fight: missing weapon %s", sdef.foe, sdef.weapon))
      else
        sdef._wpn_i = next_i
        sdef.weapon = list[sdef._wpn_i]
        emu.log(string.format("  weapon fallback → %s", sdef.weapon))
        attacks = attacks + 1
        local cmd = string.format("KILL %s WITH %s", sdef.foe:upper(), sdef.weapon)
        enqueue({ cmd })
      end
    elseif screen:find("CAN'T SEE ANY " .. sdef.foe:upper(), 1, true)
        or screen:find("CAN'T SEE THE " .. sdef.foe:upper(), 1, true)
        or screen:find("WHAT " .. sdef.foe:upper(), 1, true) then
      fail(string.format("%s fight: foe not here", sdef.foe))
    elseif attacks >= MAX_ATTACKS then
      fail(sdef.foe .. " not dead after max attacks")
    elseif sdef._next_distract and sdef.distract and sdef._distract_i <= #sdef.distract then
      local item = sdef.distract[sdef._distract_i]
      sdef._distract_i = sdef._distract_i + 1
      sdef._next_distract = false
      local cmd = string.format("GIVE %s TO %s", item, sdef.foe:upper())
      emu.log("  distract: " .. cmd)
      enqueue({ cmd })
    else
      -- Alternate give/stab while distract items remain.
      sdef._next_distract = (sdef.distract ~= nil and sdef._distract_i <= #sdef.distract)
      attacks = attacks + 1
      reseed_rng(sdef.foe .. "-swing")
      local cmd = string.format("KILL %s WITH %s", sdef.foe:upper(), sdef.weapon)
      emu.log(string.format("  attack %d: %s", attacks, cmd))
      enqueue({ cmd })
    end
    return
  end

  if phase == "heal" and p == "idle" then
    screen = screen or read_screen()
    local sdef = SCRIPT[step_i]
    -- Once troll and thief are both gone, skip long WAIT heals.
    if sdef and sdef.bosses_dead then
      emu.log("  heal skip (troll+thief already dead)")
      advance()
      return
    end
    if screen_has(screen, HEALED_OK) or waits >= MAX_WAITS then
      emu.log(string.format("  heal done (waits=%d)", waits))
      advance()
    else
      waits = waits + 1
      enqueue({ "WAIT" })
    end
    return
  end

  if phase == "egg_wait" and p == "idle" then
    screen = screen or read_screen()
    -- Knife is dropped: also burn heals here so we enter the fight healthy.
    if waits == 0 then
      waits = 1
      enqueue({ "DIAGNOSE" })
      return
    end
    local healed = screen_has(screen, HEALED_OK)
    if waits >= MAX_EGG_WAITS and (healed or waits >= MAX_EGG_WAITS + 15) then
      emu.log(string.format("  egg/heal wait done (waits=%d healed=%s)", waits, tostring(healed ~= nil)))
      advance()
    else
      waits = waits + 1
      enqueue({ "WAIT" })
    end
    return
  end

  if phase == "dig" and p == "idle" then
    screen = screen or read_screen()
    if screen_has(screen, SCARAB_OK) and digs > 0 then
      emu.log(string.format("  scarab after %d digs", digs))
      advance()
    elseif digs >= MAX_DIGS then
      fail("scarab not found")
    else
      digs = digs + 1
      enqueue({ "DIG SAND" })
    end
    return
  end

  if phase == "check_score" then
    if p ~= "idle" then return end
    screen = screen or read_screen()
    if screen:find("350", 1, true)
       and (screen:find("SCORE", 1, true)
            or screen:find("MASTER ADVENTURER", 1, true)
            or screen:find("POSSIBLE", 1, true)) then
      emu.log("  score OK (350 detected on screen)")
      advance()
    else
      if not screen:find("YOUR SCORE IS", 1, true) and not screen:find("SCORE IS", 1, true) then
        enqueue({ "SCORE" })
      else
        fail("score is not 350 — screen dump follows")
        emu.log("--- screen ---")
        emu.log(screen)
      end
    end
    return
  end

  if phase == "done" then
    pass("script reached Stone Barrow ending")
  end
end, emu.eventType.endFrame)
