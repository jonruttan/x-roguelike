# Saving
# @weight 1

roguelike/save: a game written as xon and read back the same, and the
scores kept best first.


## a game

### written and read back, a game is where it was

```roguelike
(def g (spec-calm 9 (list "." ".")))
(spec-drop-here! g "short blade")
(spec-drop-here! g "healing")
(game-key! g ",")
(game-key! g "w")
(game-key! g "b")
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set) 24 80))
(File unlink path)
(def p (game-player g))
(def q (game-player h))
(def names (fn (_ x) (List map (fn (_ it) (Str8 append (item-letter it) ") " (items-name x it))) (game-pack x))))
(write (list (not (null? h)) (= (game-turn g) (game-turn h)) (= (game-depth g) (game-depth h))
             (= (player-r p) (player-r q)) (= (player-c p) (player-c q)) (= (player-food p) (player-food q))
             (str=? (Str8 join "|" (names g)) (Str8 join "|" (names h))) (items-name h (player-weapon q))
             (= (List length (game-creatures g)) (List length (game-creatures h)))
             (= (List length (game-floor g)) (List length (game-floor h)))
             (= (spec-count-seen (game-map g)) (spec-count-seen (game-map h)))
             (= (first (map-down (game-map g))) (first (map-down (game-map h))))
             (game-messages h)))
```
---
    (#t #t #t #t #t #t #t "a short blade" #t #t #t #t ("Welcome back."))

### no save is nil

```roguelike
(write (save-read "/nonexistent/x-roguelike-save" (spec-set) 24 80))
```
---
    ()

## scores

### kept best first, at most ten

```roguelike
(def tmp (File temp "/tmp/x-roguelike-scores-"))
(File close (first tmp))
(def path (rest tmp))
(File unlink path)
(save-score! path 120 3 "killed by a cave rat")
(save-score! path 1450 20 "won")
(save-score! path 50 1 "quit")
(def rows (save-scores path))
(List for-each (fn (_ n) (save-score! path n 2 "quit")) (List range 1 12))
(def many (List length (save-scores path)))
(File unlink path)
(write (list rows many))
```
---
    (("  1450  level 20  won" "   120  level 3  killed by a cave rat" "    50  level 1  quit") 10)

## where

### each set its own directory under HOME: a save on one is never read on another

```roguelike
(import roguelike/save save-path)
(def home (Sys getenv "HOME"))
(def tmp (File temp "/tmp/x-roguelike-home-"))
(File close (first tmp))
(File unlink (rest tmp))
(File mkdir (rest tmp))
(Sys setenv "HOME" (rest tmp))
(def under (fn (_ p) (Str8 sub (+ (Str8 length (rest tmp)) 1) (- (Str8 length p) (+ (Str8 length (rest tmp)) 1)) p)))
(def got (list (under (save-path "delve" "save")) (under (save-path "kettle" "save"))
               (under (save-path "data/kettle/" "scores"))
               (File exists? (save-path "delve" "save"))
               (str=? (save-path "delve" "save") (save-path "kettle" "save"))))
(Sys setenv "HOME" home)
(List for-each (fn (_ d) (File rmdir (Str8 append (rest tmp) d))) (list "/.x-roguelike/delve" "/.x-roguelike/kettle" "/.x-roguelike" ""))
(write got)
```
---
    (".x-roguelike/delve/save" ".x-roguelike/kettle/save" ".x-roguelike/kettle/scores" #f #f)
