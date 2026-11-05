# AF Armageddon — User Guide

AF Armageddon is a campaign mod for *Total War: Warhammer 3* that makes the middle and late game
harder. On each of their turns AI factions get bonuses, and these bonuses grow as the campaign
goes on:

- gold, which grows with the turn number and with the number of your regions;
- experience for their characters;
- experience for the units in their armies;
- an effect bundle with research, recruitment and growth.

Every AI faction of another culture than yours gets them: alliances, vassals and wars change
nothing. The AI factions of your own culture and the rebels never get them. In the settings you
can make the bonuses smaller or bigger for each culture.

## Installation

1. Subscribe to [AF Armageddon](https://steamcommunity.com/sharedfiles/filedetails/?id=3665832094).
2. Subscribe to [Mod Configuration Tool](https://steamcommunity.com/sharedfiles/filedetails/?id=2927955021)
   (MCT). It provides the settings window. Without it the mod still works with the default
   settings, but you can't change them.
3. Enable both in the launcher. The order of the mods doesn't matter.

You can add the mod to a running campaign. Don't remove it afterwards, see
[Good to know](#good-to-know).

## Settings

![The settings window](../imgs/armageddon/armageddon-settings.png)

Open the Mod Configuration Tool window in the game and choose **AF Armageddon**, then **Settings**.
The version of the mod is shown in its title.

| Section | Option | Default | What it does |
|---|---|---:|---|
| Gold | Percent of income per player region | 4 | Each of your regions adds this share of the AI income, 0-100 |
| Gold | Percent of income per turn | 2 | Each turn of the campaign adds this share of the AI income, 0-100 |
| Character experience | Experience per turn number | 200 | Multiplied by the turn number, 0-5000 |
| Character experience | Start turn | 10 | The first turn with this bonus, 1-200 |
| Unit experience | Start turn | 10 | The first turn with this bonus, 1-200 |
| Unit experience | Every n-th turn | 2 | How often a unit gets a whole extra rank: 1 is every turn, 3 is only the turns divisible by 3, up to 50. Divided by the bonus multiplier of the culture |
| Debug | Write a log file | Off | Writes a log, useful for finding problems |
| Bonus multiplier for cultures | One list for each culture | 1 | 0.1 to 5: makes the gold and the experience of this culture smaller or bigger |

The settings are the same for all your campaigns, except the bonus multipliers. A change takes
effect from the next turn of an AI faction.

### Your own culture

The AI factions of your culture never get the bonuses, whatever the settings. Its multiplier is
on the list too, as the main menu doesn't know which culture you'll play, but it changes
nothing. All other cultures always get the bonuses.

### Bonus multiplier for cultures

The last section lists the cultures of the game and its DLCs. It's long, so scroll the right
column of the window to see all of them.

Each culture has a multiplier: 0.1, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4 or 5. With the
default 1 the culture gets the bonuses as they are. The multiplier changes:

- the gold: multiplied by it;
- the character experience: multiplied by it;
- the unit experience: **Every n-th turn** is divided by it and rounded, but it's never less
  than 1. With the default 2: the multiplier 0.1 gives a rank every 20th turn, 0.25 every 8th
  turn, 0.5 every 4th turn, 0.75 every 3rd turn, 1 and 1.25 every 2nd turn, 1.5 and more every
  turn.

The effect bundle stays the same, and so do the start turns. To weaken a culture as much as
possible, give it 0.1.

Each campaign has its own multipliers. A change made in a campaign applies to that campaign
only. In the main menu it applies to the next campaign you start, not to the ones already
running. If you add the mod to a running campaign, every culture has 1 until you change it
there. Cultures from other mods aren't on the list, so they always have 1.

## What the AI gets

### Gold

From the first turn, on each of its turns a faction gets a share of its income:

```
income × (turn × percent per turn + your regions × percent per region) × bonus multiplier
```

So the gold grows on its own as the campaign goes on, and faster when you expand. With the
default settings, on turn 44 with 61 regions the share is 44 × 2% + 61 × 4% = 332%: a faction
with an income of 6,691 gets 22,214 gold on that turn. With the multiplier 0.5 its culture would
get half of that, 11,107.

### Character experience

From the start turn, on each of its turns every character of the faction gets the turn number
multiplied by **Experience per turn number** and by the bonus multiplier of its culture. With the
default settings that's 2,000 on turn 10 and 8,800 on turn 44.

### Unit experience

From the start turn, every unit in an army with a general gets one rank, up to rank 9. With the
default settings that's on every 2nd turn: 10, 12, 14 and so on.

**Every n-th turn** counts from the start of the campaign, not from the start turn. With 3 and
the start turn 10, units get a rank on turns 12, 15, 18 and so on. The bonus multiplier of the
culture divides it, see [Bonus multiplier for cultures](#bonus-multiplier-for-cultures).

### Effect bundle

This bonus has no settings, and the bonus multiplier doesn't change it. Each faction has one
bundle at a time, the one of the current turn:

| From turn | Research rate | Local recruitment capacity | Growth |
|---:|---:|---:|---:|
| 10 | +50 | +2 | +20 |
| 20 | +70 | +4 | +40 |
| 30 | +100 | +6 | +60 |
| 35 | +150 | +8 | +80 |
| 40 | +200 | +10 | +100 |

Research applies to the faction, recruitment and growth to each of its provinces. The bundle
lasts two turns and is renewed every turn, so when a faction stops getting the bonuses it
loses the bundle soon after.

## Compatibility with other mods

AF Armageddon was made to be used with **Radious**, and it's compatible with any other mod.

- It consists of a script and its own effect bundles, and it doesn't change any existing game
  data.
- The order of the mods doesn't matter.
- The gold depends on the AI income, so mods that change the economy change this bonus too.

## Balance

Balance depends on many things: mods, factions, random events, your skills and your style. All
you can expect is that the difficulty gradually grows.

If it's too hard, lower the two gold percents, move the start turns later or lower the
multipliers of the strongest cultures, down to 0.1. If it's too easy, raise the percents, move
the start turns earlier or raise the multipliers, up to 5.

## Good to know

- The mod is made for single player campaigns. It isn't designed for multiplayer and doesn't
  support it.
- Don't remove the mod from a running campaign: saves made with a mod may fail to load or crash
  without it.
- Turning a bonus off doesn't take back what the AI has already got.
- The log, if it's turned on, is `!!af_armageddon.txt` in the game folder, next to the game
  itself. Each turn starts there with a section of all the settings. It grows fast, close to
  1 MB per turn in a late game, so turn it on only to find a problem.
