# The score
# @weight 1

roguelike/game's score: what a game is worth, by the set's (score
(NAME POINTS) ... (par TURNS POINTS)), or gold, fifty a level and a
thousand for the win when the set names none; and its lines in words.


## a set without a score

### the classic set scores gold, fifty a level reached and a thousand for the win

```roguelike
(def g (spec-game-on (spec-set) 1 ()))
(player-gold! (game-player g) 120)
(game-deepest! g 4)
(def before (game-score g))
(game-over! g 'won)
(write (list before (game-score g) (game-score-lines g)))
```
---
    (320 1320 (('gold 120 120) ('deepest 4 200) ('won 1 1000)))

## a set's score

### only what the set names counts: gold, screens visited, places gone into, quests done, the win, and each turn under par

```roguelike
(def set (pair '(score (gold 2) (screens 10) (places 25) (quests 100) (won 500) (par 3000 1))
               (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0)) (spec-valley))))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(player-gold! p 40)
(game-quest-state! g "an errand" 'done)
(game-quest-state! g "another" 'open)
(game-turn! g 1000)
(game-over! g 'won)
(write (list (game-score g) (game-score-lines g)))
```
---
    (2725 (('gold 40 80) ('screens 2 20) ('places 1 25) ('quests 1 100) ('won 1 500) ('par 2000 2000)))

### the par pays only on a win, and only for the turns under it

```roguelike
(def set (pair '(score (won 500) (par 3000 1)) (spec-valley)))
(def g (spec-game-on set 4 ()))
(game-turn! g 1000)
(def lost (game-score-lines g))
(game-over! g 'won)
(game-turn! g 3500)
(write (list lost (game-score-lines g) (game-score g)))
```
---
    (() (('won 1 500)) 500)

### each line in words, the set's (message score-NAME "TEXT") in place of the engine's

```roguelike
(def set (pair '(score (gold 1) (won 500) (par 3000 2)) (pair '(message score-par "{points} for coming home in good time") (spec-valley))))
(def g (spec-game-on set 4 ()))
(player-gold! (game-player g) 7)
(game-turn! g 2900)
(game-over! g 'won)
(write (game-score-text g))
```
---
    ("7 for 7 gold" "500 for the ledger on the well-head" "200 for coming home in good time")

## the kettle set's own

### kettle counts gold, errands, screens and doors, the Lodestar brought up the pit, and the ledger home; a game just begun has walked the square's screen

```roguelike
(def set (spec-valley))
(def g (spec-game-on set 4 ()))
(write (list (List map first (data-one set 'score ())) (game-score g) (game-score-text g)))
```
---
    (('gold 'quests 'screens 'places 'goals 'won) 10 ("10 for screens of the valley walked: 1"))
