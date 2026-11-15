# Quests: where the salvager stands
# @weight 1

roguelike/quests: on each level he keeps, the salvager stands as near the
arrival as he can without cutting a way.  On the delve set; two games,
one whose stairs open onto a room and one whose stairs are at the end of
a passage one cell wide.

## the salvager

### he stands a cell or two off the arrival, or, with the stairs at the end of a passage one cell wide, where it opens out

```roguelike
(def stops (fn (_ seed)
  (def h (spec-game-on (spec-set-named "delve") seed ()))
  (player-hp! (game-player h) 100000)
  (def met (Vector of ()))
  (def look! (fn (_)
    (def q (game-player h))
    (def him (List find (fn (_ cr) (str=? (creature-name cr) "salvager")) (game-creatures h)))
    (unless (null? him)
      (Vector set! 0 (pair (list (game-depth h) (state-dist (creature-r him) (creature-c him) (player-r q) (player-c q)) (spec-cuts-no-way? (game-map h) him (pair (player-r q) (player-c q)))) (Vector ref 0 met)) met))))
  (def down! (fn (_) (def mm (game-map h)) (game-creatures! h ()) (player-at! (game-player h) (first (map-down mm)) (rest (map-down mm))) (game-key! h ">") (spec-settle! h)))
  (List for-each (fn (_ i) (down!) (look!)) (List range 0 9))
  (List reverse (Vector ref 0 met))))
(write (List map stops (list 1 3)))
```
---
    (((4 2 #t) (7 5 #t) (10 2 #t)) ((4 2 #t) (7 2 #t) (10 25 #t)))
