# Pactblade - custom vocation (VSB pack + companion Lua) - design notes 2026-10-19

User spec: Fighter base, sword only (no shield), level-up growth of Mystic Spearhand, Thief core skills Controlled
Fall + Footpad, Defend replaced by "Eldritch Blast" (tap) / "Charged Eldritch Blast" (hold) using Mystic Spearhand's
Redouted/Forbeding Bolt animations, Magike Sperepelote's blast visual scaled down, MSP charge glow ALWAYS on the left
hand (recoloured) while Pactblade is active, "Misty Step" = Quik Fot after a charged blast lands, Onslaught/Empale
1.5x speed. Damage idea: tap = 5x Sorcerer Magick Bolt, charged = 10x (of the tap? ask).

Game facts found:
- Skill names (game text): job07_act_02 Redouted Bolt, act_03 Forbeding Bolt, skill_04 Magike Sperepelote,
  normal_01 Quik Fot; job04_normal_02 Controlled Fall, normal_03 Footpad; job01_act_02 Defend.
- Actions: Job01_Guard (Defend); Job07_AttackLeft (Redouted?), Job07_MagicBindImcomplete / Complete (Forbeding
  uncharged/charged), Job07_MagicBindJustLeap(+Landing) = Quik Fot, Job07_MagicBindJustExplosion = Scatering Bolt,
  Job07_Gungnir/GungnirShoot/Abort = Magike Sperepelote.
- Shells ch230shellparamdata_job07.user / humanshellparamdata_job07.user: 0-5 bind bolts, 11-14 Gungnir charge sizes.
- HumanNormalSkillID: Job04_BreakFall 17 (Controlled Fall), Job04_KickWall 18 (Footpad), Job07_MagicBindJustLeap 27
  (Quik Fot); Fighter shield ones: HalfJustGuard 4 / JustGuard 5 (Deflect/True Deflect), TuskToss 6, FallGuard 7
  (Steeled Foundation), EnchantGuard 8 (Enchanted Counter). Checks: HumanSkillContext.isNormalSkillEnable(ID),
  PlayerInputProcessorDetail.isNormalSkillEnable(ID), HumanSkillAvailability.isNormalSkillAvailable(ID).
- Level-up growth: app.JobStatusParamHolder.getJobStatusParam(JobEnum) -> JobStatusParam (Hitpoint, Stamina, Attack,
  Defence, MagicAttack, MagicDefence, Blow, BlowResistance, Weight).
- Effects: via.effect.EffectPlayer set_Color, CreatedEffectContainer setRootColor/setGroupColor (recolour = to test).
- Fighter shield weapon skills: Shield Summons, Springboard, Shield Bash, Counter Slash, Impeccable Guard, Perfect
  Defense. Tusk Toss is a sword move (keep?).
- VSB: core skills (kind "core") with trigger replace_action (e.g. Job01_Guard) / input_combo (press/hold/tap),
  conditions incl. button_held, hit_landed; no colour API in DragonCore; no vocation-wide speed.

## Decisions 2026-10-20 (user)
- Damage: tap = 5x Sorcerer Magick Bolt, charged (hold) = 10x Magick Bolt.
- The blast must come out of the left PALM (spawn at the left hand joint, aimed at crosshair/target).
- Passive: physical damage +20 %, magick damage x2 (to offset swords having no Magick).
  Game: DamageInfo has SlashDamage / ShootDamage (physical) and MagicDamage parts besides Damage;
  AttackUserData has ActionAttackValue (physical) and ActionMgcAttackValue (magick). Plan: after
  HitController.calcDamageValue scale Damage by (1.2*phys + 2*mag)/(phys+mag) for the player's hits (own + shells).
  Calibrate 5x/10x from the shell files' attack values (Magick Bolt shell vs Gungnir shell; both use Magick).
- Eldritch Blast must NOT flinch (Redouted Bolt) or bind/hold (Forbeding Bolt) targets: the bolt actions' own
  shells are suppressed; only the blast (Magick Bolt attack values) hits. Misty Step therefore triggers on our own
  "charged blast landed" check (VSB hit_landed + Jump window), not on the game's bind.

## Probe 0.1 results (2026-10-20, user was Warfarer job 10, later Mystic Spearhand)
- Job07ActionCtrl + MagicBindCtrl exist on the character regardless of vocation (all 10 job controllers on Human).
- Job07_MagicBindImcompleteFullBody and Job07_MagicBindComplete play fine -> candidates for tap / charged blast
  (user wants to see both once Eldritch Blast works; leaning to Complete).
- Core-skill grant hooks: game asked 0 times. Cause: only the CURRENT vocation's input handler runs. Lenient Stagger
  and Exhaustion (installed) does Controlled Fall for everyone by calling
  player.<InputProcessor>.DetailInstances[3]:processBreakFall() every frame (if skillContext:isNormalSkillEnable(17)).
  Same route for Footpad: DetailInstances[3]:processKickWall(); Quik Fot: DetailInstances[6]:processJustMagicBind().
- onHitMagicBind(enemy, pos) accepted, but no leap (no Job07 handler running) -> retest with the handler.
- Damage: Damage = SlashDamage x ActionRate x DamageRate (e.g. 1269 x 1.0 x 1.1 = 1395.9; Empale-type rates 1.3-2.0).
  Physical part = Slash/Shoot, magick part = MagicDamage -> passive split is doable.
- Charge effect: setRootColor tints only a big faint outer cloud, not the cyan arm glow (user screenshots). 0.2 tints
  each EffectPlayer layer separately and records the effect IDs (requestEffect) to replay the glow permanently.

## Probe 0.2 results (2026-10-20)
- User: Pactblade must NOT rely on Lenient Stagger -> it calls Thief's processBreakFall itself (watch for doubling
  when LSE is also installed).
- Footpad WORKS via DetailInstances[3]:processKickWall() every frame.
- Quik Fot: no leap even as Mystic Spearhand after onHitMagicBind -> 0.3 also restarts MagicBindHitTimer.
  Fallback: custom Misty Step (Job07_MagicBindJustLeap action + own movement to the marked enemy).
- Per-layer tint of MagicBindChargeEffect (ch00 file 0 id 160 = faint cloud) only tints the cloud: the arm glow is
  another effect. Recorded while charging as MSP: ch07 file "VFX/Effects/Character/ch07/13_ch07_ns_Ref.pfb"
  (index 13) id 25 elements 0 and 50. Replaying ch00 160 = invisible cloud; a later replay crashed (0/25/11, not a
  charge effect). As Fighter index 13 is another file -> MSP's file must be added:
  ObjectEffectManager2.addExternalDataContainer(via.Prefab, Int32) / requestSetDataContainer; the prefabs are in
  app.HumanCombatEffectResourceHolder.EffectContainer.EffectDataSetList (DataContainerId + EPVData prefab).
  via.Prefab has no set_Path in this build (DragonCore note; RampartNox uses DD2MethodLibrary.prefab_set_path).
- Alternative for the glow: body-material effect (MaterialInterpolationRequestManager.requestMaterialMode); 0.3 records it.

## Probe 0.3 results (2026-10-20)
- Quik Fot does not fire from onHitMagicBind + hit timer restart, even as MSP -> DECIDED: custom Misty Step
  (Job07_MagicBindJustLeap animation on Jump right after a charged blast hit + own movement to that enemy).
- While charging Forbeding Bolt (MSP) the game requests: efx ch07 13_ch07_ns id 25 el 0 (start) and el 50,
  ch00 160 (cloud), and body-material modes (MaterialInterpolationRequestManager.requestMaterialMode, category 8,
  a = -1): 1545610377 (b 4) and 1704633256 (b 2). User thinks the glow is 13_ch07_ns; a Play made the character
  invisible (which one unknown: log was pushed out). Probe 0.4: one row per distinct entry, press log, Undo for
  materials (requestMaterialModeDefault).

## 2026-10-20: arm-glow colour parked (user: "only visual, later"). Probe 0.7 patch written, NOT installed.
- 0.6 finding: the replayed 13_ch07_ns id 25 el 0 container has ONE layer (effect_ch000000_00) with one colour slot
  "Charge", no groups; the game requests it with requestEffect(EffectID, GameObject nil, -1, nil) (no follow) ->
  our replays stay in the world ("detached").

## Pactblade 0.1-test (src/Pactblade.lua, installed): Eldritch Blast on DragonCore
- live.on = cfg.active and weapon_job()==1. Fighter shield actions (Job01_* containing Guard/Shield) refused in
  ActionManager.requestActionCore pre-hook.
- JobSpecialAction tap (< holdSec 0.5) -> tapAction + Gungnir shell 11 at L_Hand_Palm after tapDelay; hold+release ->
  chargedAction + shell 12. cast.face crosshair + lock_range 30 (soft lock to nearest enemy).
- calcDamageValue: blast hit (attacker HitCtrl == our shell record's HitCtrl) -> Damage = magick base x mbRate x
  DamageRate x magBonus(2) x 5/10; other hits: Damage x (1.2 phys + 2 mag)/(phys+mag). mbRate (Magick Bolt's
  ActionRate) still to be measured (default 1.0).

## 2026-10-2x resume: user OK with current blast settings (tapDelay 0.46, tapFx 1.0, chargedFx 0.5, flash own/tap,
## scale ~1, speed 2). New asks: beam trail from hand, MSP hand glow constantly on.
- Pactblade 0.4-test: trail = cosmetic, muted copies of a chosen shell (Magick Bolt / Sperepelote tiny / Forbeding
  look / Magike Cut) spawned at the blast's current position (cast.mode "previous", opts.from = record) every
  trailEvery s, speed 0.01, lifetime trailLife; stops on hit / when the blast stops moving / after 3 s.
- Probe 0.7 installed: LIVE checkbox keeps the game's own effect containers for the player (requestEffect post-hook)
  and logs getFollowTarget(0) / getParent(0) / layer count -> learn how the game keeps the arm glow attached.
  Next for the glow: replicate that attach, then load MSP's effect file on a Fighter (HumanCombatEffectResourceHolder
  prefab -> ObjectEffectManager2.addExternalDataContainer) with a crash guard.
- CORRECTION (user, rightly annoyed): earlier mods already answered this. Blink Behind MODLOG: Job07 efx/sound
  containers ARE available on a pure Fighter (efx 14/7/10-11, 13/0/10 played as Fighter); Blink Behind 1.5.x tried
  recolouring a Fangtooth efx: tint multiplies, teal outline not recoloured -> dropped by user. Dimension Door: plays
  a .efx FILE on its own via.effect.EffectPlayer (create_resource EffectResource -> create_holder -> createComponent
  EffectPlayer -> set_Resource, set_AutoStart) on a chosen GameObject; WispProbe found files via
  EffectPlayer:get_Resource():get_ResourcePath().
- Glow plan now: probe 0.8 LIVE reads the .efx paths of the game's charge effect layers (one MSP charge); Pactblade
  then plays that file on an EffectPlayer on a GameObject kept on the left arm joint every frame.
- 0.5-test (clean-up at user request): probe removed from autorun (kept in probe/). Pactblade: tuned values fixed in
  BLAST/TRAIL tables; menu = Active, Beam trail, folded Debug (status, trail state/error, last 5 hits with
  attack multiplier, "find the hand effect's file" -> reframework/data/Pactblade_effects.json). Trail default look
  now Sperepelote tiny (shell 11, same file as the blast, surely loaded). User: the hand effect also shows on a
  TAPPED bolt (as MSP), no charge needed. 0.4's trail showed nothing (cause unknown; Debug now shows its state).
- Hand glow file (user found it): vfx/effects/character/ch07/ns/13_ch07_ns_025_00.efx (+ _50 while charging).
- 0.6-test: trail REMOVED (pieces flew on, each replayed shell 11's launch flash = "bigger launch", and one blast
  failed "shell id 11 not in" after 117 trail spawns). Hand glow with two methods (Debug): A = .efx on an
  EffectPlayer on an anchor GameObject moved to the arm joint every frame (Dimension Door; warning from DD: some
  efx stay invisible from file); B = player's ObjectEffectManager2 requestEffect(ch07 index, 25, 0) short overload
  WITH the player GameObject as parent. Renewed every 2 s.
- 0.7-test: Nox sword look ported from Stalwart Nox 1.6 for the sword in hand (no WeaponID check, no stat change):
  shimmer effect 25 via the sword's ObjectEffectManager2 (DataContainerIndex -1), tint 126/0/54 x1.3 on each part's
  original colour, blade glow MaterialInterpolationEnchant mode 2834278566 + Enchant_Color1/2 = 91/26/142 (lighter
  second) in BeginRendering, start/stop in pre UpdateBehavior. Menu toggle "Nox sword look".
