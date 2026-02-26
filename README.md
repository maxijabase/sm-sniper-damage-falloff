# Sniper Rifle Damage Falloff

A SourceMod plugin for Team Fortress 2 that adds configurable distance-based damage falloff to sniper rifles, with a built-in visual wizard for tuning values in-game.

## Origin

This plugin was originally extracted from [[TF2] Adjustable Damage Falloff/Ramp up](https://forums.alliedmods.net/showthread.php?t=227237) by **Assyrian + TAZ**, which handled falloff/ramp-up for every weapon type in TF2 using flat percentage multipliers.

This version strips everything down to sniper rifles only and replaces the damage model with a proper linear falloff curve, adding:

- **Configurable start distance** — no longer hardcoded at 512 units.
- **Gradual drop rate** — damage decreases linearly per 100 units past the threshold instead of a sudden flat cut.
- **Damage floor** — a minimum percentage so damage never drops below a chosen value.
- **Visual wizard** — an in-game tool that draws laser beams, distance rings, and a HUD overlay so admins can see and tune the falloff in real time.
- Falloff now applies to **all sniper rifle shots** including headshots (the original skipped crits entirely).

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `sm_sniper_falloff_enabled` | `1` | Enable/disable the plugin |
| `sm_sniper_falloff_start` | `512.0` | Distance (Hammer units) where falloff begins |
| `sm_sniper_falloff_rate` | `5.0` | Percentage points of damage lost per 100 units past start |
| `sm_sniper_falloff_mindmg` | `50.0` | Minimum damage as a % of base (damage floor) |

A config file is auto-generated at `cfg/sourcemod/sniper_damage_falloff.cfg`.

### Damage formula

```
if distance <= start:
    multiplier = 1.0
else:
    multiplier = max(1.0 - ((distance - start) * rate / 10000), mindmg / 100)

final_damage = base_damage * multiplier
```

### Example (start=512, rate=3, mindmg=67)

| Distance | Multiplier | Noscope (50) | Charged Body / QS Head (150) | Charged Head (450) |
|---|---|---|---|---|
| 512u | 100% | 50 | 150 | 450 |
| 1012u | 85% | 42 | 127 | 382 |
| 1612u | 67% | 33 | 100 | 301 |
| 2000u+ | 67% | 33 | 100 | 301 |

## Wizard

Toggle with `!sniper_wizard` (requires `ADMFLAG_CONFIG`).

While active, the wizard renders:

- A **laser beam** from your crosshair to where you aim, color-coded green (full damage) through yellow to red (minimum damage).
- A **yellow ring** around you at the falloff start distance.
- A **red ring** at the distance where the damage floor is reached.
- A **HUD overlay** showing current distance, damage multiplier, calculated damage for all three shot tiers, and the active cvar values.

Changes to cvars are reflected in real time — adjust values in console while the wizard is active to immediately see the effect.

## Requirements

- SourceMod 1.12
- [AutoExecConfig](https://github.com/Impact123/AutoExecConfig) (compile dependency)

## Installation

1. Compile `scripting/sniper_damage_falloff.sp`.
2. Place the compiled `.smx` in `addons/sourcemod/plugins/`.
3. Load or restart the server. The config file will be auto-generated on first run.
