# People
# @weight 2

roguelike/quests: a building's (keeper NAME LINE ...) stands inside it
on the level that lays it, unless the game's chain gives NAME a screen
of its own; walked into with nothing to ask, the keeper says a LINE,
the next each turn.  The town's buildings each name theirs.


## the keepers

### on each district every keeper stands inside their own building, one of them, unless the chain sends them out, and then not there

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def givers (List map (fn (_ q) (List ref 2 q)) (game-chain g)))
(def town (data-region (spec-set-named "kettle") "town"))
(def keepers
  (fn (_ s)
    (List flat-map (fn (_ b) (List map (fn (_ k) (pair (first b) (first k))) (data-all (rest b) 'keeper)))
      (data-all (rest (rest s)) 'building))))
(def placed?
  (fn (_ bk)
    (def m (game-map g))
    (def found (List filter (fn (_ cr) (str=? (creature-name cr) (rest bk))) (game-creatures g)))
    (def inside (List filter (fn (_ cr) ((fn (_ p) (if (null? p) #f (str=? (first p) (first bk)))) (map-place-at m (creature-r cr) (creature-c cr)))) found))
    (if (List includes? (rest bk) givers) (null? inside) (if (= 1 (List length found)) (= 1 (List length inside)) #f))))
(def square (List find (fn (_ s) (str=? (first s) "the Square")) (data-all town 'screen)))
(write (list (List map rest (keepers square)) (List all? placed? (keepers square))
             (List length (List flat-map keepers (data-all town 'screen)))))
```
---
    (("town surveyor" "innkeeper") #t 12)

## the lines

### a keeper walked into says a line of theirs, over the counter where they keep a shop, and walked into again the next

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def lines '(("town surveyor" "The town's charter is kept here, and the levels are mine." "The water in the lower galleries rises a hand a week.")
             ("innkeeper" "Carriers still come over the pass, fewer each month." "The yard takes a packhorse train, when there is one.")))
(def cr (List find (fn (_ cr) (not (null? (Assoc find (creature-name cr) lines)))) (game-creatures g)))
(def mine (rest (Assoc find (creature-name cr) lines)))
(game-creatures! g (list cr))
(def key (spec-beside! g cr))
(game-key! g key)
(def one (List ref 3 (game-ask g)))
(spec-settle! g)
(game-key! g key)
(def two (List ref 3 (game-ask g)))
(write (list (List includes? (first one) mine) (List includes? (first two) mine) (not (str=? (first one) (first two)))))
```
---
    (#t #t #t)

### a keeper with no lines, or a quest's giver, still speaks as before

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def giver (List find (fn (_ cr) (str=? (creature-name cr) "Guild clerk")) (game-creatures g)))
(game-creatures! g (list giver))
(game-key! g (spec-beside! g giver))
(write (list (List ref 0 (game-ask g)) (List ref 1 (game-ask g))))
```
---
    ('look "Guild clerk")
