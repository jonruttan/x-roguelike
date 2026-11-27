# Night
# @weight 3

roguelike/game: the world of a set with `(day DAWN DUSK START)` keeps
the hour on the game's clock.  From dusk to dawn under the sky only the
set's `(night-view N)` is seen, night and dawn are told as they come,
and every place is heard first as "PLACE by night" (see
`docs/sound.md`).  A world with no day has no night.

## the hour

### the valley's day begins at three in the afternoon; night falls at eight and is gone at six; the Delve alone has no hour

```roguelike
(def n38-g (spec-game-on (spec-valley) 4 ()))
(def n38-at (fn (_ s) (game-clock! n38-g s) (list (game-hour n38-g) (game-night? n38-g))))
(def n38-d (spec-game-on (spec-set-named "delve") 4 ()))
(write (list (n38-at 0) (n38-at 17999) (n38-at 18000) (n38-at 53999) (n38-at 54000)
             (list (game-hour n38-d) (game-night? n38-d))))
```
---
    ((15 #f) (19 #f) (20 #t) (5 #t) (6 #f) (-1 #f))

## the dark

### at dusk night falls and is told, and only the cells near are in view; at dawn it breaks and the screen is seen whole

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def m (game-map g))
(def n38-lit (fn (_) (List fold (fn (_ a r) (+ a (List count-if (fn (_ c) (map-visible? m r c)) (List range 0 (map-cols m))))) 0 (List range 0 (map-rows m)))))
(game-creatures! g ())
(spec-settle! g)
(def n38-day (list (game-daylight? g) (n38-lit)))
(game-clock! g 17995)
(game-key! g ".")
(def n38-night (list (game-daylight? g) (< (n38-lit) 50) (List any? (fn (_ s) (str=? s "Night falls.")) (game-messages g))))
(game-clock! g 53995)
(game-key! g ".")
(write (list n38-day n38-night
             (list (game-daylight? g) (n38-lit) (List any? (fn (_ s) (str=? s "Dawn breaks.")) (game-messages g)))))
```
---
    ((#t 1760) (#f #t #t) (#t 1760 #t))

## heard by night

### under the night sky the band is heard by night before itself; the world's night music and every night air are songs and sounds of it

```roguelike
(import roguelike/sound sound-places)
(def g (spec-game-on (spec-valley) 4 ()))
(def n38-day (sound-places g))
(game-clock! g 20000)
(def n38-k (spec-set-named "kettle"))
(def n38-w (List append n38-k (List flat-map rest (data-all n38-k 'region))))
(def n38-named? (fn (_ head n) (List any? (fn (_ f) (str=? (first f) n)) (data-all n38-w head))))
(def n38-props (fn (_ key) (List flat-map (fn (_ a) (List map (fn (_ p) (List ref 1 p)) (List filter (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest a))))
                              (List filter (fn (_ a) (Str8 ends-with? (first a) " by night")) (data-all n38-w 'ambience)))))
(write (list n38-day (sound-places g)
             (n38-named? 'song (List ref 1 (List find (fn (_ m) (str=? (first m) "default by night")) (data-all n38-w 'music))))
             (List all? (fn (_ b) (n38-named? 'song b)) (n38-props 'bed))
             (List all? (fn (_ r) (n38-named? 'sound r)) (n38-props 'random))
             (List all? (fn (_ b) (n38-named? 'ambience (Str8 append (first b) " by night"))) (data-all n38-k 'band))))
```
---
    (("Kettle") ("Kettle by night" "default by night" "Kettle") #t #t #t #t)
