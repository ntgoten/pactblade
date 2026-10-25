# Pactblade

A custom vocation for Dragon's Dogma 2: a pact-bound swordsman with a fast, magick-charged blade in one hand and
eldritch magick in the other. No shield. Inspired by the D&D 5e warlock (names only).

Pactblade is built on **Vocation & Skill Builder (VSB)** as a Fighter vocation and runs as a REFramework script.
Play it as Fighter, or as Warfarer with a sword. Version **1.0**.

**Download:** the zip from [Releases](../../releases) - it includes the effect / sound pak, which is not in the source here.

## Requirements

| What | Version | Why |
|---|---|---|
| Dragon's Dogma 2 (PC, Steam) | post-DLC update | Tested on the current build. |
| [REFramework](https://github.com/praydog/REFramework) | current | Runs the script and loads the effect pak. |
| [_DragonCore](https://www.nexusmods.com/dragonsdogma2/mods/1916) | 1.2.0 or newer (tested 1.2.5) | Pactblade's library. |
| [VocationAndSkillBuilder (VSB)](https://www.nexusmods.com/dragonsdogma2/mods/1917) | 1.4.0 or newer | The vocation and its 8 skills. |
| [_ScriptCore](https://www.nexusmods.com/dragonsdogma2/mods/30) | current | Ground checks (Dimension Door, Misty Strike landings). |

Recommended: [Fluffy Mod Manager](https://www.fluffyquack.com/) to install.

## Install

1. Install the requirements.
2. Add the zip to **Fluffy Mod Manager** and enable it. Or copy its `reframework` and `pak_mods` folders into the game
   folder, next to `DD2.exe`, merging folders.
3. Start the game. In the REFramework menu (Insert): **VocationAndSkillBuilder → Vocations → Fighter: pick Pactblade**.
4. Be a Fighter (or a Warfarer with a sword in hand). The skills are at the Vocation Guild.

Back up your saves before trying any new mod.

## Stats and passives

- **Magick damage x1.5:** the magick part of all your hits is multiplied by 1.5 (the physical part is unchanged).
- **The sword carries magick:** with a sword in hand, its Magick equals its Strength (shown on the status screen),
  and it carries full-strength **Thunder**. Back to normal when Pactblade isn't active.
- **Fast blade:** Onslaught 1.5x faster, every other attack 1.2x.
- **Core skills:** Thief's **Controlled Fall** and **Footpad** are on. Fighter's shield core skills are off.
- **No shield:** a shield can't be equipped while Pactblade is active; the shield actions are off.
- **No boons:** elemental boons (Fire / Ice / Thunder Boon) can't be put on you; the sword's Thunder replaces them.
- **Stat growth:** Fighter's.

## Always available (no skill slot)

| Ability | Input | What it does |
|---|---|---|
| Swift Step | tap the **vocation button** | Thief's dodge roll. |
| **Eldritch Bolt** | **hold** the vocation button, release | A charged magick bolt. **Binds** the target it hits. |
| **Eldritch Burst** | vocation button **during / right after a sword attack** | A point-blank blast. **Binds** the target. |
| **Hex** | **Interact** while a target is bound | Hex for 15 s: -10 % defence; if it dies hexed, you get 15 % of your max HP back. |
| **Misty Step** | **Jump** while a target is bound | Leap to it (after a Bolt) or warp to its far side (after a Burst). |
| **Hellish Rebuke** | **Interact** right after an enemy hits you | The attacker flinches and catches green fire. 30 % of your max stamina, once every 6 s. |
| **Dimension Door** | hold the vocation button + **d-pad up** (keyboard: **B**) | Aim (a pillar of frost light marks the spot, up to 500 ft), press again to open a door, walk through it. Press once more to close it. |

## Skills

Learned at the Vocation Guild with Discipline (DCP), equipped like any weapon skill.

| Skill | Rank | DCP | What it does |
|---|---|---|---|
| Eldritch Slash | 1 | 300 | A sweeping arc of eldritch force that cleaves foes from afar. |
| Tasha's Caustic Brew | 1 | 300 | A chant, then a torrent of acid that washes over the foes before you and poisons them. |
| Misty Strike | 2 | 500 | Step through the mist behind a foe and strike before they can turn. Works from a jump. |
| Misty Dive | 3 | 800 | Vanish into mist and plunge down on a foe from above. Works from the air. |
| Eldritch Blast | 5 | 1500 | A searing beam of eldritch energy from your off hand. Works from the air. |
| Archfey Combo | 7 | 2500 | A fey-born flurry: vanish and strike from every side in quick succession. |
| Eldritch Smite | 8 | 3000 | A crushing two-part overhead blow that knocks even great foes to the ground. |
| Tasha's Otherworldly Guise | 9 | 4000 | A spectral armour from beyond for 60 s (see below). Costs half your stamina. |

Each skill has a second level for 100 DCP at the same rank (it's there for the game's skill menus; it doesn't change
the skill). A hit strong enough to make you flinch or fall interrupts a chant (Caustic Brew, Guise).

**Tasha's Otherworldly Guise** (60 s, paused in menus):
- +20 % Defense and Magick Defense
- Fire, burning and poison resistance (all on the status screen)
- **Levitate:** hold Jump in the air, steer with the stick (no Eldritch Bolt while levitating)
- A ghostly armour over your own

## Combos

```
Sword attack (Onslaught / Empale / Tusk Toss)
 └─ vocation button right after → ELDRITCH BURST ── target bound ─┬─ Interact → HEX
                                                                  └─ Jump     → MISTY STEP: warp to its far side
Hold the vocation button
 ├─ release when charged → ELDRITCH BOLT ── target bound ─┬─ Interact → HEX
 │                                                        └─ Jump     → MISTY STEP: leap to it
 └─ + d-pad up → DIMENSION DOOR (the Bolt is cancelled)
Get hit (a flinch or no reaction)
 └─ Interact right after → HELLISH REBUKE   (while a target is bound, Interact goes to Hex instead)
Eldritch Burst
 └─ an attack during its recovery → straight into the attack
Misty Strike
 └─ after its hit: attack / skill / jump / vocation button / dash → straight on (no recovery)
Jump
 ├─ Eldritch Blast / Misty Dive / Misty Strike → their air versions
 └─ with Otherworldly Guise on: hold Jump → LEVITATE
```

## Settings

REFramework menu (Insert) → Script Generated UI → **Pactblade 1.0**: Nox sword look on/off, arm effect on/off, and
**Dimension Door** (on/off, also for other vocations, the key, range, how long a door stays open, the door's look).

## Safe for your save and online

Nothing Pactblade changes is written into your save or into the pawn / Arisen data the game uploads: the sword and the
Guise chest piece go back to their originals while the game saves or uploads. Uninstalling leaves a normal save.

## Uninstall

Disable it in Fluffy Mod Manager, or delete `reframework/autorun/Pactblade.lua`, the `reframework/autorun/Pactblade`
folder, `reframework/data/VSB/packs/pactblade`, `pak_mods/Pactblade.pak` and `reframework/data/Pactblade*.json`.

## Known issues

- Single player only (your character, not pawns).
- As Warfarer, switching weapons keeps an active Guise on.
- Resting at an inn or camp doesn't end the Guise.
- When the Guise ends, a faint gold shimmer of its decoy can stay where it ended (gone with the next cast).
- The chant animations are made for a staff, so the hands are posed for one.
- Lenient Stagger and Exhaustion: Pactblade triggers Controlled Fall itself; with both installed it may double.

## How it was made

- [docs/PACTBLADE_MODDER_GUIDE.md](docs/PACTBLADE_MODDER_GUIDE.md) - for modders: how the vocation and each skill were built.
- [docs/PACTBLADE_AI_GUIDE.md](docs/PACTBLADE_AI_GUIDE.md) - the same in compact technical form, for AI coding assistants.

Both are also in the release zip (Pactblade_docs).

## Credits

- **Capcom** for Dragon's Dogma 2. The effects, animations and most sounds are the game's own, used by ID or as
  recoloured copies. No game file is replaced.
- **praydog** for REFramework.
- **Bloodragon** for _DragonCore and VocationAndSkillBuilder.
- **SilverEzredes** and **alphaZomega** for _ScriptCore.
- **Nickesponja** for UDD2P and NickCore, whose scripts showed how to play effects, add animation banks and warp.
- REE-Lib (effect files), ree-pak-cli (paks), vgmstream (sounds).
- Built by ntgoten with AI assistance: [Claude Code](https://claude.com/claude-code) and the
  [universal-modder](https://github.com/rehan-remade/universal-modder) toolkit.
