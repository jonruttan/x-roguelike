# The chain
# @weight 1

roguelike/chain on the kettle set: an errand drawn each game from the
set's scenes, a link a screen farther out, read outward by what each
person says and paid inward by what each gives, the goal at the end
of it and the win at the hub.


## the set

### the kettle set has nineteen scenes, two of them giving the goal, a goal with no level, and a chain of two or three

```roguelike
(def set (spec-set-named "kettle"))
(def scenes (data-all set 'scene))
(write (list (List length scenes) (List count-if (fn (_ s) (eq? (first (data-prop s 'gives ())) 'goal)) scenes)
             (List length (data-one set 'goal ())) (data-one set 'chain ())))
```
---
    (19 2 2 (2 3))

## the way to a screen

### the way from one screen to another is said as the people say it: where it lies, then which way from here

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(write (list (chain-where g (pair 3 2) (pair 5 1)) (chain-where g (pair 3 2) (pair 3 4)) (chain-where g (pair 3 2) (pair 2 2))
             (chain-where g (pair 3 2) (pair 4 0)) (chain-where g (pair 3 2) (pair 3 2))))
```
---
    ("up in the hills, east of here" "up in the hills, south of here" "out in the farms, west of here" "up in the hills, north-east of here" "right here")

## the chain drawn

### a new game's chain: the goal's giver on the hub, each link a screen farther out, each want the next link's gift, the last want lying a screen beyond

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def chain (game-chain g))
(def prop (fn (_ q key) (data-prop (rest q) key ())))
(def at (fn (_ q) (prop q 'screen)))
(def n (List length chain))
(def hub? (fn (_ q) (if (= (List ref 0 (at q)) 3) (= (List ref 1 (at q)) 2) #f)))
(def dist (fn (_ s) (game-screen-distance g (List ref 0 s) (List ref 1 s))))
(def rings (List map (fn (_ i) (dist (at (List ref i chain)))) (List range 0 n)))
(def gift (fn (_ q) (List ref 1 (first (prop q 'rewards)))))
(def want (fn (_ q) (List ref 1 (prop q 'wants))))
(def linked? (List all? (fn (_ i) (str=? (want (List ref i chain)) (gift (List ref (+ i 1) chain)))) (List range 0 (- n 1))))
(def last (List ref (- n 1) chain))
(def lies (List map (fn (_ i) (null? (prop (List ref i chain) 'lies))) (List range 0 n)))
(write (list (< 1 n) (< n 4) (hub? (first chain)) (first (first (prop (first chain) 'rewards))) rings linked?
             lies (dist (prop last 'lies)) (List length (List distinct (List map (fn (_ q) (List ref 2 q)) chain)))))
```
---
    (#t #t #t 'goal (0 1 2) #t (#t #t #f) 3 3)

## the errand

### the goal's giver stands in the square and, walked into, says the way to what they want

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def chain (game-chain g))
(def prop (fn (_ q key) (data-prop (rest q) key ())))
(def first-q (first chain))
(def second (List ref 1 chain))
(def where (chain-where g (pair 3 2) (pair (List ref 0 (prop second 'screen)) (List ref 1 (prop second 'screen)))))
(def giver (List find (fn (_ cr) (str=? (creature-name cr) (List ref 2 first-q))) (game-creatures g)))
(game-creatures! g (list giver))
(def key (spec-beside! g giver))
(game-key! g key)
(def rows (spec-screen g))
(write (list (not (null? giver)) (creature-trait? giver 'talks) (spec-row g 0)
             (List any? (fn (_ r) (Str8 includes? where r)) rows) (game-quest-state g (List ref 1 first-q))))
```
---
    (#t #t "Guild clerk  --any key--" #t 'open)

### the last want lies where the chain says, walked to; the errand paid inward from there ends with the goal in the square, and the win

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(player-hp! (game-player g) 1000)
(def p (game-player g))
(def chain (game-chain g))
(def prop (fn (_ q key) (data-prop (rest q) key ())))
(def calm! (fn (_) (game-creatures! g (List filter (fn (_ cr) (if (creature-trait? cr 'talks) #t (not (null? (creature-carried cr))))) (game-creatures g)))))
(def step!
  (fn (_ dx dy)
    (match ((< dx 0) (do (player-at! p 11 0) (game-key! g "h")))
           ((< 0 dx) (do (player-at! p 11 79) (game-key! g "l")))
           ((< dy 0) (do (player-at! p 0 40) (game-key! g "k")))
           (#t (do (player-at! p 21 40) (game-key! g "j"))))
    (calm!)))
(def travel!
  (fn (self x y)
    (def here (game-screen g))
    (unless (if (= (first here) x) (= (rest here) y) #f)
      (do (step! (- x (first here)) (- y (rest here))) (self x y)))))
(calm!)
(def last (List ref (- (List length chain) 1) chain))
(def lies (prop last 'lies))
(travel! (List ref 0 lies) (List ref 1 lies))
(def want (List ref 1 (prop last 'wants)))
(def on-floor (List any? (fn (_ it) (str=? (item-name it) want)) (game-floor g)))
(def carried (List any? (fn (_ cr) (if (null? (creature-carried cr)) #f (str=? (item-name (creature-carried cr)) want))) (game-creatures g)))
(def take! (fn (_ name) (def it (item-make (spec-item g name) 1 0)) (item-letter! it "z") (game-pack! g (pair it (game-pack g)))))
(def serve!
  (fn (_ q)
    (def s (prop q 'screen))
    (travel! (List ref 0 s) (List ref 1 s))
    (spec-press-until g (lit escape) (fn (_) (null? (game-ask g))) 5)
    (def giver (List find (fn (_ cr) (str=? (creature-name cr) (List ref 2 q))) (game-creatures g)))
    (def key (spec-beside! g giver))
    (game-key! g key)
    (game-key! g (lit escape))
    (game-key! g key)
    (game-key! g "a")
    (game-quest-state g (List ref 1 q))))
(take! want)
(def states (List map serve! (List reverse chain)))
(write (list (if on-floor #t carried) states (game-over g) (List any? (fn (_ it) (eq? (item-class it) 'goal)) (game-pack g))
             (List any? (fn (_ it) (eq? (item-class it) 'token)) (game-pack g)) (first (game-log g))))
```
---
    (#t ('done 'done 'done) 'won #t #f "You lay the ledger on the well-head.  Kettle has its proof, and the Guild has lost its mine.")

## saving

### the chain comes back from a save, and so does a link's state

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def giver (List find (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(game-creatures! g (list giver))
(game-key! g (spec-beside! g giver))
(game-key! g (lit escape))
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(def names (fn (_ x) (List map (fn (_ q) (List ref 1 q)) (game-chain x))))
(write (list (not (null? h)) (= (List length (game-chain g)) (List length (game-chain h))) (names g) (str=? (Str8 join "|" (names g)) (Str8 join "|" (names h)))
             ((fn (_ w) (str=? (w (game-chain g)) (w (game-chain h)))) (prim-ref (lit io) (lit write-to-str)))
             (game-quest-state h (List ref 1 (first (game-chain g))))))
```
---
    (#t #t ("the clerk" "the town surveyor" "the scrap-picker") #t #t 'open)
