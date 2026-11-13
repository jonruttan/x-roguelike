# Stores
# @weight 2

roguelike/shops: a building with (sells (CLASS NAME) ...) or (buys
CLASS ...) keeps a shop.  Walked into, its keeper puts up the counter:
a letter buys, s sells one thing of a class the keeper takes, anything
else leaves.  A thing is worth its (price N) or its class's in the
world's (worth ...), and the shop's (rate SELL BUY) percent of that is
asked and paid.


## the counter

### the innkeeper walked into shows the goods, their prices, the way to sell and the purse

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list host))
(game-key! g (spec-beside! g host))
(def asked (game-ask g))
(write (list (first asked) (List ref 1 asked) (rest (rest (List ref 3 asked)))))
```
---
    ('choose "The innkeeper: what will you have?" ("a) cheese, 4 gold" "b) bread, 4 gold" "s) sell something" "" "You have 0 gold."))

### the counter's answers, for a gamepad: each of the goods by its letter, and selling

```roguelike
(import roguelike/game game-answers)
(write (game-answers g))
```
---
    (("a" . "cheese, 4 gold") ("b" . "bread, 4 gold") ("s" . "Sell something"))

## buying

### a letter pays the price, puts the thing in the pack and leaves the counter up with the purse counted again

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list host))
(player-gold! p 10)
(game-key! g (spec-beside! g host))
(game-key! g "a")
(def board (List ref 3 (game-ask g)))
(write (list (player-gold p) (List map item-name (game-pack g)) (first (game-messages g))
             (first (game-ask g)) (List ref (- (List length board) 1) board)))
```
---
    (6 ("cheese") "You pay the innkeeper 4 gold." 'choose "You have 6 gold.")

### a thing that cannot be afforded is not sold, and the counter is put away

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list host))
(player-gold! p 3)
(game-key! g (spec-beside! g host))
(game-key! g "a")
(write (list (player-gold p) (game-pack g) (game-messages g) (game-ask g)))
```
---
    (3 () ("You cannot afford the cheese: 4 gold.") ())

## selling

### s asks what to sell among what the keeper takes; one of a stack goes for half its worth, and the counter stays up

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list host))
(spec-drop-here! g "bread")
(spec-drop-here! g "bread")
(spec-drop-here! g "survey")
(game-key! g ",")
(def loaf (List find (fn (_ it) (str=? (item-name it) "bread")) (game-pack g)))
(game-key! g (spec-beside! g host))
(game-key! g "s")
(def offered (list (first (game-ask g)) (List ref 1 (game-ask g)) (List ref 3 (game-ask g))))
(game-key! g (item-letter loaf))
(write (list offered (player-gold p) (item-count loaf) (first (game-messages g)) (first (game-ask g))))
```
---
    (('item "Sell what?" ('food)) 2 1 "You sell a bread for 2 gold." 'choose)

### with nothing the keeper takes, s says so; a thing in hand is not sold

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(game-creatures! g (list host))
(game-key! g (spec-beside! g host))
(game-key! g "s")
(def none (list (game-messages g) (first (game-ask g))))
(spec-settle! g)
(spec-drop-here! g "hatchet")
(game-key! g ",")
(def axe (first (game-pack g)))
(game-key! g "w")
(game-key! g (item-letter axe))
(shops-open! g "smith" '((buys weapon armour)) "")
(game-key! g "s")
(game-key! g (item-letter axe))
(write (list none (player-gold p) (List length (game-pack g)) (first (game-messages g))))
```
---
    ((("You have nothing the innkeeper buys.") 'choose) 0 1 "You would have to take that off first.")

## what a thing is worth

### a shop's rate is the percent of a thing's worth asked and paid, and a thing worth nothing is not bought

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def dear '((sells (potion "mending") (ring "warding")) (buys potion token) (rate 150 40)))
(shops-open! g "Guild clerk" dear "")
(def board (List take 2 (List ref 3 (game-ask g))))
(spec-settle! g)
(spec-drop-here! g "mending")
(spec-drop-here! g "the mill pin")
(game-key! g ",")
(def sale
  (fn (_ name)
    (shops-open! g "Guild clerk" dear "")
    (game-key! g "s")
    (game-key! g (item-letter (List find (fn (_ it) (str=? (item-name it) name)) (game-pack g))))
    (first (game-messages g))))
(def pin (sale "the mill pin"))
(write (list (shops-kept? dear) (shops-kept? '((size 8 9))) board pin (sale "mending") (player-gold p)))
```
---
    (#t #f ("a) mending, 18 gold" "b) warding, 75 gold") "The Guild clerk has no use for the mill pin." "You sell a potion of mending for 5 gold." 5)
