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

### every said, condition and bonus sound names a sound of the set, and every bonus a ring's

```roguelike
(def spec-set (data-load "data/delve"))
(def spec-sound? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all spec-set 'sound))))
(def spec-heard (fn (_ head) (List flat-map (fn (_ f) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (List includes? (first p) '(on off every struck strikes mends)) #f)) (rest f)))) (data-all spec-set head))))
(def spec-bonuses (List flat-map (fn (_ r) ((fn (_ b) (if (null? b) () (list (symbol->str (first b))))) (data-prop r 'bonus ()))) (List filter (fn (_ i) (eq? (first i) 'ring)) (data-all spec-set 'item))))
(write (list (List all? (fn (_ s) (spec-sound? (List ref 1 s))) (data-all spec-set 'said))
             (List all? spec-sound? (spec-heard 'condition))
             (List all? spec-sound? (spec-heard 'bonus))
             (List all? (fn (_ b) (List any? (fn (_ n) (str=? n (first b))) spec-bonuses)) (data-all spec-set 'bonus))
             (< 0 (List length (spec-heard 'bonus)))))
```
---
    (#t #t #t #t #t)

### the Kettle world's songs make trackers, and its music, fights, beds, footsteps and random sounds are the world's

```roguelike
(import x/audio/tracker)
(def spec-k (data-load "data/kettle"))
(def spec-world (List append spec-k (List flat-map rest (data-all spec-k 'region))))
(def spec-named? (fn (_ head n) (List any? (fn (_ f) (str=? (first f) n)) (data-all spec-world head))))
(def spec-props (fn (_ head key) (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest a)))) (data-all spec-world head))))
(write (list (List all? (fn (_ s) (str? (Tracker name (Tracker make (pair 'song s))))) (data-all spec-world 'song))
             (List all? (fn (_ m) (spec-named? 'song (List ref 1 m))) (List append (data-all spec-world 'music) (data-all spec-world 'fight)))
             (List all? (fn (_ b) (spec-named? 'song b)) (spec-props 'ambience 'bed))
             (List all? (fn (_ f) (spec-named? 'sound (List ref 1 f))) (data-all spec-world 'footstep))
             (List all? (fn (_ r) (spec-named? 'sound r)) (spec-props 'ambience 'random))
             (List all? (fn (_ b) (spec-named? 'music (first b))) (data-all spec-k 'band))))
```
---
    (#t #t #t #t #t #t)

### every sound of the Kettle world, the Delve's among them, renders to frames

```roguelike
(import x/audio/mixer)
(def spec-k (data-load "data/kettle"))
(def spec-set (List append spec-k (List flat-map rest (data-all spec-k 'region))))
(List for-each (fn (_ w) (Mixer wave! (first w) (rest w))) (data-all spec-set 'wave))
(def spec-voices (fn (_ s) (List map rest (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'voice) #f)) (rest s)))))
(write (List all? (fn (_ s) (< 0 (rest (Mixer render 8000 (spec-voices s) ())))) (data-all spec-set 'sound)))
```
---
    #t

### every room, music effect and held effect of the Kettle world is one the mixer takes, and every room is a place's

```roguelike
(import x/audio/mixer)
(def spec-t (data-load "data/kettle"))
(def spec-world (List append spec-t (List flat-map rest (data-all spec-t 'region))))
(def spec-m (Mixer make 8000 256))
(def spec-takes? (fn (_ spec) (guard (e #f) (do (Mixer effect! spec-m 'spec spec) #t))))
(def spec-held (fn (_ key) (List flat-map (fn (_ f) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest f))))
                                (List append (data-all spec-world 'condition) (data-all spec-world 'bonus)))))
(def spec-place? (fn (_ n) (List any? (fn (_ f) (str=? (first f) n)) (List append (data-all spec-world 'ambience) (data-all spec-world 'music)))))
(write (list (List all? spec-takes? (List flat-map rest (data-all spec-world 'room)))
             (List all? spec-takes? (List map first (data-all spec-world 'music-effect)))
             (List all? spec-takes? (spec-held 'effect))
             (List all? (fn (_ r) (spec-place? (first r))) (data-all spec-world 'room))
             (List all? (fn (_ n) (< -10000 n)) (List append (spec-held 'pitch) (spec-held 'pace) (spec-held 'muffle)))
             (List map (fn (_ l) (List length l)) (list (data-all spec-world 'room) (spec-held 'effect) (spec-held 'pitch)))))
```
---
    (#t #t #t #t #t (11 3 3))
