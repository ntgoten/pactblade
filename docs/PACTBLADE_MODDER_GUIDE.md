# How Pactblade was made - a guide for modders

Pactblade is a custom vocation for Dragon's Dogma 2: a sword in one hand, eldritch magick in the other, 8 new skills
and a handful of always-on abilities. This guide explains how it's put together and how each part was built, so you
can make something similar, or continue Pactblade. It assumes you know Lua basics and have used REFramework.

A denser, more technical version for AI assistants is `PACTBLADE_AI_GUIDE.md`. The source is the script
`reframework/autorun/Pactblade.lua` (search it for the names used here).

---

## 1. The building blocks

| Piece | What it does for Pactblade |
|---|---|
| **REFramework** | Runs Lua scripts inside the game: you can hook (intercept) any game method, call game functions, read and change game objects. It also loads `pak_mods` (custom file packs). |
| **VocationAndSkillBuilder (VSB)** | Adds a custom vocation (name, icon, description, which vanilla vocation it's based on) and custom skill entries the game treats like real skills: they appear at the Vocation Guild, cost Discipline, unlock at a rank and go into skill slots. |
| **_DragonCore** | A helper library: the player as an easy object (`a:request_action`, `a:button_pressed`, `a:stamina()`...), spawning projectiles (shells), effects, summons. |
| **_ScriptCore** | Ray casts against the ground (where to land, where a door goes). |
| **A pak** | Our own effect and sound files (recoloured copies of game effects), loaded at game start. |

The big idea: **VSB makes the vocation and the skill entries; the Lua script does everything the skills actually do.**
The VSB skills themselves are empty shells. When you press one, the script recognises it and runs its own code.

---

## 2. How a skill press reaches the script

1. VSB gives each of our skills an ID (it keeps them in `reframework/data/VSB/state/idtable.json`, keyed by the skill's
   fixed uuid).
2. When you press a skill button, the game calls `PlayerInputProcessorDetail.processCustomSkill(...)` with that ID.
   Pactblade hooks this method.
3. An **adapter** translates our VSB ID into the Fighter skill ID the skill's code was originally written for (the
   first versions replaced Fighter skills directly) and marks the press as "ours". Every Pactblade skill only reacts to
   presses marked this way, so the real Fighter skills keep working normally.
4. The skill code then plays animations, spawns effects and deals damage itself, and tells the game to skip its own
   handling of the press (`SKIP_ORIGINAL`).

Two catches you'll meet too:
- **In the air** the game drops ground skills before step 2. Pactblade also hooks the button's own entry
  (`processCustomSkill(CharacterInput.Action, ...)`), which still fires mid-air - that's how the air versions work.
- The game asks "is this skill available?" (`HumanSkillAvailability.isCustomSkillAvailable`). For shield skills
  without a shield it says no, so the script answers yes for its own presses.

### The skill JSON (VSB)
```json
{ "schema_version": 1, "uuid": "...", "id": "pb_smite", "kind": "custom",
  "presentation": { "name": {"en": "Eldritch Smite"}, "desc": {"en": "..."}, "icon": 35 },
  "availability": { "mode": "all" },
  "levels": { "1": {"unlock_rank": 8, "dcp_cost": 3000}, "2": {"unlock_rank": 8, "dcp_cost": 100} },
  "trigger": { "type": "slot" },
  "timeline": [ { "id": "n1", "type": "script", "frame": 0, "fn": "return true" } ] }
```
Two levels per skill: with only one, the Vocation Guild crashed. The icon is a number into the game's own skill icon
sheets (VSB's editor shows them).

---

## 3. Making things happen

### Animations
- **Borrow any vanilla action:** `a:request_action("Job05_CrescentSlashNormal", 0)` plays a Warrior swing on a Fighter.
  Most actions of other vocations work if the character has their animations loaded.
- **Cut and speed them:** every frame, read the full-body layer's frame (`get_Frame`) and jump with
  `changeMotion(bank, motion, frame, blend, 1, 1)` (a crossfade looks much better than a hard `set_Frame`). Fire things
  at chosen frames (the beam fires at frame 57 of its animation).
- **Stop the game from interrupting:** hook `ActionManager.requestActionCore` and refuse the follow-ups / landings the
  game tries to start while your skill plays. Mark your own requests so you don't block yourself.
- **Animations from another vocation's file:** add the motion list as a dynamic motion bank (the Mage chant is
  `ch00_006_atk.motlist`, bank 9112), then force the motion every frame and pause the character's animation state
  machine (`MotionFsm2`) while it plays.
