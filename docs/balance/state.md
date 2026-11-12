# Balance: the state

What the `delve` set does today, and what has been measured of it.
Nothing here is a decision or a proposal: the decisions are in
[design.md](design.md), the proposals in
[proposals.md](proposals.md).

Readings are of `main` at `77937e2` unless a section says otherwise,
and go stale as the set changes.  The fights and the budget are
`tools/model.x`'s.

## The factors

Everything the game holds or applies to a player on a turn.  The last
column says whether `tools/model.x` counts it.

### What the player is

| Factor | Effect | Modelled |
|---|---|---|
| Hit points and their most | Dead at none.  The most grows 3 to 8 a level; drain lowers it. | yes |
| Level and experience | A level adds 5 to the chance to hit, and quickens regeneration. | yes |
| Strength and its most | Gates gear; adds damage at 17 and at 19.  Venom lowers it, vigour raises it. | fixed at the start's |

### What the player carries

| Factor | Effect | Modelled |
|---|---|---|
| Weapon | Its dice, its upgrades; lands less when it asks more strength than there is. | the best the level can hold |
| Armour | A point takes 5 from a creature's chance to hit. | the best the level can hold |
| Rings | Protection, strength, regeneration, stealth. | no |
| Potions | Mending, deep mending, quickness, clear sight, restoration, vigour; miasma harms. | no |
| Scrolls | Survey, blink, panic, stillness, upgrade. | no |
| Wands and charges | Sparks, lethargy, banishing, leeching. | no |
| Food, oil flasks, gold, tokens | Supplies and errands. | no |

### What the player is under

| Condition | Effect | Modelled |
|---|---|---|
| Confused | A step or a blow goes any of eight ways. | yes, from dazzle |
| Slowed | Every creature acts twice a turn. | yes, from cold |
| Held | No step; a blow still lands. | no |
| Hasted | Creatures act every other turn. | no |
| Blind; seeing | What is seen, the invisible with it. | no |
| Hungry, weak, starving | Starving costs hit points and stops regeneration. | no |

### The clocks

| Clock | Effect | Modelled |
|---|---|---|
| Food | A store of 43200 seconds at the start, run down by the clock. | no |
| Lamp oil | A full lamp burns 1800 seconds; out, only the cells beside are seen. | yes, as the time on a level |
| Regeneration | A hit point every 12 seconds. | yes |
| Arrivals | A creature wanders in about once in 40 turns. | shown, not counted |

A turn is a second in the Delve.

### Where the player stands

| Factor | Effect | Modelled |
|---|---|---|
| Passage or open ground | How many can strike at once. | packs only |
| The stairs | A way out, unless a guardian bars the way down. | no |
| Traps | Hurt, hold, alarm, drop; hidden until found. | no |
| What is seen and mapped | Where a step is safe. | no |

### What is around the player

| Factor | Effect | Modelled |
|---|---|---|
| A creature's state | Asleep, wandering, awake, fleeing.  Every creature starts asleep, a wakeful one wandering.  A blow on a sleeper or a wanderer always lands, twice over. | no |
| Who sees the player | Creatures hunt by sight; stealth keeps sleepers asleep. | no |
| How many are beside | Each strikes every turn. | packs only |
| Their traits | fast, slow, ranged, venom, sticky, dazzle, cold, drain, thief, summon, regen, invisible, stationary, erratic. | fast, slow, cold, dazzle, regen |

## A fight's cost

From `roguelike/odds.x`, which reads the engine's own rolls.

| Term | Rule |
|---|---|
| Chance to hit | `70 + 5 x level - 5 x defence`, kept between 5 and 95 |
| Hurt a turn | the creature's chance to hit x its mean attack x its speed (fast 2, slow 1/2) |
| Turns to kill | the mean swings to take its hit points, by the player's chance and dice |
| Cold | its blows slow the player 4 turns; slowed, it strikes twice as often |
| Dazzle | 3 blows in 10 confuse for 4 turns; confused, 1 swing in 8 reaches it |
| Regeneration | a hit point back every third turn: its hit points come off that much slower, or never |
| **A fight** | **hurt a turn x turns to kill** |

A pack of `k` costs `k` fights met one at a time, and `k(k+1)/2`
fights met all at once.

## The budget as it stands

`tools/model.x`'s, in hit points, of the set with the starting
numbers in the [design](design.md).  The time on a level is its
light: the oil it holds, and the first lamp's share.  The cost
includes the guardian's.