- 0.8-test: hand glow speed slider (EffectPlayer.set_PlaySpeed / container setPlaySpeed, default 0.5, live); renewal every 2 s / speed; Debug shows whether the effect loops by itself. User 2026-10-2x: sword (Nox) + hand glow WORK.
- 0.9-test: user: slowed glow looks choppy -> freeze mode (default): one copy at speed 1 until freezeAt (0.4 s, slider restarts it), then PlaySpeed 0, never renewed. Slow-speed mode kept as the alternative.
- 0.10-test: freeze moment 1.99 s (user's pick) is the default; hand glow only while the weapon is drawn (a:weapon_drawn()).
- 0.11-test: freeze moment 2.90 s; on draw the glow fast-forwards to it in ~0.15 s (PlaySpeed freezeAt/0.15), then PlaySpeed 0.
- 0.12-test: user: first Eldritch Blast had no effects -> warm-up (one cosmetic, muted, tiny 0.1 s shot of each blast 60 m below the player when Pactblade becomes active) loads effects + learns params. Explosion size slider (default 0.5): requestEffect hook on our blast shells' own effect managers; Hit/HitAdd/HitTerrain/HitTerrainAdd/Finish ElementIDs -> container setUniformScale.
- 0.13-test: user: lingering teal cloud after the explosion is NOT changed by the hit-element scaling (not the shell's own hit effects). Cloud recorder: 3 s after each blast, every requestEffect (any manager within 15 m) + requestCreateShell near the blast -> data/Pactblade_cloud.json.
- Cloud recorder result: the lingering teal cloud = effect 0/160/0 (ch00 common file) requested by the PLAYER during the bolt animation = MSP charge cloud (MagicBindChargeEffect; normally ended by the bolt logic we replace). Blast shells' own effects = container 8 on ShellBase (-1/8/x). 0.14-test: player's 0/160 request while Pactblade active -> setUniformScale(cloud size) or finishAll at 0; recorder removed.
- 0.15-test: user: cloud size slider had no effect (setUniformScale ignored), 0-0.04 (finishAll) removes it. Now also every LateUpdateBehavior: setUniformScale + each EffectPlayer GameObject set_LocalScale(k). If that fails too -> on/off only.
- 0.15 WORKS (transform LocalScale per frame): cloud size 0.30 = default (user).
- 0.16-test: Fighter kit. isNormalSkillEnable/Available (player ctx/avail + PlayerInputProcessorDetail): grant 17/18,
  deny 4/5/7/8. Thief handler DetailInstances[3]: processKickWall every frame; processBreakFall + Job04BreakFall.
  setMotion hook -> next frames changeMotion(bank 145, same motion id) + 100 stamina (LSE's method), skipped when
  LSE's "LSE - Controlled fall" on_frame exists. Onslaught/Empale etc.: Job01_* names with Attack/FinishingMove
  (not Shield/Guard/Hindsight/Cymbal) -> a:set_speed(1.5) per frame. Shield: ItemManager.setEquip slot Sub (1)
  for the player refused when the StorageData isn't already _IsEquipped; worn shield -> menu warning (removeEquip
  flags unknown, not called).
- 0.17-test: user: tap right after Onslaught/Empale often didn't play -> input buffer: re-request every frame until the action starts (0.6 s), after 0.2 s fall back to Job07_MagicBindImcompleteFullBody on layer 0.
- 0.18-test: user idea PACT BURST: blast button within 0.4 s of / during Onslaught-Empale -> MagicBindComplete + Magike Cut shell 6 at owner +1 m up/+1 m forward, lifetime 0.25, damage_type Hitback_L, damage = Magick Bolt formula x5 (assumed), arc 150 deg / 2.5 m (outside -> Damage 0; reaction may still show), stagger power x2 via calcDamageReaction. Warm-up includes it. (0.17 buffer confirmed working by user.)
- 0.19-test: user: Pact Burst should be exactly the charged blast minus the long flight -> shell 12, fx 0.5/flash tap, x10, at owner +1.2 up/+1.5 fwd, speed 0.3, lifetime 0.25 (keeps Hitback_L, arc, stagger x2). User asked if Magike Cut's projectile (shell 6) could be reshaped for Eldritch Blast -> Debug TEST: tap uses shell 6 with scale_axes (width/height/length sliders).
- 0.20-test: user: Pact Burst borrows only the charged LOOK (animation + effects); damage back to x5, arc/stagger as designed.
- 0.21-test: user: 0.18's burst look (Magike Cut shell 6) is PERFECT for Eldritch Blast -> tap = shell 6 (speed 1.5). Burst renamed ELDRITCH BURST, no visible projectile: charged animation + hidden hit area (shell 13, fx 0.01, no flash). Charged keeps Sperepelote 12 with shell 11's flash (11 warmed up for that). Debug stretch test now on the tap projectile.
- 0.22-test: user: the projectile visible in 0.21's burst (shell 13, fx 0.01 did NOT hide it) is the one wanted for Eldritch Blast -> tap = shell 13, speed 2. Burst hit area = shell 6 with hidden=true: every requestEffect from its shell's manager -> container killAll.
- 0.23-test: user: no visible tap projectile (shell 13 at speed 2 too fast) -> speed 0.4 + Debug slider. Burst should show the CHARGED blast's palm launch effect: burst = shell 12 from L_Hand_Palm (fx 0.5, flash = shell 11 start), every effect except the current StartElementID killed.
- 0.24-test: user: tap projectile too fast to see; Eldritch Burst GOOD (to test vs enemies). BEAM: cosmetic copies of the tap shell laid every 0.4 m from the blast's start to its current position (cast previous, offset back along its rotation), max 60, pinned each frame (shell GO transform set_Position), their StartElement effect killed, their other effect containers kept and killAll'd when the blast hits / stops / after 4 s. Menu toggle Eldritch Blast beam.
- 0.25-test: user: beam lingered ~0.5 s after the hit; copies made ground explosions that went on a long time. Now pieces keep ONLY ShellElementID (flight visual), every other effect + anything after death killed; beam ends the same frame the real blast's damage hook fires (b.hitNow) or after 2 still frames.
- 0.26-test: beam ends when the real blast requests a Hit/HitTerrain/Finish element (terrain hits). TEST DUMMIES (Debug): Bugaboo ch220005_00 (DLC goblin, Mes_ch220005) and Beorcan Fighter ch230004_01 (DLC bandit, Mes_ch230004) via a:summon hostile, found by GameObject name tag in EnemyManager._EnemyList, AI = every via.behaviortree.BehaviorTree component except MotionFsm2 set_Paused (kept paused), hits on them logged then Damage 0. Remove all = summons.request_remove_all().
- 0.27-test: BEAM PUT AWAY by user (off, hidden; code kept). Open beam bug: hitting a new spot also triggered the previous spot's explosion. Dummies were invisible (likely no_dissolve + AI paused at 1 s) -> normal fade-in, pause after 3 s; pawns attack them -> all damage to dummies zeroed (pawns still swing).
- 0.28-test: stagger (DamageReaction) x0.25 tap, x0.5 charged, x0.5 burst (user); burst's forced Hitback_L removed so it behaves like the charged blast.
- 0.28: dummies WORK (visible, standing). Beorcan (ch230 human) is NOT invincible - user: keep it like that. (Likely its damage target object differs from the app.Character's GameObject for humans.)
- 0.29-test: burst stagger power back to x2 (user), still no forced Hitback_L.
- 0.30-test: Eldritch Burst: hyper armour (a:set_super_armor) 1.5 s from the start (user); after the burst fires (+0.1 s, up to 2 s) an AttackS/AttackL press requests NormalLocomotion on layer 0 to cut the charged animation's recovery.
- 0.30 confirmed good (burst recovery cut). 0.31-test: burst stagger x1 (halved, user). Terms: stat screen Knockdown Power = 'Blow' in code; per hit DamageReaction (reaction strength, what we scale) and BlowDamage (separate, unverified role).
- 0.32-test: user: Eldritch Burst must never knock down, only flinch -> getReactionDamageType post-hook for burst hits: Quake 3/4, Hitback_L..Blown_L 7-19, FlashFlood 22 -> Hitback_M (6) (DamageType/ActType/OverwriteBlownType + return value). Debug counts them.

## OPEN TODO (user)
- Eldritch Burst's knockdown/stagger power may still need adjusting (now: stagger x1 of shell 12's own, reactions capped at Hitback_M, no knockdowns). Revisit after more testing.
- 0.33-test: hit log adds IsMagicAttack + AttackUserData._ElementType (+ OverwriteElementType) and writes the last 40 hits to data/Pactblade_hits.json. Magick Bolt = non-elemental magick unless enchanted (game text job03_act_detail_00).
- 0.34-test: user wants Magick (stat) x3 as Pactblade passive, from STATS (visible on status screen); example target = fire-enchanted sword hit (1269 phys + 1269 mag). Found: PlayerStatusCalculator.calcBasicAttackDefence -> PlayerBasicAttackDefenceStatus (BasicMagicAttack/AdditionalMagicAttack), ValidationStatusCaps (per-level online caps -> needs online guard like Dragonforge). Damage math: PlayerDamageCalculator.calcMagicAttack/calcPhysicsAttack -> calcAttack(4 floats), calcDamage(5 floats); logger -> data/Pactblade_calc.json to derive the formula.
- 0.35-test: user: give the SWORD Magick = its Strength (duospears are always 1:1; swords have 0, only 3/104 >0). ItemWeaponParam of the held weapon (getItemData(app.WeaponID)): _MagicAttack = _PhysicalAttack, _Element/_ElementStore = 0 while active, restored when off/other weapon/reset; ItemManager.applyEquipDataForCharacter() refresh. Unenchantable: PlayerDamageCalculator.isEnchantApplyable -> false for the player while active. Passive kept (+20% phys, x2 magick) for now. TODO before release: online upload guard for the weapon change (like Dragonforge); base Strength only (no smith upgrades).
- 0.36-test: user: inventory shows the sword's new Magick, status screen not -> also EquipData.updateEnhanceEquip(StorageData of the equipped sword, found by _ItemId = ItemWeaponParam._Id) for every storage member, then applyEquipDataForCharacter.
- MSP test: swings pure physical (1333 x rate); Magike Cut adds a SEPARATE magick hit (0 phys / 1285.9 mag x1.67). With the magick sword, blast magick part 23.9 -> 1123.9 (burst 12,363). 0.37-test: blast damage = magick part x DamageRate x factor (tap 0.2127, charged/burst 0.4255) = the old 263 / 526 on the dummy (passive included). Boons blocked: StatusConditionCtrl.reqStatusConditionApplyCore(15/16/17) skipped for the player while active; active boon cured (DragonCore statuses) each second.
- 0.38-test: user wants a REAL magick part on every swing & skill (game-computed, option 3); fallback OK: Holy element on the sword scaling from it. Found: no magick bit in AttackFlagEnum; AttackUserData has _ElementType (swings -1 NoSet, blasts 0 None -> likely the magick switch, IsNoSetMagic), ActionMgcAttackValue, Enchant (EnchantData: MagicalFactor/PhysicalFactor/StatusDamageFactor), NonMagicElementRate. Debug EXPERIMENT selector A element none / B ActionMgcAttackValue 1 / C 100 / D element Holy (4), applied to the player's own swing hits only during the calc.
- 0.38 result: A-D (attack data _ElementType / ActionMgcAttackValue) changed NOTHING (swings 1269/0). 0.39-test: change the hit's own DamageInfo before calcDamageValue: A IsMagicAttack, B set_ElementType(0), C set_ElementType(4 Holy), D A+C, E IsEnchantAttack+EnchantRate 1, F E+Holy; applied counter; log hit element + EnchantDamage.
- 0.40-test: dummy Bugaboo (jumps around) replaced by Beorcan Warrior ch230004_05; dummy check also by the victim's HitController (DamageOwnerHitController) so human dummies (Beorcan) are invincible too.
- 0.39 result: A-F on the hit's DamageInfo changed nothing either (element read back -1): the game re-derives magick/element/enchant inside the calc -> option 3 (game-computed magick on swings) NOT possible; user rejects script-computed parts. DECISION: Holy like The Exalted (1102: Fighter sword phys 270 / mag 120 / _Element 4 / _ElementStore 100; elemental weapons carry Magick). 0.41-test: held sword _Element 4, _ElementStore 100 + Magick = Strength; Nox look kept; swing experiment removed; hit log adds NonMagicElementDamage; dummies recognised by position (within 6 m of spawn point, not present before, 20 s).
- 0.42-test: dummies killable again (user: zero damage = can't see hits); dummy recognition by position works ('(dummy)' marks). Holy shows in the inventory but swings carry no element/holy part (elemental 0, element -1) -> suspect the weapon's element is cached at equip time; test: re-equip the sword while active.
- 0.43-test: user: dummy hits register but no reaction / no hit sound (AI pause hit too much). Pause now skips every tree that is_a MotionFsm2 or has 'Motion' in its type; component list of the dummy -> data/Pactblade_dummy_components.json.
- 0.43 result: swings still element -1 even after re-equip; component dump not written (pause loop errored). FOUND: app.Weapon (held sword object) has its own ElementType field. 0.44-test: held weapon ElementType = 4 (Holy) while active, original restored when off/reset/other sword; component dump loop guarded per component.
- 0.44: user: Holy VISUAL appears on the sword (unwanted; keep Nox look). Dummy components: the ONLY BehaviorTree is MotionFsm2 -> AI lives in app.AIDecisionMaker/AIBlackBoardController/NavigationAI; missing reaction/sound earlier = the zero-damage invincibility. 0.45-test: Debug TEST sword element selector (Holy/Fire/Ice/Thunder/none) for data + sword object; dummy AI = AIDecisionMaker set_Enabled(false); hit log notes the chosen element.
- 0.45 result: element on swings stayed -1 for ALL elements; element visuals/sounds need a re-equip. User wants: HOLY damage + only the Nox visuals + FIRE's swing/hit sounds. Cause of no element damage: our isEnchantApplyable=false (weapon element runs through the enchant path). 0.46-test: unenchantable hook REMOVED (boons still blocked); setElemntTypeOnEnchant pre-hook swaps the player's hit element to Holy (Debug 'damage element': Holy / same as sword); recorder of the held sword's requestEffect + MaterialInterpolation(Enchant) requestMaterialMode* -> data/Pactblade_sword_fx.json (Nox's own marked ours); changing the test element triggers updateEnhanceEquip refresh.
- 0.46 RESULT: element now works through the enchant path: swings = phys 1259 + enchant 1259, hit element = sword element; game 1620 -> passive 2593. setElemntTypeOnEnchant swap did NOT change the hit element. Sword visuals per element: Fire fx 10/11/15, glow 3544830310/4102612728/4212053742; Holy fx 40/41/45, glow 1714057310/3791582900; Ice fx 20/25, glow 4172614299; all: glow 4165826821; Nox ours: fx 25 + glow 2834278566. 0.47-test: sword element default Fire (sounds); getElementTypeByEnchant post returns Holy (Nullable packed hasValue|value<<32); every sword effect not from nox_start -> killAll, every sword blade-glow request not ours -> SKIP.
- EFFECT RECOLOUR research (2026-10-20): extraction needs tools/ree-unpacker (REE_FILTER env, project DD2_STM_Release, re_chunk_000.pak) - ree-pak-cli reads TU3.2 paks as garbage (new-items MODLOG). Extracted to dd2-research/efx: 13_ch07_ns_025_00.efx (15372 B) + _50 (14422 B), magic 'efxr'. Inside: colours as plain RGBA bytes (0,255,255,255 / 0,128,191,255 ...) and float triples (0,1,1 / 0.15,1,1); strings 'Charge' (extern colour), 'L_Arm_Lower' (attach joint), EffectLight, app.PtMaterialInterpolation MIRequest (_RequestCategory/_RequestMode) = the sleeve-surface glow is a body material mode (colour in MI data, not in the efx). Plan offered: same-length byte recolour copy under a NEW path, packed (ree-pak-cli pack, loaded from <game>/pak_mods), played by Pactblade glow method A; MI colour changed at runtime while active.
- 0.47 result: sword fire visuals gone (Nox only), but the FIRE SWING TRAIL + embers remain (not from the sword's effect
  manager) and hits stayed element 1 (Fire): neither setElemntTypeOnEnchant nor getElementTypeByEnchant swaps worked.
- DECISION 2026-10-20 (user): option 2 = THUNDER for everything (damage, trail, sounds); sword visuals still only Nox.
  0.48-test: sword element Thunder by default, damage element "same as the sword".

## PARKED for later (user: "note this down, maybe I come back to this")
- Element MIX: Holy damage + Fire (or Thunder) swing/hit sounds + Thunder trail. Needs: (1) where the game really sets
  the hit element (both swap hooks failed; maybe victim-side calcDamageValueDefence / Weapon.ElementType read again);
  (2) where the swing trail comes from (not the sword's ObjectEffectManager2; record the player's requestEffect during
  swings per element).
- Effect recolour by file (see EFFECT RECOLOUR research above) - offered, not started.
- 0.48 GOOD (Thunder trail/sounds, Nox shimmer) but the Nox BLADE GLOW (MaterialInterpolationEnchant mode 2834278566) was gone -> 0.49-test: when a game glow request on the sword is blocked, the Nox glow is requested again at the next UpdateBehavior (noxGlowAgain).
- 0.49 CONFIRMED (user): Thunder sword + Nox shimmer + Nox blade glow all good.

## VOCATION (2026-10-21, user decisions)
- Own rank (VSB progression block), available right away (unlock_rank 1, difficulty 1).
- Final split (set up LATER, after all moves exist; until then everything is available for testing/creating):
  core = Eldritch Blast, Footpad, Controlled Fall; learned with DCP = Charged Eldritch Blast, Eldritch Burst and
  later moves (Misty Step, ...).
- VSB pack: vsb_pack/pactblade/pack.json (id "pactblade", uuid 00373ca2-..., vocation weapon Job01) installed to
  reframework/data/VSB/packs/pactblade/.
- 0.50-test: active = _G.VSB_API.app.picks.Job01 == "pactblade" and weapon_job()==1; checkbox removed; Debug
  "force active" for tests; menu shows pick status (VSB missing / not picked / active).
- 0.50 CRASH (user): picked Pactblade in VSB, drew the sword -> c0000005, RIP in heap (bad native call), no Lua error, crashguard empty. 0.51-test: Debug 'ignore VSB pick' for bisecting: (1) VSB example Ember Knight + script off, (2) Pactblade pack + script off, (3) Pactblade + script on.
- 0.51 bisect: NO crash in either test (picked + script off, picked + script on + draw). The 0.50 crash was a one-off; suspect VSB 'Rescan packs' / first setup right after installing (re-registers skills in the game's lists live). Watch for repeats; prefer a game restart over rescans after pack changes.

## Skill Maker 1.19 study (2026-10-21; extracted dd2-research/skillmaker, line numbers = SkillMaker.lua)
- Recolour: shell effects change_efx2_color L1489-1552 (EffectManager2.CreatedEffectDataList -> CreatedEffects;
  EffectPlayer:set_Color + c_effect:setRootColor; killAllInternal hides); extern params getExternParameter(name)
  :set_Color for "ParticleColor"/"BaseColor"/"FireColor"/"LightningColor" L4983-4985; action effect
  getExternParameters(1/2/3) L5114-5121; BLADE GLOW at the source: MaterialInterpolationEnchant._DefaultModeData
  ._MaterialList._items[0]._VariableF4List._items[v]._Value = colour*255 L4958-4962 (restore L4941-4945) + mesh
  Enchant_Color1/2 -> try the same on the body MaterialInterpolation* for the sleeve glow.
- Beam: native beam shells pinned per frame: ch252shellparamdata.user #0/#2 (Golem laser), ch255000shellparamdata.user
  #0 (Medusa ray); attach-to-joint re-sets pos/euler each frame L5521-5537. Freeze shell: WorkRate NextRateValue/
  NextApplyRate = 0 L5500. Non-colliding: <ColliderStep>=99999 + CachedRequestSetCollider:set_Enabled(false) L5469.
  No omen flash: ShellBaseParam.UseOmenPhase=false. Flying copies = CHILD shells (_ShellAdditionalParameter):
  find in ShellList by <ShellParamId>, <RequestId> > req_id, destroy L5550-5570.
- Misty Step: set_Position in UpdateBehavior AND once in UpdateMotion L4715-4721; victim from getReactionDamageType
  hit_info:get_DamageOwnerHitController():get_CachedCharacter() L6686-6701; leap: FreeFallCtrl startWithFrame(vec3,
  -9.8) L5374 (+ fall damage params L3911-3923); dash: set_Position per frame to 1.33 m L5362.
- Charging pose: upper-body Prepare node + layer 0 forced to "Locomotion.Strafe" via MotionFsm2Layer.setCurrentNode
  (System.String, via.behaviortree.SetNodeInfo, via.motion.SetMotionTransitionInfo) L626-632/L5100; freeze pose via
  WorkRate ~0 (0.04/0.1) L5014-5025.
- Dummies: get_AIDecisionMaker():set_Enabled(false) EVERY frame (too early -> CTD) + Ch2._TargetController:
  changeTarget() + ActionManager.Fsm:restartTree() L3398-3404; freeze pos per frame L3439; near-invincible:
  chara:get_Hit():set_DamageRate(1/huge) L4441 (reactions still play); reset L1396-1420.
- "Simplify Action": enable only the first action of a vanilla FSM node = animation without its shells/effects
  L5144-5157 (cleaner than our bolt-shell blocking). Faster attacks = WorkRate.NextRateValue 1.5 per frame.
- Element swap: NOTHING (commented-out shell <EnchantElementType>). Boons = reqStatusConditionApplyCore(15/16/17).
- Skills looked at for the user: Eldritch Blast (MagicBindImcompleteFullBody; ch227001 levin #3 hand flash 0.31x;
  ch227 darkbullet #8 at the TARGET, purple 0.38/0/0.55), Darkness, Blink Toss (BlinkStrike -> TuskToss),
  Hellfire Slash, Hell Brine, Judgement Cut (world speed 0.35, Skeleton Lord waves ch226003 #0 + Magike Cut #6).
- 0.52-test: (1) Debug TEST "Skill Maker's Eldritch Blast" for the tap (BLAST.sm: MagicBindImcompleteFullBody,
  ch227001 levin #3 flash at the palm 0.245 s, ch227 darkbullet #8 at the target 0.722 s, colours via Skill Maker's
  change_efx2_color method = colour_shell). (2) user: while CHARGING the hand glow plays normally, then restarts
  frozen after the charged blast / a cancelled charge; a hit/stagger while charging cancels the charge. (3) Debug TEST
  hand glow colour: glow effect player set_Color + extern params Charge/ParticleColor/BaseColor/FireColor/
  LightningColor; sleeve glow = RimLight material mode (RequestListCategory 8 = RimLight; modes 1545610377 /
  1704633256) -> player's MaterialInterpolationRimLight ModeDataList/UserDatas/AddDatas -> Mode._ModeValue ->
  _MaterialList[]._VariableF4List[] (_IsColor) _Value recoloured, restored when off; mode list dumped to
  data/Pactblade_rimlight_modes.json.
- 0.53-test: user meant only the HAND EFFECT returns to frozen when a charge ends without a shot; the hit-cancels-charge rule from 0.52 removed again.
- 0.54-test: user: hand effect plays normally WHILE the blast button (JobSpecialAction) is held, back to the frozen version on release.
- 0.55-test: charge time 2.5 s (HOLD_SEC, user).
- 0.56-test: arm glow colour = main setting (rim light only, the vibrating-air effect keeps its colour; brightness x1-8, default 2, saved); 'blasts don't work, all variants' after 0.55 -> trace of every blast step to data/Pactblade_trace.json. (01:17 'crash' = user alt-F4; logged getWeapon exception harmless.)
- 0.57 trace: UPDATE ERROR line 744 'compare nil with number' = BLAST.*.flash name clash (launch-flash choice string vs the Skill Maker palm flash table, since 0.52) -> broke ALL blasts. 0.58: palm flash key renamed palmFlash; arm colour retries each second until colour values are found (0 found at load was remembered as done).
- 0.58: taps work again; user: charged 'doesn't work' (trace: no hold ever reached 2.5 s -> released early = tap), arm recolour not working (rim-light modes 1545610377/1704633256 ARE on the component and get changed - so 0.52's visible arm colour likely came from the effect's colour slots, removed in 0.56). 0.59-test: Skill Maker style REMOVED (user dislikes it); trace logs charging/early release; Debug colour-route checkboxes (rim / set_Color / Charge / ParticleColor / BaseColor / FireColor / LightningColor), each restarts the glow.
- 0.59 result: only 'whole effect' (EffectPlayer set_Color) recolours the arm (and the air with it); rim light and colour slots do nothing visible. 0.60-test: charge time 1.5 s (user).
- 0.61-test: user: while the blast button is held, loop only the 2.56-3.00 s part of the hand effect (no vibrating air) instead of playing it on. Relay of copies: each fast-forwarded to 2.56 s hidden 100 m below, shown at 2.56, ended at 3.00; successor started 0.15 s before; frozen copy at 2.90 plays straight into the loop; release -> back to the frozen copy.
- 0.61 looks okay (user). 0.62-test: loop plays at half speed (GLOW_LOOP_SPEED 0.5; successor lead scaled); charge time 1 s.
- 0.63-test: held-button loop range 2.65-3.00 s (user).
- 0.63 ok. 0.64-test: blast colour (cfg.blastTint, arm colour sliders): set_Color/setRootColor on effects requested by our shells, during our spawn, and by the player within 2 s of a blast press (charge cloud, action effects); plus the shell record walk for 6 s.
- 0.65-test: charged/burst animation ground mist stayed teal -> also colour containers from requestEffectInternal / FromFsmOrSequence / FromFsm (animation timeline effects), deduped; Debug shows counts per route.
- 0.65 good (mist coloured). 0.66-test: arm colour route default = whole effect (set_Color), rim off; route checkboxes saved (armRoutes). Colours/brightness/blastTint were already saved.
- 0.67-test: Quik Fot via the real Forbeding Bolt: the charged animation's own bind bolt is no longer blocked (tap/burst still are), its hit does 1 damage, its flight visuals are killed (bind effect on the enemy stays, coloured), skill 27 granted, DetailInstances[6]:processJustMagicBind() every frame, Debug shows the Quik Fot window. User asked if the bind can be an attribute of our blast: no - it's the bolt projectile's own hit script (Job07MagicBindShell), so the bolt rides along invisibly. Charging pose dropped (user: MSP animation works while moving).
- 0.67 result (trace): Forbeding Bolt hits, IsJustMagicBindEnable opens, but Jump = normal jump (processJustMagicBind never starts the leap as Fighter). 0.68-test: Jump while the window is open -> request_action Job07_MagicBindJustLeap layer 0, re-requested for 0.3 s until it plays (trace notes).
- 0.68 result: Quik Fot leap WORKS whenever the Forbeding Bolt hits (trace: request -> Job07_MagicBindJustLeap plays). Bolt often missed (own aim). 0.69-test: bolt shell GO captured from its effect requests; LateUpdateBehavior puts it on our charged blast's position/rotation each frame until our blast is gone.
- 0.69 WORKS (user): bolt kept on the charged blast -> binds reliably. 0.70-test: after Quik Fot (action leaves Job07_MagicBindJustLeap, or 3 s), enemy Character.<BindCtrl>.get_MagicBind():stop(false) + deleteBindEffect, MagicBindController.resetHitMagicBindInfo.
- 0.71-test: charge time 0.5 s (the original value from 0.5-0.54).
- 2026-10-21: AnimPlayer 0.1 dev tool (dd2-mods/animplayer) for picking parts of Cloudfall Strike (Job01_RisingLunge*?) and Tornadic Strike (Job01_BravesRaid*? - Riotous Fury line, job01_skill_05_TU_01). Records full-body clips per action, preview by changeMotion + set_Frame each UpdateMotion, marks -> AnimPlayer_marks.json.
- 0.70/0.71 ok. AnimPlayer 0.1 used by user. User's combo design (2026-10-21): Job02_StartFlightShot 0-71.6 -> warp
  left/right of the target -> Job01_RushAttack 34-67 -> warp behind -> Job01_RushAttackFinish 25-54 -> warp in front
  above the head -> Job01_EndRisingLunge 0-end -> game's Job01_RisingLungeLanding. Target = first enemy the opening
  hits. Each warp: Blink Behind cues (depart 14/7/10 + snd 1717783091, arrive 14/7/11 + 13/0/10 + snd 2823464530,
  finishAll after 1 s), coloured with the blast colour. Trigger (user): replaces Cloudfall Strike
  (HumanCustomSkillID Job01_RisingLunge) while Pactblade is active. Stamina 250 (guess). Name: not given yet.
- 0.72-test: combo built (combo_0_72.lua inserted before the menu). Input hook processCustomSkill (id low 32 bits)
  -> SKIP + combo; requestActionCore guard turns any vanilla Job01_RisingLunge* (not Landing) into the combo. Parts:
  request action (retry 0.4 s), wait for the new motion on FullBodyLayer, set_Frame(from), at frame >= to: warp
  (_SharedCore raycast wall/ground check if installed; head joint Head/Neck +0.6 m), reapply 2 frames, next part.
  Onslaught speed-up and burst window off during the combo. Top-level locals ~182 of Lua's 200 limit!
- 0.72 'pretty good' (user). Wants the warp cues = Quik Fot's effects instead of Blink Behind's. 0.73-test: TEST recorder (recorder_0_73.lua): requestActionCore *MagicBindJustLeap* by the player opens a 3 s window; requestEffect/Internal EffectIDs, FromFsm(OrSequence) container/element, WwiseContainerApp.trigger ids -> data/Pactblade_quikfot_fx.json (t, action, by).
- 0.73 recording (Quik Fot as Pactblade, data/Pactblade_quikfot_fx.json): takeoff t0.01 player 13/22/0, 13/22/3
  (+0/20/20 = generic jump, skipped), snd 1781269347; whoosh 0.18 snd 4087819823, 4052369681; arrival 0.23-0.29
  13/23/1, 13/22/15, 13/22/10, snd 1840818767 (0.23), 1863385021 (0.26); landing 0.33 (LandingToRun). The leap
  itself is only ~0.33 s. Charged blast as MSP-anim: player 13/20/55, 13/23/0, 13/20/50.
- CRASH 02:44 under 0.72 (before 0.73 was loaded): c0000005 null read at DD2.exe+0x52345ae on a worker thread, stack
  only DD2.exe (+0x5259001, +0x5233d17, +0x53772ad...) - nearest managed symbols are via.render.* -> native render
  side, no Lua/REFramework frame. Trace: last a tap blast at 1732.9 s (Quik Fot ~5 s earlier). One-off so far; watch.
  Dump parser: jobs tmp dmp.py (exception stream + module map + stack scan).
- 0.74-test: passive physical x1.0 (was 1.2), magick x1.5 (was 2.0) per user; blast damage formula unchanged.
  Combo warp cues = Quik Fot's (cfg.warpFx "quikfot", menu combo; "blink" = old). Recorder removed again.
- CRASH #2 02:50:47 (0.74): REFramework log has a symbolised stack: c0000005 in List<app.OxcartStatus>..ctor <-
  app.OxcartManager.getStatusList <- OxcartUtil.getOxcartStatus_Entity <- CharacterAvoidController.checkOxForwardArea
  <- CharacterNavigationController.update <- HumanNavigationController <- NPCNavigationController.update. = an NPC's
  navigation (oxcart avoidance). Suspect: our summoned human test dummies (ch230004, AI decision maker off every
  frame) - the dummy had just been killed by the combo. Not proven. Ask user to test without dummies.
- Kite Arrow = Job02_StartFlightShot (app.Job02StartFlightShot: onAttackHit -> requestAction(Action at
  ActionChangeFrame), SuperLargeTarget, Down/Finishing actions; app.Job02FlightShot has DisableMoveXZ). As Fighter the
  2nd kick ran past the target (user). 0.75-test: after the opening's first hit, the player's XZ offset to the target
  is frozen (root motion only moves up/down), facing the target; sword DrawSelf off during Job02_ parts.
- 0.76-test: TEST warp wisps (wisps_0_76.lua): enchant wisps element 20 played by the HELD sword's ObjectEffectManager2 on anchors (noxStarting=true bypasses our sword-effect blocker; user: 'use the enchanted weapon's hidden wisps'), donor Stalwart (requestInstantiate, child of our owner, DrawSelf off) as fallback. Points feet/hips/chest/head/back(-0.35 m)/shoulders by joint name candidates; all joint names -> data/Pactblade_joints.json. Menu 'TEST: warp wisps' with Show on me now, points, size, element slider. Not yet used in the warps.
- 0.76 trace: with the stick, the 2nd kick hits -> game requests Job02_FlightShotAttackHitJump (kick-off) -> combo 'interrupted'. 0.77-test: requestActionCore of any other Job02_* by the player during combo part 1 is refused (noted once).
- 0.77: user: sword still floats (DrawSelf did nothing), wisps' transparent layer gets coloured, wants an effect
  player like the hand glow's, menu cleanup, wisps replace the warp effect, only feet + butt/groin points.
- 0.78-test: sword hidden by disabling every via.render.Mesh of the held sword + children each frame during Job02_
  parts (restored after). Wisps: effect player (normal / frozen at / loop A-B relay with hidden fast-forward copies,
  speed, effect time readout), own per-layer colouring (getAllPlayers list, cfg.wispLayers, layer names from
  get_Resource path) instead of the blast colour list; WISP_POINTS = feet + hips only. Warp look default "wisps":
  burst at the departure joints (stay) + on the body at arrival (follow) for warpWispSecs (0.8), finishAll, Quik Fot
  sounds kept. Menu rewritten (menu_0_78.lua): removed freeze toggle/glow speed, colour routes, sword element tests,
  glow method/joint, stretch/blast speed, ignore-pick; Debug = status, dummies, hits, log.
- Top-level locals ~195 (Lua limit 200)! Next cleanup: remove dead code (beam, colour routes, rim light, element
  tests, glow method B) and/or wrap sections in do-blocks. Real compile check: PYTHONPATH=tools/pylibs python ->
  lupa LuaRuntime load(src) (Lua 5.5).
- 0.79 (not shipped alone): wisps element 30 (user's pick, saved cfg.wispElement); "Coloured effects" list in the
  menu (every tinted container with its effect ID d/c/e or fsm c/e, how, count; "keep its own colour" -> cfg.noTint,
  saved; tint_update whites + drops it). Dead locals look/ROUTE_NAMES removed. Measured: 2 free local slots.
- User: the near-fullscreen see-through thing is the dust of RushAttack / RushAttackFinish. 0.80-test: the player's
  own effect requests during combo parts 2-3 are killed (requestEffect: want=kill; Internal/FsmOrSequence hooks:
  killAll in post), warp cues exempt (combo.cueing); new IDs noted in the trace; menu "no dust from the combo's Rush
  parts" (cfg.comboNoDust, default on). Combo + wisps sections wrapped in one do-block -> 41 free local slots.
- 0.80 trace: parts 2-3 killed 0/15/0, 0/10/11, 2/13/0, 0/30/1501, 2/13/30, 2/13/15, 1/0/0, 0/30/1105, 0/10/20, 2/13/25, 2/13/20, 0/30/1010 - user still sees a big effect. 0.81-test: combo effect recorder (every object, per part) -> data/Pactblade_combo_fx.json; Debug TEST switches: all player effects off in every part, + sword effects, no warp wisps.
- LESSON 0.81: a do-block does NOT help Lua's 200-locals limit (inner locals stack on the outer ones; the 0.80 count
  of "41 free" was measured after the block). The combo + wisps section is now `;(function() ... end)()` (own limit).
  A broken 0.81 was copied to autorun for a minute (compile check printed False but the && chain went on) -> the
  install line now exits non-zero when lupa's load() fails. Always: lupa compile with sys.exit before cp.
- 0.81 combo recording: sword makes no ObjectEffectManager2 requests; the purple veil = the Quik Fot warp cues
  (user's saved warpFx was still "quikfot"; 13/22/x + 13/23/1 tinted). User then: "looks good now" with warpFx
  "wisps", wisps loop 0-5 s at speed 1, element 30, feet + hips, size 1, 1 layer coloured; colour 255/3/30 x5.2;
  hand glow frozen 2.59 s; cloud 0.31; Nox on; no dust on. 0.82-test: these are now the script defaults.
- Skill name (user): "Archfey Combo" (menu/notes renamed; the game's skill list still shows Cloudfall Strike).
- 0.83-test: Misty Step (= Quik Fot after the bind) uses the warp wisps: requestActionCore Job07_MagicBindJustLeap
  by the player -> wisps.burst(depart), combo.mistyUntil 2 s kills the player's 13/22/0, 13/22/3, 13/23/1,
  13/22/15, 13/22/10 (combo_dust, EffectID paths); when the action leaves JustLeap -> wisps.burst(arrive). Only with
  warp look = wisps. Quik Fot sounds kept.
- User: final strike doesn't always connect. 0.84-test: head warp closer (radius+0.6 m, head+0.4 m); part 4 also keeps the XZ offset to the target (follows knockback) until it hits; trace 'final strike hit' / 'final strike MISSED'.
- 0.84 'better now' (user): final strike connects.
- User: opening misses -> sword floats ~3 s (Kite Arrow plays on). 0.85-test: on a miss at frame 71.6 the action is cut (NormalLocomotion, or WaitToFall in the air); the sword is shown again only when no Job02_ action plays (max 5 s).
- 0.85: sword still floated ~3 s after a miss (it flies back into the hand after the Archer pose). 0.86-test (user's idea): sword stays hidden 3 s after the combo stops early (and while any Job02_ action plays, max 6 s).
- 0.86 ok; 0.87-test: sword hidden 2 s after a failed opening (user).
- 0.88-test: sword shown exactly 2 s after a failed opening (no Job02_ wait, user).
- 0.89-test: sword shown 1 s after a failed opening (user).
- 0.90-test: FINAL (user): sword shown 1.5 s after a failed opening.
- 0.91-test (user): Onslaught (Job01_AttackLeft/Right/Air) stays 1.5x; every other sped-up Job01 attack (Empale = *HeavyAttack*, dash, climbing, hold-down, finishing moves, RushAttack outside the combo) 1.2x.
- 0.91/0.92: user felt Onslaught at 1.2x too (its real action names probably aren't Job01_AttackLeft/Right/Air) and said: keep it like this, don't fix. 0.92 only logs 'speed xN: action' once per action to the trace.
- User: Eldritch Blast also shows the full-screen see-through effect when coloured. 0.93-test: noTint defaults 13/23/0, 13/23/1, 13/23/2 (MSP haze family seen in the charged animation + Quik Fot). Saved noTint only ADDS (true values).
- 0.93: user ticked -1/8/1, -1/8/4, -1/8/40, -1/8/43 + defaults, tap still shows the veil -> not in the tint list. 0.94-test: removed spawn_blast's colour_shell (whole shell CreatedEffectDataList, set_Color + setRootColor for 6 s, ignores noTint).
- 0.94: user found the veil layers: -1/8/40 and -1/8/43 (blast shell container 8). 0.95-test: both in the default noTint list.
- 0.96-test: TEST effect player (fxplayer_0_96.lua, menu 'Effect player'): one EffectID replayed on an anchor in front of the player via a source manager: hidden still blast shell (tap 13 / charged 12, spawned 60 m down, lifetime 110 s), the player, or the held sword; normal / frozen / loop A-B, speed, coloured (setRootColor + layers), distance. Default -1/8/40.
- 0.96: without colour_shell the projectile's effects stay uncoloured (they never pass our hooks). 0.97-test: colour_shell back, but its CreatedEffectDataList walk skips entries whose CreatedEffectData.id (EffectID) is in cfg.noTint.
- User (effect player): -1/8/43 not needed, -1/8/40 fine coloured. 0.98-test: BLAST_DROP -1/8/43 = killed on blast shells (combo_dust path, EffectID hooks); default noTint no longer has -1/8/40; removed -1/8/40 from the user's saved noTint.
- User: still 1 screen-covering effect, explosion at the target not coloured. 0.99-test: colour_shell walk registers ids in dbg.walkSeen (shown in 'Coloured effects' with keep-own-colour); tint_wanted colours effects of ANY player-owned shell for 6 s after a press (follow-up explosion shells); recorder (renamed data/Pactblade_fx_record.json) also runs 4 s after each blast press.
- 0.99: the screen-covering ones are -1/8/40 AND -1/8/43 (user). 1.00-test: effect player frame stepping (freeze mode: -1/+1 frame buttons, frames per step, frame readout at 60/s; 'Pause here' from normal play). Each step restarts a copy and fast-forwards it (0.15 s).
- User: cut off the first 0.1 s of -1/8/40 and -1/8/43. 1.01-test: both played + coloured again (BLAST_DROP / noTint emptied of them); BLAST_TRIM: when a blast shell requests them (requestEffect / Internal), the container is held at scale 0 for 0.1 s (clouds list got per-entry k + hideUntil; a hit-cloud entry just gets the hide time), then its normal size.
- 1.01 result: still covers the screen with the 0.1 s cut. User went to sleep (2026-10-21 ~04:30). RESUME HERE:
  options for -1/8/40 / -1/8/43 (blast shell container 8, coloured they make a see-through screen-wide veil):
  (a) longer cut / per-effect cut lengths, (b) jump ahead instead of hide (setPlaySpeed burst), (c) keep both in
  their own colours (noTint) - the only state known to have no veil (0.95/0.98-ish), (d) colour only some layers
  (getAllPlayers) of them, (e) drop 43 again (user once said it isn't needed). Effect player (menu) with frame
  stepping exists for the user to inspect them; user found the view there "looks different" from the real blast.
- 2026-10-21 mod study (user's vocationbuilder folder; notes in dd2-research/vocationbuilder_mods/NOTES_*.md):
  * veil fix candidates (il2cpp): EffectPlayer getGroupParameters(i)/getGroupNames/set_GroupEnabled,
    get/set_EmitMaskBit + MaskName, ExternParameters (NickCore colours them by index), set_Action(Pause/Step/Resume)
    for real frame stepping; CreatedEffectContainer setGroupColor(name, colour), setEmitMaskBit, setExternParameter,
    getPlayers(ProviderData), killForEPV. Plan: dump all of these for -1/8/40 + -1/8/43, colour only extern
    params / groups, find the veil emitter by clearing mask bits one by one.
  * efx-file edits (SechingCrossBlade): same-count attribute rewrites, length-prefixed paths (longer OK), blank
    uvs to hide sprite layers, mesh layer -> new mesh+mdf2, colour in mdf2 AND copied in the efx. Copy to a new path
    + play with our EffectPlayer = per-layer recolour without touching the game's skill.
  * new animations (Ring of Evasion): loose motlist (.1057) + via.motion.DynamicMotionBank (set_MotionList,
    BankID/Type/MaskBit + Overwrite flags, setDynamicMotionBank), played by rewriting a host action node's bank /
    motion (raw +0x20/+0x24) in its start pre-hook; donor motions keep collider keys = hits. Authoring tools not
    included. Sounds: WwiseContainerApp:trigger(UInt32) by hash, any job's sounds, no pak.
  * weapon model (Azure Glaive): replaces Lindworm Fang mesh + textures in place (pre-DLC file versions -> needs
    DD2 Pak Bridge); a new weapon entry would need .user item data (post-DLC .user paks crash).
- 1.02-test: parts control for -1/8/40 / -1/8/43 (parts_1_02.lua + menu parts_menu_1_02.lua): captured from blast
  shells (requestEffect/Internal hooks, replaces the 0.1 s trim), read once per id: per player EmitMaskBit,
  MaskName, EmitterInstanceNum, extern parameter names, group parameter/name names -> data/Pactblade_parts.json;
  applied every frame (live blasts + effect player copies): mode whole / extern (ticked slots set_Color) /
  groups (GroupParameter set_Color + container setGroupColor) / none, and emit mask (unticked bits = emitters off).
  General colouring (tint list, projectile walk) skips these ids (dbg.partsIds). Effect player: game's own
  Pause / Step / Resume via EffectPlayer set_Action (via.effect.PlayerAction values read at runtime).
- 1.02 result (user + Pactblade_parts.json): -1/8/40 = 1 layer, no extern params, group name "lv2", mask all
  bits, 0 emitters reported; only "whole" colours it (= veil; set_Color seems to REPLACE the colour, so a near-
  invisible dark layer becomes bright). Emit-mask bits change nothing visible. -1/8/43: extern GroundColor0..2 /
  GroundAlpha0..2; GroundColor0 colours the explosion's leftover smoke -> keep coloured.
- 1.03-test: defaults 40 = not coloured, 43 = GroundColor0 only (also written into the user's saved settings);
  parts.read also records each layer's effect file path (get_Resource():get_ResourcePath()...) + GameObject/parent
  names, for an edited efx copy of 40 (SechingCrossBlade method). Old parts dump kept as Pactblade_parts_1_02.json.
- User: the effect player's replay of -1/8/40 has NO veil. Guess: the projectile turns on its 'lv2' group (Speregonne = Sperepelote lv2) and the veil belongs to that group. 1.04-test: per-effect 'lv2 group' choice keep / clearGroupName / setGroupNamesCount(0) / set_GroupEnabled(false), applied every frame; effect player checkbox adds addGroupNameLv('lv2') to its copies.
- 1.04 result: 40 'lv2' group ways 1-2 remove nearly the whole effect (wanted part too), way 3 = no change; the effect player copy already has group lv2 (so lv2 is not the difference). 43: user says it makes the big effect regardless of its setting. File path getters returned nothing. 1.05-test: part mode 'hidden' = killAll on creation (not played), to find which effect the veil belongs to.
- User: 40 makes its big part when the blast fires, 43 when it hits/explodes (one each). Plan: edited efx copies. 1.06-test: effect player button dumps the hidden blast shell's ObjectEffectManager2 (DataContainerPath, ExternalDataContainers, StandardDataMap key 8 fully, 3 levels, resource paths) -> data/Pactblade_efx_files.json.
- 1.06: dump button wrote nothing (needed a 2nd press; the info line is overwritten every frame). User: the Archfey Combo's last hit leaves a sound repeating like static, stacking over uses. 1.07-test: dump retried every frame for 4 s, result in fxp.msg (own line); sound recorder (WwiseContainerApp trigger/triggerLogLess/triggerWithSyncSpace, during the combo + 3 s after -> Pactblade_fx_record.json, warpCue flag); Debug 'no warp sounds' test.
- User (rightly): the veil only shows on real blasts, why read from the effect player? 1.08-test: the first real -1/8/40 / 43 container of a session dumps its Creator's ObjectEffectManager2 (same dump, from = 'your real blast') -> data/Pactblade_efx_files.json + trace note.
- 1.08 result: real blast's manager DataContainer = VFX/Effects/Character/ch07/13_ch07_cs_Ref.pfb (index -1 = its own
  container); container 8 = folder cs008, extracted to dd2-research/efx/cs008 (21 efx: 01 04 10 11 20 21 30 31 50 60
  70 80 101 104 110 111 120 121 130 131 160 - no 40/43; element IDs != file names). Prefab extracted to
  dd2-research/efx/cs_ref. Sound record: the warp-sound switch stops the static (so a Quik Fot sound loops); user
  says it also disabled visual effects (cues(): only the sound loop is skipped - check).
- 1.09-test: live -1/8/40 / 43 layers read EffectPlayer:get_ResourcePath once ReadyResource -> trace + data/
  Pactblade_parts_files.json; 'not played' kills only after the file is read.
- User idea (2026-10-21): Eldritch Blast beam look = Golem's magick beam recoloured (Skill Maker: ch252shellparamdata.user
  #0/#2 Golem laser, pinned per frame) - after the veil fix.
- 1.10-test: warp sounds without Quik Fot's mid-air whoosh pair 4087819823 / 4052369681 (suspected loops = the stacking static); takeoff 1781269347 + arrival 1840818767 / 1863385021 kept.
- 1.10: static still there (so it's 1781269347 / 1840818767 / 1863385021 or another); recorder caught no sounds (our cues use soundlib.SoundContainer.trigger, not WwiseContainerApp). 1.09's file-path read logged nothing after a tap blast. 1.11-test: menu 'Sound player' (warp sounds + any number via cue_sound on the player).
- 1.11 load error (Pactblade.lua:2410 'wisps' nil: wisps.play_sound set before the wisps table exists). 1.12-test: combo.play_sound instead. LESSON: the compile check can't catch nil-at-load; anything run at load inside the combo/wisps function must only touch tables made before it.
- User (sound player): 1840818767 (Quik Fot arrival 1) keeps going forever. 1.13-test: out of the warp sounds; Stop buttons (soundlib.SoundContainer stopTriggered(id, go, 0) on the player's containers).
- 1.13: sound problem fixed (user). 1.14-test: warp wisps last 0.6 s (default + user's saved value, was 0.8).
- 1.15-test: warp wisps 0.4 s (user).
- Found 40/43's files (catalog-tool `pfbflat` on 13_ch07_cs_ref.pfb, container 08_CS_Gungnir): element 40 =
  cs008/13_ch07_cs_008_10.efx (launch: smoke/spiral/shockwave/debris/fire/dust/spark/impact/cone + a 1500 lm LIGHT
  + app.PtRadialBlur + camera shake), 43 = cs008/13_ch07_cs_008_30.efx (explosion: GroundColor/Alpha slots, wind,
  decal, smoke/spark/dust, several 13_Liquid_distortion_000_00.mdf2 layers). Suspects: 40's light, 43's distortion
  layers. User rejected "leave them uncoloured"; efx-edit route still open.
- 1.16-test (user's idea): cosmetic Golem laser (AppSystem/ch/ch252/userdata/ch252shellparamdata.user shell 0 or 2)
  spawned with each tap/charged blast from the palm (crosshair aim + lock-on, follow always), size/length sliders,
  coloured via colour_shell. Real blast unchanged (still does damage, still visible).
- User clue: after Eldritch Burst the next sword trail (normally near-invisible) gets coloured for ~0.5 s (TINT_WINDOW). => colouring DISTORTION layers paints the background = the veil. Test 1 (pak_mods/x0002-PactbladeFx-test1.pak, efx/ folder): 13_ch07_cs_008_30.efx (= 43) with its two Liquid_distortion layers' meshes pointed at missing files (13_Magic_006_99 / 13_Liquid_000_99, same length). Overrides the game's own file (also changes Mystic Spearhand's Magike Sperepelote explosion) - test only. Needs a game restart.
- Test 1 pak (43 with missing-mesh distortion layers) CRASHES THE GAME AT STARTUP (3 tries; fine without) - missing
  resource paths in a resident efx are fatal. Pak moved to pactblade/efx/removed/. Next efx try must point to
  EXISTING files.
- 1.16 result: Golem beam appears through the character, doesn't move; user expected it to replace the projectile.
  1.17-test: beams list - beam shells re-placed every LateUpdate at the palm with the blast's spawn rotation
  (record.rot) * degrees_quat(pitch, yaw) (menu sliders); "hide the normal projectile" (default on): blast-shell
  requests of ShellElementID / StartElementID killed (flight + launch flash = 40), real blast speed x beamFast (4)
  so its hit + explosion land as the beam fires.
- 1.17 screenshot: beam = vertical column through the player (no rotation applied: record.rot was nil at spawn, DragonCore sets r.rot later per frame), user's saved beamHide was false (starburst = 40 visible). 1.18-test: beam rotation read from the blast record every frame (fallback: player facing), default tilt 90 (laser lies along its up axis); user's saved settings set to hide on, tilt 90.
- No tool parses DD2's current efx (5965310): REE-Lib fails (also read as Pragmata 5965300), REE-EFX-Unified + ZippoIG DD2 template = launch version 4064419 only. Field params in efx: 'ff ff <idx u16> <default f32> <hash u32> <name>'. Test 2 (pak_mods/x0002-PactbladeFx-test2.pak): 13_ch07_cs_008_10.efx (= 40) Intensity 100 -> 0 (offset 796, light) and BlurPower 10 -> 0 (offset 22538, radial blur). Values only, no paths. Overrides the game's file (MSP's Sperepelote launch too).
- Test 2 (values only) ALSO crashes at startup, same point as test 1. Test 0: pak with the ORIGINAL unmodified 13_ch07_cs_008_10.efx (x0002-PactbladeFx-test0-original.pak) to tell content from the pak mechanism (efx lives in re_chunk_000.pak base; mod paks are injected into family sub_000).
- Test 0 (untouched efx in a pak) ALSO crashes -> not the edit. Test D: pak with only natives/stm/pactblade/dummy.txt (x0002-PactbladeFx-testD-dummy.pak): third-pak/slot problem vs efx-in-pak problem.
- Test D (dummy txt pak) starts fine -> only paks OVERRIDING this efx crash (even byte-identical). Test N: the edited 40 (light + blur 0) at a NEW path natives/stm/vfx/effects/pactblade/pb_blast_launch.efx (x0002-PactbladeFx-testN-newpath.pak). If it starts: play our copy via EffectPlayer (glow method A) and kill the original 40.
- Test N (new-path efx pak) starts fine (user also updated DragonCore -> 1.2.2 and NickCore). 1.19-test: part mode 'ours' (default + user's saved for -1/8/40): the real 40 container is killed, our copy vfx/effects/pactblade/pb_blast_launch.efx plays on an anchor that follows the container's Creator (ShellBase) for 3 s, coloured whole (set_Color). Beam test switched off in the user's settings.
- 1.19: our copy of 40 plays (trace), veil unchanged -> not the light/blur. Variant pak
  (pak_mods/x0002-PactbladeFx-variants.pak, src efx/pak_srcV, verified with ree-pak-cli unpack + own list): 40 copies
  (light+blur 0) v0 base, v1 spiral1 (off 2752 -> Debris_000_01), v2 shockwave (4615 -> Player/ch04/13_Hook_000_00),
  v3 magic008 (13263 -> Debris/13_Wood_000_00), v4 cone (19319 -> Wood_001_00), v5 spiral2 (20890 -> Debris_000_02),
  v6 all five; 43 copies w0 base, w1 haze1 (19361 Magic_006 -> Wood_000_00), w2 haze2 (20784 Liquid_000_27 ->
  Debris_000_01), w3 both. Same-length swaps to EXISTING meshes only. Needs a game restart to load.
- 1.20-test: 'ours' plays the variant chosen in the menu (cfg.parts[id].variant); user's saved: 40 = v6, 43 = w3.
- 1.20: veil still there with every mesh variant (so a sprite layer, or not a single layer); 43's swapped-in meshes show as rocks/debris. 1.21-test: per-effect colour strength (cfg.parts[id].strength, default 0.25 x armBright) for whole/ours on 40/43 - theory: set_Color REPLACES the colour, the boosted x5.2 colour turns a faint dark see-through layer into a wall. User's saved: both 'whole', strength 0.25 (back to the game's own files).
- 1.21: colour strength 0.00 -> the veil turns BLACK: EffectPlayer set_Color overwrites colour AND alpha of every layer
  (see-through layers become solid). No runtime colour can work on 40/43.
- Recolour in the file (pak_mods/x0003-PactbladeFx-recolour.pak, log efx/recolour_log.json): rA = RGBA bytes with
  R<=60, G,B>=90 (outside path strings, offset>=400) -> max(G,B) x hue (255,3,30), alpha kept; rB = rA + float
  triples x<0.3, y,z in 0.4..20 -> max x hue. 40 (light+blur 0 base): 91 / 127 changes, 43: 300 / 432.
- 1.22-test: variants rA/rB played WITHOUT set_Color (o.baked); user's saved: both 'ours' rA. Needs a game restart.
- 1.22: the rA recoloured copy CRASHED THE GAME when the blast fired (guessed 'colour' bytes were not all colours). 1.23-test: rA/rB removed from the menu, 40 default 'none', user's settings: 40 none, 43 GroundColor0 only (both the game's own files). Byte-guess recolouring abandoned until a real EFX parser for 5965310 exists.
- User: why no veil in the effect player? Candidates: camera distance (replay 2.5 m ahead vs real at the palm - camera inside a big see-through layer), parent (shell vs static), cloud-size scaling of 43. 1.24-test: effect player 'play it at my left palm' + distance slider down to 0.
- FOUND: since 1.02 the effect player coloured 40/43 through parts.apply = the user's part mode (extern-nothing / none) -> the replay was NOT coloured, so 'no veil in the effect player' meant nothing. 1.25-test: effect player 'coloured' always = whole (setRootColor + set_Color on every layer), like the real blast.
- User: the 1.24 palm replay WAS coloured whole -> real difference. Theory: velocity-stretched particles on the fast-moving shell parent. 1.26-test: 'ours' copy follows the projectile only if p.follow (menu checkbox, default off = stays at the spawn point); user's saved 40 = ours v0 (light+blur 0 copy), strength 1.0, not following.
- 1.26 RESULT: 40 as our static copy (v0, not following the shell), coloured whole at full strength -> NO VEIL. Cause = the fast-moving shell parent (stretched particles). Next: 43 the same (user's saved: 43 = ours w0, strength 1, static).
- CORRECTION: 1.26 result was 'no veil in the EFFECT PLAYER still' - the real attack still shows it, even with 40 as our static copy. User's idea: something the projectile adds gets coloured. 1.27-test: Debug-ish menu 'FIND THE VEIL' with 3 switches: dbg.offWalk (colour_shell walk), dbg.offTints (tint list), dbg.offParts (40/43 parts + our copies).
- 1.27 result: switch 3 (40/43 colouring) removes the veil (and their colour). Theory: the veil layer is drawn at the effect's OWNER (the shell) or scaled by it - the effect player's owner is the hidden shell 60 m down at scale 0.01. 1.28-test: part mode 'replay' (default + user's saved for 40 and 43): the real container is killed and the same EffectID is requested from the hidden tap shell's manager on an anchor at the real one's Creator position/rotation, coloured whole (setRootColor + every layer), up to 5 s.
- 1.29-test: the hidden tap shell is made / renewed every 3 s while Pactblade is active (first blast replays too). User asked the script to play the effects itself instead of the projectile - that is the replay mode.
- 1.29 BUG: prewarm re-made the hidden shell every few s; each spawn played 40 incl. app.PtRadialBlur (screen post effect, distance-independent) -> screen distortion every ~5 s. 1.30-test: prewarm removed; user's saved 40 none / 43 GroundColor0 (no replay, no hidden shell). User now knows the veil is inherent to 40/43 whole colouring (also in the effect player, intermittently). Pending choice: 1 switch 40/43 off, 2 keep them teal, 3 accept veil.
- 1.31-test CLEANUP (user: too many options): menu = Look (hand glow + frozen at, Nox, arm / blast colour +
  sliders, cloud size) + Skills (bind/Quik Fot, warp look + wisps last, no dust) + Debug (status, dummies, hits,
  log). Removed: Golem beam test, effect player + replay + effect-file dump, sound player, FIND THE VEIL switches,
  Coloured-effects list / see-through parts / wisp effect player menus (their saved settings still apply:
  40 not coloured, 43 GroundColor0 only). TAP = Thief's dodge (Job04_Dodge, re-requested for 0.3 s until it plays;
  note in the trace if it doesn't start); hold = Charged Eldritch Blast; burst unchanged. 3288 lines, 24 free locals.
- Test paks no longer used: pak_mods/x0003-PactbladeFx-recolour.pak (remove when the game is closed).
- 1.31: dodge always goes forward (user). 1.32-test: with the stick held (CharacterInput isLeverInputL), TargetAngleController get_MoveAngleDeg = stick direction; Front/Move AngleDeg + transform yaw set to it right before Job04_Dodge and for the first 0.1 s.
- 1.32: 'somewhat better', spammable, repeated taps keep going forward (face_yaw overwrote TargetAngleCtrl.Move = where the stick is read). 1.33-test: only Front + transform turned; taps during a dodge younger than DODGE_LOCK 0.45 s do nothing.
- 1.33: chained dodges still only forward (TargetAngleCtrl Move isn't updated during the dodge). 1.34-test: stick direction = camera->player ground direction * AxisL.y + right * AxisL.x; the right side's sign is calibrated against get_MoveAngleDeg while in NormalLocomotion with a clearly sideways stick (note in the trace).
- 1.34: character spins / U-turns when dodging sideways (rotation snapping). 1.35-test: no turning at all; only TargetAngleCtrl.Move (+ setMoveAngleDeg) = the stick direction before / for the first 0.1 s of Job04_Dodge, so Job04Dodge's directional motions (_MotionArray angle ranges, mirror) can pick sideways / back steps.
- 1.34/1.35 BUG: the stick-side calibration on_frame sat above 'local live' -> 'attempt to index a nil value (global live)' every frame (user screenshot), calibration never ran. 1.36-test: moved right below live's definition.
- 1.36 CONFIRMED (user: 'now this feels good'): tap = Job04_Dodge with Move direction from stick+camera (side calibrated in NormalLocomotion), no turning, 0.45 s lock.
- 1.36 confirmed. 1.37-test: COMBO_WINDOW 0.4 -> 0.15 s (burst = press during Onslaught/Empale or <0.15 s after; dodge = tap release). Dodge stamina measured: trace 'dodge stamina: before -> after' (0.7 s later) + app.ConsumeStaminaAction start DataId during a dodge.
- 1.37 result: our dodge 1573 -> 1573 (no stamina, no ConsumeStaminaAction). User: Thief's dodge (as Warfarer with daggers) costs no stamina either -> same as Thief, nothing to add. 1.38-test: measurement removed. Burst window = the Onslaught/Empale action incl. recovery + 0.15 s after it ends.
- 1.39-test (user): Burst window = the first 0.3 s of each Onslaught / Empale swing (a swing = new basic-attack action or new FullBodyLayer motion), and only while that swing still plays; after it the tap is the dodge.
- 1.40-test: Burst window slider (cfg.burstWindow, saved, 0.05-1.0 s, default 0.3) under Skills.
- 1.41-test: Burst windows per attack: Onslaught cfg.burstWindow (default 0.8 = user's pick), Empale ground (Job01_Short/LongRangeHeavyAttack) cfg.burstWindowEmpale 0.3, Empale air (names with Heavy+Air: Job01_HeavyAttackAir, ...AirLanding) cfg.burstWindowEmpaleAir 0.3; three sliders.
- 1.42-test: ground Empale burst window = FullBodyLayer frame/endFrame >= cfg.burstFromEmpale (default 0.5, slider %) until the swing ends; air Empale (s from start, kept 0.3) and Onslaught (0.8) unchanged.
- 1.43-test: air Empale window back to 0.8 s (= the single window before 1.41, user); user's saved Onslaught 0.8 / air 0.8 / ground from 50%.
- 1.44-test: a tap released while an Empale (Job01_*Heavy*, ground or air) plays does nothing (no dodge out of Empale, user).
- 1.45-test: ground Empale Burst = FullBodyLayer frame 56.6..110.5 (cfg.empaleFrom/To, sliders, user's values); taps after frame 110.5 dodge (empale_recovering), before 56.6 nothing; air Empale: no dodge while it plays, Burst 0.8 s from start. (empale_recovering placed after cfg/save_cfg - first draft sat above cfg = nil at runtime.)
- 1.46-test: Tusk Toss (Job01_TuskToss*, Onslaught held) Burst = FullBodyLayer frame 50..91 (cfg.tuskFrom/To, sliders). Dodge during Tusk Toss unchanged (a tap outside the window dodges).
- 1.47-test: no dodge during Tusk Toss until frame > cfg.tuskTo (91), user.
- User: after a blast press, water splashes / ripples (and sword trails) turn purple - TINT_WINDOW coloured EVERY player effect for 2 s. 1.48-test: the player's own effects are coloured only if their id starts with 13/ (MSP effect file: the bolt animations) or 0/160/ (charge cloud).
- 1.48 result: water still purple; fx record of a CHARGED blast: -1/8/10 + -1/8/13 = the charged shell's versions of 40/43 (prefab: element 10 -> cs_008_11, 13 -> cs_008_31 + wind) were coloured whole. 1.49-test: PART_ALIAS - launch ids 0,10,40,50,100,110 -> 40's settings, explosion ids 3,13,43,53,103,113 -> 43's; tint / walk skip all of them.
- 1.49: user sees no difference (veil + purple water remain with charged / burst). 1.50-test: every coloured effect logged once per id+path to data/Pactblade_coloured.json (requested / projectile walk).
- 1.51-test: Archfey Combo result on screen 4 s (draw.text, green HIT / red MISSED / red 'stopped in part N: why') + last result in Debug; dummies: Cyclops ch250000_00 and Chimera ch254000_00 (AI paused like the bandits; untested on monsters).
- 1.51: monster dummies work (user). Final strike HIT shows; looks slightly short visually - fine for user. VEIL / purple water / trails: PARKED by user (2026-10-21). State: 40-family not coloured, 43-family GroundColor0 only; 1.50 coloured-effect log still in (data/Pactblade_coloured.json) for when it's resumed; theory: a coloured effect with a distortion layer (charged anim 13/20/55? Forbeding Bolt -1/20/x? projectile parts) paints the refracted background.
- NEW SKILL "Eldritch Slash" (user, 2026-10-21): Hindsight Sweep's slot (HumanCustomSkillID Job01_HindsightSlash,
  input hook + requestActionCore guard for Job01_HindsightSlash*) plays Warrior's Job05_CrescentSlashNormal frames
  0-97 (then NormalLocomotion), super armour while it plays (user), and at cfg.slashFrame (slider, default 30 - user
  to set) fires Magike Cut's wave = Job07 shell 6 from R_Hand_Palm, crosshair + lock-on, coloured via colour_shell.
  Stamina 150 (guess). 1.52-test.
- CRASH 23:46 (1.52): c0000005 at DD2.exe+0x5236228 on a worker thread ~0.6 s after the slash wave spawned + coloured;
  near crash #1's 0x52345ae (after a tap blast) -> suspect: colour_shell walking + rewriting the projectile's
  CreatedEffectDataList every frame while the game updates it on its threads. User: no crash with Blast colour off.
  1.53-test: colour_update runs 5x/s and colours each container once (j.done); wave = mode owner, offset (0,1.2,1.3),
  face owner (straight ahead, no lock-on), fires at frame 64 (user; default + saved).
- 1.54-test: Eldritch Slash wave has its own colour (cfg.slashR/G/B/Bright, default 255/60/170 x6, sliders) - user: pinker, brighter.
- 1.54: slash colour didn't apply (colour-once doesn't stick: the game resets effect colours each frame); user: parts
  of charged blast / burst back to teal (1.49 alias made the charged launch/explosion 'not coloured').
- 1.55-test: colour_update = discovery 5x/s (the only CreatedEffectDataList walk), found containers held (add_ref) and
  coloured EVERY frame via setRootColor + getAllPlayers/set_Color. Launch + explosion families back to 'whole'
  (strength 1.0; veil returns - parked by user). Slash wave: scale_axes (1,2,1) = 2x taller, lifetime = 3x the
  shell 6 ShellBaseParam.LifeTime (learned from the warm-up, which now also spawns shell 6).
- 1.55: charged blast + burst colours OK (user). 1.56-test: slash wave 5x lifetime; 1.2x speed from cfg.slashFastFrom (slider, default 0 = whole skill; the played part 0-97 is only ~1.5 s); wave colouring also through the requested-effect list (tint_wanted: player-owned shells within 6 s of dbg.slashT, entries flagged slash -> slash_colour()).
- 1.56: the animation plays on after 97 (NormalLocomotion didn't cut it); user wants that ~2 s recovery at 1.2x. 1.57-test: no cut; 1.2x from cfg.slashFastFrom (default + saved 97) until the action ends; super armour until then.
- 1.57 trace: 'wave lifetime unknown' every time (warm-up record.param not there yet), slash ends ~0.7 s after frame 97 (recovery = another action), wave effects -1/10/1, -1/10/6 coloured but user sees no colour. 1.58-test: base lifetime learned from the slash's own wave record (logged: UseLifeTime/LifeTime) -> later waves 5x; 1.2x set every frame from cfg.slashFastFrom and kept through following Job05_* actions (end note names the next action); wave shell's own <ShellEffectContainer> coloured every frame in slash colour.
- 1.58 trace: wave shell 6 UseLifeTime false (LifeTime 30 unused) -> lifetime override useless; 1.2x set from frame
  97.5 every frame but not visible; colour not visible. User: 1.52 (crash build) DID colour the wave.
- 1.59-test: distance = DragonCore keep_alive for 5x the measured normal flight (first wave measures, trace note);
  speed also via FullBodyLayer set_Speed(1.2) each frame; wave meshes (shell GO + children) dumped once to
  data/Pactblade_wave_mesh.json and their *color* material Float4s set to the slash colour each frame; per-frame
  colouring of held containers back to the 1.52 way (ce.CreatedEffects players set_Color + setRootColor).
- 1.59: wave still uncoloured, no flight measurement, no mesh dump. 1.60-test: wave structure dump 0.2 s after it fires (parts, GO names, components, children, ShellEffectContainer, ShellParamId) -> data/Pactblade_wave.json; flight end = GameObject/shell get_Valid false.
- 1.60 dump: the wave = ShellBase (app.Shell, ObjectEffectManager2, ShellAdditionalJob07SubNormalAttackShell,
  ShellAdditionalMagicBindBooster...) with child 'effect_ShellBase' = via.effect.EffectPlayer (+ WindEffectSetting,
  ColorCorrectControlUnit, RadialBlurControlUnit) = the visible crescent - no colouring route reached it. Flight
  'measurement' gave 0.01 s (get_Valid false at once) -> 0.05 s lifetime = shorter range + wrong size.
- 1.61-test: no lifetime / keep-alive (range + size back to 1.58); every child EffectPlayer of the wave shell set_Color
  (slash colour) every frame; wave ShellParameter dumped once (3 levels, plain values) -> data/Pactblade_wave_params.json.
- 1.61: range + size back; colour still not changed. Wave params: no movement param in ShellParamBase; the range = app.ShellAdditionalJob07SubNormalAttackShell.DefaultRangeDist (+ AdditionalRangeDist for 'just' release). 1.62-test: both x8 on the wave's component once found (trace note old -> new).
- 1.62 screenshot: the whole wave (crescent + rocks) in original teal. VSB integration was OFF after the quest crash. 1.63-test: colour_shell(..., everyFrame) - the slash wave's list walked + coloured every frame (as 1.52, which coloured it); blasts keep 5x/s + held containers.
- 1.63: wave still teal; user: it worked when it shared the blasts' colour; menu too crowded. 1.64-test: BLAST.slash (shell 6, no damage factor, noScale) - the wave is added to the blasts list and coloured exactly like a blast (colour_shell blast colour + tint path via blast_shell_info); own pink + child-EffectPlayer colouring + test dumps off; menu: Burst windows + slash frame/speed in a collapsed 'Timing' section, wave colour sliders removed.
- 1.64: wave coloured (blast route) but red clouds appear along its path (see-through dust turned solid). Wave effects: -1/10/1 flight, -1/10/3 hit, -1/10/6 finish. 1.65-test: three keep-own-colour checkboxes (cfg.noTint) for them under Timing.
- 1.65: the red clouds belong to -1/10/1 (the crescent's own effect) -> can't separate. 1.66-test: cfg.slashWave magike / skeleton (AppSystem/ch/ch226/userdata/ch226003_shellparamdata.user shell 0, not coloured, not in blasts), cfg.slashRange slider (x DefaultRangeDist, Magike only), both under Timing; user's saved: skeleton, 8.
- 1.66: Skeleton Lord wave = only dust/fog/shockwave (its look is in the Skeleton Lord's own effect files) -> option removed. Range slider did nothing: the component has no DefaultRangeDist (il2cpp dump: it is on app.ShellAdditionalJob07SubNormalAttackShellParameter = <DetailParam>, shared with real Magike Cut). 1.67-test: hook ShellAdditionalJob07SubNormalAttackShell.update() pre: our waves only, DetailParam.DefaultRangeDist x cfg.slashRange, post: put back. Turn toward enemy (user: the character): nearest living enemy within cfg.slashTurnRange 10 m / cfg.slashTurnCone 70 deg of facing picked at the press, character turned toward it at cfg.slashTurnSpeed 360 deg/s (set_Rotation + TargetAngleCtrl) until the wave frame; sliders under Timing.
- 1.67: turning + 8x range OK (user). Hits (dummy): wave = magick 1117, ActionRate 1.675, 2058 -> 3087 (passive x1.5); 'hit' phys 1259, ActionRate 4.0, 5540 (probably the Crescent Slash sword). 1.68-test: hit log also writes attack name, DamageReaction (stagger), DmgReactionValue/ActionDmgReactionValue/DmgReactionRate, DamageType / lean / blown, HitBackZ/Y, StaminaDamage.
- 1.68 hits: sword phys 1259 x4.0 = 5540, DmgReactionRate 6.0, lean Hitback_L(7) / blown Upper_S(16); wave magick 1117 x1.675 = 2058 -> 3087, DmgReactionRate 2.0, lean Hitback_L / blown Blown_S(18); DamageReaction 0 in the damage hook (filled later in calcDamageReaction). 1.69-test (user): wave dmgMul 2 (after the passive -> ~6175 on the dummy), stagger x5 in calcDamageReaction (= rate 10).
- 1.70-test: FIRST REAL EFX EDIT. Patched local REE-Lib reads/round-trips DD2New efx (17/21 cs008 byte-identical incl. 40/43 = cs_008_10/30); recolour tool catalog-tool efxtint: every RgbCommon (DD2New id 248) channel colour at attribute bytes 4 + 24 -> hue of 255/3/30 keeping S/V (14 colours, 42 bytes each file, nothing else). Copies pb_40_t1 / pb_43_t1 at vfx/effects/pactblade (pak_mods/x0004-PactbladeFx-tint.pak, src efx/pak_srcT, verified by unpack). Menu Look: 'blast effects from the recoloured files' = parts 40/43 mode ours variant t1 (baked: no set_Color). x0003 recolour pak moved to efx/removed.
- 1.71-test (user: night too dark to see effects): Debug 'Skip to daytime (10:00)' = app.TimeSkipManager.requestPlayerWarp at the player's spot (as Nick's Devtools); 'keep it daytime' (cfg.keepDay) skips to 10:00 when 19:00-4:59, checked every 5 s, not during Archfey Combo / Eldritch Slash, max once per 30 s. Fixed: cfg.slashTurn was saved but not read back.
- 1.70 result: veil still there - our 40 copy did play (trace), but the burst's other effects (-1/8/11 flight = cs_008_01, -1/8/13 = cs_008_31 + wind, 14 = cs_008_04 ...) are still tinted at runtime. Container 8 map (cs_ref): 0/40->cs_008_10, 1/11->01, 2/42->20, 3/43->30+Wind, 4/14->04, 10/50->11, 12/52->21, 13/53->31+Wind, 20->60, 21->50, 22->70, 60->80, 100->110, 101/111->101, 102->120, 103->130+Wind, 104/114->104, 110->111, 112->121, 113->131+Wind, 160->160.
- User: the veil = one LAYER of an effect (like the arm cloud). Arm effect 13_ch07_ns_025_00 round-trips byte-identical; 13 layers Root, Light, MI, prsm, dis, tnn, tn, oo, o, invv, inv, ig, s. catalog-tool efxoff: a layer's Spawn (id 18) MaxParticles (first u32) = 0 (1 byte). Copies pb_arm_no_<layer> in pak_mods/x0005-PactbladeFx-arm.pak (x0004 was locked by the running game). User screenshot: the arm's red cloud shows the warped background = distortion -> 'dis'. 1.72-test: Look > Hand glow > 'arm effect (test: one layer off)' (cfg.glowVariant, default 'dis'); falls back to the game's file if the pak isn't loaded.
- User (1.70 option on): launch at the hand = original colour, no veil; explosion = red, NO VEIL (baked works) but rock debris. 43 layers 34-57 = debris meshes stone/snow/ice (the game picks one by ground; our standalone copy shows them). Also distortion layers dis(7) blur(8) MHdis(15) Mdis(16). 1.73-test: pb_43_t2 = t1 + debris layers off (24 bytes), pak_mods/x0006-PactbladeFx-nodebris.pak; the baked checkbox uses t2 for 43; user's saved 43 -> t2.
- 1.72 CRASH (Eldritch Slash start): 'Heap allocation failed', stack through app.ActionManager.changeAction + native effect/render code DD2+0x522c1f2; dump (crash_1_72_slash.dmp) c0000005 at DD2+0x524feb4 - same native region (0x5226xxx-0x5261xxx, after via.render.CustomFilter) as the 1.52 slash crash (+0x5236228) and crash #1 (+0x52345ae). Cause (likely): colour_update kept found effect containers and set_Color'ed their players EVERY FRAME for 6 s with no liveness check -> writes into finished/freed effect players -> heap corruption (worse with 8x wave range: more overlap). parts.live + tint_update already checked get_isFinished. 1.74-test: colour_update: job dropped once its projectile is gone (after 0.5 s grace), every held container checked with get_isFinished before touching (colour_container), finished ones dropped.
- 1.74 CRASH: fresh boot, first Eldritch Slash -> same 'Heap allocation failed' stack (changeAction -> DD2+0x522c1f2 -> allocator). Deterministic, not slow corruption. Worked in 1.71 (before x0005/x0006 paks + glowVariant). Suspect: arm copy with 'dis' MaxParticles = 0 (size underflow -> huge alloc when the layer is rebuilt). Test: user's glowVariant set to '' (game's own arm file).
- 1.74 CRASH 2: charged blast, last trace line 'effect -1/8/43: our edited copy plays (pb_43_t2)' -> crash, same stack. With glowVariant '' (game's arm file). => MaxParticles = 0 layers (efxoff) crash the game ('Heap allocation failed') once they emit; the 1.72 slash crash = the zeroed 'dis' arm copy. t1 (recolour only) never crashed. NEW layer-off method: catalog-tool efxhide = the layer's Transform3D LocalScale = 0.001 (12 bytes per layer, decoded struct). Rebuilt pb_arm_no_* (x0005) and pb_43_t2 (x0006) that way; x0004 = t1 only. efxoff must not be used.
- 1.74 + efxhide paks: user CONFIRMED arm effect 'without layer dis' = red cloud gone, arm glow + charging still visible. => the veil = distortion layers; hiding them (Transform3D scale 0.001, new-path copy) works. Next: same for the blast files (43: dis, blur, MHdis, Mdis; 40/launch: blur0 ...).
- 1.75-test: (a) arm baked colours pb_arm_pp285/300/315 = dis hidden + efxtint hue 285/300/315 (16 RgbCommon colours) in pak_mods/x0007-PactbladeFx-armcolour.pak (x0005 was locked by the running game); with a pp variant the runtime arm tint = white x armBright (brightness only). efxtint now also tints TypeMesh (31) colour @92 (same offset in every DD2New mesh layer; teal 168885 in the launch spirals / cone / magic circle). (b) user: no cloud any more -> charging plays the WHOLE arm effect from 0 (cfg.chargeFull, default on), looped at cfg.chargeEnd 3.0 s, speed cfg.chargeSpeed 1.0 (sliders); the old 2.65-3.00 slice when off.
- 1.76-test: ONE effect pak pak_mods/x0004-PactbladeFx.pak (25 copies, src efx/pak_all; old x0004-x0008 in efx/removed). Blast effects: c285/c300/c315 = Charged/Burst launch cs_008_11 (18 colours: RgbCommon + TypeMesh @92) and explosion cs_008_31 (19 colours + debris layers 36-59 hidden), picker under Look (default purple, PART_DEFAULTS ours c285). Arm: ppb285/300/315 = pp + light colour (TypeNoDraw @4: 0D6480 teal -> hue) + light Intensity 200->800, ReferenceEffectiveRange x2 (efxparam: field param 'FF FF idx f32 hash name') + RgbCommon intensities @12/@32 x1.8 (efxbright). Own arm light: via.render.PointLight on an anchor at dbg.glowJoint, colour = baked hue or arm sliders, sliders lightLm (800) / lightRadius (4 m). Glow while sheathed: during 'charging' + 1 s, or always with cfg.glowSheathed (default off). Defaults = user's: glowVariant pp285, chargeSpeed 0.35, chargeEnd 5.0. (glowSpeed 0.1 in the user's json = old leftover, no effect with freeze.)
- 1.76 user: launch still partly teal (no veil); arm: wants the EFFECT to glow, not area light. Found: TypeNoDraw (79) has a 2nd colour @68 = the light colour (launch Light 168885 teal, arm Light 33F1FF cyan) - efxtint now tints @4 + @68. Other teal-looking hits in TypeMesh material lists / EffectShader = hashes (e.g. '...1db7' + white). 1.77-test: pak_mods/x0005-PactbladeFx-2.pak (x0004 locked by the running game): blast d285/d300/d315 (launch incl. light colour; explosion + debris hidden), arm pb_arm_h<hue>g<1-4> = no dis + colours incl. both light colours + RgbCommon intensities x1/x2/x3.5/x6 (efxbright). Menu: arm effect = game's own / no cloud / purple / pink-purple / pink + 'glow strength' 1-4; layer-test + pp/ppb entries and the arm light UI removed (armLight default off). User's saved: blast d285, arm h285g1.
- 1.77 user: glow strength 2 (normal) + 4 (charging); still some cyan streaks (Burst). Scans of d285 copies: no teal left in known colour fields (rest = hashes / '00 00 FF FF FF' white noise); only a green 66da39 @121 in 3 explosion ribbons (mi, iy0, i). => cyan likely from the NOT replaced blast parts (flight 1/11 = cs_008_01, 2/12 = cs_008_20/21, after 4/14 = cs_008_04, explosion wind 13_Wind_000_00). 1.78-test: cfg.glowLvCharge (slider, default 4) - charging copies use pb_arm_h<hue>g<charge>; resource cache per path. Debug 'Hide one blast part' (BLAST_DROP) to find the cyan source. User's saved: h285g2, charge 4.
- 1.78 user: Hide 'launch 0/10' removes the teal -> it is in our pb_40_d285 copy (byte colours all purple; suspects: mesh materials .mdf2 / float colours). 1.79-test: pb_40_d285_x<layer> copies (one layer hidden each, 14 layers) in pak_mods/x0006-PactbladeFx-launchtest.pak; Debug 'Purple launch: hide one layer' (dbg.launchHide, not saved); those copies count as baked.
- 1.79 user: hiding S0 (shockwave, launch layer 3) removes the teal. TypeMesh material parameter records = 'hash u32, index u32, 04 00 01 00 (vec4), 0 u32, f32 x4'; the colour one: hash f20fbe80 (S0 0.271 0.588 0.902 = 69/150/230 /255; explosion S5 + JS). Other recurring vec4 hashes (46352622, ac91f528, 30778464, 119066dc ...) look like ranges, left alone. efxtint recolours f20fbe80 (float HSV, keeps S/V). 1.80-test: e285/e300/e315 (= d + that) in pak_mods/x0007-PactbladeFx-3.pak; picker default purple = e285; user's saved e285. Paks to merge when the game is closed: x0004 + x0005 + x0007 (x0006 = launch layer test, can go).
- 1.80: user: blast effects GOOD (purple, no veil, no teal). Final pak: pak_mods/x0004-PactbladeFx.pak = 19 files (src efx/pak_final, list efx/final.list): pb_arm_no_dis, pb_arm_h{285,300,315}g{1-4}, pb_40/43_e{285,300,315}; all older paks in efx/removed. 1.81-test: Debug test pickers (hide blast part / launch layer) and the d285 comparison entry removed.
- 1.82-test: Eldritch Slash wave = Magike Cut shell 6, ns ref (13_ch07_ns_Ref.pfb) container 10: element 1 = ns_010_01 (flight; plain set 4-13 + Ice i_ / Thunder t_ / Fire f_ / Holy l_ sets 14-45; dis + blur distortion, smoke 'o'), 3 = ns_010_03 (hit; sets 9-36), 6 = ns_010_06 (finish; sets 9-36). Copies pb_10_<n>_h<hue>: element sets hidden, colour baked (RgbCommon / mesh @92 / material f20fbe80 / lights), no tint -> no red clouds. parts: ids + PART_ALIAS for -1/10/1,3,6, OUR_FILES tail '10_n', flight follows the shell (position + rotation + scale every frame, ends 0.3 s after the creator is gone). Warp wisps = sword wp00_111 enchant element 30 = 13_wp00_111_enchant_30 (layers Light, tb dust, ff fire, tn lightning, dis distortion = the teleport cloud): pb_wisp_h<hue> = dis hidden + colour baked, played by wisps.play_file (own EffectPlayer + adapter for setPlaySpeed / finishAll (PlayerAction.Finish) / getAllPlayers = none); hue from the blast picker (e<hue>), else the sword route. Picker 'blast / Eldritch Slash / warp colour' sets all. Files in pak_mods/x0005-PactbladeFx-2.pak (x0004 locked); merge when the game is closed.
- 1.82 user: Eldritch Slash wave GOOD (copies + follow). Archfey Combo: no cloud but NO wisps either. The wisp efx has 15 expression (extern) params fed by the weapon enchant system (BaseColor/FireColor colours, ParticleSize default 0.018, alphas, intensities); bones 'Main' (arm uses L_Arm_Lower and works standalone, so not the bone). 1.83-test: wisps.play_file reads the sword route's extern values once (hidden probe 1000 m below, read 0.3 s later in update_bursts, logged 'warp wisps: the sword's effect values read'), then sets them on every copy of ours; colour params = picker hue via set_Color (parameter colour, no veil). The first warp after a script load uses the sword route.
- 1.83: probe read OK (ParticleSize 0.022 etc. - same tiny values the sword route uses, so not the cause); wisps still invisible (only the first, sword-route one showed). 1.84-test: pb_wisp_h<hue>n = catalog-tool efxunbone (every ParentOptions BoneName 'Main' -> '', bone links -1; first SIZE-CHANGING edit: 8845 -> 8805 B, reads back + round-trips) in pak_mods/x0006-PactbladeFx-wisps.pak.
- 1.84: unbound copy also invisible (only the first sword-route wisp showed). 1.85-test: back to the sword route for every warp; right after the container is made, each of its players gets set_Resource(our pb_wisp_h<hue> holder) (dis hidden, colour baked; bone intact); no wisp tint on swapped containers (wisps.swapped). Note 'warp wisps: X of Y players given our file' once. play_file / probe code left unused.
- 1.85: 'warp wisps: 1 of 1 players given our file' but the wisps kept their own colour (set_Resource on a started player does nothing); no cloud without tint. 1.86-test: wisps.swap now sets the wisp effect's own colour params BaseColor + FireColor (getExternParameter -> set_Color, picker hue) every frame; no whole-effect tint on them (the cloud = tinted 'dis').
- 1.86: wisps GOOD (user). Wisps last default 0.5 (user's value). AFTERIMAGE idea (user): MSP ghost clone where the warp starts, our pose, 0.3 s, our colour. Game: app.AfterImage (: app.CloneCharacter, used by Job07 Mirage Dance) via Human.<Job07ActionCtrl>.<AfterImageHandler> (CloneCharacterHandler<AfterImage>: setup(Human[, Prefab]) / create() / start(StartInformation{Position via.Position, Rotation}) / finish() / vanish(); Instance; Parameter._AfterImagePrefab). AfterImage: requestMotion(uint id, f32, f32, f32, InterpolationType), requestWorkRate(f32, f32), MaterialInterpolationSettings (ghost look). 1.87-test: Debug 'Afterimage (test)': handler state, create (setup owner if none), spawn here (start + our motion/frame, frozen, finish after a slider time), log.
- 1.87 user: handler HasInstance=true InProcess=false Appeared=false; start/pose/freeze/finish calls OK but nothing visible. Driver = Job07MirageDanceController (start(target GO, motion int, lv2 bool)). CloneCharacter StatusType None 0, Appear 1, Disappear 2, Operating 4, Sleeping 8. 1.88-test: Debug afterimage buttons inspect / set owner + build body (setOwner(Human) + cloneOwner()) / appear (applyStartInfo + addStatus(Appear) + DrawSelf).
- 1.88 CRASH: 'set owner + build body' = cloneOwner() on the already built clone (inspect before: CompletedClone true, HasOwner true, Status 0, IsEnd true, go Job07_AfterImage draw false update false, parked 1542 m away). NEVER call cloneOwner again. 1.89-test: spawn = parked clone UpdateSelf + DrawSelf on, moved to us, own motion layer changeMotion(bank, id, frame, 0, 1, 1) + speed 0, after the time hidden + switched off + back to the park spot; create/build/appear buttons removed (code left unused).
- 1.89: inspect during the window: still draw false / update false / 1548 m - our switches + position are undone each frame (clone stays 'ended'). 1.90-test: handler init(false) + start(StartInformation) (game flow), pose on its own layer, auto inspect + handler state 0.2 s after, handler finish() at the end.
- 1.90: init(false) + start(info) DOES make the clone appear (Appeared true, InProcess true, draw + update true, 0.0-0.4 m from the player) but the user sees nothing (Status stays 0 = no Appear status -> ghost material / start effect probably never fade in; it also tracks the player's root history). CRASH (c0000005, executing freed memory, stack DD2+0x527354d / 0x52afc04) 2 s after a second spawn made while the previous clone was still in process. 1.91-test: afterimage test menu disabled (if false) - PARKED. Lessons: never cloneOwner a built clone; never init/start the clone while InProcess.
- 1.92-test (user: script bloated again; dropdowns with colour): menu = Look (ONE colour picker purple / pink-purple / pink / game colours -> blasts e<hue>, wave h<hue>, wisps (via 40's variant), arm h<hue>g<lv>, tints on/off; arm effect + glow strength + while charging + sheathed; Nox), Skills (bind, warp look, wisps last), Advanced (arm freeze / charge loop, runtime tint + RGB, cloud size, combo dust, Burst windows, Slash timings + turn), Debug (status, dummies, daytime, hits, log). Purple theme (push_style_color FrameBg/Button/Header/SliderGrab/CheckMark, titles light purple). Dead code removed: afterimage test, standalone wisp player + probe, our_holder, launch-layer test hook, wave keep-own-colour checkboxes, arm layer-test entries. 4305 -> 4086 lines.
- User wants the afterimage (not parked). Clone API: requestMaterialMode(RequestListCategory, Nullable<uint>), requestStartEffect(), requestBodyEffect(), addStatus, setLifeTime(Nullable<float>); AfterImage fields Basic (RequestListCategory), DelayTime, RootInformationHistory, RootMoveScale. 1.93-test: Debug 'Afterimage (test)' again with guards (no spawn while InProcess / within 3 s of the end, no cloneOwner): init(false)+start(info), then each post-LateUpdate RootMoveScale 0 + pinned to the spot, requestStartEffect + requestBodyEffect, frozen pose, inspect at 0.3 s (incl. distance to the spot), handler finish() after the slider time (default 2 s).
- 1.93 user: GHOST APPEARS (transparent copy of the character, pinned to the spot - 0.0 m from the spot while the player walked away), but not MSP's teal afterimage look. Guards worked (no crash). 1.94-test: + requestMaterialMode(inst.Basic, Nullable<uint> none) and a one-time dump of _MaterialInterpolationSettings (category + userdata paths) to data/Pactblade_afterimage_materials.json.
- 1.94 user: look unchanged (dump: _MaterialInterpolationSettings null -> material mode had nothing), mid-Onslaught the clone stood in a near-default pose (our attack motions not in its banks). Mirage Dance = cs ref container 10 (Boisterousdance): cs_010_00 / cs_010_20 have an 'MI' layer (material switch on the body they play on), cs_010_03 'Dissolve'. 1.95-test: play container 10 element 0 / 20 / both (Debug combo) on the clone via the player's ObjectEffectManager2 (ch07 cs ref index); pose = player's joints (local pos + rot) snapshot at the press, applied every post-LateUpdate, clone Motion disabled while shown (re-enabled at the end), effects finishAll at the end.
- 1.96-test: (main-chunk 200-locals limit hit: ai helpers are ai.hsv / ai.rgb / ai.FX now) - 0.3 s after spawn all clone mesh material float4s -> data/Pactblade_afterimage_mesh.json; teal/cyan ones (hue 150-230, sat > 0.35) overwritten in BeginRendering with the picker hue (S/V kept).
- 1.96 user: ghost body PURPLE; aura + wisps teal (visible layers of cs_010_00 / cs_010_20). 1.97-test: copies pb_ai00 / pb_ai20 _h<hue> (efxtint: 10 + 4 colours incl. light @68) in pak_mods/x0007-PactbladeFx-afterimage.pak, played on an anchor parented to the clone (ai.src 1 = ours, 2 = game's, 3 = game's + ours - in case the MI material switch only works through the game's request); anchors Finish at the end, destroyed 2 s later.
- Merged (game closed): pak_mods/x0004-PactbladeFx.pak = 34 files (efx/pak_final, list efx/final.list): arm no_dis + h{285,300,315}g{1-4}, blast pb_40/43_e*, wave pb_10_{1,3,6}_h*, afterimage aura pb_ai00/20_h*. Wisp copies dropped (wisps coloured through their own BaseColor/FireColor). x0005-x0007 moved to efx/removed.
- 1.97 user: all coloured, but the ghost body teal for a split second each time. Ghost colour = RimLight_Emissive_Color_A (0.118 0.235 1.0) + RimLight_Emissive_Color_B (0.235 1.0 0.784) in all 58 clone materials (1.96's generic float4 scan also overwrote scalars - removed). 1.98-test: those two by name hash (getMaterialVariableIndex), looked up at the spawn frame, set in BeginRendering from frame 1 with the picker hue (S/V of the game's values).
- 1.98 user: no teal flash any more (better). 1.99-test: afterimage on every warp start (Archfey Combo warps + Misty Step leap, right after the departure wisps, before the move): ai.warp - still showing -> moved to the new spot + pose (no restart), else ai.spawn if not InProcess; cooldown after the end 0.3 s (was 3); cfg.afterimage (default on) + cfg.afterimageSecs (0.3) under Skills; Debug test section removed; dbg.ai = ai (the combo function reaches it through dbg).
- 1.99: user OK ('good for now'): afterimage on warps accepted.
- 2.00-test (user: a bit of tracking on the Archfey Combo's first hit): at the press the nearest living enemy within cfg.comboTurnRange 12 m / cfg.comboTurnCone 70 deg is picked (combo.pick_target = slash_pick_target(a, range, cone)), the character turns toward it at cfg.comboTurnSpeed 360 deg/s (combo.turn_to) during stage 1 until the first hit (combo.target set). Advanced > Archfey Combo: on/off, speed, reach.
- SAVE (user): versions/Pactblade-2.00-SAVE-ArchfeyCombo-fixed-warps.lua = Archfey Combo with fixed warps (side -> behind -> in front, closer) + opening tracking. Next: dynamic warp spots (user design).
- 2.01-test (user design, confirmed): dynamic Archfey Combo warps = a cross around the enemy, its own sides front/back/left/right (enemy_sides: current side = best dot of player-from-enemy dir). Warp 1 (part 2) = opposite of the current side (then the perpendiculars if blocked); warp 2 (part 3) = an unused side, back first if free, else random; warp 3 (part 4, air finisher, head height) = the last unused side (then used ones except the current). warp_spot(a, how, forced dirs) returns the side name; note 'warp to part N: from the enemy's X to its Y'. cfg.comboDynamic (default on; Advanced > Archfey Combo), off = the saved fixed spots.
- 2.01: dynamic warps good (user); air finisher too high. 2.02-test: cfg.finisherHeight (default -0.3 m relative to the head joint; was +0.4) slider in Advanced > Archfey Combo.
- 2.02: user happy with the default (-0.3 m = 0.3 m below the head; slider untouched).
- IDEA LIST + (user 2026-10-22): 'Misty <word> Strike' = like the MSP skill that teleports above the enemy and strikes downward. Name ideas given: Misty Plunge (suggested), Misty Descent, Misty Dive, Misty Rend, Misty Fall. Est. easy-medium (warp + wisps + afterimage + head spot + targeting exist; needs: animation choice, slot, damage/stagger/stamina).
- Name chosen (user): MISTY DIVE.
- 2.03-test: Charged Eldritch Blast renamed ELDRITCH BOLT (user) in the menu, notes and BLAST name (internal kind stays 'charged').
- TASHA'S CAUSTIC BREW (user idea): 3 s cast like Mage/Sorcerer, on release a big cauldron appears ~3 m up in front, falls, liquid pours out in a 2 m x 15 m line. Cauldron = camp cooking pot: gimmicks gm51_381(_00/_01)/382(_00)/383(_00) (camp + interact), meshes Environment/Props/sm5X/sm51/sm51_381 (_00/_01/_02), sm51_382 (_00/_01), sm51_383 (_00/_01) + shared sm50/sm50_020; prefabs extracted to dd2-research/gimmick_pfb. 2.04-test: Debug 'Model preview (cauldron...)': spawn each mesh + mdf2 on a make_anchor object 3 m in front, size slider, remove all (Dimension Door MeshProbe pattern).
- 2.04: preview failed (forward_of / flat_dir are locals of the combo function, not visible in the main chunk). 2.05-test: forward from rot * (0,0,1).
- 2.05: script-built meshes invisible (engine limit, as in Dimension Door). 2.06-test: cauldron gimmick prefabs (camp/gm51_381, _01, gm51_382, gm51_383; interact/gm51_381_00, 382_00, 383_00) spawned the RampartNox way: via.Prefab + MethodLibrary.prefab_set_path (DD2MethodLibrary.dll installed) + set_Standby, instantiate(vec3, quat) when Ready (10 s timeout), scaled; components -> data/Pactblade_prop_components.json.
- 2.06 CRASH: raw via.Prefab:instantiate of a gimmick prefab (no dump; log stops). 2.07-test: _NickCore GimmickSpawner method - GenerateManager gimmick catalog prefab by ID + requestCreateInstance(ctrl, GenerateInfo category 5 + setGimmickID + universal position/angle, 0, InstanceInfo, nil, nil); IDs (NickCore list): 358/359/360 cooking pot 381_00/382_00/383_00 (interact), 743 cooking pot 381_01 (camp), 220/221/222 campfire 381/382/383, 742 poison vase gm80_154_00.
- 2.07: gimmick spawn works (no crash) but each cauldron = the whole campfire. Parts (dump): effect_gm51_381_00 (EffectPlayer, fire), Point_Torch_Indoor (PointLight), gm50_020 (Mesh + Gm50_020 gimmick comps; shared by all styles = the pot?), Cloth (Mesh), root (fire pit / stand meshes). 2.08-test: preview checkboxes per part of the last spawn (Mesh Visible/DrawDefault/ShadowCast, EffectPlayer + lights Enabled, child DrawSelf; root = own components only).
- 2.08 user: gm50_020 = rake/tool next to the fire; root mesh (sm51) = the soup; pot + campfire stay with every switch. 2.09-test: every Mesh / EffectPlayer / Light component in the whole tree (depth 6) listed (object + kind + mesh file), one checkbox each; list -> data/Pactblade_prop_parts.json.
- 2.09: camp cooking pot = one model with its campfire (user). User's pick: the big two-handled clay jar in the city (screenshot). 2.10-test: preview list = gm80_256 cooking pot (704) + vases 27/635/667/668 gm50_041(_xx), 19 gm05_062, 28 gm80_152, 29 gm80_153, 30 gm80_154 poison vase, 241 sphinx vase gm81_077, 272 gm51_218, 368 gm51_136, 369 gm51_164, 32 gm05_057 (NickCore IDs).
- Caustic Brew vessel (user's pick): SPHINX VASE gm81_077 (NickCore gimmick ID 241), spawned via GenerateManager.requestCreateInstance (Pactblade props.spawn).
- Caustic Brew decisions (user): slot = Full Moon Slash (Job01_FullMoonSlash, user has it equipped), acid-green, small damage + medium stagger + poison build-up, built first. Damage candidate: humanshellparamdata_job02 shell 35 poison arrow (player-owned, poison). Visual candidates: ch254 shell 0 / ch254001 shell 0 (Chimera poison breath), ch221001 0-3 (poison gun / all directions), ch221003 2 / ch254 2 (poison gas), ch228002 0 (small poison cloud). Cast: Dimension Door's motion-bank cast (ch00_006_atk 700/701/750) has no effects/sounds (user) -> 2.11-test Debug 'Cast test': request the real Job06_Prepare* / Job03_Ready* actions (with their effects + sounds) on Pactblade.
- 2.11: Job06_Prepare* request -> true but back to NormalLocomotion at once (needs the Sorcerer's spell state). User: plays Warfarer, can equip staves and chant. 2.12-test: Debug 'Recorder': N s (default 8) of the player's own effects (id + effect set path of the container index), sound triggers (WwiseContainerApp trigger*), full-body motion changes (bank/id, frame, action) -> data/Pactblade_chant_record.json; works with any weapon (not gated by live.on).
- Recorded Mage chant (user, Warfarer+staff, ended in Guard Bit): effects ch03 ns 0/40 + cs 0/104 at start, cs 0/104 + cs 0/304 (~1.5-1.9 s), ns 0/41 + cs 0/3 ready (3.4 s); sounds 2921097576 start, 3366100101 chant loop, 3990051307 ready; motions 131/20, staff set 130/710 -> 712, 1202 ready, 1204 cast. 2.13-test: Debug 'Cast replay test': DD motion-bank cast (ch00_006_atk bank 9112, FSM paused) 710 -> 712 loop -> 750 at cast time (slider 3 s) + those effects (Mage sets by path) + sounds (combo.cue_sound), step log.
- 2.13 CRASH: switching staff -> sword (Warfarer), right after 'warmed up the blasts' (c0000005 DD2+0x525c56e, effect/render native region). Cause (likely): warm-up (hidden blast shells) + arm glow start while the weapon and its effects are rebuilt. 2.14-test: live.onSince / live.settled - warm-up, arm glow + arm light only 2 s after Pactblade becomes active.
- 2.14: staff <-> sword switching stable (user); cast replay works but the chant sound never stops. 2.15-test: chant loop 3366100101 triggered once, stopped at the release (SoundContainer.stopTriggered(id, go, fade ms) via combo.stop_sound) and again at the end.
- 2.15: stopTriggered did not stop the chant sound. 2.16-test: chant loop trigger off by default (checkbox) to see whether the endless sound is ours or the 712 motion's own sound events; buttons to fire the recorded cast sounds (3321385309, 2605810471, 732561637, 673994548, 2184176315, 3241999422, 1487858092) to find the stop.
- 2.16 user: sound 2605810471 STOPS the chant sound. 2.17-test: castT.STOP 2605810471 sent at the release and at the end (stopTriggered removed from the flow).
- 2.17: the endless chant sound comes from the 712 motion's own sound events (loop trigger was never on) -> loop trigger stays off; 2605810471 at the release stops it. Cast part of Caustic Brew settled.
- 2.18-test: Debug 'Acid effect preview' (dbg.acid - main chunk at the 200-locals limit): standalone EffectPlayers for Chimera ch54/001 liquidshell_020_00..03, breath_040_01, est_status_211_00; ch21/000 liquidshell_020_00/01/03/05, badstatus_100_11; ch21/003 liquidshell_022_00/01/03/05; 3 m in front or a wave of 8 copies over 15 m.
- BUG (user): carrying a body + L1 (throw) -> dodge. 2.19-test: vocation button handling skipped while carrying (CatchController.CaughtChara set, or current action name has Catch/Carry/Lift/Hold/Throw/Grab/Caught).
- 2.20 (2026-10-22) CAUSTIC BREW POUR LOOK: user picked ch54_001_liquidshell_020_03 but its black cloud must go. Layers (47): liquid
  meshes B/BB/B_M* (13_Liquid_000_*, colour 4B00C2 = the purple), water billboards sw_*/dw_* (white, tint BFDFFF), dark dust
  t (9) + d (33), smoke ky (25) / s0 (11) / shock_s0 (45), dark liquid billboards b (10) / tby (8) / dw_wtbbb (12), distortion
  tn_dis / dw_Mg / dw_M / dw_MM (left untinted), Light0 3E0068, blood decals, debris. efxtint 110 255 0 (32 colours) then efxhide:
  pb_acid_g1 = t,d; g2 = + ky,s0,shock_s0; g3 = + b,tby,dw_wtbbb. Game was running -> separate pak_mods/x0005-PactbladeAcid.pak
  (src efx/pak_acid, acid.list); also added to pak_final/final.list + rebuilt efx/x0004-PactbladeFx.pak (37 files) to install
  over the old one when the game is closed (then remove x0005). Preview: Debug > Acid effect preview, buttons pb_acid_g1..3.
- 2.21 (2026-10-22) CAUSTIC BREW DROP TEST (Debug > "Caustic Brew drop test"): sphinx vase (241) spawned via props.spawn
  (new onReady callback), its Colliders / HitController / RigidBodySet / RigidBodyMeshSet / AdjustPress / CrushController
  switched off (a vase gimmick's parts seen on gm05_057: root + child "Broken" with CrushController), then moved by script
  every LateUpdate: gravity fall from 3 m, tip 90 deg around its base (axis choice X+/X-/Z+/Z-, since the mouth axis is
  unknown), lying height slider, then the acid wave (pb_acid_g1..3) from the mouth (dbg.acid.wave got a 'start' offset).
  Sounds: the vase's own SoundContainer triggers listed as buttons; the Recorder can now also log sounds of objects within
  10 m (obj name + container kept in dbg.rec.scs) -> play / use as landing / use as pour.
- 2.22 (2026-10-22) ALL-GREEN ACID: user (g1 picked): still dark blue/purple, white and black, ground layer dark blue/purple.
  Found: header extern params GroundColor0 261E15 / GroundColor2 F2F7FF / GroundColor3 1A331A (table at 0x39b: hash16,
  hash8, type 1, RGBA) - GroundColor2 drives the GPU water particles (TypeGpuPolygon 265 refs its hash cf7a14f9);
  particle type colours @4/@12 in ids 26/35/67/264/268; my efxtint skipped white/grey. New catalog-tool `efxforce in out
  r g b tr tg tb [skip layers]`: strong colours hue only (same as before), white/pale (RgbCommon/mesh/light) -> 2D8C0A,
  dark (<0.3) -> 1B5406; skipped dw_Mg dw_M dw_MM tn_dis (distortion = veil) + com_Cam com_Radial empty_Nodraw. Header
  params patched by offset. pb_acid_v2 (t,d hidden) / v2n (+ Decal, Decal0 hidden) in pak_mods/x0006-PactbladeAcid2.pak;
  efx/x0004 rebuilt with 39 files for when the game is closed (then drop x0005 + x0006).
- 2.23 (2026-10-22) PERFORMANCE check (user: can the Archfey Combo clones hurt?). The clone = the game's ONE reused Mystic
  Spearhand AfterImage clone (never more than one, moved on re-warp, 0.3 s), effects on 2 anchors destroyed 2 s later.
  Real costs found: (1) note() wrote Pactblade_trace.json on EVERY note (3-4 per warp), calc/hits files on every hit,
  sword fx + combo fx records -> synchronous disk writes on the game thread. Now dbg.save(name, data) + an on_frame flush
  at most every 2 s. (2) ai.apply_pose made a closure + 2-3 managed calls per joint per frame; now joints resolved once
  per pose (ai.pose list), then 2 calls per joint per frame. Snapshot per warp unchanged (once per warp).
- 2.24 (2026-10-22) user (v2): still purple liquid, grey-blue water, black bits, dark blue/purple ground; vase sits on the ground
  and doesn't turn. Found: TypeMesh @12 = a second mesh colour (2B0070 on all 7 liquid meshes) -> efxforce now does 31 @12
  + @92 (only bytes with alpha FF). Ground stain candidate: Decal layer -> VFX/MarkSystem/Decal/13_BloodDecal_001_00.pfb
  (via.render.VolumeDecal BaseColorMod 4D0000FF dark red @0x3fc; _000_00 = meat texture, white). User asked to make the dark
  red teal as a test: copy 13_pbaciddecal_01_00.pfb.18 (00B4B4FF), same-length path swapped in the efx -> pb_acid_v3t.
  v3 / v3t / v3n (no decals) / v3w (no water layers) in pak_mods/x0007-PactbladeAcid3.pak (src efx/pak_acid3).
  Lua: GroundColor0/2/3 extern params forced green every frame on our acid effects (in case the game sets them from the
  surface; the count found is shown); pour sound on every splash of the wave (onCopy, sound at the splash anchor).
  Vase = a pick-up gimmick (PickUpController, gm50_000 with executeBreak, DynamicsLocker, DynamicsDamage, RigidBodySet...):
  those switched off too; its root RigidBodySet gets setPosition/setRotation(0, ..), zero velocity, gravity 0 each frame,
  placed in LateUpdate AND BeginRendering; "pushed away by up to X m" readback shown.
- 2.25 (2026-10-22) user (2.24): v3 "not all green"; v3n (no decals) removes the purple ground -> the stain IS the decals; no
  teal in v3t (pfb copy colour ignored: colour given at spawn, or the path is not what spawns it); vase gone completely;
  no sound. Textures: meat decal 13_Meat_001_00_ALB BC1 avg rgb 79/47/39 (brown, not purple); blood decal BC7.
  catalog-tool `tex2dds in out`. Now: VolumeDecals named *BloodDecal*/*PbAcid* within 8 m of our acid found via
  scene findComponents (every 0.15 s while it is out) and set_BaseColorMod green for 2 s (pooled objects). Vase: back to
  2.21 switch-offs + DynamicsDamage/DynamicsLocker; pick-up logic optional; physics body mode combo (1 resetTransform +
  zero velocity + gravity 0 with the body ON, 2 = 2.24 setPosition, 3 = 2.21 body off); where-is-it line. Sounds: on the vase.
- 2.26 (2026-10-22) user: "get the actual skill working first; the look is acceptable (v3), colouring later". (Colour work
  parked: v4 = dark -> full 2D8C0A (EFX_DARK=1.0), v4m = meat decal (layer 20) hidden, v4c = colour-coded layers (red b/tby/
  dw_wtbbb, blue GPU sw_wtb.., yellow water billboards, magenta smoke/glow) built in efx/pak_srcH, NOT packed; catalog-tool
  efxsetcol added; meat decal BaseColorMod at 0x3ac of 13_blooddecal_000_00.pfb.18. 2.25 runtime stain scan found 0 decals
  and GroundColor extern params 0 effects -> the decals aren't findable as VolumeDecal components that way.)
  TASHA'S CAUSTIC BREW live in Full Moon Slash's slot (processCustomSkill FULLMOON_ID skip + requestActionCore
  Job01_FullMoonSlash skip, Track.All/Skill check): castT chant (3 s, waits for the motion bank) -> castT.onRelease ->
  sphinx vase via props.spawn(opts up 3 / ahead 3 / size 2) falling with its OWN physics (only HitController,
  DynamicsDamage, DynamicsLocker, CrushController, AdjustPress off) -> landing = y stops dropping (or 2 s) -> land sound +
  setAngularVelocity(0, right axis x spin 6) on its RigidBodySet (0.15 s) -> after 0.5 s the pb_acid_v3 wave from the vase,
  onCopy = pour sound at the splash + hidden hit: JOB07 shell 13 (fx 0.01, no flash) cast 'previous' at the splash
  (opts.from pos + yaw), scale 4, speed 0.01, life 0.3, mute; BLAST.brew factor 0.06 / stagger x2 / flinchOnly (our
  damage + stagger + flinch-cap hooks via blasts kind "brew"); poison: DragonCore hits.effect_start(shell HitCtrl,
  {status = StatusConditionEnum.Poison, buildup 34}) for 1 s. Vase removed 2 s after the pour. Sounds: soundlib
  SoundContainer.trigger(id, vec3, owner, 0, 0, nil x4) first, request-info fallback; picks saved (cfg.brewLand/Pour).
- 2.27 (2026-10-23) user (2.26), angry: vase hung in the air; a HUGE magenta dome per splash (faded after a while); no
  sound. Causes: (1) hidden hit = JOB07 shell 13 at scale 4: shape_effects only shrinks its flight effect, not its
  impact / field effects (+ blast tint made them magenta) - my untested assumption. Now: combo_dust kills EVERY effect of
  a brew shell (and of any player-owned shell not from an Eldritch blast) while dbg.brewHitsUntil; scale 1; splash hits
  OFF by default + "test one hidden hit 4 m ahead" button. (2) DynamicsLocker (fields LockObj, CompRB, FallDist) holds
  the body: switching it off kept it held -> now left on + setUnlock() + body nudged down. (3) sound status shows
  "no landing/pour sound picked" or the trigger's answer. VSB's own crash guard showed "integration OFF" (game crashed
  shortly after start last time) - DragonCore's frame loop (hits.late_update = poison) may not run while that is off.
- 2.28/2.29 (2026-10-23) user: "no vase, skip it; make it work with sound and everything" + "clean up the script". User's
  idea: Sorcerer's (High) Salamander = a spell running forward along the ground. Its shells (HumanShellParamData_JobMagic
  .user, insts order / _ShellParamIdHash): 40 Salamander 2274290786, 41 Lv.2 3151664427, 82 Lv.Ex 1566254462 (118-120
  same names, other hashes). CAUSTIC BREW now: castT chant 3 s -> release sound -> hidden High Salamander shell (DragonCore
  spawn, owner +1 m, muted, index found by hash at run time) + acid wave pb_acid_v3 (8 copies from 1 m ahead) + splash
  sound per copy. While dbg.brewHitsUntil (8 s): player-owned non-Eldritch shells = "brew": effects killed (combo_dust,
  "show its fire" to see them), AttackUserData._ElementType 0 during calcDamageValue, BLAST.brew factor 0.06 / stagger x2 /
  flinch cap, burn statuses refused (reqStatusConditionApplyCore hook), poison meter 25/hit -> Poison asked on late update.
  Sounds: player sounds via combo.cue_sound, recorded objects' sounds via their container (positional trigger first).
  CLEANUP 2.29: removed props / model preview / vase drop test / vase physics, acid preview + stain scan + GroundColor
  externs, shell-13 hits, cast tests (Prepare actions, replay test UI). Caustic Brew = one IIFE (src/brew_section.lua) + one
  menu (src/brew_menu.lua). 5577 -> 5060 lines. efx: pak_final now 35 files (+pb_acid_v3, -g1..3/v2/v2n moved to
  efx/removed/acid_tests); efx/x0004-PactbladeFx.pak rebuilt, to install when the game is closed (then delete x0005-x0007).
- CRASH 2026-10-23 00:16 (game session from 23:40, scripts 2.25-2.27): access violation in via.effect.script.EffectManager
  .doUpdate -> CreatedEffectContainer.before -> Dictionary<ProviderData,...>.FindValue. From 23:51:19 on, ~70/s
  "via.Component.get_GameObject InvalidOperationException", surviving every script reset = a game-side zombie: the
  GenerateManager-spawned VASES that the drop test / skill removed with a raw destroy(via.GameObject) - their
  ObjectEffectManager2 kept requesting effects (our effect hooks called get_GameObject on it every frame) and the effect
  manager finally read freed provider data. RULE: never destroy() a GenerateManager-spawned gimmick (go through the game's
  own removal) - moot now, the vase is gone in 2.29. After the crash: x0004 (35 files) installed, x0005-x0007 moved to
  efx/removed.
- 2.30 (2026-10-23) user (2.29): no damage, fire effects + burning sound sometimes, no splash sound. Salamander removed
  completely (its damage-path / effect-kill / burn hooks too). AREA DAMAGE (user's own plan): every 0.5 s for 5 s the
  enemies of app.EnemyManager._EnemyList inside the strip (from 1 m ahead to the wave's front, max 15.3 m; half width
  1.25 m; |dy| < 2.5) get app.HitManager.directDamage(DamageInfo{Damage = 120}, target Hit, player GO, false, player Hit)
  (Skill Maker's call, with nil attacker as fallback) + 35 on their poison meter (100 -> Poison via
  reqStatusConditionApplyCore on the late update). Optional stagger test: DamageType/DamageActType 6 (Hitback_M) +
  IsDirectDamageEnableAllDamageType on the first tick per enemy. No splash sound so far because the saved pick was the
  vase's (gone) and the recording held only chant sounds.
- 2.31 (2026-10-23) user: "can't we just get the sound from the vase?" Any non-player sound pick (the vase's 3240890287
  from 2.25, or an object's id from a recording) is now played by id through the PLAYER's app.WwiseContainerApp with the
  static trigger(app.WwiseContainerApp, UInt32, via.vec3) at the splash. Works only if that sound's bank is loaded.
  Recorded objects' containers are no longer kept or called (could be freed -> crash risk). Menu button: "try the vase's
  sound 3240890287 as the splash". Saved picks keep src/id/label for every source.
- SOUNDS (2026-10-23): user's saved splash pick = the vase's only trigger 3240890287 (picked blind - it never played;
  pottery, not liquid); landing pick was never saved (pre-2.26). The acid effect's owner monster (vfx ch54/001 =
  em ch254001) has a projectile sound set shl_ch254001_fx_containerlistdata = triggers ch254001_fx + ch221000_fx, banks
  Sound/Wwise/ch254001_fx_m.sbnk + ch221000_fx_m.sbnk (media; trigger lists carry ids only, no names). REE.Unpacker
  prints UNPACKING for the _m banks but writes nothing -> new catalog-tool `pakget <game dir> <out> <path>...`
  (REE-Lib CachedMemoryPakReader, all re_*.pak, newest first) got them (969053 / 220150 B). vgmstream r2117 (tools/
  vgmstream) -S 0 -> 17 + 10 wavs in dd2-mods/pactblade/sounds/ for the user to pick the splash.
- 2.32 (2026-10-23) user picked B 02 (wem 182037654) + B 06 (669272264). ch221000_fx_es HIRC (type 2 Sound / 3 Action /
  4 Event / 5 RanSeq / 7 ActorMixer, ids found by reference search): both in RanSeq 921405723 = random of B 02/06/08/10
  -> Action 514555585 -> Event 2302967703 -> trigger 3870869112 (_Limit 2, range 25). Other triggers: 4215563712 (B 01/04),
  2250414418 (B 05/07/09), 1079711464 (event 2836569262, B 03, no trigger list entry seen... listed 4th). Playback: the
  projectile sound set Sound/Resource/EM/ch254001/Containers/shl_ch254001_fx_ContainerListData.user (create_userdata
  soundlib.SoundContainerListData) loaded into the player's app.WwiseContainerApp with loadContainableUserData (once per
  character, at the chant start / test button) -> splash = by-id trigger at every splash, test = cue_sound. Default splash
  pick = that trigger (the saved vase pick is replaced). To hear 02 or 06 alone: the RanSeq's child list would have to be
  cut in an override of ch221000_fx_es.sbnk (changes that monster's own sound too) - after the in-game test.
- 2.33 (2026-10-23) user (2.32): "play the splash here" -> nothing. Sound test with step reports (Caustic Brew menu):
  A = set into my app.WwiseContainerApp (loadContainableUserData) -> after 1 s: trigger count / splash present / bank count /
  set count, then cue_sound, trigger(UInt32), static by-id; B = own anchor + new app.WwiseContainerApp, set added to its
  _UserDataList right after createComponent (before its start; loadContainableUserData if that fails) -> after 1.5 s the
  same report + trigger(id) / by id / request info.
- 2.34 (2026-10-23) 2.33 result: BY_ID nil - the static trigger(app.WwiseContainerApp, UInt32, vec3) is a method of
  app.WwiseDamageController (my type-dump scan ran past the end of the WwiseContainerApp entry; scan per type with the
  type's start/end next time). A: 1191 triggers / 85 banks / 6 sets, splash not in _TriggerInfoList; B: 0 / 0 (own
  container never set up). Container's real calls: WwiseContainerApp.triggerLogLess(UInt32, vec3, GameObject, Boolean)
  -> bool, SoundContainer.trigger(UInt32). Test now also reports AllTriggerInfoListData (per-set trigger lists).
- 2.35 (2026-10-23) 2.34 test (screenshots): loading works - A 85 -> 89 banks, splash in AllTriggerInfoListData (42
  lists); B 2 lists / 4 banks, splash in its lists - but trigger(id) / triggerLogLess(id, pos, go, false) (returned nil)
  are silent: they only search _TriggerInfoList. Now find_info() also searches AllTriggerInfoListData and the splash is
  played like cue_sound: createRequestInfo(info, go, go, ...) + trigger(RequestInfo) through the player's container.
  User: a short splash is heard ONCE when the acid starts (source unknown: the acid efx has no sound attribute in its dump).
- 2.36 (2026-10-23) user: test A works (splash via request from the loaded set's info through my container); test B works
  too, just silent the first time (set still loading). SPLASH AT EACH SPLASH: at the chant start the set goes into my
  container (once per character) + 8 fresh invisible sound objects of ours (make_anchor + app.WwiseContainerApp, set
  added to _UserDataList + loadContainableUserData; old ones destroyed first - never reused across casts / scene changes);
  each splash moves the next object to its spot and plays the splash there (find_info + createRequestInfo + trigger);
  fallback = my container. Sound tests removed; menu: "play the splash 3 m ahead (the first press loads the sounds)".
- 2.37 (2026-10-23) user: enemies get poisoned (confirmed); splash sound good (2.36). Poison build-up 35 -> 50 per 0.5 s tick (poisoned after 2 ticks = 1 s instead of 3 = 1.5 s); the meter's steps: 34-49 = 3 ticks, 50+ = 2.
- 2.38 (2026-10-23) user: hits every 0.3 s with 35 poison instead (poisoned after 3 hits = 0.9 s). Damage per hit 120 -> 72 so the damage per second stays 240 (my choice, said so). Tick interval = sk.tickSecs, slider in the menu.
- 2.39 (2026-10-23) POISON DAMAGE x2 for Caustic Brew's poison only (user chose option 2 of: global
  CharacterCommonDamageParameter.PoisonParam Small/Large/PlayerOrPawn factors vs our own). Game poison tick =
  app.StatusConditionActionSlipDamage.setDirectDamage(Single, Boolean, StatusConditionInfo) (ActionParam =
  StatusConditionActionParamSlipDamage: DamageRate, IntervalFrame, _ElementType ...). Hook: if the action's OwnerCharacter
  was poisoned by us (sk.ourPoison[address], set when we ask Poison, kept 120 s) and _ElementType == 0 -> damage arg x
  sk.poisonMul (float_to_ptr). Menu slider + "poison ticks made stronger" count. User: test dummies never get poisoned
  (normal enemies do) - dummies are probably status-immune.
- 2.39 SAVED as versions/Pactblade-2.39-SAVE-CausticBrew-working.lua (user: good for now, more testing later). Open: Caustic Brew stamina cost, acid colours (parked), 02/06-only splash (needs an edited ch221000_fx_es bank), release sound, stagger test, poisonable dummies; then Misty Dive.
- 2.40 (2026-10-23) user: the Mage chant circle (ch03 cs 0/304) lay on the ground between the feet (a Mage has it upright in front - on the staff). Now cs 0/304 + the release flash cs 0/3 are requested with an anchor of ours as parent (castT.front: 0.7 m ahead, 1.3 m up, tilted 90 deg about its sideways axis, follows the player while chanting, destroyed 2 s after the cast); sliders for distance / height / tilt in the Caustic Brew menu.
- CRASH 2026-10-23 01:24 (36 s after loading 2.40): EffectManager.doUpdate -> CreatedEffectContainer.before. Cause: 2.40
  requested the chant circle through the PLAYER's ObjectEffectManager2 with our anchor as parent and destroyed the anchor
  2 s after the cast -> the container's parent dangled (same family as the vase crash). The parent didn't even move it.
  RULE: never destroy a GameObject that a game effect container (requestEffect) uses as parent.
- 2.41: the circle (cs 0/304) + release flash (cs 0/3) requested on the player as before; castT.move_front reads the
  container's files (getAllPlayers -> get_ResourcePath), killAll's the game's copy, and plays the same files on our OWN
  EffectPlayers on our anchor in front of the chest (acid-style, safe to destroy); at the end Finish action + anchor
  destroyed 2 s later.
- 2.42 (2026-10-23) user (2.41): circle still at the feet, sliders do nothing (= the move never happened). Now all 5 chant effects (ns 0/40, cs 0/104, cs 0/304, ns 0/41, cs 0/3) go through castT.move_front (file read with get_Resource():get_ResourcePath() / get_ResourcePath()), menu line 'chant effects: ...' shows players / files / moved. Anchor from the Head joint (user: at the head, 0.5 m forward), height offset 0, tilt 90. Sheathe cancel: requestActionCore of the player during the chant with Sheath/Holster/Unequip/Stow/PutAway/Unwield/WeaponOff in the name -> castT.cancel (no release, effects finished, stop sound, FSM resumed) + the request asked again; names seen during the chant listed in the menu.
- 2.43 (2026-10-23) user (2.42 screenshot): 'an effect could not be moved (1 effect player(s), 1 file(s))' = file known, our copy failed -> the error is now shown ('move failed: ...'). Sheathe: during the chant the game sends no action request (seen: Job04_Dodge, NormalLocomotion) -> app.CharacterInput.Flag 'Sheathe' read directly (a:button_pressed) in the chant update -> castT.cancel. The request hook / seen list removed.
- 2.44 (2026-10-23) user (2.43 screenshot): 'move failed: Pactblade.lua:4494 attempt to index a nil value' = createComponent(EffectPlayer) nil: ONE EffectPlayer per GameObject - the 2nd moved effect failed and the game's copies stayed at the feet. Now each moved effect gets its own child object (set_Parent to the anchor, local 0); dropped / destroyed children first.
- 2.45 (2026-10-23) user (2.44): circle almost in the right spot but showing fire + lightning + ice + dark orbs = the Mage effect files hold every element's version, the game's player picks one via its look. Our copies now take the game player's EmitMaskBit, MaskName, GroupEnabled, GroupNames, GroupParameters, ExternParameters (castT.copy_look; shown as 'copied: ...' in the menu).
- 2.46 (2026-10-23) user: the element look is right now (2.45 copy_look works). User's top-down drawing: circle more to the right (sword side) and forward -> castT.frontSide 0.4 m right (right = (fz, 0, -fx) of the flat forward), frontDist 0.5 -> 0.65 m; slider 'to the right (minus = left)'.
- 2.47 (2026-10-23) user: circle looks good at 'to the right' -0.47 with 2.46's formula -> my right was the left: character's right = (-fz, 0, fx) of the flat forward (DD2 / RE: X right of +Z forward is NEGATIVE here). Default frontSide 0.47 with the corrected sign, frontDist 0.65, height 0, tilt 90 = the user's spot.
- 2.48 (2026-10-23) user: Eldritch Slash's wave vanishes at the wanted range but flies on invisibly and appears again only to hit (range = shell flight x8 via DefaultRangeDist, the look has a fixed duration). Now when our copy -1/10/1 (following the shell) is over - via.effect.PlayerState Running 2 -> ForceStop 3 / Finish 4 / Finished 5 (enum low 32 bits; Idle 0 Start 1 Restart 6), or no emitters for 3 frames - the shell it follows gets app.Shell.set_RequestKill(true) (only if it has ShellAdditionalJob07SubNormalAttackShell and Owner = player). Note 'the wave's look ended'.
- 2.49 (2026-10-23) user (2.48): still invisible hits; trace has no 'look ended' (our copy never reported finished/empty). Now also a distance limit cfg.slashHitRange (default 30 m, saved, slider 'wave ends after (m)'): set_RequestKill once the shell is that far from where our copy first saw it; per-frame record (time, distance, state, emitters) -> data/Pactblade_slash_wave.json to find the real fade point.
- 2.50 (2026-10-23) 2.49 record: our wave copy Running (2, 46 emitters) -> IDLE (0) at 1.60 s / 28.5 m = the visible fade (2.48 watched only 3/4/5). User: at the 30 m cut the wave 'reappeared' = the shell's end effect -1/10/6 (our copy) where it was ended. Now Running -> Idle also ends the shell, limit default 28 m, and effects requested by a shell we ended are dropped for 0.5 s (dbg.slashKilled[shell GO] checked first in combo_dust -> kill).
- 2.51 (2026-10-23) user: Eldritch Slash range fix good (2.50). Wave record removed. Saved as versions/Pactblade-2.51-SAVE-slash-range-fixed.lua.
- 2.52 (2026-10-23) ELDRITCH SMITE (user's design): Job05_ShortRangeHeavyAttack 0-66.6 -> Job05_ArcOfObliterationEnd from 60, FullBodyLayer speed 1.5 only from 270 (user: only 270-347), at 347 NormalLocomotion (WaitToFall in the air). Slot = Burst Strike (user's equipped); guessed id Job01_RushAttack; cfg.smiteSkill (saved) + menu 'bind to the next skill I press' (next processCustomSkill id -> enum name). Guards: processCustomSkill skip; requestActionCore of the bound name skipped unless the combo runs / our own request. Combo-style stage runner (start check 0.4 s, motion change wait, set_Frame to from). No stamina cost / effects yet.
- 2.53 (2026-10-23) user: Burst Strike = Job01_BlinkStrike (bound with the button; now the default). Part 2 from 50, 1.5x from 150 to 347. Smoother join: the start frame is reached with FullBodyLayer changeMotion(bank, motion, from, sm.blend 12 frames, 1, 1) on the same motion instead of set_Frame (set_Frame only if that call fails); blend slider.
- 2.54 (2026-10-23) Eldritch Smite visuals (user): part 2 start -> dbg.nox_boost(true): blade Enchant_Color1/2 x NOX.boostGlow 2.5, a SECOND Frost Boon shimmer (element 25) on the sword (more mist), every shimmer player's own object scaled x NOX.boostScale 1.6 (never the sword object), shimmer colour x1.5 (capped 1); off at the smite's end (extra shimmer finishAll, scale back). First player melee hit during part 2 (calcDamageValue pre, attacker GO = player) -> on the next late update our Eldritch Bolt explosion copy -1/8/43 (purple) at the victim +1 m, scale x2.5 (combo to switch to -1/8/40). Sliders in the Eldritch Smite menu. Sounds: later (user).
- CRASH 2026-10-23 12:27:50 while switching vocation / weapons as Warfarer: RIP in unknown memory (no stack), no Pactblade
  action logged for 2 min before (trace: smites 'interrupted by StartRunningOutOfStamina / PenaltyOnRunningOutOfStamina'
  - the Job05 heavy attacks drain stamina). Suspect: 2.54's every-frame LocalScale on the shimmer effect players' objects
  (destroyed on a weapon swap). 2.55: those objects are touched only while boosted and once to restore; finishAll only on
  containers not yet finished. Explosion x2.5 -> x1.5 (user: 60 %).
- 2.56 (2026-10-23) user: no mist changes (only those) -> second shimmer, shimmer resizing and the x1.5 shimmer colour removed (also the crash suspect); the blade glow boost (Enchant_Color x NOX.boostGlow 2.5 during part 2) and the hit explosion (x1.5) stay.
- 2.57 (2026-10-23) user: sliders for the Nox look again -> 'Nox look settings' under the Nox checkbox: blade glow R/G/B/brightness (Enchant_Color1/2, x the smite boost) + mist R/G/B/brightness (shimmer tint, capped at 1 per channel), saved (cfg.noxBlade*/noxMist*), defaults = the old fixed values (91/26/142 x1, 126/0/54 x1.3), reset button.
- 2.58 (2026-10-23) user: in part 2 the blade lights the area until it hits the ground. sm.light: our anchor + via.render.PointLight (no shadow) at the held sword, colour = Nox blade colour normalised, 1500 lm / 5 m, on from part 2's start to frame sm.lightUntil (default 120, guess; menu shows the part-2 frame of the first hit), off at the end; kept (never destroyed) until script reset.
- SOUNDS (user, 2026-10-23): user's own eblast.mp3 (5:03, 48 kHz stereo) in dd2-mods/pactblade; cut on request: sounds/custom/eblast_07-09s.wav (2.0 s) + eblast_23-26s.wav (3.0 s), 16-bit PCM 48 kHz stereo (ffmpeg from LosslessCut). For: custom-sound bank later (template = small monster bank, PCM sources, new ids).
- 2.59 (2026-10-23) user: settings done (Nox saved: blade 255/26/135 x8, mist 180/0/54 x4); Caustic Brew fine, circle 60 %
  -> castT.frontScale 0.6 (anchor LocalScale, the copies are its children); Eldritch Slash good. RECORDING (Mystic
  Spearhand charging Forbeding Bolt): ch07 ns 13/25/0 at 0.34 s (arm = our arm effect's source), ch00 0/160/0 (cloud),
  13/25/50 at 2.34 s (charge complete) + sound 3584713415, release Job07_MagicBindComplete 170/700-702 + 13/20/55, sounds
  2217285698 / 3366100101 / 2124478878 / 673994548 / 1251200690. dbg.charge_fx: ch07 ns 25/50 requested on the player
  (attaches itself), its players' extern colour "Charge" set every late update (picker hue, default 285) for its life
  (max 4 s) - at smite part 2 and at Eldritch Bolt ready (holding -> charging). Smite sliders now saved (cfg.smite, auto
  1.5 s after a change + a button). Audio (user): charge = sounds/custom/eblast_charge_05-09s.wav (4.0 s), hit =
  eblast_hit_24.4-26s.wav (1.6 s; the explosion is ~1.5 s into the 23-26 cut).
- 2.60 (2026-10-23) user's smite values (screenshot) = defaults + a one-time override of the saved ones (cfg.smite.userSet): speed 1.5, blend 12, blade glow x2.5, explosion 43 x1.5, light on until frame 132 (first hit was at 83), 562 lm, 3 m. User: the audio cuts are good.
- 2.61 (2026-10-23) OWN SOUNDS. sounds/build_bank.py: template ch221000_fx_es/_m (Wwise bank v140, ids = FNV-1 of the
  lowercase name: ch221000_fx_es = 0x2a28a7cf checked) -> pactblade_fx_es (bank 1670542689) / pactblade_fx_m: every HIRC
  object id remapped (fnv1('pactblade_obj_<old>')), references by 4-byte search; Sound objects (data: u32 plugin, u8 stream
  type, u32 source id, u32 media size, ...) -> plugin 0x00010001 PCM, stream 0, our media; RanSeq 921405723's 4 sounds = charge
  (sounds/bank_src/charge_mono.wav = eblast 5-9 s, mono 48 kHz), the other 6 = hit (24.4-26 s). Media .wem = RIFF/WAVE fmt
  0xFFFE (24 B, Wwise channel config 0x4101 mono) + data, 16-aligned in DATA, DIDX rebuilt. vgmstream reads it: 2 PCM
  streams 4.000 / 1.600 s. Trigger list / bank list = the monster's copied with catalog-tool `userrep` (now also lists):
  triggers 3870869112 -> 199459528 (charge), 2250414418 -> 3434957627 (hit), 4215563712 -> 1047135920, 1079711464 ->
  1047135923, events remapped, _Bank / _BankList -> @Sound/Wwise/pactblade_fx_es/_m.sbnk. pak_mods/x0005-PactbladeSounds.pak
  (src sounds/pak_sounds, sounds.list). Lua: sm.load_sounds = create_userdata(SoundBankListData / SoundTriggerInfoListData,
  Sound/Resource/pactblade/pactblade_fx_*.user) + loadContainableUserData into the player's WwiseContainerApp (at the
  smite press); sm.sound = find_info + request_play (exposed from the brew section). Charge at part 2, hit with the
  explosion; menu test buttons + 'sounds:' line.
- 2.62 (2026-10-23) user (2.61): (1) the teal at the hands = ch07 25/50, NOT the wanted look: Mystic Spearhand's charge
  tints the WHOLE body (screenshot: everything teal) = a body material mode -> 25/50 calls removed; Recorder now also logs
  app.MaterialInterpolationRequestManager.requestMaterialMode / requestMaterialModeSub / requestMIMode of the player
  (mode u32, category = RequestListCategory low 32 bits: PtEnchant 0, Status 2, Poison 3, Bruise 4, Decompose 5, Decay 6,
  Basic 7, RimLight 8, BaseColor 9, Deform 10, DustCover 11, Dragon 12, Brainwash 13, Npc 15, Gimmick 16, Monster 17) ->
  needs a new recording. (2) user: "by default the sword looks like it should only during the skill" -> cfg.noxSmite = the
  user's slider values (moved once), everyday look back to 91/26/142 x1 + mist 126/0/54 x1.3; dbg.nox_look() picks by
  NOX.boosted; menu: everyday + 'during Eldritch Smite' blocks. (3) our sounds 'not loaded yet' (pak WAS injected at boot -
  IntegrityCheckBypass 'injected 4 custom pak(s)'): loose trigger/bank lists apparently not taken -> our own container list
  pactblade_fx_ContainerListData.user (shl_ch254001_fx's, its 4 user-file refs -> our 2 lists; userrep now rewrites
  RSZUserDataInfo paths) loaded instead; failure line shows the load state + trigger list count. x0005 repacked (5 files).
- User: the 2 sounds go ON TOP of everything (nothing replaced) - so built: new ids, the template bank untouched.
- 2.63 (2026-10-23) RECORDING 2 (body material): Mystic Spearhand charge = RimLight (cat 8) requestMaterialMode 1545610377
  at the charge start (0.18 s, with 13/25/0), 1704633256 at full charge (2.20 s, with 13/25/50) and again at the release.
  dbg.rim_glow(a, on): player's app.MaterialInterpolationRequestManager requestMaterialMode(1704633256, 8, -1, -1) /
  finishMaterialMode; RimLight_Emissive_Color_A/B slots of the player's meshes (dbg.ai.meshes) re-hued to the picker hue
  every BeginRendering (keeps the game's S / V). On at smite part 2 and at Eldritch Bolt ready; off at the smite's end /
  0.6 s after the charged bolt fires. Smite look (Nox boost) from 0.3 s into part 1 (sm.lookAfter); blade light = while
  boosted (frame slider gone). Sounds: 2.62 result 'set loaded, 40 trigger lists' (no new lists); header user-file CRCs
  are 0 in the game's file too (not the cause). Now our trigger list + bank list are created by name first, then the
  container list loaded; 'check our sound files' shows found / trigger count + first id + event bank, bank count + path,
  sets in the container (+ empty ones).
- 2.64 (2026-10-23) user: body glow only a ~1 s pulse at smite part 2 and Eldritch Bolt ready (sm.RIM.secs 1.0, rimOffAt set at every rim_on). Sounds: 2.63 check = our 3 files found and read right (4 triggers first 1047135920, banks Sound/Wwise/pactblade_fx_es/_m.sbnk, container 4 sets, 0 empty) but still 40 trigger lists. 'sound diagnosis': BankResourceExtension.getBankId of our holders (0 = not loaded), our banks in the container's BankResourceList, our trigger list loaded directly (list count before/after), control: the monster's container list (count before/after).
- 2.65 (2026-10-23) user: Eldritch Bolt body pulse 0.3 s (rim_glow secs arg); smite look + blade light end at part-2 frame 86 (sm.lookUntil; on since 0.3 s into part 1); diagnosis steps separated (2.64 printed nothing: the first find_type_definition error ended the whole pcall).
- 2.66 (2026-10-23) diagnosis said 'global my_container is not callable' (a local of the smite function, the menu is outside) -> sm.my_container; the result also goes to data/Pactblade_sound_diag.json. Smite look + light last 0.2 s past frame 86 (sm.lookExtra).
- 2.67 (2026-10-23) OWN SOUNDS WORK (user: "sounds play now"). 2.66 diagnosis: getBankId event 1670542689 / media
  1102948846 (both our banks loaded fine - PCM accepted), container list route added nothing ("77 banks, 0 of ours"),
  OUR TRIGGER LIST LOADED DIRECTLY: AllTriggerInfoListData 40 -> 41 -> plays. Now bank list + trigger list loaded
  directly (container list unused, still in the pak), and early: once Pactblade is on (retried every 5 s until done).
  Diagnosis / check buttons removed; play-test buttons kept. User: sword look + light end good (frame 86 + 0.2 s).
- (2026-10-23) user: the charge sound is at 2.0-3.5 s of eblast.mp3 -> sounds/custom/eblast_charge_02-03.5s.wav, bank rebuilt (charge 1.50 s, hit 1.60 s, same ids), efx/sounds x0005 repacked; to install when the game is closed.
- 2.68 (2026-10-23) new charge sound (2.0-3.5 s) pak installed. User: Eldritch Smite knocks ANY enemy down, guaranteed: DamageTypeEnum list (Wind 0-2, Quake_S 3, Quake_L 4, Hitback_S 5 .. Hitback_LLL 9, Hitdown_S 10, HitdownQuick_S 11, Hitdown_L 12, HitdownQuick_L 13, Slam_S 14, Slam_L 15, Upper_S 16, Upper_L 17, Blown_S 18, Blown_L 19, Dialog_Blown 20/21, FlashFlood 22). During the smite every player melee hit: getReactionDamageType -> sm.downType (Slam_L 15 default, Hitdown_L 12 option) + DamageType/DamageActType/OverwriteBlownType; calcDamageReaction -> DamageReaction x sm.downPower (100). Menu: choice + power slider + count.
- 2.69 (2026-10-23) user: charge sound in sync with the sword look + light (sm.chargeAt = look start + sm.chargeDelay, slider 0-1.5 s, saved) instead of at part 2; hit explosion + hit sound only when the damaged object is in app.EnemyManager._EnemyList (is_enemy).
- 2.70 (2026-10-23) user: crates / barrels may trigger the hit explosion; only a slam into bare ground (no hit) must not - which is how the damage-hook trigger already worked -> the enemy-only check removed again.
- 2.71 (2026-10-23) user (2.70, after a restart): sounds silent again, 40 trigger lists - loaded once at the start, then (likely) the game rebuilt the player's container and sm.soundsFor kept us from reloading. Now 'loaded' = our charge trigger found in the container (checked every 5 s and before each play); before a reload our sets are removed from the container's _UserDataList (else the load may be skipped); status line says whether our sounds are in.
- 2.72 (2026-10-23) user: sounds play (2.71 fix works); the charge sound sooner + louder. Delay now relative to the look's start, -0.3 .. 1.5 s (minus = sooner, down to part 1's start), default -0.2 (once over the saved 0). Charge audio +6 dB with alimiter 0.97 (bank_src/charge_mono.wav), bank rebuilt, x0005 repacked - install when the game is closed.
- (2026-10-23) user: -0.2 s charge timing good. Hit sound 1.5x (volume=1.5 + alimiter 0.97, bank_src/hit_mono.wav), charge +6 dB (from before); bank rebuilt, x0005 installed (game closed).
- 2.73 (2026-10-23) user: Slam_L threw a bandit metres away. Default Hitdown_L (12, knocked down on the spot) + no push-back: HitBackZ/HitBackY/HitBackAddZ 0 and HitBackVec 0 after getReactionDamageType and calcDamageReaction (sm.noPush, checkbox); Slam_L still selectable. User asks if the fly-away is the game's own physics - partly: the reaction type picks the animation/ragdoll, the push numbers and our x100 stagger drive the distance.
- 2.73 REVERTED (user: the bandit just disappeared somewhere after the hit) -> back to 2.72 (Slam_L forced, stagger x100, no push changes). Likely cause: HitBackVec = (0,0,0) (a direction) / zero push values broke the reaction's direction maths. 2.73 kept as versions/Pactblade-2.73-test-REVERTED-bandit-vanished.lua. Don't zero HitBackVec.
- 2.74 (2026-10-23, built on 2.72) MENU CLEANUP (user): new "Skill settings" section (Eldritch Smite: slot + bind, speed,
  blend, blade glow, explosion size, knockdown type + power, blade light on / strength / reach, charge sound timing - auto
  saved; Tasha's Caustic Brew: hits every / damage / poison build-up / poison x / acid lasts / strip width; Misty Dive).
  Removed: sound test buttons, save button, explosion-effect choice, Caustic Brew splash pickers / sound tests / stagger
  test / chant-circle sliders + status. Debug keeps status, dummies, daytime, Recorder, last hits + log.
  MISTY DIVE (user's skill): air Empale = Job01_HeavyAttackAir (+ its landing). Press -> combo.pick_target (15 m, 70 deg) ->
  combo.dive_spot (head joint + md.above 2.0 m, md.back 1.0 m toward the player, facing the enemy; none: 3 m ahead, +3.5 m)
  -> combo.warp_to (the combo's warp look: wisps / Quik Fot cues, afterimage, sounds; CharaController warp; face) ->
  Job01_HeavyAttackAir requested (re-asked for 0.5 s), position held 3 frames. Slot cfg.mistySkill (default
  Job01_ShieldSummons, saved; 'put it in the next skill I press'). No stamina cost yet.
- 2.75 (2026-10-23) user: Misty Dive's slot is a shield skill (Shield Summons / user's Shield Drum) and there is no shield -> app.HumanSkillAvailability.isCustomSkillAvailable / ...WithoutItemCondition(id) answer true for the player's own (field Chara = player) when id = cfg.mistySkill, Pactblade on (count in the menu). Shield skills = isLeftWeaponSkill.
- 2.76 (2026-10-23) user has Shield Drum (not Shield Summons) -> default mistySkill Job01_CymbalAttack (guess: Shield Drum); while binding, the availability check says yes for any of the player's skills (else a shield skill press never reaches the bind).
- 2.77 (2026-10-23) user: Misty Dive worked after binding (Shield Drum); wants a start delay + sound, the same preparing
  jump as Mystic Spearhand's teleport-dive. RECORDING (MSP's skill): Job07_SkyDive - 0.61 s motion 170/1100 (prepare) +
  ch00 0/15/0, sound 3610636506, RimLight 2545042611, cs 14/7/20, ch00 0/30/1010, Basic 2830666171; 0.76 sound 1717783091;
  0.93 motion 170/1101 (teleport) + sound 2823464530, ns 13/0/10, cs 14/7/21, RimLight 3087473640; 1.24 sound 2909910614;
  1.63 motion 170/1102 Job07_SkyDiveLanding + sounds 2333241765 / 1148675647, effects 0/10/2, 14/7/22, 14/7/23, RimLight
  1545610377. Misty Dive now: request Job07_SkyDive (its prepare jump + its own start fx / sound), when FullBodyLayer is
  on 170/1101 (or 0.6 s after it started / 0.4 s if it never starts) -> our dive: target spot, combo.warp_to, cue sound
  2823464530, Job01_HeavyAttackAir.
- 2.78 (2026-10-23) user: use the WHOLE SkyDive (its own targeting + teleport) and only swap the strike after the teleport. md.mode 'msp' (default): Job07_SkyDive runs; md.afterTeleport (0.05 s) after FullBodyLayer reaches 170/1101 the air Empale Job01_HeavyAttackAir is requested (no warp of ours); 'ours' = 2.77 (our spot + warp). Recolour of SkyDive's teal (effects + RimLight modes 2545042611 / 3087473640 / 1545610377) = next step.
- 2.79 (2026-10-23) user (2.78, no target): sometimes falls 'kinda backwards' after the teleport. At the swap: CharaController warp() (no leftover speed), rotation back to the facing at the press (md.face), held 4 frames (rotation only, position left to the game).
- 2.80 (2026-10-23) user (on 2.78): after the teleport kept flying upwards for a while - SkyDive's launch speed kept when its strike is replaced; 2.79's CharaController warp() at the swap clears it. Extra: if the air Empale does not start within 0.5 s -> speed cleared + WaitToFall.
- 2.81 (2026-10-23) user (2.80): still falls down + in the opposite direction of the stick, not straight down. Now the X/Z position at the swap is locked every UpdateBehavior until the air Empale (incl. its landing) is over - only the height changes.
- 2.82 (2026-10-23) user (2.81): good without a target; with one SkyDive teleports above MYSELF (its targeting has nothing to use on a Fighter). Now the target is picked at the press (combo.pick_target 15 m / 70 deg); at SkyDive's teleport (170/1101 + afterTeleport) we move to combo.dive_spot above it (2.0 m over the head, 1.0 m toward us), facing it, held 3 frames, then the X/Z lock there; no target = as 2.81.
- CRASH 2026-10-23 22:51 (switching Mystic Spearhand -> Fighter as Warfarer): effect culling in a parallel job
  (Parallel.ForEach ... EffectDistanceCullingSettings.getAlpha). 2nd crash on a weapon switch (12:27 was the 1st).
- 2.83: Nox: on a sword change the old sword is FORGOTTEN (no finishAll / no blade material restore on a possibly deleted
  object), a new sword gets the Nox look only after 1.5 s in hand. combo.dive_spot head = highest joint with 'head' in its
  name, else CharaController height, else +1.7 (user: on the Cyclops it put me at its chest). Misty Dive default mode
  'ours' (user: from scratch): SkyDive's prepare jump, at its teleport our target + combo.warp_to (warp clears the jump
  speed) + teleport sound + air Empale, position held 3 frames + X/Z lock; notes in the trace.
- 2.84 (2026-10-23) user (2.83 'ours'): teleported ~200 m up (trace: 'no enemy in front: dove ahead' = only +3.5 m from us) -> SkyDive's upward push lands in its teleport's first frame AFTER a warp made in that frame (msp mode waited 0.05 s, so it was fine). Our dive now waits md.afterTeleport after 170/1101 too, and every hold frame (3) sets the spot + CharaController warp (speed cleared). Head joints only count within 6 m sideways and 0-15 m above the creature.

### 2.85-test (2026-10-23) - Misty Dive height + target
- User: worked on Cyclops / Chimera, dummies sometimes not targeted; teleport too high above the enemy.
- md.above 2.0 -> 1.0 m above the head joint (slider "height above the enemy's head").
- The enemy picked at the press (on the ground) is used at the dive while alive; re-pick only without one. Pick
  loosened for Misty Dive: 20 m, 90 deg, height gap 6 m (slash_pick_target got an optional gap arg, default 4).
- No target -> the trace says why for the nearest enemy (distance, angle, height gap, alive) via md.why.

### 2.86-test (2026-10-23) - Misty Dive targeting by the camera
- User: targeting doesn't work for the dummy or the Cyclops; hits only when standing right next to them.
- Trace (2.85): the pick at the press found nobody; one dive re-picked in the air 0.8 m from the enemy, the other was
  11.8 m above an enemy 0.3 m away (SkyDive's lift) -> nobody. The press pick used the CHARACTER's facing; the user aims
  with the CAMERA.
- md.pick: enemies within md.range (20 m) and 8 m height gap, within md.cone (90 deg) of the camera look (camera -> me,
  flat) or my facing; best = distance x (1 + angle/90). The press result is noted ("Misty Dive press: ...").

### 2.87-test (2026-10-23) - Misty Dive: enemies counted as dead
- User: on top of the Cyclops it warped off forward into the empty air.
- Trace 2.86: every press "N enemies listed, 0 alive" although their HP read > 0 -> is_alive() (get_Valid step) turns
  enemies down here. md.alive reads the HP itself. Height gap up to 15 m; within 3 m any direction counts (on top of it).
- To check: is_alive() is also used by Eldritch Slash's turn and the Archfey Combo turn - they may never have turned.

### 2.88-test (2026-10-23) - Misty Dive: right above, no air slide
- User: lands close to the enemy but not above, then slides forward in the air onto it.
- Trace 2.87: targets picked every time (0.8 - 4 m) -> targeting OK now.
- md.back 1.0 -> 0 (right above the centre); dive_spot faces me -> enemy (works with back 0).
- The XZ lock only moved the transform; the CharaController kept the air Empale's forward push. Lock now also warps the
  controller (Update + LateUpdate, toggle md.lockWarp); if no height is lost in 0.3 s the warp is dropped for that dive.
  Each dive notes the largest sideways push per frame. Lock released after 3 s at most.

### 2.89-test (2026-10-23) - Misty Dive: execution only on a staggered, standing enemy
- User: the air Empale's execution (Job01_AirFinishingMoveFront/Back, paired animation) only when the enemy is
  staggered and standing (trace 2.87 showed both after Misty Dive hits).
- Game check: app.HumanCatchProcessor.processFinishingMove(HitController.DamageInfo, Character) -> Nullable<bool>
  (also isEnableFinishingMove / isEnableFinishingMoveWithoutSpecialMotion there; HumanActionSelector.isEnableFinishingMove).
- During the dive, my hit on an enemy whose current action has no stagger word (damage/stagger/flinch/...) or has a
  down word (down/blown/lie/slam/fall/...) -> original skipped, returns null. Every check noted with the enemy's action
  name. Menu: execution animation = staggered only / always / never. UNTESTED: whether null = "no finishing move".

### 2.90-test (2026-10-23)
- User: the finisher still plays with the 2.89 block -> leave it to the game (md.finish default "always"; the hook
  stays but does nothing unless picked in the menu). Dive height 1.0 -> 1.8 m above the head.

### 2.91-test (2026-10-23) - Misty Dive in our colour
- User: Misty Dive good enough; recolour all its teal.
- From the 2.77 recording: SkyDive plays on me cs 14/7/20 (prepare, ch07/cs007/13_ch07_cs_007_20), cs 14/7/21 (teleport,
  _007_21), ns 13/0/10 (teleport, ch07/ns/13_ch07_ns_000_10) + rim-light modes 2545042611 / 3087473640 (category 8).
- Baked: efxtint hue 285/300/315 -> pb_sd20 (8 colours), pb_sd21 (9 incl. T_m material colour), pb_sdns10 (12) _h<hue>
  in efx/pak_final (44 files) -> pak_mods/x0004-PactbladeFx.pak rebuilt (old one in efx/removed). Sources efx/skydive.
- Runtime: ObjectEffectManager2 request hook asks dbg.md_fx (Misty Dive busy + 1.5 s, my GO, one of the 3 ids, Look
  colour not 'game's') -> post: our copy on an anchor following me (copy_look from the game's player 0), the game's
  container killAll; anchors destroyed after 4 s. Rim light: dbg.rim_entries / dbg.rim_paint (from the Smite), painted
  in BeginRendering while busy (skips dark/white/already-purple). Menu checkbox 'our colour on its effects + body glow'.

### 2.92-test (2026-10-23)
- User screenshot: teal burst at Misty Dive's start = 0/15/0 = ch00 container 15_EXSkill_DLC element 0 =
  VFX/Effects/Character/ch00/atk/13_ch00_EX_000_00.efx (found with pfbflat on 13_ch00_ref.pfb.18: container id = the
  child GameObject's number prefix, element ID follows its Resources line). Its layers ig / g_inv are INVERTED (orange
  FFB31A in the file shows teal) -> baked with the opposite hue (285 -> file hue 105, 300 -> 120, 315 -> 135):
  pb_sdex_h<hue> in efx/pak_skydive -> pak_mods/x0006-PactbladeFx-skydive.pak (x0004 locked, game running) + copies in
  efx/pak_final for the next merge. 0/30/1010 = Common/Wind/13_Wind_000_00 (left alone).
- User: re-picking Pactblade in VSB after every script reset. VSB's boot guard (data/VSB/state/boot_guard.json
  starting=true since 2026-10-20) keeps its game integration OFF -> its script-reset hand-over never runs, picks only in
  memory. Pactblade writes data/Pactblade_vsb_pick.json on reset and re-picks within 60 s via VSB_API.app:set_vocation_pick.
- 2.92 (sounds, user): Eldritch Smite charge + hit 2x louder: bank_src/*_mono.wav (peaks -0.2 dB already) -> volume 3.0 +
  alimiter 0.95 -> *_mono_x2.wav (mean -13.5/-13.8 -> -8.2/-8.5 dB, peak -0.4); build_bank.py rebuilt (ids unchanged),
  pak_sounds updated; game running (x0005 locked) -> sbnk pair also in pak_mods/x0007-PactbladeSounds-loud.pak (same
  paths, higher number). Merge into x0005 when the game is closed. Old banks in sounds/removed/before_x2.

### 2.93-test (2026-10-23)
- User (2.92): no green / orange, but the afterimage clone teal again and the launch effect teal. BUG from 2.91: the
  ObjectEffectManager2 post hook returned for a Misty Dive copy BEFORE popping the tint / parts stacks -> every later
  effect got another one's kill / colour (afterimage aura not killed, blast launch copy not played). All three stacks
  popped first now. Each Misty Dive copy noted ("Misty Dive: our copy plays (...)").
- Game closed: x0004-PactbladeFx.pak rebuilt from efx/pak_final (47 files incl. pb_sdex_h*), x0005-PactbladeSounds.pak
  from sounds/pak_sounds (louder smite banks); x0006 / x0007 moved to efx/removed / sounds/removed.

### 2.94-test (2026-10-23) - diagnosis: which teal is left
- User (2.93): clone + launch still teal. Trace: only 13/0/10 swapped; 14/7/20, 14/7/21, 0/15/0 never reached dbg.md_fx.
- Notes every effect on me during Misty Dive once per dive ("Misty Dive fx: id via how"), from requestEffect + the
  ObjectEffectManager2 hooks; 0.15 s after the dive warp the teal material colours on me and the clone ("Misty Dive teal
  on me / clone: var xN") + data/Pactblade_misty_teal.json. Next: per-layer hide copies (efxhide) of the teal file.

### 2.95-test (2026-10-23)
- Trace 2.94: as a FIGHTER SkyDive plays 14/7/10 (prepare) + 14/7/11 (teleport) + 13/0/10, plus generic 0/30/1010,
  1/0/0, 0/10/x, 0/160/0; no 0/15/0 (MSP's 2.77 recording had 14/7/20 / 21). Baked pb_sd10 / pb_sd11 _h285/300/315
  (cs_007_10: 8 colours incl. Light @68 + JS material; cs_007_11: 9 incl. T_m; no inverted layers) -> efx/pak_final
  (53) + pak_mods/x0006-PactbladeFx-skydive2.pak (game running). md.FX gets 14/7/10 + 14/7/11.
- Material teal dump = noise (scalar variables read as float4) -> off. Teal on the clone not in RimLight A/B (painted).
- User: a dummy spawn put them under the ground; a Misty Dive there threw them ~2 km up (trace: afterimage 32 m away in
  0.35 s, controller lock dropped). Lock caps the height at dive spot + 2 m (Update + LateUpdate, controller warp).

### 2.96-test (2026-10-23) - no ending up under the ground
- User: the 2 km launch came from being under the ground, but getting there is the problem. Trace 2.94: the dive onto
  the dummy (23:42:50) lasted 12 s (HeavyAttackAir on its head - XZ lock right above its centre), then
  Job01_AirFinishingMoveFront -> under the ground.
- The XZ lock lets go at the enemy's head height + 0.3 m (L.head = dive spot - md.above). Still in HeavyAttackAir 2.5 s
  after it started -> stepped 1.5 m back (away from the enemy) + controller warp, once per dive.

### 2.97-test (2026-10-23)
- User (2.96): colours good, but now and then the launch effect (14/7/10) OR the after-teleport cloud (14/7/11 / 13/0/10)
  is teal - never both, hard to reproduce. Trace: our copy played every time. Cause (likely): copy_look also copied the
  game's ExternParameters / GroupParameters = its teal colour values, only when the game's player was ready that frame.
  Misty Dive copies now take only EmitMaskBit, MaskName, GroupEnabled, GroupNames.

### 2.98-test (2026-10-23) - SAVED: versions/Pactblade-2.98-SAVE-MistyDive-coloured.lua
- User (2.97): "probably good now" - Misty Dive colours done. Per-effect notes (dbg.md_seen) off by default (md.logFx).
- To do when the game is closed: merge pak_mods/x0006-PactbladeFx-skydive2.pak into x0004 (efx/pak_final already has
  all 53 files: rebuild x0004 from it, move x0006 to efx/removed).
- 2026-10-23 user: the Smite has never stopped from low stamina (even twice in a row) -> the 12:27 'interrupted by
  StartRunningOutOfStamina' trace lines were not a real cut-off; no stamina work needed for the Smite.
- 2026-10-23 user: Archfey Combo + Eldritch Slash tracking work fine (since it was added) -> is_alive() is NOT broken
  for them; nothing to change there (only Misty Dive's pick uses md.alive).

### 2.99-test (2026-10-23) - weapon-switch crash, round 3
- User (2.98): crash after ~5 weapon switches (23:57:59, c0000005 in a parallel job; dump crash_2_98_weaponswitch.dmp).
- Log: bursts of 'Exception ... via.render.Mesh.getMaterialFloat4' (~120/s; 23:47, 23:52 x2080, 23:55) = the Nox blade
  glow (BeginRendering) still reading / writing the OLD sword's mesh after a switch: 2.83 only handled sword -> other
  sword, not the frames with NO sword in hand (want = false -> nox_stop() touched the gone sword; the blade kept the old
  mesh during the 2 s fade). Native exceptions on deleted objects = likely the memory damage behind the later crash.
- Now: dbg.heldAddr = the sword in hand this frame; with no / another sword, noxPlaying is forgotten untouched and the
  blade dropped without restore; the blade glow only runs for the held sword (blade.addr); material slots checked
  (v < 65535) before getMaterialFloat4.

### 3.00-test (2026-10-24) - weapon-switch crash, round 4
- User (2.99): crash very quickly, Pactblade -> Mystic Spearhand -> Pactblade (00:03:09; dump crash_2_99_vocationswitch.dmp).
- Log: 00:02:53-55 ~180x 'Exception ... app.WeaponElementController.getWeapon' (held_weapon + held_sword, every frame,
  even with Pactblade off), crash 14 s later. getWeapon throws inside the game while the vocation changes.
- Now dbg.right_weapon(): CharacterManager ManualPlayer -> get_WeaponAndItemHolder -> get_RightWeapon (slot) ->
  field <Weapon>k__BackingField; nil while slot.IsStartPrepare or not IsCreated. No getWeapon calls left.
- Rule: after any crash, look for bursts of 'Exception thrown in REMethodDefinition::invoke' before it.

### 3.02-test (2026-10-24) - weapon-switch crash, round 5: the real suspect
- 3.01 crash 00:08:16 (dump crash_3_01_switch.dmp): no invoke-exception burst before it (6 getWeapon ones at 00:05 came
  from SmallerShield.lua), crash in a parallel job (AIGoalPlanning area - symbols unreliable).
- User asked if it's because these aren't our own effects. Close: the Nox shimmer (game effect 25 on the sword's own
  effect manager, parent = the sword) + MaterialInterpolationEnchant glow run OUTSIDE the game's enchant system, so the
  game never stops them before deleting the sword at a switch -> effect left on a deleted parent (same class as the 2.40
  EffectManager crash). 2.83/2.99 'forget, don't touch' kept exactly that alive.
- Now: hooks (pre) on app.WeaponAndItemHolder.Slot / WeaponSlot clear, release, equipPrepared, createWeapon,
  requestEquipWeapon, prepareWeapon, changeWeapon, setDirectAndDestroyOld, onStartPreparing, cancelPreparing - for MY
  right / left slots: the shimmer container killAll + glow finish while the sword still exists, then hold 1 s.
  Trace: 'Nox look stopped before the weapon change (<method>)'.

### 3.03-test (2026-10-24) - crash test without the blade glow MODE
- 3.02 crash 00:11:32 (dump crash_3_02_switch.dmp), 1.5 s after 'Nox look stopped before the weapon change
  (setDirectAndDestroyOld)'; stack in app.MaterialInterpolation.updateMatarial / updateNext / lateUpdate.
  Suspects: (a) our MaterialInterpolationEnchant mode 2834278566 on the sword (finishing it starts a fade on a sword
  being deleted; not finishing left it running before), (b) our hook BLOCKS the game's own requestMaterialMode(Sub) on the
  sword while Pactblade is on - the game may need them to clean up at a switch.
- dbg.noxGlowMode (not saved, default false): no glow mode request, no blocking. Shimmer + Enchant_Color blade colour
  stay (blade 'active' no longer needs glowComp). Menu checkbox under 'Nox sword look'.

### 3.03 -> 3.06 (2026-10-24) - weapon-switch crash SOLVED (user: ~20 switches, no crash), blade glow back without the mode
- 3.03 (no glow mode, no blocking of the game's glow requests): ~20 switches, no crash -> the cause was the sword's
  MaterialInterpolationEnchant mode 2834278566 requested by us (+ blocking the game's requests on the sword).
- 3.04/3.05 dump (data/Pactblade_glow_mode.json): modes live in mi.UserDatas[0]._ModeDataList (not ModeDataList); mode
  2834278566, material 2180083513: F4 3284380957 / 2930713855 = Enchant_Color1/2 (50/120/255, 128/190/255), F 2797575560
  0 -> 0.15 (Interpolation 0 = instant), F 2415810413 0.5 (= default). Default mode 4165826821.
- 3.06: blade code writes F 2797575560 = 0.15 (setMaterialFloat) with the colour, restores the read value. No mode.
  dbg.noxGlowMode stays false (checkbox = old way, crash-prone).
- 3.06 user: glow back, 10+ switches no crash. SAVED versions/Pactblade-3.06-SAVE-switch-crash-fixed.lua
- 3.07-test: log 00:17:51-52 / 00:18:00-01 ~1 s bursts of getMaterialFloat4 exceptions (~2 per frame) = the Smite /
  Misty Dive rim-light repaint on slots that can't be read. Slots now join only after one test read, and a slot that
  fails while painting is dropped.

### 3.08-test (2026-10-24) - Eldritch Burst binds + Hex (first version)
- User spec (2026-10-24): Burst gets Eldritch Bolt's bind (stun + Misty Step); after a Burst bind, Jump steps to the
  OPPOSITE side of the enemy. Hex on Examine (Circle = flag Interact, maybe GimmickAction - logged) for 15 s, X effect on
  the enemy, -10 % defence, killing it restores 15 % HP; a new Hex removes the old (original idea-list spec; its 0.5 s
  Onslaught = teleport in front / Empale = behind follow-ups NOT built yet).
- Burst: its animation (Job07_MagicBindComplete) fires the real Forbeding Bolt -> let through for lastKind burst too
  (requestCreateShell, captures, is_bind_bolt); bind_follow puts it on combo.pick_target(4 m, 100 deg) at +1 m for 0.8 s.
  Jump in the bind window after a Burst (dbg.lastKind) -> dbg.burst_step: combo.warp_to the far side (enemy + dir x
  max(1.8, radius + 1)), facing the enemy, then unbind - no Quik Fot leap.
- Hex IIFE (dbg.hex): md.pick target; X = 2 x 7 anchors with Dimension Door's shimmer file
  (wp00/009/13_wp00_009_enchant_25.efx) on own EffectPlayers, camera-facing diagonals at chest (h x 0.55 + lift), colour
  = Nox mist; damage on it x 1/(1-0.10) (mine in the main damage hook via dbg.hex_mul, others in a 2nd hook); hp <= 0 ->
  player HitController recoverHp(OriginalMaxHp x 0.15, false, 0, false). Menu: Skill settings -> Hex (sliders).
- Learned: code above line ~480 can't see lastKind/lastFire/combo (defined later) -> dbg.lastKind / dbg.lastFireT.
- 3.09-test (user on 3.08): the X was a ring of shimmer at the legs (CharaController height << real height). Hex is a
  bind-window action like Quik Fot: Examine (Interact / GimmickAction) in the window after an Eldritch Bolt OR Burst
  bind = Hex on the bound enemy (get_MagicBindShellHitOwner); Jump = teleport (Burst: far side). Free Examine Hex gone.
  X above the head (user: maybe better): centre = highest head joint (every 0.3 s) + over 0.4 + arm, arm = clamp(h x
  0.3, 0.5, 2.5) x size, 9 points per line, lift -0.4 (plume rise). Menu sliders 'X above the head', 'rise compensation'.
  Window: Hex does not close it (Jump still teleports after a Hex).
- 3.10-test (user on 3.09): the X = the shimmer effect TWICE (it is a straight line), each rolled +-45 deg about the
  view axis, camera-facing, above the head (over 0.6), frozen at hex.freezeAt (set_PlaySpeed 0; slider rebuilds the X
  live), bright pink 255/70/200, 2 copies per line. Test button 'Hex the enemy in front'. Burst step failed every time
  ("global 'yaw_rotation' is not callable" - it's local to the combo IIFE) -> combo.yaw.
- 3.11-test (user on 3.10): Burst step "detached me from my body" (the afterimage clone stayed: spawn logged, no step-0
  / ended notes) - combo.warp_to was called from re.on_frame (after the game's update). Now the press sets
  dbg.burstWant; the step runs in the next pre UpdateBehavior (like the combo's warps); a Jump* action the same press
  started -> NormalLocomotion. User asked to reuse the Archfey Combo's warp: it IS combo.warp_to, only the timing was off.
- X: was a V (each line grows from its anchor along local up) -> anchor = centre - up x half x scale (slider 'line
  centre', 1.5). Our solid pink copies: the shimmer is a FluidParticle2DSimulator billboard; its colours are inside the
  simulator raw (0D3380FF, f32 1.0, 80D5FFFF) -> C8148C / FF78DC, intensity 1.5 / 2.5 / 4 = pb_hexx_b1/b2/b3
  (efx/pak_hex -> pak_mods/x0006-PactbladeFx-hex.pak, game was running; copies in pak_final). Runtime tint 255/255/255.
- User: the -10 % defence does not stack (one multiplier per hit, checked against the one hexed object).
- 3.12-test (user on 3.11): pink look good, X in the wrong place (two lines apart near the ground) -> debug dots
  (re.on_frame draw.world_to_screen + filled_circle: green = X centre, red = each line's anchor, blue = anchor + 1 m
  along the line's own up) + sliders 'along itself' (hex.half) / 'apart' (hex.side). Burst step: the character sometimes
  jumped after it -> requestActionCore *Jump* for me refused for 0.4 s after the step.
- 3.13-test: dots (user screenshot): each line starts at its anchor and runs ~1.1 m along its own up -> half 1.5 -> 0.6 (line midpoints on the centre = X); dots off by default.
- 3.14-test (user: X better, teleport good; X tiny on the Cyclops, not visible on the Chimera): X size + height over the head x clamp(height/1.8, 1, 4); first placement per Hex noted (feet, head, joint found?, size, centre).
- 3.14 user: X looks good on the Chimera (with the size scaling) - kept.
- 3.15-test: user: Eldritch Bolt's lingering fog after the explosion 70 % smaller. Explosion = our pb_43_e<hue> (cs_008_31
  copy): 40 layers; fog candidates = the billboards i0 6, ig0 7, ky0 11, sk0 12, sm 13, ss 14, mkky 23, mtb 24, miky 25,
  mky 26, msk 27. catalog-tool efxhide now takes EFX_SCALE (multiplies the layer's Transform3D scale; default 0.001).
  Test copies pb_43_e<hue>f<layer> (that layer x0.3) -> pak_mods/x0007-PactbladeFx-fogtest.pak; Debug tree 'Eldritch Bolt
  fog test' (dbg.fogLayer, not saved) swaps the explosion file through OUR_FILES.
- 3.16-test: user: fog = layer 12 sk0 -> remove it completely: efxhide 12 on pb_43_e285/300/315 in efx/pak_final
  (originals in efx/removed/before_fog). Fog test menu removed. User: slow loading since the last pak (also had an
  online connection failure). Weapon-slot hooks (3.02) now return at once unless the Nox look plays (they see every
  NPC's slots). PENDING (game running): rebuild x0004 from pak_final, delete x0006-hex + x0007-fogtest paks.
- Published 2026-10-24: https://github.com/ntgoten/pactblade (public, source only: script, VSB pack, build_bank.py,
  DESIGN.md, README, MIT). No effect/sound paks (eblast.mp3 rights unclear - user).
- 3.16: game closed -> x0004 rebuilt from efx/pak_final (56 files: fog-free pb_43_e*, pb_hexx_b1-3); x0006-hex + x0007-fogtest moved to efx/removed. Paks now: x0004 effects, x0005 sounds.
- 2026-10-24: field note PR https://github.com/rehan-remade/universal-modder/pull/423 (knowledge/games/dragon-s-dogma-2/pactblade-*.md, from ntgoten's fork; clone A:/.ClaudeModding/um-kb-clone).
- 3.17-test (user on 3.16): fog NOT gone; Burst jump fixed, X good, Hex heal works. Installed x0004 checked (unpacked
  with final.list): pb_43_e285 sk0 scale 0.001 -> the remaining fog is another layer or another effect. Live test:
  dbg.fogCut (slider above Skill settings, default 1.0 s): our -1/8/43 copy gets PlayerAction.Kill that long after it
  starts. cfg.boom (game explosion scale) = 0.31 in the user's json. User doesn't remember the Hex follow-up idea
  (Onslaught/Empale teleports, from their pasted idea list) -> dropped unless they ask.
- User wish: Misty Dive usable while jumping (in the air) - next.
- 3.18-test: Misty Dive from the air (user): md.press notes every press ('in the air' / 'refused: skill track closed'); airborne (character:get_IsGround() false) presses pass and start() skips SkyDive's prep -> md.pick + dive() at once. Unknown: whether the game still calls processCustomSkill for Shield Drum in the air (the note tells). Hex done (user).
- 3.19-test (user): Cloudfall Strike-type skills work from the air -> slots swapped once (cfg.slots319): Misty Dive = Job01_RisingLunge (Cloudfall Strike), Archfey Combo = cfg.comboSkill Job01_BravesRaid (Riotous Fury, game text job01_skill_05), saved; combo has its own 'put it in the next skill I press' button (Skills section). RISING_ID -> SKILL_IDS/SKILL_NAMES from app.HumanCustomSkillID. Misty Dive from the air (3.18) now reachable through Cloudfall Strike's air use.
- 3.20 (user): the f12 test copy (sk0 at 30 %) hid the fog and kept the explosion, the fully hidden sk0 did not -> the tested pb_43_e<hue>f12 files are now the final pb_43_e<hue> (pak_final + pak_mods/x0006-PactbladeFx-fog2.pak until the next x0004 merge); the extra ky-layer hide dropped.
- 3.20-test: user: sk0 at 30 % only REDUCED the fog -> sk0 + the 'ky' smoke layers ky0 11, mkky 23, miky 25, mky 26 hidden in pb_43_e285/300/315 (base: removed/before_fog2), merged into x0004 (game closed); fogCut test default 0 (off).
- 3.19/3.20 user: Misty Dive (Cloudfall Strike slot, also from the air) and Archfey Combo (Riotous Fury slot) work.
- 3.20 user: fog still there but disappears quickly - leave it. Misty Dive (Cloudfall Strike) + Archfey Combo (Riotous
  Fury) confirmed.
- NEXT (user 2026-10-24): Eldritch Blast skill = beam from the left hand (BG3 references), Riotous Fury's opening
  animation (shield bash); beam efx on our own anchor at the palm, aimed + stretched 0 -> distance in ~0.1 s, tip flash,
  starburst + damage on arrival. Golem laser shell's efx path still to find (ch25x effect folders listed, no 'beam' name).
  Plan in HANDOFF.md.
- 3.21-test (2026-10-24): ELDRITCH BLAST BEAM, first build. Golem laser efx FOUND: vfx/effects/character/ch52/000/
  13_ch52_000_generalshell_030_02.efx (layer 'ch52_Beam_test' = mesh VFX/Mesh/Enemy/ch52/00/13_ch50_Beam_000_00.mesh,
  AABB -1.5..1.5 x/y, z -5..+10 = 15 m along +Z, 3 m wide; glows tb/g/hb/h at the origin), _01 = launch (magic circle
  Mgc_lp1/Aur_lp0 + shock), _03 = hit (Grow, Fire, kyy1 smoke), _05 = ground fire, _00 = charge. Baked pb_beam / pb_beamhand /
  pb_beamhit _h285/300/315 (efxtint 9/11/12 colours; the mesh core has no colour of its own) -> pak_final (65 files) -> x0004
  (old pak in efx/removed/x0004-before-beam.pak). Skill: cfg.beamSkill (default Job01_CymbalAttack = Shield Drum, saved,
  rebindable, shield check answered yes) -> Job01_BravesRaidStart (Riotous Fury's opening) -> at bm.fireFrame (14, guess)
  the beam anchor at L_Hand_Palm, rotated +Z onto the target (md.pick, hip), scale (w, w, len/(to-from)), grows in 0.1 s,
  hit = directDamage 150 + Hitback_M + hit flash, hold 0.35 s, thins 0.15 s; anim ends at bm.endFrame (40, guess) ->
  NormalLocomotion. Combo hook ignores BravesRaid while the beam plays; the game's Job01_BravesRaid follow-up refused.
  Menu 'Eldritch Blast (beam)': frame readout, all sliders, mesh from/to, flip, dots, 'fire now' test button.
- 3.21 user test: 'put it in the next skill I press' made Shield Drum work; beam fired BACKWARDS and was nearly
  invisible (faint dark-red line); fire frame ~57 (motion end 200). Cause of the colour: the beam mesh's colour is the
  gradient texture vfx/texture/gradient/13_heal_000_00_alb (128x1 RGBA, black -> warm white) x our magenta tint.
  3.22-test: own gradients 13_p285/p300/p315_000_00_alb (hue-rotated, saturation x1.3, same header) + efx copies
  pb_beam2 / pb_beamhit2 _h<hue> with the texture path swapped (same length) -> pak_mods/x0006-PactbladeFx-beam2.pak
  (src efx/pak_beam2; also copied into pak_final: drop x0006 at the next x0004 rebuild). Beam: mesh point 0 at the palm,
  -5 at the target (to < from = mesh turned around), thickness 0.25, tint off, fire 57, end 75.
- 3.22 user: no beam at all (mesh never visible on our anchor, even with own gradients); hand flash (pb_beamhand =
  Golem 030_01) looks good (pink burst at the palm). 3.23-test: beam = CHAIN of pb_beamhand copies, n = dist/spacing
  (0.5 m, max 50), copy i at i/n of the palm->target line, created when the growth passes it, scale 0.35, follows palm +
  target every frame, thins out with the rest. Mesh beam now optional (off). Anchor dot yellow.
- 3.23 user: beam look GOOD (row of hand flashes). 'Wisps' to remove -> 3.24 hit flash (Golem 030_03: smoke ribbons kyy1 / fire) off by default (guess; no warp notes in the trace). No damage on the dummy = expected: test dummies' damage is zeroed (0.27); real enemy test pending.
- 3.23 user: beam look GOOD (row of hand flashes). 'Wisps' to remove -> 3.24 hit flash (Golem 030_03: smoke ribbons kyy1 / fire) off by default (guess; no warp notes in the trace). No damage on the dummy = expected (test dummies take 0 damage, 0.27); real-enemy test pending.
- 3.24 user (real enemy): no explosion, no stagger, tiny damage; trace: every shot 'no target' (md.pick 20 m / 90 deg).
  Wisps = sparkles left ~1 s along the beam after it's gone (hand flash's drifting smoke). Riotous Fury's opening plays
  slow-mo. 3.25-test: pick range 30 m (md.range swapped for the call); nothing picked -> beam along the CAMERA (-Z) and
  the first living enemy within lineRadius (1.2) + its radius of that line is the target; hit = Eldritch Bolt's
  explosion (parts.play_ours -1/8/43, scale 1.0) + damage note with HP before/after; row flashes = pb_beamrow (Aura 7 +
  shock 11 hidden; pb_beamrowb also Aura2 8) in pak_mods/x0007-PactbladeFx-beam3.pak (src efx/pak_beam3, also in
  pak_final: drop x0006/x0007 at the next x0004 rebuild); layer speed 1.5 until the beam fires (note logs the game's).
- 3.25 user: row without drifting smoke = no beam (the smoke IS the beam) -> full row again (default). No stagger
  (directDamage + DamageType 6 doesn't stagger; damage 150 = ~2 % of a 7900 HP enemy, user saw 'very small'). User:
  NO projectile (0.24-style tries were bad) - only Eldritch Bolt's hit explosion VISUAL on the enemy. Pink whirlwind
  outwards at the start = suspected Riotous Fury's own effects. 3.26-test: hit = our -1/8/40 + -1/8/43 copies (the
  bolt's starburst + explosion) turned along the beam, scale 1; every player requestEffect during bm.stage killed
  (bm.animFx, ids noted once in the trace).
- 3.26 user: whirlwind still there - grey wind + a purple one expanding outwards from the character; trace: no
  animation effect was killed (Riotous Fury's opening starts none) -> it's our flash copies: dis / com_CamS /
  com_RadialS / com_blur (screen distortion, radial blur, camera shake - x every copy) + shock (expanding ring).
  3.27-test: pb_beamrowc_h<hue> (layers 4, 9, 10, 11, 12 hidden) in pak_mods/x0008-PactbladeFx-beam4.pak (src efx/pak_beam4,
  also in pak_final) for the row (rowLook 4) and the hand flash (handClean); hold 0.35 -> 0.65 s (user: +0.3 s).
- 3.27 user: only the hit explosion + the animation's grey whirlwind - NO beam: pb_beamrowc (shock 11 hidden) shows
  nothing -> the 'shock' layer (Velocity3D + emitter, smoke texture) IS the visible beam (3.24 beamrow also hid it).
  The grey whirlwind persists with every blur layer gone -> it is the animation's, coming through
  requestEffectFromFsmOrSequence / FromFsm / Internal (not requestEffect). 3.28-test: pb_beamrowd (only 4, 9, 10, 12
  hidden; Aura + shock kept) in x0009 (src efx/pak_beam5, also pak_final) for row + hand; the animation-effect kill
  also hooks those Fsm / sequence / Internal methods (player's manager only, noted once each).
- 3.28 user: look right (row 'full', hand without blur; no purple whirl) but a huge light-up drowns the beam (each of
  ~30 row copies has a 1500 lm Light layer), and the explosion seems to come before the beam arrives. 3.29-test:
  pb_beamrowe = full minus Light 1 (x0010, src efx/pak_beam6, also pak_final) = default row; hit waits bm.hitDelay
  0.15 s after the growth reaches the target (slider). Paks x0006-x0010 to merge into x0004 when the game is closed.
- 3.29 user: 'full, no lights' = NO beam. pb_beamrowe differed from the working file only in Light's scale -> in
  030_01 the Light layer is the PARENT of the other layers (scale passes down): efxhide only works on leaf layers
  (explains beamrow / beamrowc too). Rebuilt pb_beamrowe: full file, Light's light colour (TypeNoDraw @68) set to
  black, scale untouched (x0010 repacked while the game ran - same sizes; restart needed).
- 3.29 user: no whirl / light-up any more (rowe works), but each flash is bright only ~0.2 s, then smoke/wisps; the beam should stay. 3.30-test: every row copy + the hand flash frozen (set_PlaySpeed bm.frozenSpeed 0) at bm.freezeAt 0.10 s of its own age, held through the hold, then thinned out as before (sliders).
- 3.30 user: beam stays a bit too long, smoke goes with it (screenshot: radial blur + smoke), base keeps following the hand. 3.31-test: hold 0.45; start fixed at the palm's position when fired (bm.followHand off); row F = rowe minus 4,8,9,10,12 (still smoke Aura2 gone) / G = rowe minus 4,7,9,10,12 (drifting smoke Aura gone), x0011 (src efx/pak_beam7, also pak_final); default F.
- 3.31 user: row F and G = NO beam. Every efxhide'd copy of 030_01 shows nothing, whatever layer (beamrow, rowc, rowe
  v1, F, G); only byte-patched copies work -> efxhide (scale 0.001) breaks this effect entirely. New rule: hide layers of
  030_01 copies by ALPHA: Billboard3D (26) colour alphas @7/@15, RgbCommon (248) @7/@27 set to 0 (direct byte patch of
  the working rowe). F/G rebuilt that way under the same names (x0011 repacked, restart): both dis + com_blur, F also
  Aura2, G also Aura. com_CamS / com_RadialS (camera shake / radial blur, NoDraw) still in.
- 3.31 user (alpha-patched F/G): looks good. Launch cloud in front of the hand stays too long -> 3.32-test: row copies within launchLen 1.5 m of the palm + the hand flash shrink away from launchSecs 0.15 s over launchFade 0.10 s, then dropped (chain slot false = never re-made).
- 3.32 user: visuals DONE. Next: damage, stagger, targeting. User: Eldritch Blast = a flinch / stagger only (the Smite
  is the big knock-down, D&D prone). Range 20 m; aiming with the LEFT STICK must beat a closer enemy.
  3.33-test: damage = dbg.blastDmg.charged (last Eldritch Bolt hit's final Damage, recorded in the calcDamageValue
  hook; tap x2 as a fallback; else fixed 900) x bm.dmgRate 1.0, Hex x1/0.9, IsMagicAttack. Flinch: DamageType /
  ActType / OverwriteBlownType 6 (Hitback_M), DamageReaction bm.react 300, and if the game asks getReactionDamageType /
  calcDamageReaction for our info (address match, 1 s) -> 6 / at least bm.react (counted in the hit note). Target:
  aim_pick = smallest angle to the stick direction (stick_yaw) or else the camera's, within aimCone 20 deg, 20 m,
  distance only a tie-break (x0.1); stick pushed + nothing there = no nearest-enemy fallback, beam along the stick.
- 3.33 user: flinch works. Damage must NOT match the bolt (free core skill, low damage); the beam costs stamina and should
  do decent magick-only damage. 3.34-test: dbg.boltMag = the game's raw magick value (MagicDamage + EnchantDamage) x
  DamageRate of the last Eldritch Bolt hit, before our 0.4255 factor; beam = boltMag x bm.magRate 2.5 (~6 bolts, ~2
  sword swings of ~1300); fixed 2000 before any bolt hit; IsMagicAttack + MagicDamage set; stamina 150
  (a:consume_stamina) when the animation starts. Menu shows the magick value and the resulting damage.
- 3.35 (user): beam damage x1.6 -> magRate 4.0, fixed 3200.
- 3.36 (user): aiming at distant targets felt off -> pick range + no-target beam length back to 30 m (trace: stick aiming picks fine at 1.5-12.7 m).
- 3.37 (user): range back to 20 m, aim window 40 deg.
- 3.38: BUG since 3.35 - the damage edit put a '-- comment' in the MIDDLE of the bm table line, commenting out react / aimCone / stagger / hue / tint -> anchor() format(nil) error, no beam. Fixed (comment moved to the line end). Lesson: when adding a comment with a string replace, put it at the END of the line, never before other fields.
- 3.39 (user): damage 1.4x the 3.34 value instead of 1.6x -> magRate 3.5, fixed 2800.
- 3.39 user: damage 1.4x (not 1.6x). Wish: beam usable in the AIR with the air Eldritch Bolt / Burst animation, same
  beam / damage. 3.40-test: press allowed when airborne (get_IsGround false); stage "air" = Job07_MagicBindComplete
  (layer 0), beam at airFire 0.30 s (BLAST.charged.delay), WaitToFall at airEnd 0.9 s; the action's own Forbeding Bolt
  blocked in the requestCreateShell hook while bm.stage == "air". Unknown: whether the game calls processCustomSkill
  for Shield Drum in the air at all (the press note says "(in the air)" if it does).
- 3.40 user: nothing mid-jump; trace: no press at all -> the game never calls processCustomSkill(id, ...) for Shield Drum in the air. 3.41-test: hook the button's own entry processCustomSkill(app.CharacterInput.Action, id, UInt64, LockOnController.Option, bool x3) (args[4] = id): airborne + beam slot -> bm.press() + skip; first call noted ('the button's entry is called (in the air)'). If that isn't called in the air either: put the beam on an air-usable skill / read the Skill1-6 buttons ourselves.
- 3.41 user: WORKS in the air (button entry hook). 3.42-test: in the air the beam's start follows the palm (sh.inAir + bm.airFollow); on the ground it stays where it fired.
- 3.42 user: add the air Eldritch Burst's launch effect. 3.43-test: in the air the animation's own effects are kept (bm.airAnimFx: no kill) + our -1/8/40 copy (blast launch flash) at the palm when the beam fires (airLaunch, scale 1).
- 3.43 user: OK. 3.44-test: Eldritch Smite's own hit sound (sm.SND.hit 3434957627 via dbg.smite.sound) when the beam fires, ground + air (bm.sound).
- 3.45 (user): the sound 0.2 s before the beam (bm.soundLead): air = time-based (airFire - lead), ground = frames left / measured frame rate <= lead; fire() plays it if it wasn't yet.
- 3.45 user: flying harpies never targeted; trace: nearest enemy 49.8 m flat / 13.2 m up (GameObject position). 3.46-test: aim_pick measures the body (aim_of = Hip joint) instead of the object, height limit maxUp 20 m; when nothing is picked a note lists up to 6 enemies with body vs object distance / height.
- 3.46 user: calm harpy (screenshot, est. 25-35 m, ~10 m up) not targeted; can't repeat easily. 3.47-test: enemies more than airUp 4 m above me are aimed at / line-hit up to airRange 35 m (ground ones 20 m). The 3.46 enemy-list note will show real distances whenever nothing is picked.
- 3.47 user: perched harpy hit (20.6 m). Trace before it: harpy 20.7 m / 15 up = in reach, yet 'nothing where the stick points' -> stick_yaw's stickSide guess (flips -1/1) can mirror the aim. 3.48-test: aim direction = TargetAngleCtrl.Move AngleDeg (game's own stick direction) while isLeverInputL; stick_yaw only as a fallback. Also seen: harpy ch222005 HP -5600 per 2800 hit (x2: harpy weakness or a double application - check on other enemies).
- 3.48 user: damage is fine as it is (left alone).
- 3.48 user: Eldritch Blast DONE (stick aim untested; user will play-test later). Next: Smite throws enemies far away; then Misty Dive ('ain't good', details asked). 3.49-test: Smite keeps Slam_L x100 but the hit-back push (HitBackZ / Y / AddZ / Vec, ForceFactor) x sm.push 0 in pre-hooks of HitController.updateDamageReaction + setDamageType for my smite hits; note logs the values before. Enum low words: Hitdown_L 12, HitdownQuick_L 13, Slam_L 15, Blown_L 19 (7..19 = Hitback_L..Blown_L).
- 3.49 user: Misty Dive - the strike misses; sometimes flies up / to a side instead of striking straight down. 3.50-test:
  with a target, our own descent (md.follow): x/z = the enemy's (it may move) + 0.4 m on my side (blade in front), y never
  up and forced down at fallSpeed 14 m/s to its head - strikeDepth 0.3; there (or as soon as the Empale's blade hits:
  calcDamageValue pre during stage "dive" -> md.hitLanded, or after 1.5 s) md.strike: our directDamage 1500 + Hitback_L
  (react 300) only if the blade didn't hit, then set down on the ground beside it (radius + landGap 0.8, my side), warp.
  Every action during the dive is noted (to see what throws me). Menu sliders.
- 3.50 user: Misty Dive drags me backward / toward where I started. 3.51-test: landing straight below where I am, pushed out of the enemy only to radius + landGap 0.1 (was: radius + 0.8 toward my starting side); notes the landing distance and any move > 1 m in the 1.2 s after it (with the action).
- 3.51 user: Smite still throws with Slam_L AND Hitdown_L; trace: HitBack z/y/addZ were 0 already -> the reaction itself. 3.52-test: sm.noBlown: BlownReactionRate 0, BlownReactionConvertLevel 0, IsTwoRankUpReaction false at updateDamageReaction / setDamageType; notes the reaction fields + the enemy's action 0.35 s later.
- 3.52 user: at the lowest stagger power the bandit didn't fly; most flights were kills. Trace: x100 power 74865 -> DmgRagdollBlown, ~x10 7486 -> DmgRagdollSlam. 3.53-test: downPower 10; a killing hit (info.Damage >= victim HP at calcDamageReaction) gets no multiplier (the game's own death reaction).
- 3.53 user: back to the ORIGINAL Smite (x100 power, Slam_L; today's push / noBlown / lethal-skip changes off - sm.push 1, sm.noBlown false, sm.lethalSkip false) but very low damage: 3.54-test sm.dmgMul 0.1 on every player hit while sm.stage (calcDamageValue post, after the bonuses + Hex).
- 3.54 user test: 10 % damage + x100 = knock-downs in place -> the flights are DEATHS. 3.55-test: damage x1 again; sm.lethalSkip: a killing blow (info.Damage >= victim HP) gets neither the forced Slam_L (getReactionDamageType) nor the x100 power (calcDamageReaction); notes at both points.
- 3.55 user: still flies. Trace: killing blow caught at both checks, left alone (power 7486 = the Smite's own, type -1) and the game still picked DmgRagdollBlown. 3.56-test: on a killing blow sm.soften: type Hitdown_L 12 forced (OverwriteBlownType too), power x deathPower 0.05, ForceFactor 0, BlownReactionRate 0, HitBack 0 - at getReactionDamageType, calcDamageReaction and updateDamageReaction / setDamageType.
- 3.56 user: the flight is the DEATH ragdoll (bodies carry loot - thrown far = loot lost). 3.57-test: on a smite kill (sm.mark_dead) for 2 s: app.DamageRagdollBlow.start pre -> set_IsBlownWithAttackVelocity(false) + IsDisableCalcVelocity = true; every LateUpdate the body's app.CharacterRagdoll limitLinearVelocity(2.5, 1.0) (fallback 1-arg 2.5). Notes for each. Classes: DamageRagdollBlow (calcRagdollLinearVelocity -> Nullable vec3, calcVelocity, RagdollVelocity, BlowSpeedLimiter), DamageRagdollSlam, CharacterRagdoll (setLinearVelocityAll, clearLinearVelocity, limitLinearVelocity).
- 3.57 user: killed bodies no longer fly (Smite FIXED: x100 knock-down on the living, death ragdoll tamed on kills).
- 3.58 (user test): Smite knock-down power x500.
- 3.59 (user): Debug buttons 'Spawn a NORMAL Cyclops / Chimera (fights)' = dummy.real: the same DragonCore summon (hostile, 8 m ahead), not paused, not tracked as a dummy; 'Remove all dummies' removes them too.
- 3.59 user: DUMMIES ARE NO GOOD FOR REACTION TESTS - the paused dummy Cyclops only kneels (stagger), a normal summoned Cyclops falls prone from ONE Smite (x500). Test knock-downs / reactions on the 'normal' spawns.
- 3.60: Griffin spawn (ch253000_00) added. User: normal Chimera only staggered at x500. Trace: 'killing blow' check (Damage >= HP) true for a Chimera that lived (region / part rates) -> soft Hitdown_L (DmgHitdownSpot). 3.61-test: no more softening (every smite hit Slam_L + power); kills only get the ragdoll measures, and only while the body's HP is really 0 (blow start + cap check HP).
- 3.61 user: x500 = one Smite floors Cyclops + Griffin, the Chimera needs 2; goal one for every enemy (maybe not final bosses). Reaction power does NOT change damage (DamageReaction only). 3.62-test: HitController.checkReactionThresholdPass(info, bool) + checkRegionReactionThresholdPass(int, info, bool) return true for smite hits (sm.forcePass), counted in the menu, 'no -> yes' noted.
- 3.62 user: Chimera still 2 smites. Trace: no threshold checks ran; smite 1 -> DmgRegionShrink (body-part reaction replaced the knock-down), smite 2 -> Ch254_PanicDown. 3.63-test: sm.noRegion: HitController.isRegionReaction(int) -> false for others' HitControllers while sm.stage == 2, info.IsRegionReaction = false at getReactionDamageType / updateDamageReaction / setDamageType (noted).
- 3.63 user: Chimera still 2. Trace: smite 1 -> Ch254_TailBreak (part break replaces the knock-down); no region / threshold override ran. 3.64-test: sm.followUp: 0.35 s after a smite hit (sm.watch, now in LateUpdateBehavior) the enemy's action has no down / slam / blown / ragdoll / die / dead / fall / lie word and HP > 0 -> one directDamage (1 damage, Slam_L, OverwriteBlownType, DamageReaction 1e8, IsRegionReaction false), checked again 0.35 s later (no third).
- 3.64 user: the Chimera goes down with the follow-up (LargeBlownDown; a real 2nd smite gave Ch254_PanicDown) - 'not sure it's the full one'. Bugs: dodge usable on the rope (rappelling) and while downed; Misty Dive usable on the rope (can teleport into the ground). 3.65-test: dbg.can_dodge (Track All / Evasion / Cancel / SpecialCancel, never in rope / climb / hang / dmg / down / grab ... actions) gates the tap dodge; dbg.air_ok (airborne only from a jump / fall / air action, same word list excluded) gates Misty Dive's and the beam's air presses. Refusals noted.
- 3.65 user: Chimera still needs a real 2nd smite for the wanted knock-down (Ch254_PanicDown; follow-up gave LargeBlownDown). 3.66-test: follow-up = MemberwiseClone of the real smite DamageInfo (taken at updateDamageReaction / setDamageType), Damage 1, sent with directDamage; fallback the Slam_L hit.
- 3.66 user: the copied follow-up didn't give the panic knock-down either -> 3.67-test: the Smite block + its menu restored from versions/Pactblade-3.58-test.lua (3.57 death ragdoll fix incl. the soften-on-'lethal' guess; no threshold / region / follow-up code), x1000 (slider up to 2000). Spawn buttons + 3.65 dodge / air fixes kept. Pre-revert copy: versions/Pactblade-3.66-test-before-smite-revert.lua.
- 3.68 user: Smite knock-down power x150 - DONE ('that's it'). Chimera needing 2 smites accepted.
- 3.68 user: on a bandit Misty Dive slides ~3 m sideways at its head and hits the ground. Trace: head reached 0.12 s after the warp (before the stab), landed 0.5 m from its middle (inside) -> shoved 1.4 m. 3.69-test: fallSpeed 7, held at the head until the blade hits (headHold 0.25 s max) before the backup hit, landGap 0.5 (outside its body). Normal-spawn buttons for both Beorcan bandits.
- 3.69 user: Misty Dive seems GOOD now (normal bandit).
- 3.69 user: Eldritch Bolt castable while rope climbing. 3.70-test: dbg.busy_action (AIR_NO words in the current action) blocks the vocation button's press (tap blast / bolt / Burst) and the charged release.
- 3.71: Skill Maker 'Darkness' (dd2-research/skillmaker/.../Skills/Darkness.json) = Sorcerer combo: Job05_GroundDrill + Sphinx warp dark bullets (ch253001warpdarkbulletsshellparamdata 0-5), Job05_FinishingMoveLargeBelow + shell 7, ch253_seismspellshellparamdata, then ch254_darkareashellparamdata #0 (lifetime 30 / 3) = the dark cloud. Debug button spawns that dark area (cosmetic, 15 s, 10 m ahead). Darkness design (user): cast + ground circle 10 m out, rotatable; cloud nothing can be seen through; red / green outlines of enemies / pawns drawn ABOVE the fog - via.render.Outline component (OnlyDrawHiddenPart, DrawColorNum, OutlineSettingElement Outline/SilhouetteColor, DrawMode Outline/Silhouette/Both); hate: enemy HateSystem setCustomRate(go, rate) / clear(go).
- 3.72: Skill Maker's ch254_darkareashellparamdata path no longer exists (empty userdata -> 'shell id 0 not in'). Dark-area files now: ch254/001/60/ch254001_60darkareashellparamdata (1 shell), ch223/004/ch223004darkareashellparamdata (1), ch227/001/ch227001darkareashellparamdata (4, lifetime 1.2 on some). Debug buttons spawn each (cosmetic, 15 s, 10 m ahead).
- 3.72 user: the dark areas (Chimera variant etc.) = flat ground patches with wisps, not the Darkness wanted. 3.73-test: Debug 'black FOG BOX' = our GameObject + via.render.VolumetricFog (VolumeType 2 Box / 3 BoxWorldOffset / 1 ExpHeightFog / 0 Global / 4 Mesh), live sliders density / width / height / brightness / type; transform scale = box size (guess), Radius = width/2.
- 3.74 user: the fog box still shows nothing (no trace lines - lost / not run) -> DARKNESS PARKED (design kept: cast like
  Caustic Brew, ground circle 10 m out, thick dark cloud, red / green outlines of enemies / pawns over it (via.render.Outline
  OnlyDrawHiddenPart), hate: HateSystem setCustomRate / clear; open: a fog / cloud that really hides).
- 3.75-test: super armour while Misty Dive runs (md.armor, set / cleared in its UpdateBehavior). Eldritch Bolt / tap blast:
  DragonCore's soft lock looks near the CROSSHAIR POINT (aim.nearest_enemy(target point, 30)) -> without the stick it found
  nothing; now opts.aim = the beam's aim_pick target (stick / camera, 40 deg, 20 m, fliers 35 m), noted per shot.
- 3.76 (user): Bolt / tap blast aim range halved: aim_pick(a, 0.5) = 10 m, fliers 17.5 m (the beam keeps 20 / 35).
- 3.77 (user): bolt lock-on range = flight range: tap / charged blasts get maxRange 10 m (17.5 when aimed at a flier); LateUpdate: distance from record.startPos > maxRange -> set_RequestKill on every live part.shell, noted.
- 3.78 (user): Misty Dive picks an enemy further than md.nearAny 5 m only when it is on screen (md.on_screen: camera-space depth > 0.1, |x/depth| <= tan(FOV/2)*16/9*1.05, |y/depth| <= tan(FOV/2)*1.1, aimed at the body +1 m). Range 20 m, 90 deg cone, 15 m height kept.
- 3.79 (user): Misty Dive max range 15 m.
- 3.80 (user): Eldritch Bolt turns the character toward its aim_pick target at the cast (fire, charged) and at the release (spawn_blast): rotation combo.yaw + TargetAngleCtrl move angle.
- 3.81 (user: character / launch effect out of step): one turn at the cast, held every UpdateBehavior + LateUpdate (dbg.boltHold, up to 1.5 s) until 0.1 s after the bolt spawned; no second turn at the release. Main chunk is AT the 200-locals limit: new helpers must be dbg fields / inside function blocks.
- 3.82 (user: still sometimes no turn): trace showed release-time picks without a cast-time pick, and aimed bolts cut at ~11 m. Now ONE pick at the cast (dbg.boltTarget, used by the release within 2 s; none = no aim), aimed range = palm-to-target + 2 m, the turn hold also in UpdateMotion + after LateUpdateBehavior.
- 3.83 (user: no turn only without the stick): app.TargetAngleController has Front (body facing, restored by the game) + Move; dbg.set_facing_deg sets setAngleDeg / setFrontAngleDeg / setMoveAngleDeg + both Info AngleDeg / IsSet during the bolt's turn hold.
- 3.84 (user screenshot: enemy 5.2 m at the screen's right edge, no turn, but it WAS hit): our pick rejected it (> 40 deg from the camera centre) while DragonCore's own soft lock (lock_range around the crosshair point) still homed the bolt onto it. aim_pick without the stick now also accepts anything md.on_screen; nearest the centre wins (beam too).
- 3.84 user: bolt turn 'still can happen but good enough'. Remaining gap: DragonCore's soft lock (cast.lock_range near the crosshair point) can still home a bolt onto an enemy our pick didn't choose. Fix if wanted later: turn toward DragonCore's pick, or drop lock_range when our pick finds nothing.
- 3.85-test: BLINK STRIKE v1 (user: Blink Behind remade, Riotous Fury's LAST HIT): cfg.blinkSkill (default Job01_ShieldSummons, saved, rebindable, shield check answered yes). Press -> beam aim_pick x0.75 (15 m) -> combo.warp_to behind it (radius + 1.2 m, facing it; wisps / afterimage / cues) -> Job01_BravesRaid from bs.from (changeMotion crossfade) to bs.to, NormalLocomotion. Archfey Combo hook ignores it; Riotous Fury follow-ups refused while it plays. Menu 'Blink Strike': motion + frame readout, from / to / speed / behind.
- 3.86 (user): Blink Strike range 10 m (aim_pick x0.5); 'getting ready' = Misty Dive's SkyDive preparing jump (Job07_SkyDive; warp at its teleport motion 170/1101 + 0.05 s or after 0.6 s; position held 3 frames vs SkyDive's upward push); md.busy() also true during Blink Strike so SkyDive's teal effects / rim glow get our purple.
- 3.87: the user's saved beamSkill = Job01_ShieldSummons (rebound in 3.21) -> Blink Strike default Job01_CymbalAttack (Shield Drum); at load blinkSkill is moved to a free skill if it equals the beam / Smite / Misty Dive / combo skill.
- Fighter skills (game text): 12 lines job01_skill_00-11 (base / _lv2) + DLC Whirlwind Strike -> Hurricane Strike -> Tornadic Strike (job01_skill_05_TU / _TU_00 / _TU_01, likely ID 102 Job01_RushAttack); Cloudfall Strike = DLC upgrade of Cloudward Slash. Pactblade uses 6 (BlinkStrike Smite, HindsightSlash Slash, RisingLunge Misty Dive, FullMoonSlash Brew, BravesRaid combo, ShieldSummons beam (user's saved; Summons/Drum share one ID)). Blink Strike default CymbalAttack = probably Shield Bash / Pummel (unconfirmed; use the bind button). Free: Gouging Skewer, Springboard, Shield Bash, Counter Slash, Impeccable Guard, Perfect Defense, Whirlwind Strike.
- 3.88 (user): the teleport-strike skill is named MISTY STRIKE (menu / notes; internal names dbg.blink / cfg.blinkSkill kept).
- 3.88 user: Misty Strike teleports but no hit (trace: ForwardJumpLanding 0.02 s after the warp - airborne from SkyDive's prep); prep fog / aura lingers ~0.4 s. 3.89-test: Landing / Fall / Jump requests refused while the strike plays + if one took over in the first 0.6 s the strike is re-requested (max 5); the prep's md.fxs copies destroyed at the warp; md.busy only during the prep (rim glow).
- 3.89 user: the strike now plays (whole animation). 3.90: Misty Strike starts Riotous Fury (110/1701, 282 frames) at frame 119 (user, AnimPlayer), to its end.
- 3.90 user: SkyDive prep lifts me up, then an invisible move - no teleport feel. 3.91-test: held at the press position's height during the prep (groundLock), warp after prepWarp 0.30 s (before motion 1101's vanish), SkyDive's teleport sound 2823464530 via combo.cue_sound.
- 3.91 user: still lifting. 3.92-test: ground lock (y = press height, x/z free) in UpdateMotion pre / post, LateUpdateBehavior pre / post, BeginRendering pre while stage 'prep'; prepWarp 0.25 s. Wanted order (user): crouch, no lift, teleport to the far side of the enemy, THEN Riotous Fury from 119.
- 3.93 (user): Misty Strike starts Riotous Fury at frame 106.
- 3.94 (user): Misty Strike range 15 m (aim_pick x0.75); usable from a jump: button-entry hook processCustomSkill(Action, id, ...) when airborne, dbg.air_ok gate, no prep in the air (straight warp + strike).
- 3.95 (user): Misty Strike from a jump: stage 'airprep' = position held + FullBodyLayer speed 0 for airHold 0.2 s, SkyDive's launch effects as our copies pb_sdex / sd10 / sd11 / sdns10 _h<hue> on anchors at me, its start sounds 3610636506 + 1717783091 (cue_sound); then effects removed, warp + teleport sound 2823464530, strike.
- 3.96 (user: air Misty Strike onto a Griffin on stairs = under the ground): landing spot checked with combo.nearest_hit (_SharedCore cast_ray, from +2.5 m to -3 m): ground higher -> raised onto it; < 1 m below -> set down; further below (flier) -> stays. Noted per strike. Needs _SharedCore (installed).
- 3.96 user: Misty Strike good. Misty Dive once under the ground too -> 3.97: its landing (md.strike) gets the same nearest_hit ground check.
- 3.97 user: Misty Dive + Misty Strike landings good now. MISTY STRIKE DONE.
- 3.98: stamina measured (dbg.stam_mark: a:stamina() at the press and 1.5 s later, noted) for Misty Dive and Misty Strike. MSP's dive = Skiedragoun's Fangtooth (Job07_SkyDive); job07staminaparameter.user has numbered costs (7202 130, 7203 180, 7204 250, 7205 80, 7207 110, ...) without skill names.
- 3.99: every sudden stamina drop >= 20 (one frame) noted with the current action, any vocation (to read MSP's SkyDive cost).
- 3.99 user/trace: MSP's Skiedragoun's Fangtooth (lvl 3) = -110 at once during Job07_SkyDive. 4.00-test: Misty Dive + Misty Strike cost 110 (md.stamina / bs.stamina): at the press dbg.stam_cost notes stamina, 0.6 s later takes only cost minus what the game already took (SkyDive's prep), noted.
- 4.01 (user): stamina - Eldritch Blast beam 200, Eldritch Slash 160.
- 4.01 trace: Eldritch Smite = ALL stamina (Job05_ArcOfObliterationEnd: 1579 -> 0); Caustic Brew: no drop. 4.02-test (user): Smite keeps the drain, its first hit refunds 20 % of StaminaManager MaxValue 0.3 s later (add(+x, true)); Caustic Brew 150 (dbg.stam_cost at sk.press); beam: stamina rises >= 20 also noted for 1 s after its press (the full-bar flash).
- 4.02 trace: beam press -> Job01_BravesRaidStart resets stamina to full (+309 / +353) then takes 480 (Riotous Fury's cost; ours overwritten). Brew: 'we took 150' but the user sees no cost. Smite: -1579 then +316 refund OK. 4.03-test: dbg.stam_cost refunds when the game took more (exact total); the beam uses it (200 net); stamina rises noted 4 s after a brew press.
- 4.03 user: beam's refund = a visible jump; brew still no cost (trace said 'we took 150'). 4.04-test: StaminaManager.add(Single, Boolean) pre-hook: while dbg.stamSwap (beam start, 0.6 s) a drain <= -300 on MY manager becomes -cost (Riotous Fury's 480 -> 200); brew pays at sk.press (before the chant), before/after noted.
- 4.04 user: beam stamina GOOD (480 swapped for 200). Brew: consume at the press ignored (1579 -> 1579, chant). 4.05-test (user): brew pays 150 in sk.release (when the acid pours), before/after noted.
- 4.05 trace: brew consume at the pour ignored too (1579 -> 1579). 4.06-test: StaminaManager.setRemainingAmount(current - 150) at the pour, IsEnableConsume noted.
- 4.06 user: brew stamina WORKS (setRemainingAmount at the pour). Costs now: Misty Dive / Misty Strike 110, Eldritch Slash 160, Eldritch Blast 200, Caustic Brew 150, Archfey Combo 250, Smite = the Arc's full drain + 20 % back on a hit; Controlled Fall 100. Lesson: during a chant (Mage prep actions) StaminaManager.add is ignored - set the value directly.
- 4.07 (user): Hex costs 10 % of max stamina (setRemainingAmount in hex.put).
- 4.07 user: spamming Examine in the bind window charged Hex's stamina each time (effect never stacked - per-hit defence check; timer / X restarted). 4.08: hex.put on the enemy already hexed (timer running) returns before the cost.
- 4.08 user: Hex cost OK.
- 4.09-test: HELLISH REBUKE v1 (user): an enemy's hit on me (calcDamageValue pre, DamageGameObject = me, owner = a Character) opens a 0.5 s window; Interact (not in a big reaction: down / blown / slam / ragdoll / catch / grab / ShrinkL ...; flinches allowed) -> 30 % of max stamina (setRemainingAmount), face the attacker, NormalLocomotion, motion 9112/750 (45 frames, 50 fps) forced on the FullBodyLayer at 1.2x (AnimPlayer's way, UpdateMotion), FireSpread (5) on the attacker at frame 20 (reqStatusConditionApplyCore). Hit + action noted. Green hellfire next.
- 4.09 user: rebuke works (fire + stamina). 4.10-test: + a 1-damage Hitback_M flinch (react 300) with the burn; green spark = Golem impact 030_03 baked hue 120 / 140 (efxtint + own gradients 13_g120 / g140 - 'Heal' path swapped) pb_rebuke_h120/140 in pak_mods/x0012-PactbladeFx-rebuke.pak (src efx/pak_rebuke, also pak_final), at the left palm scale 0.3 for 1.5 s.
- 4.11-test (user): Hellish Rebuke also a green fire explosion on the attacker (pb_rebuke at its hip, scale 1.2, 2.5 s) + Eldritch Smite's hit sound. Next: the whole-body 'charge finished' flash of Tusk Toss / Warrior skills - user to record it with the Debug Recorder.
- 4.11 user: stuck in the default (bind) pose - motion 9112/750 not loaded on me in normal play (not in humancommon.motbank). 4.12: if after changeMotion the bank isn't 9112 or the end frame is 0 -> no clip, back to NormalLocomotion, burn + spark anyway, noted. Asked the user what loads bank 9112 (what they did when AnimPlayer saw it). Also: the window note fired every ~1 s from a burning enemy's fire ticks.
- 4.12 user: the clip = the END of the Mage cast the brew replays. 4.13-test: castT.bank (ch00_006_atk.motlist as dynamic bank 9112) kept loaded every 5 s while Pactblade is on; the rebuke waits (max 0.4 s) for getMotionInfo(9112, 750); the missing-bank fallback stays.
- 4.13 user: the green spark (Golem 030_03 copy) = a huge BLACK octagon. Recorder (Pactblade_chant_record.json) of Tusk Toss: charge finished at 0.78 s = material mode 3460334268 cat 8 + ch00 effect 0/20/10 + sound 4127918784. 4.14-test: rebuke spark / explosion = pb_40_g120 / pb_43_g120 (efxtint of the e285 copies, x0013-PactbladeFx-rebuke2, src efx/pak_rebuke2); the flash (mode 0.6 s, effect, sound) at the cast. pb_rebuke_* (x0012) no longer used.
- 4.14 user: palm = a torch's flame green; no flinch; the on-fire effect green. 4.15-test: torch 13_wp20_000_81_torch_00 baked pb_torch_g120 (catalog-tool efxtint got EFX_ONLY / EFX_SKIP layer filters: inverted f_inv / f_inv0 at hue 300) in x0014; flinch = 30 dmg Hitback_M + OverwriteBlownType 6 + magick, sent BEFORE the burn (burn 0.1 s later); the target's effect requests for 2 s after the burn are noted with container set + files (to bake the green fire). x0013 (40/43 green) for the explosion.
- 4.15/4.16 user: green explosion good; hold the last frame 0.5 s with the flame + super armour (4.16 done); still no flinch (4.16: IsForceReceived + IgnoreBalanceReactionCalc, power 2000). Burn fx trace: 0/10/1, 0/10/101, 1/50/0, 0/20/11 ... from ch30's sets, files nil at request time; ch00/bs/13_ch00_badstatus_* = the human statuses (_15 has a fire texture). 4.17: StatusConditionActionEffectCall.setEffect / ...Endurance.callEffect ActionParam (DataContainerIndex / ProviderID / ElementID) noted for 4 s after a rebuke burn.
- 4.17 user: flinch power 10000 (works), once every 6 s, green fire on the body, a new sound to come (user looking). Trace: no StatusConditionActionEffectCall for the burn; the target's ch00 container 10 effects (0/10/10, 11, 15 ...) = ch00/bs/13_ch00_badstatus_000_<element>. 4.18-test: green copies pb_bs10/11/12/15/16/17_g120 (inv / invv opposite hue) in x0015 (src efx/pak_burn); for 12 s after a rebuke burn the target's container-10 effects get set_Resource(our copy) per player (keeps the joints); cooldown 6 s; react 10000.
- 4.19-test (user sound): hellishrebukesfx.mp3 6.0-8.0 s (Vegas ;FF = frames, 30/s) -> sounds/bank_src/rebuke_mono.wav; build_bank.py got an optional 5th wav = RanSeq 885305127's 2 sounds (trigger 4215563712 -> our 1047135920), rebuilt bank (2-sound rebuild = byte-identical to the old one) -> pak_mods/x0016-PactbladeSounds-rebuke.pak (same sbnk paths as x0005; also copied into sounds/pak_sounds). Rebuke plays trigger 1047135920 with its explosion.
- 4.19 user screenshot: burning = glowing patches ON the body (material) + embers; trace: no 'made green' (players' paths never matched badstatus_000_*). 4.20-test: hr.mat: 0.8 s after the burn the target's mesh float4 colours with hue 5-55 (s > 0.35) are collected (names noted), turned to hue 120 (same s / v, alpha kept) every BeginRendering for 12 s (rim-paint way; failing slots dropped).
- 4.20 user: there are also moving FLAMES on the body. 4.21: 1 s after the burn every via.effect.EffectPlayer within 3 m of the target is noted (name / parent / resource path) + data/Pactblade_burn_fx.json.
- 4.21 user: the scan turned the enemy's HAIR green (1800 'orange' slots: hair, dirt, eyes...); 0 effect players within 3 m (findComponents). The burning = material set Heat_* (Heat_EmissiveColor2 x78, Heat_EmissiveColorGrad x2, Heat_AnimSec, Heat_SeamMaskBlend, Heat_Base_FadeRange). 4.22-test: hr.mat_scan only Heat_*Color* (any hue); user's idea: Debug button 'set ME on fire' (FireSpread on me) -> 1.2 s later my Heat colours (+ a sample value), effect players on my child objects and my effect requests (hr.watch) noted, data/Pactblade_burn_me.json.
- 4.22 user (burn me): the burning look = flames + scorches from the material Heat_* set only: Heat_BaseColor,
  Heat_EmissiveColor1, Heat_EmissiveColor2, Heat_EmissiveColorGrad, Heat_EmissiveColorToAlbedo (x82 materials on me); no
  separate flame effect. Wanted (reference pictures): realistic game fire, green with a yellow / white core.
- 4.23 / 4.24-test: catalog-tool efxtint EFX_HOT=<hue> (brighter original colour -> that hue; weight from luminance, or
  EFX_HOT_BY=v from value for copies already one hue) + EFX_ONLY / EFX_SKIP. Baked 'gy': pb_torch_gy (from the torch,
  inverted f_inv / f_inv0 at 300), pb_40_gy / pb_43_gy (from the e285 copies, by value) -> pak_mods/x0017-PactbladeFx-hellfire.pak
  (src efx/pak_hot, also pak_final). The heat colours: hue 120 -> 62 by the original colour's luminance, every frame for
  12 s; the 'set ME on fire' test paints me too.
- 4.24 user: scorches green (Heat material OK), the FLAMES (orange billowing + embers) unchanged = an effect. 4.25: the burn-me report lists EVERY EffectPlayer component on all my objects (depth 8) with its path (get_ResourcePath / Resource holder) + state.
- 4.25 report: the FLAMES = VFX/Effects/Character/ch00/bs/13_ch00_BadStatus_000_11.efx on the character's object effect_ch000000_00 (path via the Resource holder). 4.26-test: pb_bs10-17_gy (EFX_HOT 62, inv / invv at 300) in x0018 (src efx/pak_burn2); every 0.1 s while hr.mat.go burns its objects' EffectPlayers with badstatus_000_<n> get set_Resource(pb_bs<n>_gy) + Play; heat scan at 0.05 s. Lesson: get_ResourcePath on an EffectPlayer can be nil - read it through get_Resource().
- 4.26 user: flames show ~0.2 s in the original colours, then vanish: set_Resource on the game's RUNNING player kills it. 4.27-test: the game's flame kept running but set_Color alpha 0 (every 0.1 s); our pb_bs<n>_gy on our own GameObject parented to the flame object's parent (the character), placed / turned like it every 0.1 s; destroyed when the game's flame player is gone or the 12 s window ends. Lesson: never set_Resource a running game EffectPlayer.
- 4.27 user: still orange; trace: our copy existed (pb_bs11_gy on Pactblade_hellfire) but showed nothing - the game's flame emits from the body mesh via the character's effect manager (no binding getter); alpha 0 every 0.1 s didn't hide it. 4.28-test: no copy; the game's flame players (badstatus_000_<n> on the burning object) set_Color(tint 0.45 / 1.0 / 0.25) EVERY BeginRendering for the window; tint sliders.
- 4.28 user: the tint works but washed out. 4.29-test: hr.swap_flames(go, on): the burning character's ObjectEffectManager2.ExternalDataContainers[i]:getStandardData(10):getElementFromID(10/11/12/15/16/17) (EPVStandardData.Element = ProviderData) getResources(i) badstatus_000_<n> -> setResources(i, pb_bs<n>_gy holder) BEFORE the burn starts (enemy + burn-me test), restored 2 s after the window; the tint = an old option (off). Unknown: whether this element data is per character or shared by all of its kind.
- 4.29 trace: '0 flame file(s)' - not under getStandardData(10). 4.30-test: hr.each_fx_data walks every ExternalDataContainer's StandardDataMap._entries (key -> EPVStandardData -> getElementIDList -> getElementFromID -> getResources); swap_flames searches all of them for badstatus_000_<n>; Debug button 'dump my effect data' -> data/Pactblade_fx_data.json + badstatus lines in the trace.
- 4.30 dump: 1531 standard elements on me, none with a badstatus file. 4.31: hr.each_fx_data also walks ExternalDataContainer.ExpertProviderInfoList[i]._Data.Elements (expert providers); the swap + dump use it.
- 4.32 trace while burning: 19 external sets (ch00..ch09 ns/cs Ref) + the manager's OWN DataContainer VFX/Effects/Character/13_chcm_pl_Ref.pfb (data in ObjectEffectManagerBase.StandardDataMap / ExpertProviderInfoList). 4.33: hr.each_fx_data walks the manager itself (index -1) + every external set; swap + dump use it.
- 4.33 user: a pale green WHOLE-BODY glow, no flames. Trace: the burning look sits in the manager's own set 13_chcm_pl_Ref as EPVExpertBodyEffectData (badstatus 10-12 / 15-17 fire, 20-27, 40-45 = other statuses); 15 swapped (incl. missing pb_bs20+ copies). 4.34-test: swap only 10/11/12/15/16/17; tone 'gy2' (EFX_HOT 62, inverted layers NOT flipped; x0019, src efx/pak_burn3) default, 'gy' selectable; each swap noted.
- 4.34 user: gy2 = the GOOD hellfire flames (gy had green AND purple flames). DONE for human enemies / me. Lesson: the 'inverted layers get the opposite hue' rule is NOT universal (SkyDive yes, bad-status flames no) - bake both, compare. Monsters may use other burn files (VFX/Effects/Common/BadStatus/13_Cm_BadStatus_100_xx in their sets) - not covered yet.
- 4.34 user: green on ME (test), enemy ch230004_05 still orange - trace '0 flame file(s) of it'. 4.35-test: rebuke window skips direct damage (IsDirectDamage = status ticks; logged 'a tick / direct damage - no window'); on 0 swaps the enemy's effect data is dumped automatically (data/Pactblade_fx_data_enemy.json + manager / own set / badstatus lines in the trace).
- 4.35 dump: enemy humans (ch230004_05) = own set VFX/Effects/Character/13_chcm_em_pl_Ref.pfb, fire = Common/BadStatus/13_Cm_BadStatus_100_10/11/12 (body effect, same layers as ch00 000_10-12; 100_20-22 = something else, kk/sk smoke). 4.36-test: baked pb_bc10/11/12_gy2 (x0020, efx/pak_burn4), swap matches both. Tick filter: check trace for 'a tick / direct damage'.
- user: Cyclops ch250000_00 (own set ch50/13_chcm_em_L_ch50_000_Ref) green scorches, orange flames. 4.37-test: large-monster fire = Common/BadStatus 101_10-14 -> pb_bl10-14_gy2 (x0021, efx/pak_burn5); swap matches ch00 000 (bs), cm 100 (bc), cm 101 (bl). Needs a restart for x0020 + x0021.
- 4.37 user: bandit OK; cyclops / griffin / another bandit orange; stuck in the rebuke pose longer once (cyclops). Trace: those casts had NO swap - the restore of the earlier (dead) target threw (getComponent on its GO) and aborted the swap. 4.38-test: restore without the GO, own timer hr.resUntil (14 s), errors noted; the window notes its hit (dmg/type/react...) to tell real attacks from a burning neighbour's 1-s ticks (cyclops 114-117 s, IsDirectDamage false); clip hard cap frames/(fps*speed)+hold+0.6 s + end noted. Rebuking an enemy that is ALREADY burning keeps its running (orange) flame.
- 4.38 user: GOOD - green flames on bandits (several in a row), cyclops, chimera. Clip ends after 1.25 s normally. Hit kind fields read 0/-1 in the calcDamageValue PRE hook (not filled yet) - to tell burning-neighbour ticks apart, read them in the post hook or another hook. Chimera ch254000 opened the window ~every 0.27 s while near it.
- 4.38 SAVED (user: 'good for now'): versions/Pactblade-4.38-SAVE-HellishRebuke-done.lua. Hellish Rebuke done; open: burning-neighbour hits opening the window (optional).

## TASHA'S OTHERWORLDLY GUISE (user idea 2026-10-25)
Spec (user): cast like Caustic Brew (same chant, animation, effect); lasts 60 s; 50 % stamina. A see-through purple ghost
of an armour (chest + legs) hovering over my own, ~+15 % size (tune). Bonuses: immunity to fire + poison (damage and
statuses), +10 % physical + magick defence, Sorcerer's Levitate. Colour = the user's reference (vivid violet, ~hue 268).
Armour: chest Grand Cuirass (item 5012, Tops_015: Wb tops_039, Am/Bd/Bt tops_015) - also try Allegoric Plate (10401,
Tops_401) / Kibisis Coat (10402, Tops_402); legs Raptor Claws (6009, Pants_012) / Brutal Cuisses (6012, Pants_015).
Visuals first.
- 4.39-test (visual test, Skills menu 'Otherworldly Guise (visual test)'): the AfterImage clone (ai.handler) on me every
  LateUpdateBehavior (position / rotation / scale, every joint's local pos+rot copied from mine), motion off; dress():
  the style's parts from CharacterEditManager _TopsDB/_PantsDB[Male][style] -> catalog pfb -> Character/_kit/_equipment/
  <kind>/<num>/<base>.mesh/.mdf2 (setMesh / set_Material on the clone's part meshes, same-named part or a spare part),
  every other part + the body hidden, the style's PartsEnable groups once loaded, then the ghost material mode (Basic) +
  RimLight colours painted in the hue (BeginRendering). Restored on the end. ai.warp skips while the guise has the clone.
  Probe button -> data/Pactblade_guise_probe.json. DragonCore 1.2.5 + new VSB installed by the user (API calls checked).
- 4.39 CRASH (show guise): right after 'dressed ... TopsBd->head ...' (native, updateStandGimmick/vec3 frames). Cause (likely): a body mesh on the clone's head part (own skeleton). 4.40-test: spares only Tops*/Pants*/Underwear/Mantle*; each step noted before it runs; body hidden after loading. RULE: never put a body-skeleton mesh on the head / hair / helm part.
- 4.40 user: only the clone's hair (raised) showed; crash on 'end' (setMesh restore). Trace: meshes never MeshReady (hand-made MeshResource swaps). 4.41-test: no mesh swaps - the clone's own app.PartSwapper (CloneCharacter.get_PartSwapper) _Meta._TopsStyle/_PantsStyle = ours + requestSwap(Parts.Tops/Pants) (the game builds the parts, as for the transmog); wait (<= 3 s) for _Tops*Obj/_Pants*Obj meshes ready, then every other mesh on the clone off, ghost mode + purple. End: styles back + swap, meshes on, finish. Every step noted first. Probe (4.40): Allegoric = tops_400 wb/am/bd; Kibisis = tops_400 wb/am/bd + tops_004 bt; Raptor = pants_015 lg + pants_035 lg(sub); Brutal = pants_015 lg.
- 4.41 user: worked ONCE (armour on top, scaled up); later tries: naked clone + cape for a split second, then nothing. Trace: 'loaded true' at 0.4 s = the OLD parts. 4.42-test: gu.wanted_ready = each wanted slot's _<Slot>Obj mesh path contains the wanted mesh + MeshReady (max 5 s); gu.keep every 0.25 s (wanted on, the rest off; glow colours refound when parts come back); status line each s (inst Status, DrawSelf).
- 4.42 user: show does nothing - trace 'afterimage still busy' (clone left InProcess, likely the script reset mid-guise). 4.43-test: InProcess + not ours -> handler finish(), retry 0.6 s later (max 2); styles to restore = the PLAYER's PartSwapper _Meta.
- 4.43 user: first time nothing, then a ghost of ME for a split second, gone (status 0 = None; StatusType low bits: None 0, Appear 1, Disappear 2, Operating 4, Sleeping 8). User hint: MSP DLC Bataille Twinne (job07_skill_04_TU, shade fights for a while) - app.AfterImage has IsMirageDance / IsForceContinueMirageDance / MirageDanceTrack. 4.44-test: gu.alive pre+post LateUpdateBehavior: IsEnd/IsMotionEnd false, IsForceContinueMirageDance true, EndTimer _ElapsedFrame 0 / _IsFinish false; fresh-clone + per-second state lines.
- 4.44 user: 1st show = purple Grand Cuirass ghost, good look, but BESIDE me (~1.5 m) and no legs; later shows = my own outfit (teal) for a split second. Status is 0 even when it works (not the issue). Cause of the later ones: the end's back-swap only runs when the clone runs again (= the next show). 4.45-test: ending phase (clone kept running hidden until no wanted mesh is left or 2 s, then finish; all meshes re-enabled); Hip onto my Hip in x/z (damped fix, noted); per-part on/off + visible groups noted.
- 4.45 user: same (1st OK, later only my outfit for a split second); trace identical for good + bad shows (parts in place, hip 0). Theory: start() after a finish makes a NEW Instance, we dress the old. 4.46-test: handler get_Instance checked every frame, a new one -> switch + dress from step 0 (noted with addresses). IsForceContinueMirageDance = backing field (Lua error fixed).
- 4.46 user: same; trace: the SAME instance each time -> not a new clone. Theory: the game's finish() leaves the clone fading (disappear) for later starts. 4.47-test: the end PARKS the clone (hidden, kept alive by gu.alive, on me) instead of finish(); the next show reuses it (no init/start); 'release the clone' button = the real finish (warp afterimages get it back; they're skipped while parked).
- 4.47 user: PARKING WORKS (every show OK) -> the cause = the game's finish()->start() cycle; final: Guise gets its OWN fresh clone per cast (warps keep theirs). But the ghost material NEVER applied (solid armour). 4.48-test: gu.ghost: CloneCharacter.setupMaterialInterpolation() + (via.GameObject) per armour part, finishMaterialMode(Basic, 0), requestMaterialMode(Basic, null), colours refound; button 'redo the ghost look'. Collar in front of the mouth (Grand Cuirass) = later (mesh groups).
- 4.48 user: ghost look never applies; trace: _MaterialInterpolationSettings null (mode = nothing). 4.49-test: gu.ghost also plays Mirage Dance cs_010_00/20 (ours pb_ai*_h<hue>, ai.play_fx: the 'MI' material-switch layer = the warp ghost look) on the clone; anchors kept in gu.fx (not ai.anchors); replayed when one goes Idle (checked every 0.25 s); finished at the end/park.
- 4.49 user: colour applies (chest purple, legs teal), NOT translucent, purple cloud + black pulsing distortion. 4.50-test: gu.ghost + requestBodyEffect() (checkbox, on) / requestStartEffect() (off); 'ghost effects' combo (el 0 default / 20 / both / none); glow colours refound every 2 s.
- 4.50 user: Mirage Dance element 0 = no black distortion; purple cloud stays (user likes it); still NOT translucent. 4.51-test: 'list the armour's material variables' (data/Pactblade_guise_matvars.json + see-through candidates by name) + 'see-through test' slider written each BeginRendering to every candidate float.
- 4.51 user: see-through test did nothing. Material vars (262, data/Pactblade_guise_matvars.json) include the ILLUSION set (Illusion_Enable/_AlphaRate_Front/_AlphaRate_Rim/_FadeRate/_RimAlphaGrad/_NoiseBlend/_Noise3d*/_VertexNoise3d*) + DitherFadeRate/DitherFadePosY*/RimDither*, DissolveRate, Translucency. 4.52-test: gu.ill sliders, index by name hash, written each BeginRendering on all armour materials; originals noted.
- 4.52 user: TRANSLUCENCY FOUND - Illusion_FadeRate is the main control (0 = invisible, 1 = still not fully solid); DitherFadeRate also fades (at FadeRate 1, Dither 0 = invisible), does nothing when FadeRate is 0. Default fade now 0.6 (user to pick).
- user: visibility order Illusion_AlphaRate_Front > Illusion_FadeRate > DitherFadeRate (Front is the strongest see-through control).
- 4.53-test (user): Illusion_FadeRate for the legs (Pants* parts) separately ('legs' slider); defaults fade 0.6 / legs 0.6.
- 4.53 user picked the look: Enable 1, Front 0.25, Rim 0.80, Fade chest 0.30 / legs 0.38, RimAlphaGrad 1, Noise 0, Dither 1; lasts 36 (test); width 1.10 / height 1.04 / depth 1.06; hue 269 / sat 0.81 / glow 1.90; Mirage Dance element 0 + body effect on, start effect off = DEFAULTS. 4.54-test: OWN clone: app.AfterImageHandler .ctor + setup(Human, via.Prefab = shared handler get_Prefab()._Item) + create(), wait for Instance (updateClone after 0.5 s, 3 s timeout -> shared fallback); parked between casts, never finished; the warps keep the Job07 handler (ai.guise only when the shared one is used).
- 4.54 CRASH on show: own AfterImageHandler (.ctor + setup(Human, Prefab) + create) -> app.PrefabInstantiateMediator.execInstantiate. RULE: never make our own CloneCharacterHandler. 4.55-test: 'clone source' combo: shared Job07 afterimage (default, works) / TRICKSTER DECOY (Human.<Job09ActionCtrl>.<DecoyHandler>, game-made; create() on it only if no Instance; test). Also: AstralBodyHandler exists there too.
- 4.55 user: TRICKSTER DECOY WORKS (its start effect on applying looks cool - keep), but a health bar shows. 4.56-test: gu.no_ui = every via.gui.GUI in the clone tree off (at the show + every 0.25 s), names noted.
- 4.56 user: the decoy ended itself later (its end effect after the guise; the bar = its time). 4.57-test: gu.alive also for the decoy: <ElapsedSecond> 0, <IsDie>/<FinishDamage> false each frame (pre+post LateUpdate), clearHate() each s.
- 4.58-test: 'test: the ghost 3 m to my side' (enemy interest test; hip fix paused).
- 4.58 user: enemies do NOT target the decoy ghost (side test). 4.59-test: gu.kind (after/decoy) - AfterImage-only fields (IsEnd, EndTimer, RootMoveScale, Basic material mode, body effect) only on an afterimage; decoy fields only on the decoy (Lua error gone).
- 4.59 user: no bar, no late end effect; WARP AFTERIMAGES gone even with the guise off (ai.guise stuck true); decoy start effect gone (parked = no start) - wanted; legs teal for a split second. 4.60-test: ai.blocked() live (guise on/parked/ending AND the shared clone) replaces the flag; requestStartEffect at every show for the decoy (startFx on); glow colours every 0.25 s for the first 3 s.
- 4.60 user: warp afterimages work with + without the guise, start effect back, teal flash gone = GUISE VISUALS DONE. Saved versions/Pactblade-4.60-SAVE-Guise-visuals.lua. Next: the real skill (Caustic Brew cast, 60 s, 50 % stamina), then bonuses (fire + poison immunity, +10 % phys/mag def, Levitate), other armours, Grand Cuirass collar (mesh groups).
- user: Guise skill slot = Perfect Defense / Divine Defense (Job01_DivineDefense, shield skill -> usable without a shield); defence bonus +20 % (not 10); defence + fire/poison immunity must SHOW on the character status screen (= real stat changes, not only damage hooks). 4.61-test: the skill: press (processCustomSkill / requestActionCore Job01_DivineDefense skipped; HumanSkillAvailability yes for my character) -> gu.prepare (decoy) -> Caustic Brew's chant (castT, brew castSecs) -> release: 50 % of max stamina + gu.show (60 s; recast renews). Menu 'Otherworldly Guise' (skill on / lasts / stamina).
- 4.61 user: skill works without a shield, chant OK, stamina OK, recast OK - but NO ghost armour. Cause: the skill's press flag reused gu.want (= the wanted-parts table) -> parts list wiped. 4.62-test: flag renamed gu.castWant.
- 4.62 user: armour barely visible (gold specks) from the cast AND the button (log normal). Theory: the decoy start effect (each show since 4.60) leaves it part-DISSOLVED. 4.63-test: DissolveRate held at 0 each BeginRendering (slider).
- 4.64-test (user: the purple cloud weaker + 70 % speed): our Mirage Dance players get set_PlaySpeed 0.70 + set_Color(b,b,b, alpha 0.50) once at the start and again only when a slider changes (not every frame); sliders speed / see-through / brightness.
- 4.64 user: armour NOT there at all (button + cast), cloud sliders do nothing. Log: parts on, values written. 4.65-test: decoy <TemporaryHidden> false + DrawSelf on clone + wanted parts every frame; per-second line + clone draw/hidden/distance, each part draw + distance, our cloud players' state/speed.
- LIKELY CAUSE of 4.62-4.64 'no armour': script resets only - the decoy clone survives a reset still running; the next show finish()ed + restarted it (= the look-breaking cycle). 4.66-test: a running clone (decoy / shared) at show time is ADOPTED as parked, never finished.
- 4.66 user: look GOOD again; cloud = speed 0.70 / see-through 0.20 / brightness 0.52 (defaults), wants it pinker/brighter. 4.67: cloud tint r/g/b (1.8/1.2/0.9) on set_Color. User: a sound keeps playing after the guise ends. 4.68-test: at the end the clone's finishStartEffect / finishBodyEffect + decoy smoke finishes (Possession/Recover/Transfer/FocusAim...) called.
- 4.68 user: sound STILL plays after the guise; cloud tint 3.79/0.34/1.82 = defaults. 4.69-test: gu.hush = each sound container (app.WwiseContainerApp / soundlib.SoundContainer) on the clone tree: PlayingRequestIdDict ids -> SoundManager.stopEventByRequestId(go, id, 0); at the end + each s for 5 s while parked.
- 4.69: SoundManager no singleton (-1); 4.70-test: its static stopEventByRequestId via the type's method (call(nil, ...)); containers / playing counts noted.
- 4.70 user: the leftover sound STOPS now (static stopEventByRequestId on the clone's containers). Guise SKILL + look DONE: saved versions/Pactblade-4.70-SAVE-Guise-skill.lua. Next: bonuses visible on the STATUS SCREEN: +20 % defence (phys + mag), fire + poison immunity (damage + statuses), Levitate.
- 4.70 user: sound stops now but no longer plays when cast (from the clone's first start only). 4.71-test: soundlib.SoundContainer trigger(UInt32) / trigger(SoundTriggerInfo) / createRequestInfo(SoundTriggerInfo,...) hooks record trigger ids on the clone GO for 3 s after its first start; replayed (trigger(UInt32) on its container) at every parked show. Needs a game restart (fresh first start). Status-screen research: armour items carry _FireResist/_PoisonResist (ItemArmorParam / EquipParam); app.PlayerAttackDefenceStatus.ArmorParam (EquipParam: _PhysicalDefence, _MagicDefence, _FireResist, _PoisonResist, ...) = likely the status totals.
- 4.71 user: guise sound good. 4.72-test (bonuses, status screen): post-hooks app.PlayerAttackDefenceStatus.updateDefenceParameters / updateStatusConditionResistParameters (calc.CharaID == mine): AdditionalDefence/AdditionalMagicDefence += 20 % of get_Defence/get_MagicDefence; StatusDamageRegist[1,7,5] and <ElementResistFactor>[Fire 1] = 1.0 (scale unknown - noted before/after); recalc count noted.
- 4.72 user: status screen unchanged, sound gone again (triggers only in memory). Trace: resist hook OK (0..1 scale; poison 0, burning 0.03, fire factor 1.0), defence hook silent, recalcs every frame. 4.73-test: triggers saved/loaded (data/Pactblade_guise_sounds.json); app.PlayerStatusCalculator.calcAttackDefenceWithEquipmentAndBuff (both) post -> bonus on the returned status; calcStatusConditionResistWithEquipmentAndBuff(enum) post -> 1.0 for 1/7/5, (param) post -> arrays; errors noted; no-pile-up guard on AdditionalDefence.
- 4.73 user: sound back; NO defence change. Trace: only the screen's resist-list hook ran; neither defence hook. 4.74-test: my status objects remembered (in-game + calculator results); PlayerBasicAttackDefenceStatus.get_Defence/get_MagicDefence post: mine + guise -> x1.2; counters for calcBasicAttackDefence / getters / calc hooks noted.
- 4.74 user: no change on the status screen; user: the 0.35 magick sword showed on it -> ITEM DATA route. 4.75-test: gu.armour_bonus: ItemManager.getEquipData(character).Data:get(Upper=3)._ItemId -> getItemData(int) (ItemArmorParam): _PhysicalDefence/_MagicDefence += 20 % of my total (in-game status get_Defence/get_MagicDefence), _FireDefence/_FireResist/_PoisonResist = 100; applyEquipDataForCharacter(); restored at the guise end + script reset. Getter/calculator defence adds off (viaGetters false). Caveat: item data is per item TYPE (a pawn wearing the same chest gets it too while on).
- 4.75 user: no change on the screen; trace: the chest ItemArmorParam DID change (def 416->666, mdef 294->470, fire/burn/poison 0->100). 4.76-test: gu.equip_refresh = EquipData.updateEnhanceEquip(StorageData) + EquipData.calc() + applyEquipDataForCharacter() + (Character); _EqParam totals noted; 'cnt' nil bug fixed (gu.bcnt).
- 4.76: add_ref nil (data/sd value objects) -> item changed, originals not kept, never restored. 4.77-test: keep() safe; originals per item id saved once in data/Pactblade_guise_items.json (from the untouched item, restart first) and always restored from there.
- 4.77 user screenshot: ALL equipment stats doubled (EquipData.calc() adds onto the totals; the screen reads EquipData._EqParam - proven). RULE: clearParam() before calc(). 4.78-test: clearParam + calc, updateEnhanceEquip dropped, totals before/after noted. User told: restart WITHOUT saving.
- 4.78 user: status screen GOOD (def 1526->1776, mdef 1340->1516, fire res 43->143 %, burning -3->103 %; magick 1482 + thunder = Pactblade's sword passive showing after the refresh). 4.79-test: +20 % of base (<BasicDefence>) + _EqParam (minus any of ours) = 1526 -> ~1831.
- user: the guise timer runs on in menus. 4.80-test: paused (GuiManager isPausedGUI / TimeManager get_IsTimeStop / frame gap > 0.25 s) time added to gu.t0; menu line 'left: N s'.
- 4.80 user: status screen bonuses GOOD (def 1723 / mdef 1506 shown; poison 100 % ours, frostbite was 100 already). 4.81-test: LEVITATE while the guise is on: in the air (not grounded, dbg.air_ok), Jump held 0.25 s -> a:request_action('Job03_Levitate', 0) once per jump; action noted 2 s.
- 4.81 user: no float (Job03_Levitate request 'true' but the action stays ForwardJump). 4.82-test: OUR levitate: jump held 0.25 s in the air -> post LateUpdateBehavior: height ours (rise 1.5 m/s to +2.5 m, held), x/z = game's air control, CharaController warp; ends on release / 4 s / no stamina / ground; 60 stamina/s; sliders. Animation: user to find the Mage levitate (AnimPlayer).
- user AnimPlayer: JobMagicUser_StartLevitate bank 3/5010 (172 f), _KeepLevitate 3/5000 (296 f), LandingToRun 0/405. 4.83-test: levitate animation on the FullBodyLayer each UpdateMotion (start once, keep loop, 60 fps); bank = 3 if present else Mage motlists loaded as dynamic banks 9113 (ch00_006_com) / 9114 (ch00_006_comnm), whichever has 5010+5000 (noted); loaded at the guise start.
- 4.83 user: levitate FEELS + LOOKS good (Mage anims); landing = sudden fast fall. 4.84-test: gu.lev_calm each float frame + at the end: Character.SecFall 0, FreeFallCtrl.Frame 0 + InitialFrameSpeed.y 0, FallInfo resetBaseHeight/resetFallHeight.
- 4.84 user: landing good. Bolt usable mid-float -> 4.85-test: any non-jump/fall action ends the float (calm fall; the bolt plays its normal air version, then I fall); a float starts only from a jump / fall action.
- 4.85 user: flying not working - trace: floats 'ended (ground)' after 0.2-0.4 s (per-frame FallInfo reset reads as landed). 4.86-test: per frame only SecFall/Frame/speed y, FallInfo reset at the end only, ground ignored the first 0.5 s.
- 4.86 user: still not good -> 4.87-test = 4.84 (user-good levitate) + the vocation button ignored while gu.lev.active (no Eldritch Bolt while levitating). 4.85/4.86 dropped.
- 4.87 user: after the guise wore off + recast no visual effects; next recast plain oversized armour + distortion/dithering on me; float after an air Onslaught keeps the air-slash anim. Trace: hush stopped 228 ids (stale dict slots) each time. 4.88-test: no finish*Effect at the end; hush only valid entries (hashCode >= 0); float from a non-jump/fall action -> request NormalLocomotion first.
- 4.88 user: after an air Eldritch Blast + a pawn catch (Caught_CatchAndRelease) the look was gone (bonuses on); a recast didn't bring it back (renew = timer only). 4.89-test: watchdog in the keep step (styles + wanted meshes; lost > 0.5 s -> noted + restyle + step 1 again), state line every 5 s, a recast re-dresses + redoes the look.
- 4.89 user: pawn catch removes EVERYTHING (trace: clone drawn, look kept -> suspect: the hip fix pushed it away while carried); recast = solid armour + shimmer (rebuilt parts w/o illusion). 4.90-test: hip fix capped 0.5 m + paused while my hip > 1 m from me; illusion + colours re-found every 1 s the whole guise; state line + distance/fix; LEVITATE STEERING: float x/z ours (stick_yaw x 5 m/s x stick strength, facing it; none = in place).
- 4.89 user: pawn catch removes EVERYTHING (trace: clone drawn, look kept -> suspect: the hip fix pushed it away while carried); recast = solid armour + shimmer (rebuilt parts w/o illusion). 4.90-test: hip fix capped 0.5 m + paused while my hip > 1 m from me; illusion + colours re-found every 1 s the whole guise; state line + distance/fix; LEVITATE STEERING: float x/z ours (stick_yaw x 5 m/s x stick strength, facing it; none = in place).
- 4.90 user: flying GOOD (steering). Pawn catch still removes the look; the purple cloud STAYED next to the pawn; recast = solid armour + shimmer. Trace: clone 0.00 m from me, look kept. 4.91-test: SmokeDecoy own reactions skipped for our clone (onOwnerDamageReaction, onOwnerCalcDamageEnd, onDamageHit, onCalcDamageValueDefenseHandler, fail*Smoke, releasePossesion, setStay, setTarget*, hitHealingSmoke) - noted once each.
- 4.91 user: the look STAYS through 2 pawn catches (the decoy's own reactions were the cause). Saved versions/Pactblade-4.91-SAVE-Guise-bonuses-levitate.lua. Guise = skill + look + status-screen bonuses + levitate (steering) done. Open: fire/poison damage immunity check, other armours, Grand Cuirass collar.
- 4.91 user: Guise good ('we are good'). Timers in menus (user): dbg.gclock() = os.clock minus paused time (GuiManager isPausedGUI / TimeManager IsTimeStop / frame gap > 0.25 s); 4.92-test: Hellish Rebuke's green-fire timers (hr.mat / M.*, hr.watch, resUntil, fxScanAt, fireConts) + its 6 s cooldown, and Hex's duration on dbg.gclock(); the rebuke WINDOW (0.5 s), hand flame and clip stay real time (user: the window works, leave it).
- 4.92 user: after the guise enemies didn't target me; the decoy start effect played MANY times (every ~0.1 s for 1-2 s) at start + end. 4.93-test: decoy AttensionTimer 0 + IsTargetResistered false every frame (on + parked), its via.physics.Colliders / RequestSetCollider / CharacterController off once per clone (component names noted); setTarget / setTargetFromDamageInfo / setStay no longer blocked.
- user (4.92): with the guise on, after a few enemy hits the decoy start/end effect repeats every ~0.1 s + the look goes (bonuses stay) = the decoy ending itself, revived by gu.alive, again. 4.94-test: blocked for our clone (unless gu.releasing): SmokeDecoy.finish, CloneCharacter finish/vanish/sleep/requestEndEffect/triggerEndSE, CloneCharacterHandler<SmokeDecoy> + DecoyHandler finish/vanish; counts + first block noted.
- 4.94 user: 1. look stays through hits OK; 2. enemies still don't target me after the guise; 3. catch later. 4.95-test: the decoy RELEASED at the end (handler finish; unregisters?) instead of parked (option 'park the decoy'); a cast while it's still ending waits (retry 0.5 s, no adopt); status-object marking off (leak).
- 4.95 user: GOOD (decoy released at the end: enemies target me after the guise, the look right on the next cast). User: reticle dot with the weapon drawn (since Smite days; suspects Archfey Combo's Archer opener). 4.96-test: app.Player.drawReticle skipped for my player while Pactblade is on (dbg.noReticle), first call noted (action, combo used before).
- user: the reticle dot = VSB's own 'Crosshair' option (off / weapon / always; DragonCore aim.draw_dot), set to 'weapon' - not Pactblade, not the game reticle. 4.97: the drawReticle skip off by default (dbg.noReticle false).
- 4.97 user: the look stays through a pawn catch with the decoy release (4.95+). GUISE FINAL saved: versions/Pactblade-4.97-SAVE-Guise-final.lua.
- user decisions 2026-10-25: Warfarer switch with the guise on = fine (not tested further); Fighter's stat growth (VSB has no level growth yet); icon: user picks in VSB's vocation editor (Open vocation editor > Pactblade > Choose an icon > Pick by picture); my skill descriptions approved; release = no sliders / debug. 4.98-test: SAVE + ONLINE GUARD ported from Dragonforge (save steps + online builders -> sword_restore + guise chest plain, dbg.guardHold stops the sword re-apply; back after the outermost, never during a save); a note per strip.
- user: black screen at the title 'select save data to load' (hang, not a crash; the crash log was Alt+F4) - happened before too, also with 4.97; workaround: load the latest autosave, back to the title without saving, then the load list works. Not the 4.98 guard. Suspects: VSB savesafety (requestLoad / save sidecar hooks), another mod. Isolation test pending (untick Pactblade / VSB).
- 2026-10-25: the title 'select save data to load' black screen = DD2MethodLibrary.dll (user: off -> works, Pak Bridge fine). Needed by RampartNox (MethodLibrary.prefab_set_path) + NickCore FX. User checks the plugin's newer version; fallback: RampartNox with a direct set_Material swap (no plugin).
- 4.99-test: SKILL NAMES + DESCRIPTIONS in the game menus (VSB text.lua's hooks ported): name message GUIDs of all 12 Fighter skills (+ lv2 / DLC) mapped by the current bindings to Pactblade texts (user-approved); Vocation Guild list + info window, status skill list + video panel, Dragonforged list, GUIBase.getCustomSkillName, HUD palette; only while Pactblade is active + the player's menus.
- 4.98 inn test (user): GUARD WORKS (trace: save + updatePlaydataFromCharaEditData/PawnData/OwnerData/SystemData + makeToUploadValidationWork, all with sword + chest plain); user: resting should END the guise. 4.100-test: BarRoomTimeSkipStateBase.onBarRoomTimeSkipBeforeRestart/onBeforeRestart (inn) + CampStateBase.onCampBeforeRestart/onBeforeRestart (camp) -> gu.stop('rested').
- 4.100 user: HUD palette renamed; equipped slots partly (Cloudfall Strike = Misty Dive DLC lv not); the equip list none. 4.101-test: name GUIDs of every level from CustomSkillDefineDictionary[id][lv]._SkillName; guild list + getCustomSkillName by skill ID (info.Id) - VSB's way.
- 4.101 user: guild list + info window CORRECT; one equipped slot still 'Cloudfall Strike'. 4.102-test: GUIBase.getCustomSkillName(JobEnum, id, lv) hooked (by id); GuiManager.getExCustomSkillName noted when asked for ours.
- 4.102 user: equipped slot still 'Cloudfall Strike' (no EX lookup). 4.103-test: T.retext(root) after setupEqSkills x2 / updateDispSkillEqList / setupCustomSkillInfoWindow: every via.gui.Text in the guild screen -> ours by message id or by the English vanilla name (VANILLA table).
- 4.103 user: ALL names gone - my bug: VANILLA defined after map() (nil inside it -> map errors -> every rename failed). 4.104-test: VANILLA before map().
- 4.104 user: ALL skill names show correctly (guild list, info window, equipped slots incl. Misty Dive's DLC level, HUD). Saved versions/Pactblade-4.104-SAVE-skill-names.lua. LESSON: lupa load() only checks syntax - a table used before its 'local' line is a nil global at run time; define data tables BEFORE the functions that use them.
- user picked the VSB vocation icon #46 -> pack.json vocation.icon = 46 (game data + source copies).
- 2026-10-25 SAVED the takeover build as builds/PactBladeVSBBase (lua 4.104, VSB pack, paks x0004-x0021) + versions/Pactblade-4.104-PactBladeVSBBase.lua. User: rebuild = PactBladeVSBIntegrated (own VSB skills, Fighter skills untouched); work copy src_integrated/Pactblade.lua.
- i-0.1-test (PactBladeVSBIntegrated): 8 VSB skills in the pack (skills/pb_*.json: fixed uuid5 ids, rank 1, 0 DCP, icons = Fighter skill numbers (guess), placeholder timeline = a script node 'return true'); Lua (src_integrated): ADAPTER right after 'local live' (first processCustomSkill hooks, both overloads): a press of a VSB id (idtable.json ids.custom[uuid]) -> args id = the bound Fighter id, dbg.pbDepth++ for the call; every trigger hook gated with dbg.press_ok(); name takeovers off; shield availability only during a translated press; menu text hooks off. Menu line 'VSB skills: n / 8 ... presses'.
- i-0.1 user: only Misty Dive + Eldritch Blast worked (smite/slash/brew/combo: nothing in the trace at all); a CRASH opening the vocation/skill window after learning them (suspect: 1-level 0-DCP skills = VSB maister skills). i-0.2-test: skills get 2 levels (rank 1, 100 DCP each); adapter notes EVERY press of an id >= 100 (path, known) + each translation.
- i-0.2 trace: ALL presses come through processCustomSkill(Action, id, ...) ('action' path), all 8 translated; only the 4 with a shield-availability yes (dive/blast/strike/guise) went on. i-0.3-test: the adapter answers HumanSkillAvailability isCustomSkillAvailable(+WithoutItemCondition) = yes for the translated Fighter id (A.lastFid) during a translated press, my character only.
- i-0.3 user: ALL 8 VSB skills WORK, no crash with the 2-level skills. Saved versions_integrated/Pactblade-i-0.3-SAVE-all-8-work.lua. Open: air variants (Misty Dive / Eldritch Blast / Misty Strike from the air), a real Fighter skill = vanilla, icons, remove the now-unneeded slot-binding UI / text hooks / takeover code for the release.
- user's skill icons: slash 5, smite 35, blast 36, combo 39, dive 40, strike 30, brew 7, guise 38 (pack + game copy).
- user: Eldritch Blast icon = 6 (not 36).
- user: icons Misty Dive 10, Misty Strike 0, Archfey Combo 9.
- i-0.4-test (user): Misty Strike recovery: speed x1.7 from frame 150, any attack/skill/jump/vocation/dash press from 150 ends it, cut at 235 (sliders); the Tasha chant (castT, MotionFsm2 paused = hidden super armour) is cancelled by a damage reaction request (Dmg*/Caught*/Down/Blown/Slam) for me, which then plays.
- i-0.4 user: chant interrupt GOOD; Misty Strike sliders no visible change (the game ignores layer speed / refuses NormalLocomotion mid-action). i-0.5-test: faster = set_Frame(fr + dt*60*(fastSpeed-1)) each update; cut / input cancel = set_Frame(endF - 1) + request.
- i-0.5 user: cancel works, a bit early + a weird pose reset (snap to the last frame). i-0.6-test: cancelFrom 170, the end = changeMotion crossfade to the last frame (endBlend 8 frames, slider).
- i-0.6 user: Misty Strike recovery FEELS GOOD (defaults 150 / x1.7 / cancel 170 / end 235 / blend 8). Chant interrupt by hit reactions GOOD. Saved versions_integrated/Pactblade-i-0.6-SAVE-strike-recovery.lua.
- i-0.7-test (user): Dimension Door 0.8.5 as a Pactblade feature: module autorun/Pactblade/DimensionDoor.lua (built by src_integrated/build_dd_module.py from dimension-door/versions/DimensionDoor-v0.8.5.lua): only while live.on (option all vocations), menu 'Dimension Door' in Pactblade's menu (on/off, key rebind, range, door time/look), config Pactblade_DimensionDoor.json (first run takes the standalone's key/range/time/look). Combo hold Vocation + Go! cancels Eldritch Bolt's charge (M.block: aiming / arrival / combo until release). Aiming camera: joint offset up 0.8 / right 0.6 (blend 0.3/0.4 s). Target: pillar of the door's frost shimmer (rings of 3 every 0.45 m, 7 m, no light) + old sparks; sliders.
- IDEA PARKED (user 2026-10-25): Ghostly Gaze (D&D: see through solid objects within 30 ft; creatures stay solid, crates / walls see-through with their outlines visible). User: "just a gimmick", maybe later. Options found: (1) wireframe per object if the release build still has it (not checked yet: search the dump for Wireframe / via.render.Mesh options), (2) fade env meshes within 9 m via material values (probe nearby via.render.Mesh variable names for dither/alpha), (3) hide meshes + draw their AABB outlines as a screen overlay. app.CameraFadeManager = characters only (app.CharacterFade); app.SinkDieReactionController.DitherFader = a mesh dither-fade example (setMaterialValue / setForceAlphaTest).
- (user 2026-10-25) skill unlock ranks + DCP set: brew r1/0, slash r1/300, strike r2/500, dive r3/800, blast r5/1500, combo r7/2500, smite r8/3000, guise r9/4000; level 2 = same rank, 100 DCP (no real upgrades).
- (user) brew level 1 = 300 DCP too.
- 1.0 (2026-10-25) user: eblast.mp3 (Smite) + hellishrebukesfx.mp3 (Rebuke) sounds MAY ship in the release (user's choice: keep both).
- 1.0 RELEASE BUILD (2026-10-25, not published): src_integrated/patch_i_008.py. RELEASE (json.RELEASE: a json wrapper
  that only writes Pactblade.json / guise_items / vsb_pick / guise_sounds / trace) = short menu (Nox, arm effect,
  Dimension Door without test sliders). Review fixes: player filter (live.am) first in all 11 requestActionCore hooks
  (they ran ToString + pcall for every NPC's action request), stamina watcher only while active. Main chunk is at
  200 locals: the DragonCore check moved into a do-block. Paks x0004-x0021 merged (in order, later wins) ->
  pak_mods/Pactblade.pak (136 files, all new paths, no vanilla override; source = pak_release/, names list
  pak_release_names.list). Package release/Pactblade-1.0/Pactblade (modinfo.ini, README.md, Pactblade.lua +
  Pactblade/DimensionDoor.lua, VSB pack 1.0.0, data/Pactblade.json = the user's tuned settings) ->
  release/Pactblade-1.0.zip (also in Fluffy). For a test build set RELEASE = false at the top.
- 1.0 user: freeze when bolting a TEST DUMMY (crash in requestActionCore invoked from Lua; likely DragonCore summon_ai on the summoned enemy). User: keep i-0.7 as the fallback (versions_integrated/Pactblade-i-0.7-SAVE-fallback-before-cleanup.lua), try to fix the current one quickly, else back to i-0.7.
- 1.0 rc2 (2026-10-25): fixes = live forward ref (stamina watcher; it broke LateUpdateBehavior callbacks: beam, slash wave, cloud tint) + ai.ensure (the game's Job07 AfterImageHandler create() when it has no Instance, every 5 s while settled). User test: all good; air blast leaves the MSP haze 13/23/x teal = OLD (i-0.7 too; noTint since 0.93 because tinting it veils the screen) -> fix = a baked purple copy later. Release zip rebuilt.
- 1.0.1-test (user: air blast haze teal): ch07 ns 023_00/01/10/11 (13/23/x, noTint because a tint veils the screen) baked: efxtint hue 285/300/315 (rgb 191,0,255 / 255,0,255 / 255,0,191), inverted layers (inv, inv_h, inv_l_a, inv_l_l, inv_r_a, inv_r_l, inv_s0) at the opposite hue (64,255,0 / 0,255,0 / 0,255,64) -> pak_release/.../pb_ns023_XX_h<hue> (148 files, src efx/haze). Script: dbg.haze block (end of file) swaps them in MY effect data (hr.each_fx_data, setResources, like the rebuke flames) every 2 s while live.settled at md.hue(); back otherwise / on reset. Pak repacked -> release + game x0023. User also: air blast launch effect looks BIGGER than before (to check: which version).
- 1.0.1 (Recorder, user): the air blast's teal = ch00 0/160/0 charge cloud (NOT the 13/23 haze: haze block + its 12 baked files dropped, files go at the next repack); big swirl = 13/20/56. Fix: own effects tinted during bm.stage air too (tint window), bm.airKill {13/20/56} killed although airAnimFx keeps the rest.
- 1.0.1 user: teal gone; big effect = the air launch flash (-1/8/40 copy at the palm, scale 1) -> bm.airLaunch off by default.
- 1.0.1 user: launch flashes of Bolt / Burst also bigger -> our -1/8/40 copy at 50 % (play_ours, dbg.launchScale 0.5), air copy airLaunchScale 0.5. (Open theory: the clone create() may rebuild the Job07 shell params so shape_effects edits a stale copy.)
- 1.0.1 user: launch flash Bolt (charged) + air Blast 30 %, Burst 50 % (play_ours: blast_shell_info(creator).kind).
- 1.0 RELEASE (2026-10-25): versions_integrated/Pactblade-1.0-RELEASE.lua (VERSION 1.0, RELEASE true; incl. the live fix, warp-clone create, air-blast tint + 13/20/56 kill, launch flash Bolt/air 30 % Burst 50 %), pak = 136 files (haze copies dropped -> efx/haze/removed; byte-identical to the first merge), release/Pactblade-1.0.zip (+ Fluffy). Not published.
- 1.0 user: Hex + Hellish Rebuke both fired on one Interact press -> the rebuke ignores Interact while the Hex (bind) window is open (dbg.leapOpen, set in the Quik Fot / Hex frame check).
- 1.0 user: Guise left the decoy's gold dissolve remains floating where it ended -> 1 s after finish the decoy's meshes off (gu.decoyOff), back on at the next guise cast (gu.decoy_back at gu.show) or when a real Trickster decoy is in process.
- 1.0 user: decoy still left gold + its shadow (the watcher re-enabled the meshes while the decoy was still ending) -> meshes off BEFORE its finish, kept off; back on at the next guise cast or a Trickster decoy after it was idle once (gu.decoyIdle). Rest didn't end the guise (base-class 'restart' hooks never fire) -> + BarRoomTimeSkipStateFinish.onBarRoomTimeSkipStart (inn), CampStateResetCharacterStatus / CampStateSleepTentRecover.onCampStart (camp), noted in the trace.
- 1.0 user: decoy remains + rest = leave as is / on hold (only one decoy, a recast clears it) -> both changes reverted. Release = 1.0 + Hex priority over Hellish Rebuke. Zip rebuilt.
- 1.0 PUBLISHED on GitHub 2026-10-25: repo commit 9ae2fa1 (release files, README with requirements / passives / combos, DESIGN), release https://github.com/ntgoten/pactblade/releases/tag/v1.0 with Pactblade-1.0.zip. Nexus text: release/NEXUS_DESCRIPTION.txt (BBCode).
- docs/PACTBLADE_AI_GUIDE.md (agent: architecture, ids, hooks, per-skill implementation, pipelines, rules) + docs/PACTBLADE_MODDER_GUIDE.md (human: concepts + recipes) written 2026-10-25 (user).
- 1.0 docs in the release zip (Pactblade_docs/) + GitHub (docs/, README link; commit 4a7bbfa; v1.0 zip replaced, 850370 B).
- 1.0.1-test (user): levitate again mid-air (0.3 s after the end; rise capped from the jump's first float, L.jumpY0); Guise: FireSpread / Poison / VirulentPoison refused for me (reqStatusConditionApplyCore on live.sc), fire-element hits on me x0.5 (gu.fireTaken; calcDamageValue pre DamageGameObject = me, AttackUserData._ElementType / get_ElementType 1), statuses asked for me noted once; Misty Dive: radius >= 1.0 m (md.bigRadius) = no landing beside it -> falls onto its body (Skydragon-like).
- 1.0.1-test: statuses also arrive by flag lists (no Core hook note seen, user got Blighted -> Fulminant Poison): while the guise is on, poll StatusConditionCtrl.get_ActiveStatusConditionFlagProp (bit 1<<enum) every frame; FireSpread / OilSpread (guess: Torched) / Poison / VirulentPoison cured at once (reqStatusConditionCure(enum,false)); every new status noted by name. Misty Dive on big ones: still pushed off sometimes (Gagana, radius 1.2).
- 1.0.1 user: Misty Dive on big ones = leave as is (lands on the back a few times). Eldritch Slash wave damage x3 (BLAST.slash.dmgMul 2 -> 3).
- 1.0.1 user: Guise fire OK (no burning), levitate OK. Slash wave x9 (dmgMul 9), the slash's sword swing x3 (combo.slash.on, calcDamageValue, kind nil).
- 1.0.1 user: burning without the guise OK (build-up). Guise start/end effect spammed once (1-2 s) - cause unknown (likely the script reset while the guise ran: the decoy without our blocks); not reproduced.
- 1.0.1 RELEASED 2026-10-25: release/Pactblade-1.0.1.zip (+Fluffy; 1.0 zip kept there for the user to swap), GitHub commit 20a35ed + release v1.0.1 (Latest). README / NEXUS_DESCRIPTION / AI guide updated with a changelog.
- 1.0.2-test (user: slash wave still ~no damage): wave hits come from its sub-shells (not record.parts) -> kind nil, no x9. Now: no kind + within 4 s of dbg.slashT + attacker GO is a Shell (not me) = 'slash'.
- 1.0.2-test: user: Blast / Slash ~no damage; hits showed the charged bolt magick 4.5 (was 575) = the sword stayed plain. Suspect: dbg.guardHold stuck (a save_pre without its post). Guard now lets go after 5 s by itself (noted); the sword's magick apply is noted.
- 1.0.2-test: user's NEW sword got no magick/element in the menu although the master data was set (old sword was fine for all tests) -> the equipped Main StorageData's own _ItemData copy is modified + restored too (swordMod.own), and every refresh ends with a full recalc (EquipData clearParam + calc + applyEquipDataForCharacter(me), dbg.equip_recalc).
- 1.0.2 user: Eldritch Slash sword x2, wave x3 (x1.5 magick passive on top).