- To find which animation and frames you want, a small tool that plays clips frame by frame helps a lot.

### Effects
Most of Pactblade's look is the game's own effects, recoloured purple.
1. **Find the effect.** A "recorder" logs every effect the player requests for a few seconds (effect IDs are
   `container index / container / element`). Map the ID to its file through the character's effect data.
2. **Extract** the `.efx` file from the game's paks.
3. **Recolour** it with a tool that rewrites the colour fields (keeps saturation and brightness, changes the hue).
   Layers named `inv...` are inverted: they often need the opposite hue. Some colours sit in gradient textures instead.
4. **Save it under a new path** (`vfx/effects/pactblade/pb_*.efx`). Never overwrite a game file in a pak: the game
   crashes at start.
5. **Pack** the files into a pak in `pak_mods`.
6. **Use it** in one of three ways:
   - Play it yourself: a new GameObject with an `EffectPlayer` component holding your file. Move it every frame to
     follow a hand or a target.
   - Replace the game's copy: when the game requests that effect, kill it and play yours at the same spot.
   - Swap the file inside the character's own effect data, when the effect has to stay attached to body bones (the
     green flames of Hellish Rebuke work this way).
- Tinting a running effect (`set_Color`) is quick, but it multiplies colours and can turn see-through layers into a
  solid veil over the screen. Baked copies look better.

### Damage and reactions
- Our own hits: `HitManager.directDamage` with a new `DamageInfo` (damage, magick or not, the reaction type such as
  flinch / knock-down, and its power). Strong reactions on big monsters need a high power and "force received".
- Changing the game's hits: hook `calcDamageValue` (the number), `calcDamageReaction` (the stagger) and
  `getReactionDamageType` (the reaction).
- Statuses: `StatusConditionCtrl.reqStatusConditionApplyCore` (fire, poison, ...).
- Careful with kills: a huge knock-down power on the killing hit makes the body fly away and the loot with it.

### Teleports
Move the character's transform AND call its CharaController `warp`, in the game's update step, and hold the position
for a few frames (some animations push you). Find the ground with a ray cast first, so you never land inside terrain.

### Stamina
Note the stamina at the press, then shortly after take or give back the difference, so the skill costs exactly what
you want even when the borrowed animation drains its own amount.

---

## 4. The skills, one by one

**Eldritch Slash** - a Warrior swing (Crescent Slash) cut to its first part; at a chosen frame it launches Mystic
Spearhand's Magike Cut wave (a projectile), with longer range, double damage, more stagger, and purple copies of its
effects that travel with the wave. The character turns toward the nearest enemy.

**Tasha's Caustic Brew** - the Mage's chant animation (3 s, with the Mage's magic circle placed in front of you), then
an acid-green wave flows forward from 1 m ahead. The script itself checks every 0.3 s who stands in the strip and
deals small damage plus poison build-up; enough build-up poisons. Splash sounds come from a monster's sound bank. If a
hit makes you flinch or fall during the chant, the cast is interrupted, like a vanilla spell.

**Misty Strike** - Mystic Spearhand's crouch from Skydragon, a warp behind the target, then the last hit of Riotous
Fury. After the hit the recovery plays faster, and any attack or skill press ends it at once. Works from a jump too.

**Misty Dive** - Mystic Spearhand's preparing jump, a warp above the enemy, then an air Empale straight down. The
descent is the script's own (it follows the enemy and guarantees the hit). The Spearhand's teal effects are replaced
with purple copies.

**Eldritch Blast** - a beam from the off hand. Real stretched beam meshes didn't render, so the beam is a row of
copies of a flash effect laid from the palm to the target, frozen, held, then thinned out. On the ground it uses the
opening of Riotous Fury (a shield push, which reads as a thrust of the hand without a shield); in the air the Spearhand's
bolt animation.

**Archfey Combo** - a chain of borrowed attacks with warps between them: the Archer's Kite Arrow kick, a warp to the
target's side, Rush Attack, a warp behind, its finisher, a warp above the head, the end of Cloudfall Strike. Each warp
leaves the Spearhand's ghostly afterimage (the game's own clone), recoloured, and wisps at your feet.

