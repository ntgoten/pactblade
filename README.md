# Pactblade — a custom vocation for Dragon's Dogma 2 (work in progress)

A pact-bound swordsman: a fast sword in one hand, eldritch magick from the other, no shield. Pactblade is a
Fighter-based custom vocation built on **Vocation & Skill Builder (VSB)**. Most of the mechanics are in
`Pactblade.lua`, a REFramework script. It's played as Fighter or as Warfarer with a sword.

> **Status: test build 3.15, source only.** There's no release package yet. The custom effect paks (recoloured
> effects) aren't in this repo, so without them the skills fall back to the game's own look, or show nothing where
> a skill needs our copies. See `DESIGN.md` for the full development journal.

## What it adds
- **Eldritch Blast** (vocation button, tap = Thief's dodge, hold = **Eldritch Bolt**): a magick bolt. A charged bolt
  binds the target, and **Jump** in the bind window does **Misty Step** (Quik Fot leap to it).
- **Eldritch Burst**: the blast pressed during or right after Onslaught / Empale; it binds too. Jump after a Burst
  bind warps you to the far side of the enemy.
- **Hex**: Examine (Circle) in the bind window puts a glowing X over the enemy for 15 s, lowers its defence by 10 %,
  and gives 15 % HP back if it dies while hexed.
- **Archfey Combo** (Cloudfall Strike's slot): a warp combo around the target (sides, behind, above).
- **Eldritch Slash** (Hindsight Sweep's slot): Magike Cut's wave with long range, turning toward enemies.
- **Eldritch Smite** (Burst Strike's slot): a two-part overhead blow with a glowing blade; guaranteed knock-down.
- **Tasha's Caustic Brew** (Full Moon Slash's slot): a chant, then an acid wave that damages and poisons.
- **Misty Dive** (Shield Drum's slot): Mystic Spearhand's preparing jump, a warp above the enemy, then a
  straight-down air Empale.
- **Nox sword look**: a purple mist and blade glow on the sword while drawn. Onslaught is 1.5x faster, other
  attacks 1.2x. Magick damage x1.5.

## Requirements
- Dragon's Dogma 2 (Steam, post-DLC build) with **REFramework**.
- **_DragonCore** 1.2.0 and **VSB** 1.1.0 (Pactblade is picked in VSB's menu as a Fighter vocation).
- Optional: True Warfarer (Warfarer weapon switching).

## Install (source)
1. Install REFramework, _DragonCore and VSB.
2. Copy `reframework/` into the game folder (`autorun/Pactblade.lua` and `data/VSB/packs/pactblade/pack.json`).
3. In game, pick Pactblade for Fighter in VSB's menu. The REFramework menu gets a "Pactblade" section with skill
   settings.

Uninstall: delete those two files. Logs: `reframework/data/Pactblade_trace.json` and `re2_framework_log.txt`.

## Tools
- `tools/build_bank.py` builds a Wwise sound bank (bank version 140) with your own PCM audio, cloned from a small game
  bank used as a template. It's how the Smite's custom sounds were made; the audio isn't included.

## Credits and disclosure
- Built with **Claude Code (Claude Opus 5.5)** together with the author ntgoten, using the universal-modder toolkit.
- REFramework (praydog), _DragonCore and VSB, REE-Lib (efx reading/writing), vgmstream.
- Ideas inspired by D&D 5e's warlock spells (names only).

## License
MIT for the code in this repository (see `LICENSE`). Dragon's Dogma 2 and its assets belong to Capcom; none are
included here.
