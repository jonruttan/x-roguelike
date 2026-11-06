# x-roguelike

A roguelike on x-lang, as a lang bundle: a dungeon of rooms and
passages made anew each game, creatures that wake and hunt, things to
find and work out, hunger, and one life.  Every creature, item, guise,
message and tuning number is read from a set of `.xon` files, so a set
is a game of its own on the same engine; `classic`, `delve` and
`kettle` are the three shipped, the last a world of screens rather
than a descent.

    x -l roguelike -- [-s NAME] [-S N] [-d DIR] [play]
    x -l roguelike -- scores

The goal lies on the deepest level.  Held, it opens the stairs up, and
every level climbed is made again, roused and hostile; the surface is
the win.  `S` saves a game for the next sitting; the save is read once.
Scores keep in `~/.x-roguelike/scores`.

## Keys

    h j k l y u b n   move; the arrows too.  Walk into a creature to attack it, or to talk.
    .                 rest a turn              s         search beside you
    ,  g              pick up what is here
    o                 explore until something comes into view; a key stops
    L                 what has been said lately
    m                 the map of the world, in a world of screens
    >                 go down, or in a door    <         go up with the goal, or out
    i                 your pack                d         drop a thing
    q                 quaff a potion           r         read a scroll or a page
    z                 zap a wand               e         eat
    w                 wield a weapon           W  T      wear armour, take it off
    P  R              put on a ring, take it off
    S                 save and leave           Q         quit
    ?                 the keys                 Esc       stop asking
    Ctrl-L            draw the screen again

The first row says what happened; the last is your standing: the
level, gold, hit points, strength, experience, and how hungry you are.
A lit room is seen whole from its door; a dark one, and a passage, a
cell around you.  What you have seen stays on the map.

## A set

