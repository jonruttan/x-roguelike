# Secret rooms
# @weight 3

roguelike/dungeon, roguelike/items and roguelike/game on the delve set:
rooms dug behind secret doors, a door drawn as the wall until searched
out, and each band's prize behind one on a level of the band.


## the door

### a level of the delve has its secret doors drawn as wall; s beside one finds it, and it is a door

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(def down! (fn (_) (game-creatures! g ()) (player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g)))) (game-key! g ">") (spec-settle! g)))
(def cells (fn (_) (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols (game-map g))))) (List range 0 (map-rows (game-map g))))))
(def secrets (fn (_) (List filter (fn (_ rc) (= (map-tile (game-map g) (first rc) (rest rc)) tile-secret)) (cells))))
(def find-level (fn (self n) (if (if (null? (secrets)) (< 0 n) #f) (do (down!) (self (- n 1))) (secrets))))
(def doors (find-level 8))
(def door (first doors))
(def beside (List find (fn (_ d) (map-walkable? (game-map g) (+ (first door) (first d)) (+ (rest door) (rest d))))
              (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1))))
(player-at! p (+ (first door) (first beside)) (+ (rest door) (rest beside)))
(game-creatures! g ())
(game-key! g ".")
(def drawn (fn (_) (Str8 sub (rest door) 1 (List ref (+ (first door) 1) (spec-screen g)))))
(def walled (drawn))
(game-key! g "s")
(write (list (not (null? doors)) walled (List includes? "You find a secret door." (game-messages g))
             (= (map-tile (game-map g) (first door) (rest door)) tile-door) (drawn)))
```
---
    (#t "#" #t #t "+")

## the prize

### each band's prize lies on one of its levels, once: the Flood's ring of warding, by level 6

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def down! (fn (_) (game-creatures! g ()) (player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g)))) (game-key! g ">") (spec-settle! g)))
(def warding? (fn (_ it) (if (eq? (item-class it) 'ring) (str=? (item-name it) "warding") #f)))
(def seen (Vector of 0))
(List for-each (fn (_ i) (down!) (when (< 3 (game-depth g)) (Vector set! 0 (+ (Vector ref 0 seen) (List count-if warding? (game-floor g))) seen)))
  (List range 0 5))
(write (list (game-depth g) (< 0 (Vector ref 0 seen))))
```
---
    (6 #t)

### with the lamp lit, a ring of illumination worn notices a secret door beside at a turn's end, unsearched

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def down! (fn (_) (game-creatures! g ()) (player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g)))) (game-key! g ">") (spec-settle! g)))
(def cells (fn (_) (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols (game-map g))))) (List range 0 (map-rows (game-map g))))))
(def secrets (fn (_) (List filter (fn (_ rc) (= (map-tile (game-map g) (first rc) (rest rc)) tile-secret)) (cells))))
(def find-level (fn (self n) (if (if (null? (secrets)) (< 0 n) #f) (do (down!) (self (- n 1))) (secrets))))
(def door (first (find-level 8)))
(def beside (List find (fn (_ d) (map-walkable? (game-map g) (+ (first door) (first d)) (+ (rest door) (rest d))))
              (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1))))
(def ring (item-make (spec-item g "illumination") 1 0))
(item-letter! ring "z")
(game-pack! g (pair ring (game-pack g)))
(game-creatures! g ())
(game-key! g "P")
(game-key! g "z")
(player-at! p (+ (first door) (first beside)) (+ (rest door) (rest beside)))
(game-creatures! g ())
(game-key! g ".")
(write (list (= (map-tile (game-map g) (first door) (rest door)) tile-door) (List includes? "You find a secret door." (game-messages g))))
```
---
    (#t #t)
