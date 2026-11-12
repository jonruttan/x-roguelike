# Errands below
# @weight 3

roguelike/chain and roguelike/quests on the kettle set: one world.  A
token with (below REGION LEVEL) lies on that level of the descent
REGION, so a link of the valley's chain that wants it sends the player
down the pit; the chain walks only through links that still reach its
length, so one that wants a thing below is always the last.  The
score's goals count a region's goal brought out of it.


## the chain

### a link whose want lies below has no ground to lie on: its quest says the region and level, and its lines say the way down the pit

```roguelike
(def b33-set (List reject (fn (_ f) (if (pair? f) (if (eq? (first f) 'scene) (not (str=? (List ref 1 f) "the checkweighman")) #f) #f))
               (spec-set-named "kettle")))
(def g (spec-game-on b33-set 4 ()))
(def q (rest (first (game-chain g))))
(write (list (List length (game-chain g)) (first q) (data-prop q 'lies-below ()) (data-prop q 'lies ()) (data-prop1 q 'lies-found "")
             (List any? (fn (_ l) (not (null? (Str8 index-of "down the pit, on the first level" l)))) (data-prop q 'ask ()))))
```
---
    (1 "the checkweighman" ("delve" 1) () "down the pit, on the first level" #t)

### walked into on the square, the checkweighman's errand opens, and the map says the way to what is wanted down the pit

```roguelike
(def b33-set (List reject (fn (_ f) (if (pair? f) (if (eq? (first f) 'scene) (not (str=? (List ref 1 f) "the checkweighman")) #f) #f))
               (spec-set-named "kettle")))
(def g (spec-game-on b33-set 4 ()))
(def cr (List find (fn (_ c) (str=? (creature-name c) "checkweighman")) (game-creatures g)))
(game-key! g (spec-beside! g cr))
(spec-settle! g)
(write (list (game-quest-state g "the checkweighman") (quests-errands g)))
```
---
    ('open ("! For the checkweighman, the foreman's keys: down the pit, on the first level."))

### the foreman's keys lie on the Delve's first level, gone down into from the pithead, and nowhere above

```roguelike
(def b33-set (List reject (fn (_ f) (if (pair? f) (if (eq? (first f) 'scene) (not (str=? (List ref 1 f) "the checkweighman")) #f) #f))
               (spec-set-named "kettle")))
(def g (spec-to-pithead! (spec-game-on b33-set 4 ())))
(def b33-keys? (fn (_ it) (str=? (item-name it) "the foreman's keys")))
(def b33-above (List count-if b33-keys? (game-floor g)))
(def door (map-down (game-map g)))
(player-at! (game-player g) (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(write (list b33-above (game-region g) (game-depth g) (List count-if b33-keys? (game-floor g))))
```
---
    (0 "delve" 1 1)

### every chain still runs its length, normal or large, and a link wanting a thing below is only ever the last of one; some chains end below

```roguelike
(def b33-kettle (spec-set-named "kettle"))
(def b33-below? (fn (_ q) (not (null? (data-prop (rest q) 'lies-below ())))))
(def b33-chains
  (fn (_ set)
    (List map (fn (_ s) (Heap collect) (game-chain (game-make set s 24 80))) (List range 1 9))))
(def b33-ok?
  (fn (_ lo hi chains)
    (List all? (fn (_ c) (def n (List length c)) (not (if (< n lo) #t (< hi n)))) chains)))
(def b33-normal (b33-chains b33-kettle))
(def b33-large (b33-chains (pair (list 'chain 4 5) b33-kettle)))
(write (list (b33-ok? 2 3 b33-normal) (b33-ok? 4 5 b33-large)
             (List all? (fn (_ c) (not (List any? b33-below? (List take (- (List length c) 1) c)))) (List append b33-normal b33-large))
             (< 0 (List count-if (fn (_ c) (List any? b33-below? c)) (List append b33-normal b33-large)))))
```
---
    (#t #t #t #t)

## the score

### the Lodestar held below counts nothing in Kettle's score; brought up onto the pithead, it counts as a goal brought out

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(def goal (first (data-all (game-set g) 'goal)))
(game-pack! g (list (item-make (list 'goal (first goal)) 1 0)))
(def b33-down (List find (fn (_ l) (eq? (first l) 'goals)) (game-score-lines g)))
(game-key! g "<")
(spec-settle! g)
(write (list b33-down (game-region g) (List find (fn (_ l) (eq? (first l) 'goals)) (game-score-lines g))))
```
---
    (() "town" ('goals 1 1000))
