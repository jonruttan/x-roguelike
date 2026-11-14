# Sound

The game played in a window (`-w`) is heard as well as seen. Everything
it plays is synthesised as it runs from a set's data: there are no
recordings and no sound files. The music is played by a tracker, the
effects are rendered from descriptions of their voices, and both are
mixed by x-lang's `x/audio/mixer` and played on SDL's audio streams
(`x/sys/sdl`). A world with no `(sound ...)` forms is silent, and so is a
host with no audio device or no JIT to compile the mixer's loops; the
game plays the same either way.

`roguelike/sound.x` does the hearing. Each turn it compares the game
before and after and plays what changed. `data/delve/sounds.xon` and
`data/delve/music.xon` are the delve set's sounds.

## Voices and sounds

A voice is one oscillator: a wave read at a pitch, shaped by an envelope,
through a low-pass, placed left or right.

| Prop | Meaning |
|---|---|
| `(wave NAME)` | `sine` (the default), `noise`, or a `(wave ...)` of the set |
| `(note "C4")` or `(hz N)` | pitch: a note's name (`F#3`, `Bb2`) or hertz; noise is played at `(hz 1)` |
| `(slide PITCH)` | the pitch it slides to over its envelope |
| `(env (MS PCT) ...)` | its level, straight lines between points; the voice ends at the last |
| `(cut PCT)` | the low-pass, 100 open, 1 a dull rumble |
| `(filter (MS PCT) ...)` | the low-pass's path, PCT of its cut at each MS, straight between: a sound that opens or closes |
| `(bend (MS CENTS) ...)` | the pitch's path, CENTS from it at each MS, straight between and a jump where two share an MS |
| `(pan -100..100)` | left to right |
| `(gain PCT)`, `(detune CENTS)`, `(at MS)` | its loudness, a little off its pitch, a delay before it starts |

`(wave NAME A1 A2 ...)` makes a wave of harmonics, from the fundamental:
`(wave hollow 6 0 2 0 1)` has only the odd ones.

`(sound "NAME" PROP ... (voice PROP ...) ...)` is a sound of any number of
voices. `(gain PCT)` is the whole sound's, `(vary CENTS)` plays it a little
flat or sharp at random so that a step is never quite the last, and
`(echo MS FEEDBACK WET)` gives it a room. A sound is rendered once, the
first time it is wanted, at each of three pitches and three places.

## Cues

`(cue "EVENT" "SOUND")` names the sound for each thing a turn can do:

| Event | When |
|---|---|
| `step` | the player moves; the sound is the terrain's, from `(footstep "TERRAIN" "SOUND")` (`"default"` for the rest), shaped by the conditions and bonuses (below) |
| `miss`, `hit`, `kill` | the player's blow, placed by where the creature stands |
| `struck`, `dodged` | a creature's blow on the player, landed or missed |
| `hurt`, `low` | hit points lost; `low` when the loss takes them under `(low-hp PCT)` of the most |
| `healed` | hit points back, a quarter of the most or more |
| `level` | a level gained |
| `pickup`, `gold` | something taken into the pack, gold found |
| `bought`, `sold` | gold paid at a counter; gold taken for something out of the pack |
| `stairs`, `arrived` | a level down or up; the first level of a new band |
| `hungry`, `weak` | hunger crossing the set's `(hunger ...)` marks |
| `afflicted`, `relieved` | a condition taken on, one worn off, when its `(condition ...)` has no `on` or `off` |
| `lamp-lit`, `lamp-low`, `lamp-out` | the set's `(lamp FULL LOW)` lit or filled, burning down past LOW, gone out |
| `died`, `won` | the end |
| `volume` | the sounds made louder or quieter in the window, at the new loudness |

`(cry "KIND" "SOUND")` is the cry of a creature of KIND that a turn
woke, heard whether it is seen or not, `(cry "default" "SOUND")` for the
kinds with none. It is `(cry-falloff PCT)` percent quieter for each cell
past the first between it and the player, and unheard when that comes to
nothing, and placed left or right by where the creature stands.

