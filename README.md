# x-roguelike

A roguelike on x-lang, as a lang bundle: a dungeon of rooms and
passages made anew each game, creatures that wake and hunt, things to
find and work out, hunger, and one life.  Every creature, item, guise,
message and tuning number is read from a set of `.xon` files, so a set
is a game of its own on the same engine; `classic` is the one shipped.

    x -l roguelike -- play [-set NAME] [-seed N] [-data DIR]
    x -l roguelike -- scores

The goal lies on the deepest level.  Held, it opens the stairs up, and
every level climbed is made again, roused and hostile; the surface is
the win.  `S` saves a game for the next sitting; the save is read once.
Scores keep in `~/.x-roguelike/scores`.

## Keys

    h j k l y u b n   move; the arrows too.  Walk into a creature to attack it.
    .  s              rest a turn              ,  g      pick up what is here
    >                 go down the stairs       <         go up, with the goal
    i                 your pack                d         drop a thing
    q                 quaff a potion           r         read a scroll
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
another directory: `-set NAME` under the bundle's `data/`, or `-data
DIR` for any directory.  The engine reads a closed vocabulary of traits
and effects; a set combines them as it likes.

## Running the suite

    make test            every spec, loudly
    make check           the suite against tests/contract/known-failures.txt

The specs drive a game from a seed with keys and read the state and
the screen back; nothing in them touches a terminal.

## Installing

    make install         into <share>/langs/roguelike, where `x -l` looks

## Licence

MIT No Attribution.  See [LICENSE](LICENSE).
