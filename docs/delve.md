# The Delve

The universe the `delve` and `kettle` sets share: a mining town, the
Guild that runs it, and what the mine broke into.  This file keeps it
believable from one set to the next.

Narrative is the backbone.  People explore a world to find out what
happened in it and to take a hand in what happens next; everything a
set adds serves that.  An errand is a piece of the story, a page is a
witness, a map is evidence: a shuttered door says someone left, a
cold chimney says the pumps stopped.  A mechanic that tells nothing
about the world earns its place some other way or goes.

**Canon** is what a shipped set says, in its pages, scenes, quests,
messages and names; each entry names where.  **Ideas** are proposals
until a set ships them.  A set's text never contradicts canon; when it
ships something new, it goes into canon here in the same PR.

All of it is original to x-roguelike: no names, people, places or text
from any other game or book.

## Canon

### The valley

- Kettle is a town in a valley, the valley above the Delve.  Seven
  screens by five; the town's square is in the middle, with the
  well-head in it.  (`kettle/game.xon`, `kettle/messages.xon`)
- Out from the square: the farms, hedged fields and the road; the
  hills, sheep tracks through the gorse and the bog in the low ground;
  the far valley, the old city's stones, and the Guild's men about
  them.  (`kettle/game.xon` bands)
- Behind doors: farmhouse cellars, shepherd's bothies left in a hurry,
  and the old city's vaults, which the Guild has dug into and which
  run on past where it dug.  (`kettle/interiors.xon`)
- Kettle's wells are fed by the Lodestar, below.  (`delve/pages.xon`,
  the mason's mark)

### The Pump Guild

- The Pump Guild of Kettle runs the mine: coal, wages, the pumps and
  the engine house.  It keeps ledgers, sits in council, and has
  bailiffs who carry crossbows.  (`delve/pages.xon`,
  `kettle/creatures.xon`)
- When its men broke into the old works, it cut coal to the pumps and
  told the engine house to run them harder.  When the surveyor
  reported what lay below, it resolved to bring the Lodestar up and sell
  it to the dry towns east, and left the wells of Kettle "the town's
  concern, not the Guild's".  (`delve/pages.xon`, the ledger pages)
- The Guild sealed its ledger.  Its bailiff kept it under the pump-house
  floor and died; his widow means it to go to the town.  A Guild clerk
  copied it before it was sealed.  (`kettle/scenes.xon`)
- The Guild writes sealed orders, and its men in the far valley would
  rather the ledger stayed lost.  (`kettle/scenes.xon`,
  `kettle/creatures.xon`)

### The town

- Kettle has a council, which writes letters, and will not act against
  the Guild without the Guild's own sealed order in hand.
  (`kettle/scenes.xon`)
- The pumps have stopped.  The watchman has had a cold night every
  night since.  (`kettle/scenes.xon`)
- The people of the errands: the bailiff's widow, the Guild clerk, the
  night watchman, the smith, the ferryman, the innkeeper, the miller,
  the surveyor, the councillor, the carter, the eel-catcher, the
  pedlar, the millwright, the scrap-picker, the chandler, the
  knife-grinder, the woodcutter, the cobbler and the tanner.  What each
  wants and gives is in `kettle/scenes.xon`.
- Kettle's own trade, from those scenes: a pump house, a forge, a mill
  on a race, a ferry, an inn with a cellar, a weir, a tannery, a
  woodlot of oak seasoned three summers.

### The Delve

- The mine under Kettle, twelve levels in four bands: the Galleries,
  the worked mine, propped and railed; the Flood, where the water runs
  one way; the Old Works, dressed stone set without mortar, older than
  the mine; the Heart, where the stone moves and the water is quiet.
  (`delve/game.xon`)
- The breach: at the end of the east drift the crew broke into a
  squared wall, and a dry passage running down.  (`delve/pages.xon`)
- The water of the galleries does not rise; it drains down into the
  old works, toward the breach.  "Something below is drinking the
  mine."  (`delve/pages.xon`, the surveyor's note)

### The old city and the Lodestar

