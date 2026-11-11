# The gamepad
# @weight 1

A gamepad's events turned into the keys the game takes (see
`roguelike/pad.x`). Time is handed in, in milliseconds, so the specs
step it.

## buttons

### each button is its command; a release and an unused button are none

```roguelike
(import roguelike/pad pad-make pad-key pad-event?)
(def s (pad-make))
(write (list (pad-key s '(pad-down south 1) 0) (pad-key s '(pad-up south 1) 0)
             (pad-key s '(pad-down east 1) 0) (pad-key s '(pad-down right-shoulder 1) 0)
             (pad-key s '(pad-down start 1) 0) (pad-key s '(pad-down guide 1) 0)
             (pad-event? '(pad-axis left-x 0 1)) (pad-event? '(key-down 97 0 #f)) (pad-event? ())))
```
---
    ("," () 'escape ">" 'pause () #t #f #f)

### an event with nothing after its name, a quit or a close, is no key

```roguelike
(write (list (pad-key s '(quit) 0) (pad-key s '(close) 0) (pad-key s '(other 512) 0)))
```
---
    (() () ())

## directions

### a d-pad direction moves after a moment, then repeats while held, and stops on release

```roguelike
(import roguelike/pad pad-make pad-key)
(def s (pad-make))
(write (list (pad-key s '(pad-down dpad-up 1) 0) (pad-key s () 39) (pad-key s () 40)
             (pad-key s () 100) (pad-key s () 300) (pad-key s () 400) (pad-key s () 420)
             (pad-key s '(pad-up dpad-up 1) 430) (pad-key s () 1000)))
```
---
    (() () 'up () 'up () 'up () ())

### a stick pushed to a diagonal moves once, diagonally, not straight on the way

```roguelike
(import roguelike/pad pad-make pad-key)
(def s (pad-make))
(write (list (pad-key s '(pad-axis left-x 30000 1) 0) (pad-key s '(pad-axis left-y -30000 1) 10)
             (pad-key s () 49) (pad-key s () 50)
             (pad-key s '(pad-axis left-x 12000 1) 60) (pad-key s '(pad-axis left-x 4000 1) 70)
             (pad-key s () 110)))
```
---
    (() () () "u" () () 'up)

### two d-pad buttons are a diagonal; the stick wins over the d-pad

```roguelike
(import roguelike/pad pad-make pad-key)
(def s (pad-make))
(pad-key s '(pad-down dpad-down 1) 0)
(pad-key s '(pad-down dpad-left 1) 0)
(def d (pad-key s () 100))
(pad-key s '(pad-axis left-x 32767 1) 100)
(write (list d (pad-key s () 200)))
```
---
    ("b" 'right)

## the view

### the right stick moves the view at once, then while held; the left stick still walks first

```roguelike
(import roguelike/pad pad-make pad-key)
(def s (pad-make))
(def first-look (pad-key s '(pad-axis right-x 30000 1) 0))
(def soon (pad-key s () 50))
(def held (pad-key s () 90))
(pad-key s '(pad-axis left-y -30000 1) 100)
(def walk (pad-key s () 140))
(pad-key s '(pad-axis left-y 0 1) 150)
(pad-key s '(pad-axis right-x 0 1) 160)
(write (list first-look soon held walk (pad-key s () 400)))
```
---
    (('look 1 0) () ('look 1 0) 'up ())
