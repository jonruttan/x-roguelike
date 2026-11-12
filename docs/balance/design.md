# Balance: the design

What is decided about how hard the `delve` set is.  Nothing here is a
guess: each line is a decision, and the set is wrong where it differs.

What is proposed and not yet decided is in
[proposals.md](proposals.md).  What the set does today, and what has
been measured of it, is in [state.md](state.md).

## What the game is for

- **It climbs.**  The game gets harder as it goes down, by the
  Fibonacci ladder, and is gruelling by the end.
- **The first level does not slaughter.**  It is still a game.
- **Creatures differ.**  Each kind has its own character, and the way
  a fight goes changes with it: a weak pack, a strong one alone,
  being cornered by kinds that differ.  Kinds that all act alike,
  with numbers alike, that always chase or always run, are dull.
- **A creature's character decides the answer.**  Which to strike
  first; whether to mend, or to zap; whether to evade, or to lure.
- **Play takes thought.**  A game won by striking whatever is near
  and picking up whatever lies about is not the game.
- **Waiting is not free.**  Health is not had by standing still.  The
  supply of lamp oil limits the time a player can take.
- **What the player is given fits what they meet.**  The things laid
  on a level, and the rewards of the errands, are in keeping with
  the creatures at that depth.

## The ramp

- The Fibonacci ladder is used in the scaling, and only there.
- What climbs is the **level's budget**: how much of a level's
  fighting a player can afford.  A single fight's cost is not what
  is ramped.

## The starting numbers

Where the tuning starts from, worked by `tools/model.x`.  A band's
afford, its supply over its cost, stands on a ladder: 13, 8, 5 and 3
in 13.  The rung is held as the band's mean, not level by level.

- **Regeneration is flat.**  A hit point every 12 seconds at every
  level; it does not quicken as the player's level rises.
- **Ten creatures are laid on every level.**
- **A fight's cost is raised by a kind's strength**, not by more of
  the kind.

The rules:

| Rule | Was | Is |
|---|---|---|
| Creatures laid on a level | `(creatures 4 7)` | `(creatures 8 12)` |
| Experience for level 2, doubling after | `(exp 10)` | `(exp 20)`: twice the creatures, the same level at each depth |
| Regeneration | `(regen 12)`, 2 seconds fewer a level | `(regen 12 0)`: no fewer |

The kinds, hit points and attack:

| Kind | Levels | Was | Is | A fight, of the player's hit points |
|---|---|---|---|---|
| lantern eel | 4 to 7 | 6-10, 1-4 | 9-13, 2-5 | 26% to 47%, from 16% to 26% |
| silt crayfish | 4 to 7 | 8-14, 1-5 | 11-19, 2-6 | 15% to 25% |
| great leech | 4 to 8 | 10-16, 1-4 | 14-22, 2-5 | 26% to 43% |
| drowned shade | 5 to 7 | 6-10, 1-4 | 9-13, 2-5 | 31% to 38% |
| undertow | guards 6 | 14-20, 1-4 | 22-30, 2-6 | 88%, from 38% |
| ossuary priest | 7 to 10 | 12-20, 2-6 | 16-24, 3-7 | 27% to 33% |
| glister | 9 to 12 | 40-60, 6-14, shot 4-10 | 28-40, 5-11, shot 3-8 | 121% at level 9, from 215% |
| glow-midge | 10 to 12 | 6-10, 2-6 | 3-5, 1-3 | 39% each, packs of 2 to 4, from 108% |

Every other kind, and the fireman, the warder and the Old Man, are
as they are.

What it gives:

| Band | Levels | Cost by level | Supply by level | Afford, the band's | Rung |
|---|---|---|---|---|---|
| The Galleries | 1 to 3 | 29, 40, 96 | 52, 51, 55 | 0.96 | 1.00 |
| The Flood | 4 to 6 | 86, 81, 123 | 61, 65, 70 | 0.68 | 0.62 |
| The Old Works | 7 to 9 | 125, 136, 278 | 71, 76, 76 | 0.41 | 0.38 |
| The Heart | 10 to 12 | 265, 367, 522 | 82, 82, 87 | 0.22 | 0.23 |

- Each band tightens to its guardian: the Galleries from 1.8 on level
  1 to 0.6 on level 3.
- Cost climbs at every level but one, and the cliff at level 9 is a
  step of two, not three.
- The Galleries need no dice changed: ten laid puts them on the rung.
- Still uneven: the rust golem, 62% to 76% of the hit points a fight,
  and the glister, are fights to be answered and not traded; the old
  'un is 4%.

## Forward from the starting numbers

- **A fight that is to be turned down can be.**  A band whose afford
  is under one asks for fights to be left; a kind that walks the
  level from the first turn and shoots along a line cannot be left,
  and its cost is paid whatever is played.
- **The glister sleeps as the others do.**  It is not `wakeful`: it
  starts asleep and wakes only in view, so a careful player goes round
  it.  Its dice and its shot are as they were, so one met awake costs
  what it did.

## Method

1. **Arithmetic and logic first.**  A workable starting point is
   derived, not picked.
2. **Bots second.**  Bots play it.  At least one bot must win, even
   if it takes a very good one.
3. **Tuning third.**  From there the set is tuned down.

## How the work is done

- **The bots are to be made good.**  A bot can play this game better
  than a person, as a chess engine plays chess.  Today's do not: see
  [state.md](state.md).  Until they do, a set that today's bots win
  often is trivial for a person.
- **Forward, never back.**  When the balance is wrong, the set is not
  put back to an earlier state to start over.  What has been
  measured is kept and used, and the next change starts from the
  numbers in hand.