In the window, M mutes the sound and brings it back, and [ and ] make
the music and the sounds quieter and louder together, a tenth at a time;
the options screen sets each alone. Both are kept with the options.

## Messages

`(said "KEY" "SOUND")` is heard when a turn tells the message KEY (the
keys of `messages.xon`), each key once a turn. A key whose event has a
cue (a blow, gold, the stairs, hunger, the lamp) is left to the cue, so
it is not heard twice.

## Conditions and bonuses

`(condition "NAME" PROP ...)` shapes what is heard while the player is
under the condition NAME (confused, slowed, hasted, held, blind,
seeing), and `(bonus "NAME" PROP ...)` while they wear a ring whose
`(bonus NAME N)` it is. A ring is heard whether its kind is known or
not, so it can be told by ear.

| Prop | Heard |
|---|---|
| `(on "SOUND")`, `(off "SOUND")` | as it begins, as it ends |
| `(every "SOUND" EVERY-MS GAIN)` | now and again while it holds, as the place's random sounds are |
| `(steps CENTS WANDER PCT)` | the player's steps CENTS sharper (flatter below nought), a side off up to WANDER percent of the time, at PCT percent; more than one at once add their CENTS, take the most WANDER and multiply their PCT |
| `(struck "SOUND")` | with a blow that lands on the player |
| `(strikes "SOUND")` | with a blow the player lands |
| `(mends "SOUND")` | with hit points come back a little at a time |
| `(pitch CENTS)` | the music and the air CENTS higher (lower below nought); more than one add |
| `(pace PCT)` | the music and the air at PCT percent of their tempo; more than one multiply |
| `(sway PCT PERIOD-MS)` | the music's tempo swung PCT percent faster and slower than its pace and back, once in PERIOD-MS; the widest is heard |
| `(muffle PCT)` | the music and the air through a low-pass closed to PCT percent; the most closed is heard |
| `(effect SPEC)` | an effect over the music and the air, as a room's (Music, below) |

## Fear

Tension, 0 to 100, is what the player has to fear: each creature awake
and in sight counts the more the nearer it is, `(tension-near N)` a cell,
and wounds count past `(tension-hp PCT)` of the player's hit points. It
rises quickly and falls slowly. It quickens the music, brings in its
tension layer and takes away its calm one, and the bed's dread under
both. Past `(heart "SOUND" FROM SLOW FAST)`'s FROM the player hears
their own heart, SLOW beats a minute rising to FAST and growing louder
as the tension reaches 100.

Wounds thin what is heard. Under `(thin-hp FROM MOST)`'s FROM percent of
the player's hit points, the music, the air and the turn's sounds lose
their low end, toward MOST percent of it gone with none left: the fewer
the hit points, the tinnier the world. The heart is heard whole, on a
mixer of its own, so neither the thinning nor a room nor a condition
touches it.

A hungry stomach growls. `(growl "SOUND" SLOWEST-MS FASTEST-MS GAIN)` is
heard once in SLOWEST-MS or so when the food first falls under the
hungry mark of `(hunger ...)`, and more often as it runs out, once in
FASTEST-MS with none.

## Music

