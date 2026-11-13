# The game in a window

The windowed front-end draws the same game as the terminal one, from
the same state, with pictures in place of letters.  The terminal
front-end stays, and it is the reference: anything the window shows,
the terminal shows too.

## The screen

A screen 640 by 360 pixels, drawn in x as one RGBA buffer and scaled
whole to the window: 2x at 1280 by 720, 3x at 1920 by 1080, 4x at
2560 by 1440.  Tiles are 16 by 16, shown at the zoom (1 to 4, 2 at the
start).  Text is an 8 by 8 font cut to 6 wide, drawn at twice the
screen's pixel, the art's scale: a line holds 52 letters.

| Rows (pixels) | What | The terminal's |
|---|---|---|
| 0 to 41 | messages, two lines on a strip ruled off from the level, three over the level's top when they need it; a question asks here, brighter | the top row |
| 42 to 301 | the level, as many cells as fill it at the zoom | the rows between |
| 302 to 359 | the standing, three lines: the band and level (or the screen's name) and the gold; hit points as a bar coloured by how many are left, strength (amber when spent), armour, experience level, and conditions in amber; food and lamp oil each as a bar of what is left and its percentage, green, amber when hungry or low, red when weak, starving or dark | the last row |

- **The level** is 80 by 22, as in the terminal.  The window shows 20 by
  9 of it at the first zoom; the camera keeps the player in the middle,
  the view running past the map's edge onto rock, so it scrolls as the
  player walks.
- **Dragging the view**: the mouse dragged with its left button, shift
  with an arrow key, or the gamepad's right stick, moves the view off the player a cell at a
  time, as far as puts the view's middle on the map's edge, to look at
  what lies off the screen.  It shows only what has been seen, and no
  turn passes.  Any key brings the view back to the player.
- **In view and seen**: cells in view drawn whole, cells seen before
  dimmed, rock black.  Found traps and items where they were seen;
  creatures only in view; the player last.  A warm glow round the
  player stands for the lamp.
- **The chart**: the whole level, small, in the level's bottom right
  corner, two pixels a cell: what has been seen, brighter where in
  view, walls lighter than the ground; the ways down and up, doors,
  and in teal the ground beside what is not yet seen, still to
  explore, so a chart with no teal has nothing left; the creatures in
  view in red and the player blinking white.  It steps aside while a
  creature stands under it.
- **Off the screen**: a creature in view whose cell is off the screen
  (at a close zoom the player sees further than the screen shows) has
  a red arrowhead at the level's edge, where the line from the view's
  middle to it leaves the screen, pointing its way; the player has a
  white one while the view is dragged off it.
- **Marks**: what a creature or the player is under is drawn over it,
  from the set's `mark-NAME` pictures, moving with it and going round
  their pictures: a creature held or slowed; the player confused,
  blind, held, hasted, slowed, seeing, hungry, weak or fainting.  A
  creature asleep has two small z letters drifting up from it, fading
  as they rise, unless the set draws a `mark-asleep`.
- **Poses**: the player is drawn in the set's `(pose attack)` while its
  blow is shown, in `(pose hit)` while a blow that landed on it is
  shown (hit over attack when both), going round the pose's pictures,
  and in `(pose dead)` once dead.  A set with no pose draws the player
  as ever.
- **Steps**: a thing that stepped to a cell beside it glides there
  from the cell it left, over its shadow, in about a quarter of a
  second: quick off the mark, slowing, a pixel past and back.  Its
  pictures stay its new cell's.  A key pressed meanwhile is taken at
  once; exploring does not wait for it.
- **Blows**: after a turn with a fight, about half a second of it: the
  striker lunges toward its target and eases back, a blow that lands
  flashes the target (white for the player's, red for a creature's),
  the player's kill bursts where the creature was, and the damage, or
  "miss", rises from the target.  What flies flies first, from the
  striker to the target in about a quarter of a second, with no lunge:
  a thrown stone and its dust (a knocker's), a wand's bolt as a streak
  of light, breath as a gout of flame swelling as it goes.  A bolt that
  does no harm (a slowing, a banishing) flashes its target and writes
  nothing.  A blow from a cell in view with no one drawn there, an
  invisible creature's, stirs the air there instead: a pale ring
  widening from the cell.  The message says "Something unseen hits
  you." (`unseen-hit`, `unseen-miss`).
- **Overlays**: a list looked at, the items a question can take, a
  choice, a page read, a talker's words, the world map and the end of
  the game lie over the level on a panel, as the terminal lays them
  over the rows.
- **More**: a message that runs past the strip waits on a marker at the
  strip's end, as `--More--` does.

## Menus

The title screen, the options and the pause are drawn over the level,
dimmed (`paint-menu!`): the heading large, the title's larger still,
the items in a column with the chosen one bright and marked, and along
the foot what the keys do.  The foot names the gamepad's buttons, A on
green and B on red as the buttons are, when the last key came from the
pad, and the keyboard's otherwise.  The choice moves with the keys the
game takes for up and down; enter, space or A take it, Esc or B go
back, and left and right change an option (`roguelike/menu`).

## What every set needs

Every picture is keyed by the name the set already uses: the glyph's
name for the ground, the player and the item classes, the creature's
name for a creature.

| Group | Names | Count |
|---|---|---|
| ground | `floor` `wall` `door` `passage` `down` `up` `trap` | 7 |
| the player | `player`, and its poses `attack` `hit` `dead` | 1 to 4 |
| marks | `mark-confused` `mark-blind` `mark-held` `mark-hasted` `mark-slowed` `mark-seeing` `mark-hungry` `mark-weak` `mark-fainting` `mark-wounded` | up to 10 |
| items | `potion` `scroll` `wand` `ring` `weapon` `armour` `food` `gold` `goal`, and `oil` `page` `token` where the set has them | 9 to 12 |
| creatures | every `(creature NAME ...)` of the set, talkers each their own | classic 17, delve 23, kettle 28 |
| bands | a band's own `wall` and `floor`, where its place differs | delve 3, kettle 4, town 1 |
| roofs | `roof`, where the set lays a town | town |
| the screen | `panel` (a nine-piece frame), `shadow` | 2 |

Shared by every set, in `art/` at the top of the bundle: the font (the
95 printable letters), and the standing's icons.

Anything with no picture is drawn as its glyph in the font, in the
colour the terminal gives it.  A set with no art at all still plays in
the window.

A region (a set joined to the one the game began on, gone into by a
door: the town from the valley, the Delve from the town) is drawn with
its own set's art, and the art of the set the game began on behind it
for any name it draws nothing of: the region's ground is its own, the
world's people and things look the same wherever they are carried.

## The form

A set's pictures are in `data/SET/art/*.xon`.  The set is the `.xon`
files of `data/SET` alone, so the terminal game never reads these.

    (size 16 16)
    (colour "k" 20 16 15)          ; a colour named by one character
    (colour "j" 150 210 200 90)    ; with alpha; 255 unless given
    (tile wall (rows "hhRh..." ...))
    (tile "mine rat" (rows ...))
    (tile passage (as floor))
    (tile wall (band "The Flood") (rows ...))
    (tile panel (cut 8 8 8 8) (rows ...))

- `(rows ...)`: one string a row, one character a pixel, each a
  colour of the file.
- `(as OTHER)`: drawn as OTHER.
- `(band "BAND")`: the band's, in front of the set's.
- `(cut L T R B)`: a nine-piece picture; the corners kept, the edges
  and the middle stretched.
- Several tiles of one name are its variants: a cell takes one by its
  place, the same every frame, so a level looks worked and lived in
  (coal fallen from the tubs, a dropped sleeper, standing water, a pit
  prop, pick marks).  `(weight N)`: N chances to each 1 of a variant
  without one.
- `shadow` is drawn under the player and every creature, so they stand
  on the ground.
- `(part P)`: one piece of a tile, put together by its neighbours (see
  **Walls**).  A name with no parts is drawn whole.
- `(frames TICKS (rows ...) ...)`: the tile moves.  Its own rows are
  the first picture, each `(rows ...)` here the next, every one held
  TICKS of the window's ticks (about twelve a second), round and round:
  a flame, a drip, washing in the wind.  Each cell starts the round at
  its own place, so two flames never move together.  A front-end that
  does not move tiles draws the first picture.
- The player and a creature move two ways.  On the turn it steps to
  another cell it walks: its `(walk TICKS (rows ...) ...)`, or its
  frames where it has no walk, played once round in time, then it
  stands.  Standing, it fidgets: mostly the first picture, now and then
  another for a while, at no beat, each out of step with the rest.  A
  walk is drawn only for a step; a tile with frames and no walk still
  fidgets.  The players and the Delve's guardians walk; the rest of
  the living fidget.
- `(pose P)`: the player struck a blow (`attack`), took one (`hit`)
  or is `dead`, drawn in place of the player for that moment, its
  frames played once.  A pose is never a variant.
- `mark-NAME`: drawn over the player while it is in that state, mostly
  clear, with frames as any tile; several are drawn at once.  `slowed`
  is the cold's touch as much as a potion's; `fainting` is starving
  too, where the set starves; `wounded` is under a third of its hit
  points.  The marks are in each set's own colours, in `marks.xon`,
  and the poses in `poses.xon`.  A missing pose or mark is the plain
  player.

## Walls

The level is seen from above and a little to the south, so a wall shows
its face where the floor lies south of it and its top elsewhere.  A
neighbour is solid when it is wall or rock, off the map, or not yet
seen; anything else is open.

| The cell | Drawn |
|---|---|
| wall, open to the south | `face`; `face-w` / `face-e` where open to the west / east |
| wall, solid to the south | `top`; `n` `e` `w` rims where open that way; `ne` `nw` `se` `sw` where both sides are solid and the diagonal is open |
| open, solid to the north | its ground, then the `shade` the face casts |

Variants and weights hold within a part: a face may be propped,
seeping, chalked or hung with a lamp.

## Roofs

A town's buildings and houses are under roofs (see the README, `(plan
...)`).  A cell under a roof that is on is drawn from the set's `roof`
pictures and nothing that stands or lies there is drawn; the roof the
player stands under is off, and that building's cells are drawn as
they are.  A door into the building from the street is roof too, but
in the front, where the cell to the south is open, the `doorway` is
drawn over the front.  Outside every such door the ground has a
stoop, from the roof's pictures, on the side the door opens to:
`stoop-s` below a door in the front, `stoop-n`, `stoop-e`, `stoop-w`
by the others, so a door is found from the street; and above it a
dormer, a little peaked gable in the roof with a window: `dormer` on
the cell behind a front door, `dormer-n`, `dormer-e`, `dormer-w` on a
door in those walls.  Who stands in a
door is drawn.  In the terminal a roofed cell is the `(glyph roof
"^")`, and a door into the building is its own glyph wherever it is.

A roof is peaked, its ridge along its longer side, and a cell of it is
drawn by the slope it is on:

| The roof runs | The cell | Drawn |
|---|---|---|
| east and west | north of the ridge | `north`, the far slope, in shade |
| | on the ridge | `ridge` |
| | south of the ridge | `top`, the near slope |
| north and south | west of the ridge | `west` |
| | on the ridge | `ridge-ns` |
| | east of the ridge | `east` |

A roof as wide as it is deep runs east and west.  A ridge with no
middle row lies a row north of the middle, or a column west.  Over the
slope go the `n` `e` `w` rims, the far eaves and the verges, where the
roof ends that way, a neighbour solid when it is under a roof that is
on.

Where the cell to the south is open the cell is the building's front,
one part alone.  Under a roof running east and west it is `face`, the
eaves over the wall.  Under one running north and south it is the
gable, the wall rising to the ridge with the slopes behind it:

| The cell | Drawn |
|---|---|
| under the ridge | `gable`, the peak |
| beside the ridge, to the west or east | `gable-w`, `gable-e`, the rakes |
| further west or east | `gable-ww`, `gable-ee`, the low ends |

A set with no picture of a slope draws its `top` there, one with no
picture of a gable its `face`, and a set with no `roof` its `wall`.

## Ground that joins

Ground with a `n` part is joined into one stretch with its neighbours:
water and shallows in `data/delve/art/water.xon`.  A neighbour runs on
when it is the same kind, water beside water, a wall, or not yet seen;
anything else ends the stretch with a bank.

| Neighbours | Drawn over the ground |
|---|---|
| one side ends | that side's `n` `e` `s` `w` bank |
| two sides that meet both end | the round outer corner, `out-ne` `out-nw` `out-se` `out-sw` |
| two sides run on, the diagonal between them ends | the notch, `ne` `nw` `se` `sw` |

The deep levels stand in shallows: below level 3 of the delve each
level has more of its floor under water, set in `game.xon` as
`(shallows FROM PER MOST)`.

## Light

A level is dark but for what gives light.  `(light R G B N)` on a tile
makes it give light of that colour, reaching N cells; `(flicker P)`
makes it waver by P percent, as a flame does.  A light the front-end
makes may end in a tint, how hard it takes the cells toward its
colour in percent.

- The level is drawn, then darkened; each light lifts the dark round
  it, falling off to nothing at N cells, and tints it its colour.  A
  light reaches only the cells it can see.
- A flicker moves the light's reach and strength together, by a few
  slow and quick waves, each light out of step with the rest; the
  window redraws about twelve times a second while a light flickers.
- Delve's lights: the player's lamp, the lampman's, the firedamp's
  cold glow, the Lodestar's, and a salvager's candle stub on a face
  here and there.  The Galleries' own lamps are long out (the band's
  word on arrival), so no torch burns in a bracket there.  Deeper, the
  light is the stone's water: "light from the rock".
- What the player carries: the lantern while the lamp burns.  A ring
  of light lays a cold blue over it, out as far as the ring
  reaches, and with the lamp out is the only light.
- A ring worn casts an odd light of its own, two cells round the
  player, pulsing and tinting hard, so the lantern does not wash it
  out.  Its colour is its guise's, `(glow GUISE R G B)` in
  `art/glows.xon`, so a ring not yet known shows only what it looks
  like; a guise with no glow is a pale lilac.  The art spec holds
  every ring guise of a set to a glow.

Text, so it is read with `x/codec/xon`, diffed, and drawn by hand; no
image tools.  Turned into RGBA once when the set is loaded.

The font, `art/font.xon`, is every set's: `(size 8 8)`, then `(letter
CODE (rows ...))` for each printable character, "#" ink and "."
clear, tinted by the front-end to the colour the terminal would give
the text.  A letter sits in columns 1 to 5, capitals on rows 0 to 6,
descenders on row 7.

## Each set's look

Gritty and worked, a little toward the real: muted, sooty colours;
figures with a person's proportions, small heads and no cartoon eyes;
things worn, patched, rusted and dropped.  A world people live in.

- **classic**: an old dungeon, grey stone and torchlight.
- **delve**: the drowned mine.  The Galleries: sandstone, shale and a
  coal seam, timber and iron.  The Flood: wet rock streaked with ochre,
  standing water.  The Old Works: dressed limestone laid without
  mortar.  The Heart: the stone's dark glassy rock and its pool.
- **kettle**: the dale above.  The town: soot-dark stone, slate.  The
  farms: hedges and hay.  The hills: heather, gritstone and bog.  The
  far valley: limestone pavement and scar.
