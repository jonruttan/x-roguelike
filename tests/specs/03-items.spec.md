# Items
# @weight 1

roguelike/items: things picked up, named by a guise until one is used,
drunk, read, zapped, eaten, worn and dropped.


## the pack

### what lies under the player is picked up by , and lettered; a potion wears a guise

```roguelike
(def g (spec-calm 5 ()))
(def it (spec-drop-here! g "healing"))
(game-key! g ",")
(write (list (item-letter it) (List length (game-pack g)) (not (List any? (fn (_ x) (same? x it)) (game-floor g))) (items-known? g it)
             (Str8 ends? " potion" (items-name g it)) (Str8 starts? "a) a" (first (game-messages g))) (game-turn g)))
```
---
    ("a" 1 #t #f #t #t 1)

### gold goes to the purse

```roguelike
(def g (spec-calm 5 ()))
(def it (item-make (list 'gold "gold") 30 0))
(item-at! it (player-r (game-player g)) (player-c (game-player g)))
(game-floor! g (list it))
(game-key! g ",")
(write (list (player-gold (game-player g)) (game-messages g) (game-pack g)))
```
---
    (30 ("You find 30 gold pieces.") ())

### d drops a thing; what is worn must come off first

```roguelike
(def g (spec-calm 5 ()))
(def lying (List length (game-floor g)))
(spec-drop-here! g "leather armour")
(spec-drop-here! g "short blade")
(game-key! g ",")
(def names (List map (fn (_ it) (Str8 append (item-letter it) ") " (items-name g it))) (game-pack g)))
(game-key! g "W")
(def asked (spec-row g 0))
(game-key! g "b")
(def worn (spec-row g 23))
(game-key! g "d")
(game-key! g "b")
(def refused (game-messages g))
(game-key! g "T")
(game-key! g "d")
(game-key! g "b")
(write (list names asked worn refused (game-messages g) (- (List length (game-floor g)) lying) (List length (game-pack g))))
```
---
    (("a) a short blade" "b) leather armour [2]") "Wear what?" "Level:1  Gold:0  Hp:12(12)  Str:16(16)  Arm:2  Exp:1/0" ("You would have to take that off first.") ("You drop leather armour [2].") 1 1)

### w wields; i shows what is in hand

```roguelike
(def g (spec-calm 5 ()))
(spec-drop-here! g "short blade")
(game-key! g ",")
(game-key! g "w")
(game-key! g "a")
(def said (game-messages g))
(game-key! g "i")
(write (list said (Str8 starts? " a) a short blade (in hand)" (spec-row g 1)) (game-turn g)))
```
---
    (("You are now wielding a short blade.") #t 2)

### W lists the armour in the pack over the level, and nothing else

```roguelike
(def g (spec-calm 5 ()))
(spec-drop-here! g "padded coat")
(game-key! g ",")
(spec-drop-here! g "short blade")
(game-key! g ",")
(game-key! g "W")
(def rows (spec-screen g))
(write (list (List ref 0 rows) (List ref 1 rows) (List any? (fn (_ r) (Str8 includes? "short blade" r)) rows)))
```
---
    ("Wear what?" " a) padded coat [1]" #f)

## using

### q asks for a potion; drinking one names its kind, and a full player gains a hit point

```roguelike
(def g (spec-calm 5 ()))
(def it (spec-drop-here! g "healing"))
(game-key! g ",")
(game-key! g "q")
(def asked (spec-row g 0))
(game-key! g "a")
(write (list asked (items-known? g it) (items-name g it) (game-pack g) (game-messages g)
             (player-hp (game-player g)) (player-hpmax (game-player g)) (game-turn g)))
```
---
    ("Quaff what?" #t "a potion of healing" () ("You feel better.") 13 13 2)

### the wrong kind of thing is refused and takes no turn

```roguelike
(def g (spec-calm 5 ()))
(spec-drop-here! g "ration")
(game-key! g ",")
(game-key! g "q")
(def none (game-messages g))
(game-key! g "e")
(game-key! g "b")
(write (list none (game-messages g) (game-turn g)))
```
---
    (("You have nothing like that.") ("You have no such thing.") 1)

### eating fills the player to the brim

```roguelike
(def g (spec-calm 5 ()))
(spec-drop-here! g "ration")
(game-key! g ",")
(game-key! g "e")
(game-key! g "a")
(write (list (player-food (game-player g)) (game-pack g) (Str8 starts? "That tasted " (first (game-messages g)))))
```
---
    (1999 () #t)

### a scroll of mapping shows the whole level

```roguelike
(def g (spec-calm 5 ()))
(spec-drop-here! g "mapping")
(def before (spec-count-seen (game-map g)))
(game-key! g ",")
(game-key! g "r")
(game-key! g "a")
(write (list (< before (spec-count-open (game-map g))) (= (spec-count-seen (game-map g)) (spec-count-open (game-map g))) (game-messages g)))
```
---
    (#t #t ("The level's shape comes to you."))

### a scroll of naming asks which thing to name

```roguelike
(def g (spec-calm 5 ()))
(def potion (spec-drop-here! g "venom"))
(def scroll (spec-drop-here! g "naming"))
(game-key! g ",")
(game-key! g "r")
(game-key! g "a")
(def asked (spec-row g 0))
(game-key! g "b")
(write (list asked (items-known? g scroll) (items-known? g potion) (items-name g potion) (game-messages g) (game-turn g)))
```
---
    ("Name what?" #t #t "a potion of venom" ("a potion of venom") 2)

### a wand asks which way, and its bolt strikes the first creature there

```roguelike
(def g (spec-calm 5 ()))
(def wand (spec-drop-here! g "sparks"))
(def open (spec-open g))
(spec-place! g "cave rat" (first (rest open)) (rest (rest open)) 1 'awake)
(game-key! g ",")
(def charges (item-charges wand))
(game-key! g "z")
(game-key! g "a")
(def asked (spec-row g 0))
(game-key! g (first open))
(write (list asked (game-messages g) (game-creatures g) (player-exp (game-player g)) (items-known? g wand)
             (= (item-charges wand) (- charges 1)) (game-turn g)))
```
---
    ("Which way?" ("The bolt strikes the cave rat." "You have slain the cave rat.") () 2 #t #t 2)
