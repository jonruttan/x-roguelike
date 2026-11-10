# Sound

The game played in a window (`-w`) is heard as well as seen. Everything
it plays is synthesised as it runs from a set's data: there are no
recordings and no sound files. The music is played by a tracker, the
effects are rendered from descriptions of their voices, and both are
mixed by x-lang's `x/audio/mixer` and played on SDL's audio streams
(`x/sys/sdl`). A set with no `(sound ...)` forms is silent, and so is a
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
| `step` | the player moves; the sound is the terrain's, from `(footstep "TERRAIN" "SOUND")` (`"default"` for the rest), at `(stealth-steps PCT)` percent with a ring of stealth on |
| `miss`, `hit`, `kill` | the player's blow, placed by where the creature stands |
| `struck`, `dodged` | a creature's blow on the player, landed or missed |
| `hurt`, `low` | hit points lost; `low` when the loss takes them under `(low-hp PCT)` of the most |
| `healed` | hit points back, a quarter of the most or more |
| `level` | a level gained |
| `pickup`, `gold` | something taken into the pack, gold found |
| `stairs`, `arrived` | a level down or up; the first level of a new band |
| `hungry`, `weak` | hunger crossing the set's `(hunger ...)` marks |
| `afflicted`, `relieved` | a condition taken on, one worn off |
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

## Fear

Tension, 0 to 100, is what the player has to fear: each creature awake
and in sight counts the more the nearer it is, `(tension-near N)` a cell,
and wounds count past `(tension-hp PCT)` of the player's hit points. It
rises quickly and falls slowly. It quickens the music, brings in its
tension layer and takes away its calm one, and the bed's dread under
both. Past `(heart "SOUND" FROM SLOW FAST)`'s FROM the player hears
their own heart, SLOW beats a minute rising to FAST and growing louder
as the tension reaches 100.

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

`(music "PLACE" "SONG")` names a place's song, and `(ambience "PLACE"
(bed "SONG") (random "SOUND" EVERY-MS GAIN) ...)` its air: a bed song
under the music and sounds heard at random, once in EVERY ms or so. A
place is a band's name, a region's, or `"default"`. `(music-gain PCT)`
and `(music-echo MS FEEDBACK WET)` are the music's loudness and room.

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
