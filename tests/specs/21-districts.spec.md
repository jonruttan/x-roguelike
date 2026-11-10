# The districts
# @weight 1

roguelike/data, roguelike/state and roguelike/game on the kettle set:
places in places.  Kettle, the town, is a region of the valley's world
and a world of screens of its own, five districts at two metres a cell,
its door on the valley's hub; the Delve is a region under the town,
gone into from the pithead.  A game of kettle starts on the square, a
step off the town's edge comes out onto its door, and the ledger
brought to the square is the win.


## the world

### the valley joins the town, the town joins the Delve, and both are regions of the valley's world

```roguelike
(def set (spec-set-named "kettle"))
(def town (data-region set "town"))
(write (list (List map first (data-all set 'region)) (data-all set 'start)
             (data-get set 'scale 1) (data-get town 'scale 1) (data-get (data-region set "delve") 'scale 1)
             (data-one town 'world ()) (List map (fn (_ s) (list (first s) (List ref 1 s))) (data-all town 'screen))))
```
---
    (("town" "delve") (("Kettle")) 21 2 1 ('screens 3 3) (("the Square" (1 1)) ("the Pithead" (1 0)) ("the River End" (1 2)) ("the Terraces" (2 1)) ("Guild Street" (0 1))))

### a game of kettle begins on the square: in the town, on its hub, the valley's hub kept with the town's door on it

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(write (list (game-region g) (game-screens? g) (game-screen g) (game-depth g) (game-screen-name g)
             (data-get (game-set g) 'set "") (data-get (game-top-set g) 'set "")
             (game-door g "3,2") (not (null? (game-kept-level g "3,2"))) (not (null? (game-kept-level g "town/1,1")))
             (game-log g)))
```
---
    ("town" #t (1 . 1) 0 "the Square" "town" "kettle" "Kettle" #t #t ("You make out the Guild clerk to the south-west." "Kettle's square, by the well-head.  Someone here knows where the Guild's ledger is; ask about."))

## the districts

### each district is a step off one side of the square, and says what it is the first time there

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def go
  (fn (_ key r c back r2 c2)
    (game-creatures! g ())
    (player-at! p r c)
    (game-key! g key)
    (def there (list (game-screen g) (game-screen-name g) (first (game-log g))))
    (game-creatures! g ())
    (player-at! p r2 c2)
    (game-key! g back)
    (list there (game-screen g))))
(write (list (go "k" 0 40 "j" 21 40) (go "j" 21 40 "k" 0 40) (go "l" 10 79 "h" 10 0) (go "h" 10 0 "l" 10 79)))
```
---
    ((((1 . 0) "the Pithead" "The pithead: the engine house cold, the gin still, the Tip black.") (1 . 1)) (((1 . 2) "the River End" "The river end: the mill race low, the ropewalk, the tannery's reek.") (1 . 1)) (((2 . 1) "the Terraces" "The terraces: the miners' rows, doors shuttered, the chapel beyond.") (1 . 1)) (((0 . 1) "Guild Street" "Guild Street: the Guild hall, the White Church, the Guild's shop.") (1 . 1)))

### every district is walked whole: no street cut off

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def visit
  (fn (_ key r c)
    (game-creatures! g ())
    (player-at! p r c)
    (game-key! g key)
    ((fn (_ v) (Heap collect) v) (spec-connected? (game-map g)))))
(def square (spec-connected? (game-map g)))
(write (list square (visit "k" 0 40) (visit "j" 21 40) (visit "j" 21 40) (visit "k" 0 40) (visit "l" 10 79) (visit "h" 10 0)
             (visit "h" 10 0) (visit "l" 10 79)))
```
---
    (#t #t #t #t #t #t #t #t #t)

## in and out

### a step off the town's edge comes out on the valley, on the town's door; > on it goes back in, onto the square as it was left

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def square (game-map g))
(game-creatures! g ())
(player-at! p 10 0)
(game-key! g "h")
(game-creatures! g ())
(player-at! p 10 0)
(game-key! g "h")
(def out (list (game-region g) (game-screen g) (game-depth g) (data-get (game-set g) 'set "")
               (= (player-r p) (first (map-down (game-map g)))) (= (player-c p) (rest (map-down (game-map g))))
               (game-messages g)))
(game-creatures! g ())
(game-key! g ">")
(write (list out (game-region g) (game-screen g) (same? (game-map g) square) (List reverse (List take 2 (game-log g)))))
```
---
    ((() (3 . 2) 0 "kettle" #t #t ("You leave Kettle.")) "town" (1 . 1) #t ("You go into Kettle." "The road in past the watch house, and the setts underfoot."))

### the pit is on the pithead: down into the Delve, and up again onto its door, in the town

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 0 40)
(game-key! g "k")
(game-creatures! g ())
(def pithead (game-map g))
(def door (map-down pithead))
(player-at! p (first door) (rest door))
(game-key! g ">")
(def below (list (game-region g) (List map first (game-regions g)) (game-depth g) (data-get (game-set g) 'set "")
                 (data-get (game-top-set g) 'set "") (game-door g "town/1,0")))
(spec-settle! g)
(game-creatures! g ())
(player-at! p (first (map-up (game-map g))) (rest (map-up (game-map g))))
(game-key! g "<")
(write (list below (game-region g) (game-screen g) (game-depth g) (same? (game-map g) pithead)
             (= (player-r p) (first door)) (= (player-c p) (rest door)) (game-messages g)))
```
---
    (("delve" ("delve" "town") 1 "delve" "kettle" "pit") "town" (1 . 0) 1 #t #t #t ("You climb out of the pit."))

## kept

### a game saved in the Delve under the town is read back there, and the way up finds the pithead

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 0 40)
(game-key! g "k")
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
(def read (list (List map first (game-regions h)) (game-depth h) (= (player-r p) (player-r q)) (= (player-c p) (player-c q))))
(game-creatures! h ())
(player-at! q (first (map-up (game-map h))) (rest (map-up (game-map h))))
(game-key! h "<")
(write (list read (game-region h) (game-screen h) (= (player-r q) (first door)) (= (player-c q) (rest door))))
```
---
    ((("delve" "town") 1 #t #t) "town" (1 . 0) #t #t)

### a game saved on a district is read back there, the square and the valley's hub kept

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 10 79)
(game-key! g "l")
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(write (list (game-region h) (game-screen h) (game-screen-name h)
             (List map (fn (_ k) (not (null? (game-kept-level h k)))) (list "3,2" "town/1,1" "town/2,1"))))
```
---
    ("town" (2 . 1) "the Terraces" (#t #t #t))

## home

### the ledger in hand is the win on the square, and no win on the valley's hub

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(game-pack! g (list (item-make (list 'goal "the Guild ledger") 1 0)))
(player-at! p 10 0)
(game-key! g "h")
(game-creatures! g ())
(player-at! p 10 0)
(game-key! g "h")
(game-creatures! g ())
(game-key! g ".")
(def outside (game-over g))
(game-key! g ">")
(game-creatures! g ())
(game-key! g ".")
(write (list outside (game-region g) (game-screen g) (game-over g) (first (game-log g))))
```
---
    (() "town" (1 . 1) 'won "You lay the ledger on the well-head.  Kettle has its proof, and the Guild has lost its mine.")

### the chain's first link stands on the square, in the town, and says the way out from the town's door

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def first-link (first (game-chain g)))
(def giver (List ref 2 first-link))
(write (list (Assoc find 'screen (List drop 3 first-link)) (Assoc find 'region (List drop 3 first-link))
             (not (null? (List find (fn (_ cr) (str=? (creature-name cr) giver)) (game-creatures g))))))
```
---
    (('screen 1 1) ('region "town") #t)