`(song "NAME" ...)` is a tracker song (x-lang's `x/audio/tracker`):

```
(song "galleries" (bpm 60) (rows 2) (tension-bpm 46)
  (instrument pluck (wave reed) (cut 20) (env (0 0) (4 55) (1800 0)) (release 500))
  (instrument pulse (layer tension) (wave sine) (env (0 0) (6 90) (180 0)))
  (pattern ga
    (pluck "E4 .  C4 .  .  .  A3 .")
    (pulse "A1 .  .  .  A1 .  .  ."))
  (order ga ga gb gc))
```

An instrument is a voice's props, with `(release MS)`, `(layer calm)` or
`(layer tension)`, and any number of `(voice ...)`, each a voice of its
own over the shared props. A pattern's channel is a string of cells, a row
each: a note starts that note, `.` carries on, `-` lets it go, and
`NOTE:PCT` plays at PCT percent. A voice with a pitch of its own keeps it,
as a drum does.

A cell can carry effects after its note, `/` then a letter and its
numbers, timed in ticks, `(ticks N)` a row (6 unless the song says):
`E3/v14,16` wavers 14 cents either way every 16 ticks. The letters are
`a` arpeggio, `v` vibrato, `s` slide, `p` portamento from the channel's
last note, `t` tremolo, `f` fade, `l` low-pass, `c` cut, `d` delay and
`r` retrigger (x-lang's `x/audio/tracker` has the whole of each). The
Galleries' strained note wavers, the Flood's undertow sinks as it is
held, and the Old Works' grind beats.

`(music "PLACE" "SONG")` names a place's song, and `(ambience "PLACE"
(bed "SONG") (random "SOUND" EVERY-MS GAIN) ...)` its air: a bed song
under the music and sounds heard at random, once in EVERY ms or so.
The places are looked for nearest first: the named building whose roof
is over the player, the interior stood in, then the band, else the
region, and `"default"` for the rest. A building or an interior with air
or a song of its own is heard so inside, and what it lacks is the
place's around it: the town's inn plays a reel by its fire, its
churches a hymn, and a valley cellar has no wind in it.
`(music-gain PCT)` and `(music-echo MS FEEDBACK WET)` are the music's
loudness and room; the echoes are those of the set the game began on.
`(music-effect SPEC)`, from any set of the world, is an effect over all
of it: the Delve's `(limit 92 150)` keeps the music under clipping
however its rooms and conditions stack.

`(room "PLACE" SPEC ...)` is a place's room: effects over the music and
the air while the player is there, found as `(ambience ...)` is, the
nearest place first. A SPEC is any of `x/audio/mixer`'s effects:
`(echo MS FB WET)`, `(reverb SIZE DECAY WET)`, `(phase LEAST-MS MOST-MS
PERIOD-MS FB WET)`, `(chorus VOICES MS DEPTH-MS PERIOD-MS WET)`, `(drive
GAIN WET)`, `(crush BITS HZ)`, `(sweep LOW-HZ HIGH-HZ PERIOD-MS RES)` or
`(limit CEILING RELEASE-MS)`. The Flood is wide and wet, the Old Works
grits its teeth, the Heart rings, and the town's churches ring too while
the inn stays close. A turn's own sounds keep the room each was made
with.

A condition or a bonus can change the music and the air while it holds
(see Conditions and bonuses): slowed plays them slower and lower,
hasted faster and higher, confused swirls them and sways their tempo, held strains them, the
seeing shimmer, and the blind and the stealthy hear them as through a
wall.

Every form here is looked for in the set stood in first, then in the set
the game began on and each of its regions. A region's own songs, beds and
footsteps are heard there, and what it lacks is the world's: the valley
and the town (`data/kettle`, `data/town`) have their own music and air,
the town its counter's coins, and the blows, cues and cries of the
Delve's set.

`(fight "PLACE" "SONG")` is the place's fight song: a blow struck either
way brings it in, and it plays until `(fight-turns N)` turns pass without
one, or until a turn ends with no creature awake and in sight.
`(boss "NAME" "SONG")` is a band's guardian's theme (the band's
`(guardian NAME)`, on the band's last level): it starts once the guardian
is awake and seen, or within `(boss-near N)` cells, and plays until the
guardian dies or the level is left. A guardian's theme comes before a
fight song, and a fight song before the place's music. A change of music
is made at once.

A voice's `(detune CENTS)` is for a few cents off a note, to thicken it:
the mixer's detune is near enough only for small amounts, so an interval
is written as a note of its own.
