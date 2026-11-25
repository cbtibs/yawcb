# YAWCB

Yet Another WoW Cast Bar. A World of Warcraft: Forever addon that recolors Blizzard's cast bars.

The bars stay Blizzard's. The spell icon, shield, spark, and cast timer are untouched. YAWCB desaturates the existing fill texture and tints it, so the shape stays and the color you pick shows through. It does not run its own cast timer.

## Requirements

- World of Warcraft: Forever
- Interface 16001

## Install

The addon folder has to be named `yawcb`, with `yawcb.toc` directly inside it.

1. Copy the `yawcb` folder into `_forever_/Interface/AddOns/`.
2. Type `/reload`.

A GitHub download is packed as `yawcb-main`. Rename that folder to `yawcb` before putting it in `AddOns` so the game can load it.

## Settings

`/yawcb` opens the settings page. Player and enemy bars are separate.

| Section | What it colors |
| --- | --- |
| Player cast bar | Your cast bar, including the personal nameplate |
| Enemy cast bars | The target spell bar and other nameplate cast bars |

Each section has the same choices:

- **My class color**, or any class from Warrior through Druid
- **Custom**, chosen from the color swatch. The picker has a hex field for an exact code
- **Default**, or the **Reset to default** button, which puts Blizzard's colors back

## Preview without combat

Your own bar updates on any cast, including ones you can use out of combat.

Target bar:

```
/run TargetFrameSpellBar:SimulateCast({})
```

A nearby nameplate, with nameplates turned on:

```
/run local p=C_NamePlate.GetNamePlates()[1] if p and p.UnitFrame and p.UnitFrame.castBar then p.UnitFrame.castBar:SimulateCast({}) end
```
