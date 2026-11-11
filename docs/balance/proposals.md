# Balance: proposals

Speculative.  Each section is a way to meet the
[design](design.md), offered for a decision; none is decided, and
none is in the set.  A section that is decided moves to the design;
one that is turned down is deleted.

## The budget's terms

| Term | Meaning |
|---|---|
| **Cost** of a level | every creature on it fought once, in hit points |
| **Supply** on a level | the hit points brought down, those regained while crossing it, and those its potions give |
| **Afford** | supply over cost |

Above 1 a player can fight everything and wait out the damage, and
there is nothing to decide.  Under 1 some fights must be turned
down, shortened or won with a tool.

## The ladder's rungs

Afford falls a rung a band.

| Band | Levels | Afford | Read as |
|---|---|---|---|
| The Galleries | 1 to 3 | 13 in 13 | every fight, with care |
| The Flood | 4 to 6 | 8 in 13 | most of them |
| The Old Works | 7 to 9 | 5 in 13 | fewer than half |
| The Heart | 10 to 12 | 3 in 13 | one in four |

## The guardians

A guardian cannot be gone round.  It is sized against what a player
has left at the foot of its band, and each is harder than the last
by the same ladder.

## The lamp as the clock

The health regained on a level is the seconds spent there over the
regeneration period.  Oil bounds the seconds.  For each band the rule
would set:

- the light a level gives: the oil found on it;
- the health a second gives: the regeneration period;
- what the dark costs, so that staying past the light has a price.

## What the player is given

- **Weapons and armour** grow with the creatures they meet: one
  found in a band is fit for that band.
- **Mending** heals a share of the hit points of the depth it lies
  at, not a fixed number.
- **Wands and scrolls** are the answers to the kinds that should not
  be struck: each band's tools fit that band's creatures.
- **A reward** is better than what lies about at its errand's depth.

## The creatures' parts

Each kind has a part: what it does, the answer it asks for, and what
striking it without thought costs.  Its numbers are fitted to the
part.

| Part | Kinds | The answer | Struck without thought |
|---|---|---|---|
| Pack | mine rat, pit ferret, gas mote, silt crayfish, glow-midge | a passage, one at a time | all strike at once |
| Slow and harmful | drip toad, gallery shade, old 'un | outwalk it, or kill it first | venom or cold, taken for nothing |
| Shoots and runs | knocker, glister | corner it, or close | hurt on the way in, and it is gone |
| Sits and holds | great leech | go round, or kill it from afar | held beside it |
| Unseen | drowned shade | clear sight, or leave | struck from nowhere, and slowed |
| Fast | lantern eel, cave bat | a wall at the back | cannot be outrun |
| Raises others | ossuary priest | kill it first | the fight grows each turn |
| Slow, strong, mends | rust golem | a wand, or outpace it | a trade of blows that is lost |
| Guardian | fireman, undertow, warder, Old Man | everything saved for it | no way down |

## The bot that must win

Two ways to make it, which can be had together.

**By rule.**  It is given every answer above: it fights a pack in a
passage, goes round what sits, kills first what raises others, turns
a wand on what it cannot trade blows with, mends when the next blow
would cost more than the potion gives, rests while there is light to
rest by, and goes back up when the level cannot be paid for.  It
plays as well as its rules were written, and no better.

**By search, as a chess engine.**  It tries each move it could make
on a copy of the game, plays the copy some turns on, and takes the
move whose outcomes score best.

| Part | In a chess engine | Here |
|---|---|---|
| The moves | the legal moves | step, strike, drink, read, zap, rest, climb |
| Looking ahead | the opponent's replies | the creatures' turns, by the engine itself |
| Chance | none | the dice: many copies played, the mean taken |
| What is hidden | nothing | the unseen level: guessed from what the set lays at that depth |
| The score | material and position | hit points, supplies and light left, by `roguelike/odds.x` and the budget |

The score is the same arithmetic as the model, so the bot and the
rule cannot disagree about what a thing is worth.

What it needs, by the timings in [state.md](state.md):

- **A copy of a game in memory.**  About thirty lines in
  `roguelike/state.x`, and 3 ms a copy.  Not the obstacle.
- **A faster turn.**  This is the obstacle.  A search that tries 6
  moves, 8 times each against the dice, 10 turns deep, plays 480
  turns to choose one move: 14 seconds at 30 ms a turn.  A game is
  some 1500 moves.

| A turn at | One searched move | A game searched at 50 sharp moments | A game searched throughout |
|---|---|---|---|
| 30 ms, today | 14 s | 12 minutes | 6 hours |
| 3 ms | 1.4 s | 70 seconds | 36 minutes |

So at today's speed the bot searches only where the choice is sharp,
with creatures in view, and plays by rule between.  A turn ten times
quicker makes search usable throughout.

Where a resting turn goes is in [state.md](state.md): some 15 ms of
its 25 is the set's rules read afresh, each a walk of 289 forms, and
6 ms is sight.

- **The rules kept, not looked up.**  A set's rules do not change
  during a game, a band's only at its first level: read once into the
  game's record, a read is a field.  Done: a resting turn went to
  12 ms.
- **Sight worked only on a move.**  A turn in which the player has
  not stepped and no door has changed sees what the last one saw.
  Done: a resting turn is 6 ms, 4 of it the creatures' turns, which
  are walks of each kind's own properties.
- Past these, the turn's own loops compiled with x-lang's
  `compile-fn!`.  By the chess session's measure a call is 2.4
  microseconds interpreted and about ten times quicker with caller and
  callee both compiled, 3.6 times with the caller alone.  It takes a
  fixed parameter list, a named-self loop and the object and pointer
  doors; it refuses a nested `fn` and a rest parameter.  In v0.51.0 a
  compiled `eq?` on two integers can answer false, mended on x-lang's
  main and in no release yet, so this waits on a release.  Compiling
  costs about 37 ms a function at each start.

The bot's own 200 ms a turn is mostly its path-finding, which
searches the whole level afresh each move.

## The model's next terms

For `tools/model.x` to work the budget exactly it would count:

- the blow on a sleeper, and how many creatures start asleep;
- how often the gear is found, not only whether it can be;
- the player's level when not every creature is killed;
- wands and scrolls, as the answers to the kinds they fit;
- the traits it leaves out: ranged, venom, sticky, drain, summon,
  invisible, stationary, erratic.

## To settle

- What the dark costs, beyond sight.
- The regeneration period in each band, and whether it still
  quickens with level.
- How many creatures start awake, and whether a blow on a sleeper
  stays a sure one, `(surprise N)` times over.
- Whether the guardians' rung is the next band's, or a ladder of
  their own.
- What "tuned down" means once a bot has won: the set eased until
  weaker play gets further, or the bot weakened to find how much
  skill the set asks.
