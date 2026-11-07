# The pithead
# @weight 1

roguelike/data, roguelike/state and roguelike/game on the kettle set:
one world.  The town joins the delve set as a region, and the pit's
door on the pithead, a step north of the square, is the way down into
it.  Below, the Delve's forms are the set in force; the way up out of
its first level comes back onto the door.


## the world

### the town joins the delve set: its forms are a region of the valley's world, and the pit on the pithead goes down into it

```roguelike
(def set (spec-set-named "kettle"))
(def town (data-region set "town"))
(def pithead (List find (fn (_ s) (str=? (first s) "the Pithead")) (data-all town 'screen)))
(def pit (List find (fn (_ f) (if (pair? f) (if (eq? (first f) 'interior) (str=? (List ref 1 f) "pit") #f) #f)) (List drop 2 pithead)))
(def region (data-region set "delve"))
(write (list (data-all town 'join) (data-get region 'title "") (List length (data-all region 'band))
             (rest (Assoc find 'depth (List drop 2 pit))) (rest (Assoc find 'region (List drop 2 pit)))
             (List any? (fn (_ f) (str=? (first f) "the Guild ledger")) (data-all set 'goal))
             (first (first (data-all town 'band))) (first (first (data-all region 'band)))))
```
---
    ((("delve")) "The Delve" 4 (1 1) ("delve") #t "Kettle" "The Galleries")

## the way down

### the pithead lays the pit's door, and a step onto it says where it goes

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def door (map-down (game-map g)))
(def d (List find (fn (_ d) (map-walkable? (game-map g) (+ (first door) (first (rest d))) (+ (rest door) (rest (rest d)))))
         (list (pair "j" (pair -1 0)) (pair "k" (pair 1 0)) (pair "l" (pair 0 -1)) (pair "h" (pair 0 1)))))
(player-at! p (+ (first door) (first (rest d))) (+ (rest door) (rest (rest d))))
(game-key! g (first d))
(write (list (game-door g "town/1,0") (= (map-tile (game-map g) (first door) (rest door)) tile-down)
             (= (player-r p) (first door)) (= (player-c p) (rest door)) (game-messages g)))
```
---
    ("pit" #t #t #t ("There is a way into the pit here."))

### > on the door goes down into the Delve: its first level, made by its forms, the player on its stairs up, and the pit's word and the band's

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(def m (game-map g))
(write (list (game-below? g) (game-region g) (game-depth g) (data-get (game-set g) 'title "") (band-name (game-band g))
             (game-screens? g) (game-inside g) (data-get (game-top-set g) 'title "")
             (= (player-r p) (first (map-up m))) (= (player-c p) (rest (map-up m))) (not (null? (map-down m)))
             (List reverse (List take 3 (game-log g)))))
```
---
    (#t "delve" 1 "The Delve" "The Galleries" #f () "Kettle" #t #t #t ("You go down the pit." "The winding shaft: the cage gone, ladders down into the dark, and water loud below." "The Galleries: the worked mine, propped and railed, its lamps long out."))

### the stairs below go on down and back up as the Delve's do

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">")
(spec-settle! g)
(def two (list (game-depth g) (game-below? g)))
(game-creatures! g ())
(player-at! p (first (map-up (game-map g))) (rest (map-up (game-map g))))
(game-key! g "<")
(write (list two (game-depth g) (game-below? g) (= (player-r p) (first (map-down (game-map g)))) (= (player-c p) (rest (map-down (game-map g))))))
```
---
    ((2 #t) 1 #t #t #t)

## the way up

### < on the first level's stairs up, with nothing in hand, climbs out onto the door, the pithead as it was left

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def square (game-map g))
(def door (map-down square))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(game-key! g "<")
(write (list (game-below? g) (game-region g) (game-depth g) (same? (game-map g) square) (game-screens? g)
             (data-get (game-set g) 'title "") (= (player-r p) (first door)) (= (player-c p) (rest door))
             (game-over g) (game-messages g)))
```
---
    (#t "town" 1 #t #t "Kettle" #t #t () ("You climb out of the pit."))

### the Delve's goal brought up is not Kettle's: on the pithead it is no win

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(def goal (first (data-all (game-set g) 'goal)))
(game-pack! g (list (item-make (list 'goal (first goal)) 1 0)))
(game-key! g "<")
(spec-settle! g)
(game-key! g ".")
(write (list (game-below? g) (game-over g) (item-name (first (game-pack g)))))
```
---
    (#t () "the Lodestar")

## kept

### a game saved below is read back below, and the way up still finds the pithead it left

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(def q (game-player h))
(def below (list (game-below? h) (game-region h) (game-depth h) (data-get (game-set h) 'title "")
                 (= (player-r p) (player-r q)) (= (player-c p) (player-c q))
                 (= (spec-count-seen (game-map g)) (spec-count-seen (game-map h)))))
(game-creatures! h ())
(game-key! h "<")
(write (list below (game-below? h) (= (player-r q) (first door)) (= (player-c q) (rest door))
             (data-get (game-set h) 'title "")))
```
---
    ((#t "delve" 1 "The Delve" #t #t #t) #t #t #t "Kettle")
