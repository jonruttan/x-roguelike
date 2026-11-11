# x-roguelike

A roguelike on x-lang, as a lang bundle: a dungeon of rooms and
passages made anew each game, creatures that wake and hunt, things to
find and work out, hunger, and one life.  Every creature, item, guise,
message and tuning number is read from a set of `.xon` files, so a set
is a game of its own on the same engine; `classic`, `delve`, `kettle`
and `town` are the four shipped, the last two worlds of screens rather
than a descent.

    x -l roguelike -- [-s NAME] [-c GROUP=NAME]... [-S N] [-d DIR] [play]
    x -l roguelike -- [-s NAME] scores

The goal lies on the deepest level.  Held, it opens the stairs up, and
every level climbed is made again, roused and hostile; the surface is
the win.  `S` saves a game for the next sitting; the save is read once.
Each set keeps its own save and scores, in `~/.x-roguelike/NAME/`.

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
    f                 fill the lamp from a flask
    S                 save and leave           Q         quit
    ?                 the keys                 Esc       stop asking
    Enter  Space      go on past --More--, put away what you look at
    Ctrl-L            draw the screen again

In a window (`-w`), the game opens on the set's title screen: continue
the saved game, start a new one, set the options, or quit.  The options
are the zoom, fullscreen, how loud the music and the sounds are, and
mute; they are kept in `~/.x-roguelike/options` for every set.  In the
game, + and - zoom, M mutes the sound and brings it back, and [ and ]
make it quieter and louder.  Esc, when the
game is not asking anything, pauses it: back to the game, the options,
the keys, or save and quit.  Alt-Enter (Option-Return on a Mac)
switches to fullscreen and back, and a gamepad plays too:

    left stick, d-pad  move, in eight directions; held, it keeps moving
    A  pick up, or go on past a message (Enter)
    B  stop asking (Esc)
    X  your pack       Y  explore
    LB go up (<)       RB go down (>)
    left stick click   rest           right stick click  search
    Start  pause       Back  the map of the world

A command that asks for a thing, such as quaff or wear, takes its
answer from the keyboard.

The first row says what happened; the last is your standing: the
level, gold, hit points, strength, experience, and how hungry you are.
A lit room is seen whole from its door; a dark one, and a passage, a
cell around you.  What you have seen stays on the map.  A set that says
`(light day)` lies under the sky: a level of it is in view whole from
anywhere on it, until the player steps under a roof or goes inside,
where sight is the set's `(view N)` again.  By day `(view N)` is still
how far off a creature and the player notice one another, what a
creature's tale waits for, and what stops a walk.

## A set

A set is a directory of `.xon` files, every form in them read in
file-name order.  `data/classic/` is the one shipped and documents each
form: `game.xon` the tuning, `creatures.xon` what lives there and the
traits it may have, `items.xon` what lies about and the effects an
item may carry, `messages.xon` what the game says, `tui.xon` how the
terminal draws it.  Another set is
another directory: `-s NAME`, `--set NAME`, under the bundle's `data/`, or `-d
DIR`, `--data DIR`, for any directory; `-S N`, `--seed N`, replays a dungeon.
The engine reads a closed vocabulary of traits
and effects; a set combines them as it likes.

`delve` is the second set shipped, `--set delve`: the mine under the
town of Kettle, twelve levels carved as caves in four bands, lit by
sight to a radius rather than by the room, with creatures that come in
packs, shoot along a line and call for company, potions and scrolls
known on sight, hunger as a store of food that costs hit points when
it runs out, a lamp whose oil burns by the minute, gear that asks for
strength and grows by a scroll of upgrade, traps found by searching,
a blow on a sleeper that always lands, a guardian at the foot of each
band, pages on the floor that tell, read in order, why the pumps
stopped, and three people down there who ask for something and pay
for it.
What a set may turn on, each off unless named: `(view N)` sight to N
cells, `(level-style caves)` with `(cave-fill PERCENT)`, `(known CLASS
...)`, a first `(hunger ...)` value under one, or `(starve N)` for a hit
point every N seconds past nothing in place of the faint; `(traps LO HI)`
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
`(shot "what")`, `summon` with `(summon "name")`, `talks`, `(tale
"LINE" ...)`, said a line a message the first time one of its kind
comes into view in a game: what it is, and what has changed it; and
`(article "WORD")`, said before its name where one is met, in place of
"a" or "an".

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
`(clumps LO HI)` thickets of wall, each a walk over `(clump-size LO
HI)` square metres, the outer ring always clear, no rooms and no
stairs.  `(level-style town)` lays a town: streets, and rows of
terraces `(terrace-depth LO HI)` metres deep with `(street LO HI)`
between the rows, each terrace `(terrace-length LO HI)` along with
`(lane LO HI)` between, its houses `(house-width LO HI)` each with a
door onto the street; two cells round the edge are street, and the
`(square W H)` in the middle is left clear.  Each `(building NAME
(size W D) . PROPS)` the level names is laid round the square, W
metres along and D deep, walled, its door toward the square, on the
first side it fits; the terraces keep off them, and its door, stood
on, says its `(enter "TEXT")`.  A building is put together from tiles
by a `(plan "ROW" ...)` in place of its size, a character a cell, laid
as it is drawn: `#` a wall, `.` a floor, `+` a door, a blank no part
of it, and any other character the kind of terrain a `(cell "C"
KIND)` names, the building's own or the level's, so a mill has its
race and a tannery its pits:

    (cell "," floor open)
    (cell "%" wall open)
    (cell "=" gate open)
    (building "the inn"
      (plan "#############"
            "#.....#.....#"
            "#.....+.....+"
            "#.....#.....#"
            "###+#########"
            "%,,,,,,,,,,,%"
            "%%%%%%=%%%%%%")
      (enter "The inn: carriers' talk, and stables for the packhorse trains."))

