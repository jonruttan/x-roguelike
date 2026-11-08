# Menus and options
# @weight 1

The window's title, options and pause screens (see `docs/graphics.md`):
a list of choices moved through with the keys the game takes, the
options kept between games, and the menu drawn over the dimmed level.


## the options

### every option at its default, each held in its range, a switch turned over

```roguelike
(import roguelike/options options-names options-default options-get options-set options-step options-line options-read options-write!)
(def o (options-default))
(write (list options-names
             (List map (fn (_ n) (options-get o n)) options-names)
             (options-get (options-set o 'zoom 9) 'zoom)
             (options-get (options-step (options-set o 'music 100) 'music 1) 'music)
             (options-get (options-step o 'music -1) 'music)
             (options-get (options-step (options-step o 'fullscreen 1) 'fullscreen -1) 'fullscreen)
             (List map (fn (_ n) (options-line o n)) options-names)))
```
---
    (('zoom 'fullscreen 'music 'effects) (2 0 80 100) 4 100 70 0 ("Zoom         2" "Fullscreen   Off" "Music        80%" "Sounds       100%"))

### kept and read back; a file missing some, or with a value out of range, takes the defaults' and the range's

```roguelike
(def tmp (File temp "/tmp/x-roguelike-options-"))
(File close (first tmp))
(def path (rest tmp))
(options-write! (options-set (options-set (options-default) 'zoom 3) 'effects 40) path)
(def back (options-read path))
(File write-all path "(music 250)\n(nothing 3)\n(zoom \"big\")\n")
(def partial (options-read path))
(File unlink path)
(write (list (List map (fn (_ n) (options-get back n)) options-names)
             (List map (fn (_ n) (options-get partial n)) options-names)
             (List map (fn (_ n) (options-get (options-read path) n)) options-names)))
```
---
    ((3 0 80 40) (2 0 100 100) (2 0 80 100))


## the menu

### up and down move the choice round; enter takes it, escape goes back, left and right change it

```roguelike
(import roguelike/menu menu-make menu-chosen menu-id menu-key)
(def m (menu-make (list (pair 'new "New game") (pair 'options "Options") (pair 'quit "Quit"))))
(def moves (List map (fn (_ k) (do (menu-key m k) (menu-chosen m))) (list 'down "j" 'down 'up "k")))
(write (list moves (menu-key m 'enter) (menu-key m ",") (menu-key m 'escape) (menu-key m 'left) (menu-key m 'right)
             (menu-key m "x") (menu-id m)))
```
---
    ((1 2 0 2 1) ('take . 'options) ('take . 'options) 'back ('change 'options . -1) ('change 'options . 1) () 'options)


## drawing

### a menu over the dimmed level: the heading, the chosen item bright, the prompts at the foot

```roguelike
(import roguelike/paint paint-font paint-make paint-turn! paint-frame! paint-menu! paint-art paint-width paint-height)
(import roguelike/frame frame-art)
(import x/gfx/canvas)
(def font (paint-font "art"))
(def fa (frame-art (paint-art (data-load "data/delve/art")) ()))
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def p (paint-make font))
(paint-turn! p g fa)
(def row-sum (fn (_ c y) (List fold (fn (_ n x) (+ n (first (Canvas pixel c x y)))) 0 (List range 0 paint-width))))
(def lit-sum (row-sum (paint-frame! p g 0) 150))
(def s (paint-menu! p g "The Delve" #t (list "New game" "Options" "Quit") 1 (list (pair "Enter" "Choose") (pair "Esc" "Back")) #f))
(def dimmed (row-sum s 150))
(def ink? (fn (_ y0 y1) (List any? (fn (_ y) (List any? (fn (_ x) (< 200 (first (Canvas pixel s x y)))) (List range 0 paint-width))) (List range y0 y1))))
(def title-checks (list (< dimmed lit-sum) (ink? 56 110) (ink? 170 230) (ink? 330 350)))
(def pad (paint-menu! p g "Paused" #f (list "Back to the game") 0 (list (pair "A" "Choose")) #t))
(def green? (List any? (fn (_ x) ((fn (_ c) (if (< (first c) 140) (< 150 (first (rest c))) #f)) (Canvas pixel pad x 340))) (List range 0 paint-width)))
(write (List append title-checks (list green?)))
```
---
    (#t #t #t #t #t)