A set is a directory of `.xon` files, every form in them read in
file-name order.  `data/classic/` is the one shipped and documents each
form: `game.xon` the tuning, `creatures.xon` what lives there and the
traits it may have, `items.xon` what lies about and the effects an
item may carry, `messages.xon` what the game says.  Another set is
another directory: `-s NAME`, `--set NAME`, under the bundle's `data/`, or `-d
DIR`, `--data DIR`, for any directory; `-S N`, `--seed N`, replays a dungeon.
The engine reads a closed vocabulary of traits
and effects; a set combines them as it likes.

`delve` is the second set shipped, `--set delve`: the mine under the
town of Kettle, twelve levels carved as caves in four bands, lit by
sight to a radius rather than by the room, with creatures that come in
packs, shoot along a line and call for company, potions and scrolls
known on sight, hunger as a store of food that costs hit points when
it runs out, gear that asks for strength and grows by a scroll of
upgrade, traps found by searching, a blow on a sleeper that always
lands, a guardian at the foot of each band, pages on the floor that
tell, read in order, why the pumps stopped, and three people down
there who ask for something and pay for it.
What a set may turn on, each off unless named: `(view N)` sight to N
cells, `(level-style caves)` with `(cave-fill PERCENT)`, `(known CLASS
...)`, a first `(hunger ...)` value under one, or `(starve N)` for a hit
point every N turns past nothing in place of the faint; `(traps LO HI)`
a level, of its `(trap NAME MESSAGE (effect ...))` kinds, hurt, hold,
aggravate or teleport; `(surprise N)` times the damage on a sleeper;
`(strength N)` on a weapon or armour, and `(effect upgrade)` on a
scroll; `(band NAME TO . PROPS)`,
one after another from level 1, with `(enter "TEXT")` said on its first
level, `(guardian "NAME")` a creature put by the stairs down on its
last, which stay shut while it lives, and `(colour N)` for its levels;
`(page NAME DEPTH LINE ...)` lying on its level once; `(quest NAME GIVER
. PROPS)`, the creature GIVER, one with the `talks` trait, on its
`(level N)`, spoken to by walking into it, with `(wants bring ITEM ...)`
tokens laid on the levels up to its own, or carried by a `(carrier
"kind")`, or `(wants explore)`, its `(ask ...)`, `(again ...)` and `(done
...)` lines, and `(rewards (CLASS NAME) (CLASS NAME))` to choose from;
and on a creature, `(pack LO HI)`, `ranged` with `(ranged LO HI)` and
`(shot "what")`, `summon` with `(summon "name")`, `talks`.

`kettle` is the third set shipped, `--set kettle`: the valley above the
Delve, a world of screens rather than a descent.  `(world screens W
H)` makes the world a grid of W by H screens joined at their edges: a
step off the edge of one is a step onto the next, landing on the
facing edge, and the world's own edge is said and takes no turn.  A
screen's level is kept and taken up again as it was left, what was
dropped there and who was on it; `m` lays the map of the screens
visited over the level.  A game starts on the hub screen, the one in
the middle, and a screen's depth is its distance from the hub, so what
a set says by depth -- what lives where, the gold, the goal, pages,
quests, bands -- counts from the hub outward.  With the goal in hand,
the hub is the win.  A world without `(world ...)` is a descent, as
before.  `(level-style open)` carves open ground: every cell floor,
`(clumps LO HI)` thickets of wall, each a walk of `(clump-size LO HI)`
cells, the outer ring always clear, no rooms and no stairs.

Each game of `kettle` is an errand drawn from the set's scenes: `(scene
NAME GIVER . PROPS)` is a link, the GIVER a creature that talks, who
`(wants "thing")` and, given it, `(gives CLASS "name")` or `(gives
goal)`, with its `(ask ...)`, `(again ...)` and `(done ...)` lines, in
which `{want}` is the thing wanted and `{where}` the way to it in
screens.  A scene giving the goal stands on the hub; what it wants,
another scene gives, a screen farther out, and so on, `(chain LO HI)`
links at most; the last want lies on the ground a screen beyond, or
with the token's `(carrier "kind")`.  A `(goal NAME GLYPH)` with no
level lies nowhere and is the chain's to give.  The chain is read
outward, by what each person says, and paid inward, by what each
gives; the goal laid in the square is the win.  A quest a set writes
by hand may stand on a `(screen X Y)` in place of a level, its tokens
on a `(lies X Y)`.

Behind some doors is a place of its own.  `(interior NAME . PROPS)`
is one: a screen made at a depth its `(depth LO HI)` covers lays a
door to it when its `(chance PERCENT)` comes up, the first of the
set's interiors to do so, one door a screen.  `>` on the door goes in
and `<` comes out onto it; the interior is kept like a screen.  Its
level is made by its own forms before the set's, so any knob it names
-- `(level-style ...)`, `(rooms LO HI)`, `(room-size ...)`,
`(cave-fill ...)`, `(creatures LO HI)`, `(items LO HI)` -- is its own;
it has a way out and none on, and its `(enter "TEXT")` is said the
first time in.  `(stairs up)` gives any level that shape.  `kettle`
has a farmhouse cellar in the farms, a shepherd's bothy in the hills
and an old city vault in the far valley.

What lies about is dispersed by two forms any set may use.  An item's
`(depth LO HI)` is the levels, or the rings out from the hub, where it
may lie; one without lies anywhere.  A band's `(cache CLASS LO HI)`,
as many as it likes, lays that many things of CLASS a level, each
drawn by rarity from what the depth allows and laid out of view with a
keeper beside it, a creature of the depth, asleep unless wakeful: a
thing worth having and what stands between you and it.  `kettle`'s
three rings are its bands, each with its word, its colour and its
caches, and few things lie loose.

## Running the suite

    make test            every spec, loudly
    make check           the suite against tests/contract/known-failures.txt

The specs drive a game from a seed with keys and read the state and
the screen back; nothing in them touches a terminal.

## Balance

    BALANCE_SEEDS=50 BALANCE_SET=delve x -l roguelike -f tools/balance.x

A plain bot plays a game a seed and reports where games end, what ends
them in each band, its standing on arriving at each level, and what it
used.  It plays below a person, so its numbers are a floor.
BALANCE_STYLE picks how it plays: plain, cautious, greedy, brawler or
sneak.  The header of tools/balance.x has the knobs.

    MODEL_SET=delve x -l roguelike -f tools/model.x

The set's numbers worked out with no game played: for each level the
player there, the creatures and how many come awake, how often a
weapon lies there, and for each kind what a fight costs bare-handed
and armed, and the most of them the player outlasts in the open and
in a line.  The header of tools/model.x has the formulas.

## Installing

    make install         into <share>/langs/roguelike, where `x -l` looks

## Licence

MIT No Attribution.  See [LICENSE](LICENSE).
