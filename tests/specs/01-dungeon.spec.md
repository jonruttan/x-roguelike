# Levels
# @weight 1

roguelike/dungeon: a level from a seed has rooms joined by passages,
stairs in two of them, and every floor cell reachable from the stairs
up.


## the set

### the classic set loads, and says what it is

```roguelike
(write (list (data-get (spec-set) 'set "") (data-get (spec-set) 'title "") (List length (data-all (spec-set) 'creature))
             (List length (data-all (spec-set) 'item)) (data-glyph (spec-set) 'player "")))
```
---
    ("classic" "The Sunken Vault" 17 42 "@")

## shape

### a level is 22 by 80 with six to nine rooms, and the same seed gives the same level

```roguelike
(def m (spec-level 7 1))
(def again (spec-level 7 1))
(write (list (map-rows m) (map-cols m) (< 5 (List length (map-rooms m))) (< (List length (map-rooms m)) 10)
             (= (List length (map-rooms m)) (List length (map-rooms again)))
             (= (first (map-down m)) (first (map-down again))) (= (rest (map-down m)) (rest (map-down again)))))
```
---
    (22 80 #t #t #t #t #t)

### the stairs are on floor cells, in two rooms when there are two

```roguelike
(def m (spec-level 3 1))
(write (list (map-tile m (first (map-down m)) (rest (map-down m))) (map-tile m (first (map-up m)) (rest (map-up m)))
             (eq? (map-room-at m (first (map-down m)) (rest (map-down m))) (map-room-at m (first (map-up m)) (rest (map-up m))))))
```
---
    (5 6 #f)

### every walkable cell can be reached from the stairs up, over twenty seeds

```roguelike
(write (List all? (fn (_ ok) ok) (spec-levels (List range 1 21) 1 spec-connected?)))
```
---
    #t

### deep levels are mostly dark, the first mostly lit

```roguelike
(def lit-rooms (fn (_ depth) (List fold (fn (_ a b) (+ a b)) 0 (spec-levels (List range 1 11) depth (fn (_ m) (List count-if room-lit? (map-rooms m)))))))
(def all-rooms (fn (_ depth) (List fold (fn (_ a b) (+ a b)) 0 (spec-levels (List range 1 11) depth (fn (_ m) (List length (map-rooms m)))))))
(write (list (< (* 3 (all-rooms 1)) (* 4 (lit-rooms 1))) (< (* 2 (lit-rooms 20)) (all-rooms 20))))
```
---
    (#t #t)