- A city with no name anyone can read built a well-house around the
  stone that drinks.  It gathers the water of the hills to itself and
  holds it; while it lies there the valley has wells; lift it and the
  water follows.  Kettle's wells are that city's.  (`delve/pages.xon`,
  the mason's mark)
- Keepers guard it: stone that walks, the hollow mason, the Lodestar's
  keeper.  (`delve/pages.xon`, `delve/game.xon`)
- Lifted, the Lodestar brings the water up every stair behind it; the
  Delve fills and the breach goes under a lake.  Kettle keeps its wells;
  the Guild loses a mine.  (`delve/pages.xon`, Hollis's note)

### The people of the Delve

- The foreman: posted lamps at the breach, went down with the six the
  Guild ordered past it, sent the rest back up after nine days.  "Do
  not bring it up for them."  (`delve/pages.xon`)
- Tam, lost at the fourth stair.  (`delve/pages.xon`)
- Hollis, the pump-wright, who stayed below to make the pump draw.
  (`delve/pages.xon`, `delve/quests.xon`)
- Ada, to whom an unsent letter is written: keep the pump-house door
  barred.  (`delve/pages.xon`)
- The lamp-keeper, who kept the lamps at the breach and did not come
  back up.  The surveyor, below, who lost a chain and a glass to the
  water.  (`delve/quests.xon`)

### The two stories

- **The Delve**: go down twelve levels and bring the Lodestar up; the
  water closes behind you.  (`delve/messages.xon`)
- **Kettle**: find the Guild's ledger through a chain of errands and
  lay it on the well-head; Kettle has its proof, and the Guild has lost
  its mine.  (`kettle/messages.xon`)

### Its time

Early industrial: coal-fired pumps, engine houses, lamps, crossbows,
ledgers, sealed orders, letters, a ferry.  No gunpowder has been named.

## Open questions

Things canon leaves undecided, to settle before a set leans on them.

- Which comes first, Kettle or the Delve?  Kettle's pumps have stopped,
  so Kettle's story is after the breach; whether it is before or after
  the Lodestar comes up is open.
- The surveyor: the Delve's surveyor went below and lost a chain and a
  glass to the water; Kettle's surveyor lost the brass end of a chain to
  a crow and levels for the council.  One person or two?
- What the ledger proves: the Guild's resolution to sell the Lodestar,
  the cut coal, or more?
- Ada: who she is, and whether the pump-house door was barred.

## The town of Kettle: design notes

What a believable Kettle needs on the map, roughly in order of what it
does for the town.

- **The work and the water lay it out.** A mining town grows along the
  road to the pithead and the road out to the farms: the main street
  runs from the square to the Delve's mouth, the farm road the other
  way.  Roads cross the screens' edges where the next screen agrees,
  so the valley reads as one place.  Water is the story: the well-head
  in the square, troughs, the race and the river at the low end.
- **Who lives where.** Miners' terraces near the pithead; the Guild's
  larger, better-built houses and its hall near the square; the poor at
  the edges and down by the water; gardens, sheds and allotments where
  the town thins into the farms.
- **Landmarks to go into.** The pump house, the Guild hall, the council
  house, the inn, the smithy, the engine house, a chapel and a
  graveyard of miners.  Most doors stay shut; the few that matter open.
- **Materials, then adornment.** Stone and slate from the mine for the
  Guild and the town's public buildings, timber and rubble for the rows.
  Then what people add: painted doors, the inn's sign, the smith's,
  window boxes, a notice board in the square.  A door's colour or a sign
  read on a look carries a lot for very little.
- **Its state tells the story.** Shuttered and locked doors where people
  have left, a spoil heap, the engine house with a cold chimney, the
  flooded shaft.

What the engine needs for these, most effect first: roads that meet at
the screens' edges; features, single things such as the well-head, a
trough or a notice board, each a glyph with a look; named interiors on
chosen town doors; colour by building or door, not only by band.

## Ideas

Proposals, not canon.

- The dry towns east, who would buy the Lodestar: their own set, or the
  Guild's buyers arriving in Kettle.
- Other well-houses: did the old city build one stone, or many?
- The Guild from the inside: who sits in its council, and who in it
  argued against the sale.
- Pages in Kettle as the Delve has them: notices on the board, letters,
  the clerk's copy of the ledger read a leaf at a time.

## The voice

- People talk about their work, their debts and the weather; nobody
  makes a speech.  Lines are short and concrete: a key, a flask, a
  sack of flour.
- What is known is said plainly; what is not known stays unsaid.  The
  old city has no name because nobody can read it.
- Canadian spelling: colour, centre, grey, travelled.
