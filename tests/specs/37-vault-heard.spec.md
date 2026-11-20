# The Sunken Vault heard
# @weight 2

The classic set's sounds (see `docs/sound.md`): its own songs, air and
cries, and the Delve's waves, blows and cues borrowed by `(sounds-from
"delve")` without the Delve becoming a place in its world.  Nothing here
opens an audio device.

## borrowed, not joined

### the classic set borrows the Delve's sounds and has no region

```roguelike
(def v37-c (data-load "data/classic"))
(write (list (List map first (data-all v37-c 'sounds-of))
             (data-all v37-c 'region)
             (< 0 (List length (data-all (List flat-map rest (data-all v37-c 'sounds-of)) 'cue)))))
```
---
    (("delve") () #t)

## the vault's own

### its songs make trackers, and its music, fight and bed are its own songs

```roguelike
(import x/audio/tracker)
(def v37-c (data-load "data/classic"))
(def v37-song? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all v37-c 'song))))
(def v37-beds (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'bed) #f)) (rest a)))) (data-all v37-c 'ambience)))
(write (list (List all? (fn (_ s) (str? (Tracker name (Tracker make (pair 'song s))))) (data-all v37-c 'song))
             (List all? (fn (_ m) (v37-song? (List ref 1 m))) (List append (data-all v37-c 'music) (data-all v37-c 'fight)))
             (List all? v37-song? v37-beds)
             (List map (fn (_ h) (List ref 1 (data-one v37-c h ()))) '(music fight))
             (first (data-one v37-c 'music-echo ()))))
```
---
    (#t #t #t ("vault" "vault-fight") 520)

### every creature of the vault has a cry of its own, and every cry and random sound is a sound of its world

```roguelike
(def v37-c (data-load "data/classic"))
(def v37-w (List append v37-c (List flat-map rest (data-all v37-c 'sounds-of))))
(def v37-sound? (fn (_ n) (List any? (fn (_ s) (str=? (first s) n)) (data-all v37-w 'sound))))
(def v37-cried? (fn (_ n) (List any? (fn (_ c) (str=? (first c) n)) (data-all v37-c 'cry))))
(def v37-randoms (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'random) #f)) (rest a)))) (data-all v37-c 'ambience)))
(write (list (List all? (fn (_ k) (v37-cried? (first k))) (data-all v37-c 'creature))
             (List all? (fn (_ c) (v37-sound? (List ref 1 c))) (data-all v37-c 'cry))
             (List all? v37-sound? v37-randoms)
             (List all? (fn (_ c) (v37-sound? (List ref 1 c))) (data-all v37-w 'cue))))
```
---
    (#t #t #t #t)

### every sound of the vault's own renders to frames

```roguelike
(import x/audio/mixer)
(def v37-c (data-load "data/classic"))
(def v37-w (List append v37-c (List flat-map rest (data-all v37-c 'sounds-of))))
(List for-each (fn (_ w) (Mixer wave! (first w) (rest w))) (data-all v37-w 'wave))
(def v37-voices (fn (_ s) (List map rest (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'voice) #f)) (rest s)))))
(write (List map (fn (_ s) (< 0 (rest (Mixer render 8000 (v37-voices s) ())))) (data-all v37-c 'sound)))
```
---
    (#t #t #t #t)
