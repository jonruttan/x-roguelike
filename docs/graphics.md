# The game in a window

The windowed front-end draws the same game as the terminal one, from
the same state, with pictures in place of letters.  The terminal
front-end stays, and it is the reference: anything the window shows,
the terminal shows too.

## The screen

A screen 640 by 360 pixels, drawn in x as one RGBA buffer and scaled
whole to the window: 2x at 1280 by 720, 3x at 1920 by 1080, 4x at
2560 by 1440.  Tiles are 16 by 16; text is an 8 by 8 font, so a line
holds 80 letters, as the terminal does.

| Rows (pixels) | What | The terminal's |
|---|---|---|
| 0 to 23 | messages, two lines; a question asks here | the top row |
| 24 to 327 | the level, 40 tiles by 19 | the rows between |
| 328 to 359 | the standing: band and level (or screen), hit points as a bar, strength, armour, experience, gold, hunger and conditions | the last row |

- **The level** is 80 by 22, as in the terminal.  The window shows 40 by
  19 of it; the camera keeps the player in the middle, held inside the
  map, so it scrolls only when the player walks.
- **In view and seen**: cells in view drawn whole, cells seen before
  dimmed, rock black.  Found traps and items where they were seen;
  creatures only in view; the player last.  A warm glow round the
  player stands for the lamp.
- **Overlays**: a list looked at, the items a question can take, a
  choice, a page read, a talker's words, the world map and the end of
  the game lie over the level on a panel, as the terminal lays them
  over the rows.
- **More**: a message that runs past the strip waits on a marker at the
  strip's end, as `--More--` does.

## What every set needs

Every picture is keyed by the name the set already uses: the glyph's
name for the ground, the player and the item classes, the creature's
name for a creature.

| Group | Names | Count |
|---|---|---|
| ground | `floor` `wall` `door` `passage` `down` `up` `trap` | 7 |
| the player | `player` | 1 |
| items | `potion` `scroll` `wand` `ring` `weapon` `armour` `food` `gold` `goal`, and `page` `token` where the set has them | 9 to 11 |
| creatures | every `(creature NAME ...)` of the set, talkers each their own | classic 17, delve 23, kettle 28 |
| bands | a band's own `wall` and `floor`, where its place differs | delve 3, kettle 4, town 1 |
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

## Light

A level is dark but for what gives light.  `(light R G B N)` on a tile
makes it give light of that colour, reaching N cells; `(flicker P)`
makes it waver by P percent, as a flame does.

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
