# The game heard
# @weight 2

The delve set's sounds and songs (see `docs/sound.md`): every song a
tracker can play, every name a cue or a place gives a sound or a song the
set has, and every sound rendered to frames. Nothing here opens an audio
device.

## the data

### every song makes a tracker, and every place's music and bed is a song

```roguelike
(import x/audio/tracker)
(def spec-set (data-load "data/delve"))
(def spec-songs (data-all spec-set 'song))
(def spec-song? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) spec-songs)))
(def spec-beds (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'bed) #f)) (rest a)))) (data-all spec-set 'ambience)))
(write (list (List all? (fn (_ s) (str? (Tracker name (Tracker make (pair 'song s))))) spec-songs)
             (List all? (fn (_ m) (spec-song? (List ref 1 m))) (data-all spec-set 'music))
             (List all? spec-song? spec-beds)
             (< 0 (List length spec-beds))))
```
---
    (#t #t #t #t)

### every fight and guardian's theme is a song, every band has a fight, and every guardian a theme

```roguelike
(def spec-set (data-load "data/delve"))
(def spec-song? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all spec-set 'song))))
(def spec-named? (fn (_ head n) (List any? (fn (_ f) (str=? (first f) n)) (data-all spec-set head))))
(def spec-bands (data-all spec-set 'band))
(write (list (List all? (fn (_ f) (spec-song? (List ref 1 f))) (data-all spec-set 'fight))
             (List all? (fn (_ f) (spec-song? (List ref 1 f))) (data-all spec-set 'boss))
             (List all? (fn (_ b) (spec-named? 'fight (first b))) spec-bands)
             (List all? (fn (_ b) (spec-named? 'boss (data-prop1 b 'guardian ""))) spec-bands)
             (< 0 (data-get spec-set 'fight-turns 0))))
```
---
    (#t #t #t #t #t)

### every cue, footstep, heartbeat and random sound names a sound of the set

```roguelike
(def spec-set (data-load "data/delve"))
(def spec-sound? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all spec-set 'sound))))
(def spec-randoms (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'random) #f)) (rest a)))) (data-all spec-set 'ambience)))
(write (list (List all? (fn (_ c) (spec-sound? (List ref 1 c))) (data-all spec-set 'cue))
             (List all? (fn (_ c) (spec-sound? (List ref 1 c))) (data-all spec-set 'footstep))
             (spec-sound? (first (data-one spec-set 'heart ())))
             (List all? spec-sound? spec-randoms)))
```
---
    (#t #t #t #t)

### every cry names a sound of the set and a creature of it, and there is a default

```roguelike
(def spec-set (data-load "data/delve"))
(def spec-sound? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all spec-set 'sound))))
(def spec-kind? (fn (_ n) (List any? (fn (_ k) (str=? (first k) n)) (data-all spec-set 'creature))))
(def spec-cries (data-all spec-set 'cry))
(write (list (List all? (fn (_ c) (spec-sound? (List ref 1 c))) spec-cries)
             (List all? (fn (_ c) (if (str=? (first c) "default") #t (spec-kind? (first c)))) spec-cries)
             (List any? (fn (_ c) (str=? (first c) "default")) spec-cries)
             (< 0 (data-get spec-set 'cry-falloff 0))))
```
---
    (#t #t #t #t)

### every sound renders to frames

```roguelike
(import x/audio/mixer)
(def spec-set (data-load "data/delve"))
(List for-each (fn (_ w) (Mixer wave! (first w) (rest w))) (data-all spec-set 'wave))
(def spec-voices (fn (_ s) (List map rest (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'voice) #f)) (rest s)))))
(write (List all? (fn (_ s) (< 0 (rest (Mixer render 8000 (spec-voices s) ())))) (data-all spec-set 'sound)))
```
---
    #t