**Eldritch Smite** - two parts of Warrior attacks joined (a short heavy swing into the end of Arc of Obliteration), the
second sped up. During part 2 the sword glows brighter; the first hit gets a purple explosion and a guaranteed
knock-down (except on a kill, so loot doesn't fly). Own sounds.

**Tasha's Otherworldly Guise** - the hardest one. A ghost armour over your own for 60 s:
- The ghost is the Trickster's decoy clone, dressed in other armour (Grand Cuirass and Raptor Claws) through the
  game's own part swapper, the same system transmog uses.
- Every frame it copies your pose bone by bone, slightly bigger than you.
- Material values make it see-through (illusion alpha / fade), with a purple rim light and a purple cloud.
- The decoy's own behaviour (enemies targeting it, ending itself, reacting to your hits) is switched off for it.
- The bonuses show on the status screen because they're written into the worn chest piece's item data, not hooked on
  the screen.
- Levitate is the script's own floating movement with the Mage's levitation animations.

**Always-on abilities** (vocation button, Interact):
- **Eldritch Bolt / Burst:** Mystic Spearhand's bolt animation with our projectile. The game's own binding bolt is let
  through, because its "bind" opens the window for Misty Step (Jump) and Hex (Interact).
- **Hellish Rebuke:** a window right after you're hit. Pressing Interact sets the attacker on fire, with green flames
  swapped into that enemy's own burning effect.
- **Dimension Door:** a separate script module from another mod of the author (aim, a door, a camera flight).

---

## 5. Things that will crash or break, and the rules they taught
- Never overwrite a game file path in a pak. Only new paths.
- Never create your own clone handler; use the game's existing ones (Spearhand afterimage, Trickster decoy).
- Don't put material modes on weapons; a weapon switch then crashes the game. Write the material values directly.
- Don't rewrite a projectile's effect list every frame (it runs on other threads).
- Effects with zero particles crash ("heap allocation failed"); hide layers by alpha instead.
- Lua allows 200 local variables per chunk; a big script hits that. Wrap new sections in their own function.
- A variable used above the line where it's defined is nil at run time. The syntax check won't catch it, and in
  REFramework one erroring callback can stop the others on the same game event.
- Status screen numbers can't be changed by hooking the screen; change the item data the screen reads.
- Keep modded values out of saves and online pawn data: restore them while the game saves or uploads.

---

## 6. Tools used
- **REFramework** (its console / log `re2_framework_log.txt` for errors).
- **ree-pak-cli** - unpack and pack `.pak` files (needs a file list to show names).
- **REE-Lib**-based small command line tool - extract files from the game's paks, read `.efx` layers, recolour them.
- **Wwise bank builder** (a script that clones a small game sound bank and puts your own PCM audio in it) and
  **vgmstream** to listen to game sounds.
- **Fluffy Mod Manager** - install and package (`modinfo.ini` + the folder layout).
- An **il2cpp dump** of the game (all types, methods, fields, enums) to find what to hook.

## 7. Credits
Built by ntgoten with AI assistance (Claude Code). Thanks to praydog (REFramework), Bloodragon (_DragonCore, VSB),
SilverEzredes and alphaZomega (_ScriptCore), Nickesponja (UDD2P / NickCore), and the REE-Lib / ree-pak / vgmstream
authors. Dragon's Dogma 2 and its assets belong to Capcom.