| Level | Hit points | Cost | Guardian | Light | Regained | Potions | Supply | Afford |
|---|---|---|---|---|---|---|---|---|
| 1 | 14 | 29 | | 332 s | 28 | 11 | 52 | 1.8 |
| 2 | 20 | 40 | | 283 s | 24 | 8 | 51 | 1.3 |
| 3 | 25 | 96 | 25 | 266 s | 22 | 7 | 55 | 0.6 |
| 4 | 31 | 86 | | 247 s | 21 | 10 | 61 | 0.7 |
| 5 | 36 | 81 | | 236 s | 20 | 10 | 65 | 0.8 |
| 6 | 42 | 123 | 37 | 232 s | 19 | 9 | 70 | 0.6 |
| 7 | 42 | 125 | | 236 s | 20 | 10 | 71 | 0.6 |
| 8 | 47 | 136 | | 236 s | 20 | 10 | 76 | 0.6 |
| 9 | 47 | 278 | 42 | 236 s | 20 | 10 | 76 | 0.3 |
| 10 | 53 | 265 | | 236 s | 20 | 10 | 82 | 0.3 |
| 11 | 53 | 367 | | 236 s | 20 | 10 | 82 | 0.2 |
| 12 | 58 | 522 | 140 | 236 s | 20 | 10 | 87 | 0.2 |

The model takes the best gear a level can hold for found, strength
with each band's vigour in it, every creature above killed, a turn
for a second.  It leaves out the blow on a sleeper, wands, scrolls,
rings and the traits in the table above.

### Before the starting numbers

Of `main` at `0e1f71b`: 5.5 creatures a level, regeneration
quickening to a hit point every 4 seconds by level 5.

| Level | Cost | Supply | Afford |
|---|---|---|---|
| 1 | 16 | 52 | 3.3 |
| 2 | 22 | 56 | 2.6 |
| 3 | 64 | 66 | 1.0 |
| 4 | 33 | 82 | 2.5 |
| 5 | 29 | 104 | 3.6 |
| 6 | 44 | 108 | 2.5 |
| 7 | 55 | 110 | 2.0 |
| 8 | 67 | 116 | 1.7 |
| 9 | 216 | 116 | 0.5 |
| 10 | 274 | 121 | 0.4 |
| 11 | 399 | 121 | 0.3 |
| 12 | 595 | 127 | 0.2 |

- Levels 1 to 8 gave from once to three and a half times what their
  fights cost, and level 9 cost three times level 8.
- From level 5 the light of one level regained more than all the
  player's hit points.

## The player by depth

| Depth | Level | Hit points | Weapon | Armour |
|---|---|---|---|---|
| 1 | 1 | 14 | bare hands 1-3 | none |
| 2 | 2 | 19 | pick 1-6 | boiled leather 2 |
| 3 | 3 | 25 | miner's blade 2-7 | boiled leather 2 |
| 6 | 6 | 41 | miner's blade 2-7 | scale coat 4 |
| 9 | 7 | 47 | miner's blade 2-7 | scale coat 4 |
| 12 | 9 | 58 | miner's blade 2-7 | scale coat 4 |

The model holds strength at 16.  A band lays one potion of vigour, so
strength reaches 17 after the Galleries and 18 after the Flood: the
sledge (3-10) from level 5 and the plated harness (6) from level 7
are within reach, and the model does not count them.

Over the descent a player's damage grows about one and a half times
and a creature's hit points about six.

## The guardians

| Guardian | Level it bars | Level | Hit points | Attack | Player's hit points |
|---|---|---|---|---|---|
| fireman | 3 | 3 | 14-18 | 1-4 | 25 |
| undertow | 6 | 5 | 22-30 | 2-6 | 41 |
| warder | 9 | 9 | 38-52 | 5-12 | 47 |
| Old Man | 12 | 11 | 55-80 | 7-16 | 58 |

A fight with the undertow is 88% of the player's hit points, with the
fireman 100% and with the warder 90%; with the Old Man it is 241%.

## The Flood's kinds

The fireman and four of the Flood's kinds have been changed since
they were first written.

| Kind | First | Then | Now |
|---|---|---|---|
| fireman | level 3, hit points 20-28, attack 2-7, cold regen | level 3, 14-18, 1-4, cold | the same |
| lantern eel | level 3, 8-14, 2-6, dazzle fast | level 2, 6-10, 1-4, dazzle | 9-13, 2-5 |
| great leech | level 4, 16-26, 3-9 | level 3, 10-16, 1-4 | 14-22, 2-5 |
| drowned shade | level 5, 10-16, 2-8 | level 3, 6-10, 1-4 | 9-13, 2-5 |
| undertow | level 6, 32-44, 4-10 | level 5, 14-20, 1-4 | 22-30, 2-6 |

The four below the fireman were raised with the starting numbers.

## What a level gives

Of the 5.5 things drawn for a level, 30 in 100 are gold.  The
figures are how many of each a level holds, on average.

| Depth | Potions | Wands | Weapons | Armour | Food | Oil |
|---|---|---|---|---|---|---|
| 1 | 0.76 | 0 | 0.61 | 0.61 | 1.8 | 0.61 |
| 3 | 0.97 | 0.23 | 0.58 | 0.39 | 1.5 | 0.39 |
| 6 | 0.88 | 0.48 | 0.50 | 0.36 | 1.4 | 0.27 |
| 9 | 0.93 | 0.50 | 0.41 | 0.29 | 1.4 | 0.29 |
| 12 | 0.93 | 0.50 | 0.41 | 0.29 | 1.4 | 0.29 |

