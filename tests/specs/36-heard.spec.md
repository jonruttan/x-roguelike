# Kettle and the town heard
# @weight 2

roguelike/sound above ground (see `docs/sound.md`): a building's own air
and song are heard under its roof, and an interior's behind its door,
before the band's around it; coins are heard counted onto a counter and
swept off it.  Nothing here opens an audio device.

## the places heard

### on the square the band is heard; beside the innkeeper, the inn first and the band after it

```roguelike
(import roguelike/sound sound-places sound-coin)
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def h36-out (sound-places g))
(def h36-host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(spec-beside! g h36-host)
(write (list h36-out (sound-places g)))
```
---
    (("Kettle") ("the inn" "Kettle"))

### every place the Kettle world's music and air are for is default, a band, a region, a screen, a building or an interior of it

```roguelike
(def h36-k (spec-set-named "kettle"))
(def h36-w (List append h36-k (List flat-map rest (data-all h36-k 'region))))
(def h36-buildings
  (List flat-map (fn (_ s) (List map (fn (_ b) (List ref 1 b)) (List filter (fn (_ f) (if (pair? f) (eq? (first f) 'building) #f)) (rest s))))
    (data-all h36-w 'screen)))
(def h36-names (List append (list "default") (List map first (data-all h36-w 'band)) (List map first (data-all h36-k 'region))
                 (List map first (data-all h36-w 'screen)) h36-buildings (List map first (data-all h36-w 'interior))))
(def h36-known? (fn (_ n) (List any? (fn (_ m) (str=? m n)) h36-names)))
(def h36-has? (fn (_ head n) (List any? (fn (_ f) (str=? (first f) n)) (data-all h36-w head))))
(write (list (List all? (fn (_ f) (h36-known? (first f))) (List append (data-all h36-w 'music) (data-all h36-w 'ambience)))
             (List all? (fn (_ b) (h36-has? 'ambience b)) h36-buildings)
             (List all? (fn (_ i) (h36-has? 'ambience i)) (list "farmhouse cellar" "shepherd's bothy" "old city vault"))
             (List map (fn (_ b) (h36-has? 'music b)) (list "the inn" "the chapel" "the White Church" "the smithy"))))
```
---
    (#t #t #t (#t #t #t #f))

## the counter heard

### gold that goes down is a thing bought; gold that comes up as the pack goes down, one sold; else gold found

```roguelike
(write (list (sound-coin 10 6 0 1) (sound-coin 0 2 2 1) (sound-coin 0 5 0 0) (sound-coin 5 5 0 0)))
```
---
    ('bought 'sold 'gold ())

### at the inn's counter, the cheese bought is heard as coins paid and a loaf sold as coins taken, and the world has both cues

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def h36-host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list h36-host))
(def h36-purse (fn (_) (list (player-gold p) (List fold (fn (_ n it) (+ n (item-count it))) 0 (game-pack g)))))
(spec-drop-here! g "bread")
(spec-drop-here! g "bread")
(game-key! g ",")
(def h36-loaf (List find (fn (_ it) (str=? (item-name it) "bread")) (game-pack g)))
(player-gold! p 10)
(game-key! g (spec-beside! g h36-host))
(def h36-a (h36-purse))
(game-key! g "a")
(def h36-b (h36-purse))
(game-key! g "s")
(game-key! g (item-letter h36-loaf))
(def h36-c (h36-purse))
(def h36-coin (fn (_ x y) (sound-coin (first x) (first y) (List ref 1 x) (List ref 1 y))))
(def h36-k (spec-set-named "kettle"))
(def h36-w (List append h36-k (List flat-map rest (data-all h36-k 'region))))
(def h36-cue (fn (_ n) ((fn (_ c) (if (null? c) "" (List ref 1 c))) (List find (fn (_ f) (str=? (first f) n)) (data-all h36-w 'cue)))))
(write (list (h36-coin h36-a h36-b) (h36-coin h36-b h36-c) (h36-cue "bought") (h36-cue "sold")))
```
---
    ('bought 'sold "coins-paid" "coins-taken")