Every building, and every house of a terrace, is under a roof.  From
outside it is drawn as roof, `(glyph roof "^")`, all but the doors into it, the
whole of it once any of it is seen, and nobody and nothing in it is
drawn; standing in it, a door of it included, its roof is off and the
whole inside is in view.  A cell that is `(cell "C" KIND open)` is open
to the sky and never roofed: a yard, its wall and its gate.  Its `(keeper NAME
LINE ...)` stands inside, unless the chain gives NAME a screen of its
own, and walked into with nothing to ask says a LINE, the next each
turn.  A building with `(sells (CLASS NAME) ...)` or `(buys CLASS
...)` keeps a shop: its keeper, walked into, puts up the counter,
where a letter buys the thing beside it, `s` sells one thing of a
class the keeper takes, and any other key leaves.  A thing is worth
its item's `(price N)`, or its class's in the world's `(worth (CLASS
N) ...)`, in gold, and the shop asks and pays its `(rate SELL BUY)`
percent of that, 100 and 50 unless given; a thing worth nothing, worn
or in hand is not bought.  `town`'s inn, bakehouse, smithy, tannery
and chandler's keep shops, and the Guild's shop sells dear.  In a
world of screens the bands run from
the hub, ring 0, and any form a band names besides its own -- a level
knob, a level style -- is in front of the set's on its screens, so
`kettle`'s first band, "Kettle", lays hedged fields round the town's
door on the hub, and the rings out from it are fields, hills and the
rim.

Each game of `kettle` is an errand drawn from the set's scenes: `(scene
NAME GIVER . PROPS)` is a link, the GIVER a creature that talks, who
`(wants "thing")` and, given it, `(gives CLASS "name")` or `(gives
goal)`, with its `(ask ...)`, `(again ...)` and `(done ...)` lines, in
which `{want}` is the thing wanted and `{where}` the way to it as the
people say it: the `(where "TEXT")` of the band it lies in and which
way from here, "up in the hills, north-east of here".  A scene giving
the goal stands on the hub; what it wants, another scene gives, a
screen farther out, and so on, `(chain LO HI)` links at most; the last want lies on the ground a screen beyond, or
with the token's `(carrier "kind")`.  A `(goal NAME GLYPH)` with no
level lies nowhere and is the chain's to give.  The chain is read
outward, by what each person says, and paid inward, by what each
gives; the goal laid in Kettle's square is the win.  A quest a set writes
by hand may stand on a `(screen X Y)` in place of a level, its tokens
on a `(lies X Y)`.

An errand not over leads somewhere: the first of the chain, not yet
asked, to its giver; one open, to what it wants, where that lies or
with whoever gives it; one whose want is in the pack, back to its
giver.  The map marks that screen with `!` and says the way under it,
a line an errand; it says too where the player is: in a world that
names its screens, each of them, which way it lies and who keeps a
building there, and in one that does not, the band stood in and which
way it lies from the hub.  A screen come onto says which way the one
looked for stands: "You make out the night watchman to the
north-east."

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

A level is carved in the shape of where it is.  Besides `rooms`,
`caves`, `open` and `town`, `(level-style STYLE)` is one of `pit`, bord
and pillar off a haulage road; `flood`, a channel across the level with
deep water along it; `works`, paired vaults of dressed stone off a
stair; `well`, a cave round a walled court with a pool; `fields`,
hedged closes either side of a road; `hills`, gritstone edges, bog and
gorse; or `rim`, limestone scars, shakeholes and fallen walls.  Each
style's knobs, and what each defaults to, are in its comment in
`roguelike/dungeon.x`.  `delve`'s four bands are a pit, a flooded
reach, the works and the well-house; `kettle`'s rings are the town's
fields, the farms, the hills and the rim, and `town`'s districts are
each a town.

A level is drawn at a scale.  `(scale N)` makes each cell N metres
across and the next number of the Fibonacci sequence, 1 2 3 5 8 13 21
34 ..., down; a terminal cell is about that shape, so ground keeps its
shape drawn.  A level with no scale is at 1, a metre by two, a person
a cell.  Every size a style takes -- a room, a house, a field, a
gallery, a scar -- is in metres, and comes out in cells at the level's
scale, never less than one, so one plan draws true at every scale; a
scale off the sequence is refused when the set is read.  A band's or
an interior's scale is in front of the set's, and an interior that
names none is at 1.  `kettle`'s valley is at
21, a screen near enough 1700 metres by 750, and `town` at 2.

A turn takes the time to walk a cell at the level's scale, a metre
and four tenths a second, a second at least: a second at 1 and 2,
fifteen on `kettle`'s valley.  The game keeps a clock of the seconds,
and food, `(starve N)` and `(regen N)` are counted on it, so a set
whose levels are at 1 plays a second a turn.  `(hunger STORE HUNGRY
WEAK MOST DEATH)` gives MOST, what eating fills to (2000), and DEATH,
the seconds under nothing a set with no `(starve N)` dies at (150);
`kettle` begins with half a day's food and holds a day's.

`(lamp FULL LOW)` gives the player a lamp holding FULL seconds of oil,
lit full at the start, or the first turn in the set when come from one
without.  It burns on the clock, says when LOW seconds are left and
when it goes out, and out, sight is the cells beside.  An `(item oil
NAME (oil N))` is N seconds of it, poured in with `f` to FULL at the
most.  `delve` holds half an hour, and its flasks five minutes each:
under it the lamp is what runs out, and food lasts the day.

What a cell is and how it is drawn are kept apart.  `roguelike/map`
reports each cell's kind of terrain -- floor, wall, door, water,
pillar, hedge, gate, bog and the rest, `map-terrain` listing each with
whether it can be walked on and whether it can be seen through -- and
the game turns on nothing else.  How a kind looks is the front-end's:
the terminal's, `roguelike/draw`, reads `(glyph KIND "g")` and `(colour
KIND N)`, a 256-colour index, from the set's `tui.xon`, and a kind the
set does not name is drawn as the kind it is a sort of.  Another
front-end reads its own file and the same terrain.

Sets can share one world.  `(join NAME)` brings the set NAME in beside
this one as a region: its forms are read with the set's and kept
apart, and a region's own joins are regions of the same world.  An
interior with `(region NAME)` is a door into that region instead of a
place of its own.  In it, the region's forms are the set in force, so
its places are made, peopled and drawn as that set makes them.  A
region that is a descent is gone down into, stairs and all, and the
stairs up out of its first level come back onto the door, open with or
without the region's goal.  A region that is a world of screens is
gone into on its hub, and a step off its edge comes back out onto the
door; where its screens, each at its own scale, fit on the screen the
door is on, its ground is drawn there walled at its size, the door on
the west face on the middle row.  Regions go inside regions: `kettle` joins `town`, Kettle itself,
whose door is on the valley's hub, and `town` joins `delve`, the pit on
its pithead going down into the Delve.  `(start NAME)` begins the game
through the door NAME on the hub: a game of `kettle` begins on
Kettle's square, and the goal brought home there is the win.  A
message a region does not say is said in the first set's words, and
the score is always the first set's.

A world of screens may name its screens: `(screen NAME (X Y) .
PROPS)` is screen X Y, its PROPS in front of its band's there, its
`(enter "TEXT")` said the first time there, and a world that names any
has only those.  `town` is five: the square, with the pithead north of
it, the river end south, the terraces east and Guild Street west, at
two metres a cell, each with its buildings: the inn and the council
house on the square, the engine house on the pithead, the mill on the
river, the chapel by the terraces, the Guild hall on Guild Street.

What a game is worth is the set's `(score (NAME POINTS) ...)`: POINTS
for each of `gold`, `deepest` (the level reached, or the screens out
from the hub), `won`, `quests` done, `screens` visited and `places`
gone into, and `(par TURNS POINTS)`, POINTS a turn under TURNS on a
win; what it does not name counts nothing.  A set without one scores
gold, fifty a level and a thousand for the win.  The end of a game
says a line for each, in the set's `(message score-NAME "TEXT")` where
it has one.  `kettle` counts its errands, the screens walked and the
doors gone through.

A set may offer ways to play it: `(choice GROUP NAME . FORMS)` is one,
picked with `-c GROUP=NAME`, `--choose GROUP=NAME`, one a group.  Its
forms go in front of the set's, so a knob the set has once is the
choice's and a form it has many of is added to.  `-h` with `--set`
lists what the set offers.  A save keeps a game's choices, and the
scores show them beside each game.  `kettle` offers `size` `small`, a
five by three valley and a short errand, `normal`, and `large`, the
longest errand the valley holds; and `difficulty` `easy`, `normal` and
`hard`, the creatures a screen and how hunger bites.

What lies about is dispersed by two forms any set may use.  An item's
`(depth LO HI)` is the levels, or the rings out from the hub, where it
may lie; one without lies anywhere.  A band's `(cache CLASS LO HI)`,
as many as it likes, lays that many things of CLASS a level, each
drawn by rarity from what the depth allows and laid out of view with a
keeper beside it, a creature of the depth, asleep unless wakeful: a
thing worth having and what stands between you and it.  `kettle`'s
three bands past the hub each have their word, their colour and their
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