A potion of mending heals 10 to 20 at every depth: most of a
player's hit points on level 1, a quarter on level 12.  A flask of
oil is 300 seconds of light, so a level below the first gives about
100 by chance, and each band lays three more, another 300 a level;
a level takes 250 to 500.

## The errands' rewards

| Errand | Level | Reward | Against what lies about |
|---|---|---|---|
| the lamp | 2 | miner's blade, or scale coat 4 | the coat is found from level 4 |
| the survey | 5 | wand of sparks, or ring of vigour | the Flood's prize is the ring of warding |
| the pump | 9 | foreman's pick 3-9, or ring of silence | the sledge, 3-10, is found from level 5; the Old Works' prize is the plated harness |

## The bots today

`tools/balance.x` plays by fixed rules, a move at a time, looking no
turns ahead.

| It does | It does not |
|---|---|
| weigh a fight by `roguelike/odds.x` before starting it | evade, or lure a creature to better ground |
| drink mending when what is lost fits what the potion gives | choose which of several to strike first |
| step away from a fight it is losing, when free to | use a wand or a scroll |
| wield the best weapon and armour it holds | fight a pack from a passage |
| eat when hungry, pour oil when the lamp is low | go back up a level |
| explore to the stairs | search ahead for what a move leads to |

Before a guardian it judges lost, it stands off until the turns run
out.  It plays about five turns a second.

## What a turn costs

Timed on level 1 of the Delve, seven creatures asleep, x-lang
v0.51.0, in processor time.

| What | Time |
|---|---|
| A turn spent resting | 30 ms |
| Collecting the memory a turn leaves | 4 ms |
| A turn with the bot choosing the move | about 200 ms |
| A game copied in memory: its record, the player, each creature and item, the map | 3 ms |
| A game saved to a file | 232 ms |
| A game read back | 202 ms |

- A resting turn leaves about 6 MB to collect: 300 of them without a
  collect passed 2 GB.
- The bot's own choosing is most of its turn: the engine's share is
  30 ms in 200.
- A copy in memory is about 130 times quicker than a save and a
  load.

A game is one record of 36 fields, holding the player, the creatures,
the things on the floor and in the pack, and the map as three grids
of a byte a cell.  Nothing in it stops a copy; the dice need none,
since a copy can be given a seed of its own.

### Where a turn goes

Since these readings the set's rules are kept in the game's record
and the view is kept until what it was worked from changes: on `main`
at `0e1f71b` a resting turn is 6.0 ms and 72,700 objects, 3.9 ms of
it the creatures' turns.  The table is the turn before both.

Each part timed alone, 20 times between collects.  Without the
collect a resting turn is 25 ms and makes 275,000 objects.

| Part | Time | Objects |
|---|---|---|
| A resting turn, whole | 25 ms | 275,000 |
| One rule read from the set, as `(view 7)` or `(regen 12)` | 0.68 ms | 8,000 |
| The level's forms gathered, for the scale | 1.4 ms | 17,000 |
| The creatures' turns, seven asleep | 6.4 ms | 78,000 |
| What is in view, by sight within 7 | 5.8 ms | 59,000 |
| A chance of an arrival | 0.7 ms | 8,000 |
| One message told | 1.5 ms | 18,000 |
| The conditions' tick | 0.3 ms | 3,300 |
| A search for traps | 0.04 ms | 500 |

- A rule is read by walking the set's 289 forms from the top, each
  time: 2.3 microseconds and 28 objects a form.
- A turn reads some twenty rules, one of them, `(hunt sight)`, once a
  creature.  By the sums that is about 15 ms of the 25: most of a
  sleeping creature's 0.9 ms is that one read.  The count of reads is
  worked from the code, not measured.
- Sight is the next part: 225 lines walked a cell at a time.
- The rest is small.

## What the bots have shown

| Reading | Runs |
|---|---|
| A fast creature that dazzled on every blow could not be struck back. | 58 fights in 60 lost to the lantern eel.  Mended: dazzle lands 3 blows in 10. |
| A held player could not strike. | Bots died held beside great leeches, and the undertow never lost a hit point.  Mended. |
| The fireman at level 3, hit points 14-18, attack 1-4 | beaten 94 times in 120, with half the player's hit points left |
| The undertow at level 6, hit points 32-44, attack 4-10 | 4 fights: none won |
| The undertow at level 5, hit points 20-28, attack 2-6 | 4 fights: none won, one left it at 4 hit points |
| The undertow at level 5, hit points 14-20, attack 1-4 | 4 fights: one won with 57% left, one lost with it at 6 |
| The Flood at today's numbers | 4 games from its first level: 1 reached the undertow |
| The Flood with its four kinds at their first numbers, both mends in | 4 games from its first level: none left it |
| The model against the bots, on cold | the model reads a cold fight about twice as dear as the bots find it |

## In play

- The game needs no thought: strike what is near, pick up what lies
  about.
- There are no hordes.
- The guardians are easy to kill.
- There is no need to mend: health comes back by waiting.
