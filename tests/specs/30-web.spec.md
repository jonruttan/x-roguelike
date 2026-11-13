# Played in a browser
# @weight 2

`--web` plays as `--window` does, drawn and heard through the platform's
Web in place of Sdl: the window and the sound keep the class they were
made with, and both answer the same messages.


## the command line

### --web and --listen are declared, short and long

```roguelike
(import x/sys/opts)
(def text (Opts usage roguelike-options))
(def o (Opts parse roguelike-options (list "-W" "--listen" "0.0.0.0" "play")))
(write (list (Str8 includes? "-W,--web" text) (Str8 includes? "-L,--listen" text)
             (Opts on? o "-W") (Opts value o "-L") (Opts operands o)))
```
---
    (#t #t #t "0.0.0.0" ("play"))

## the sound

### the sound is made through Web and keeps music queued ahead of the speaker

```roguelike
(import x/sys/web)
(import roguelike/sound sound-make sound-close)
(Web listen! "127.0.0.1" 0)
(def spec-win (Web open "spec" 8 8 1))
(def spec-g (game-make (data-load "data/delve") 1 24 80))
(def spec-s (sound-make spec-g Web))
(write (list (null? spec-s) (int< 0 (Web audio-queued (obj-ref spec-s 3))) (str? (Web url spec-win))))
(sound-close spec-s)
(Web close spec-win)
```
---
    (#f #t #t)

### the place's room and the music's limit go over the mix, and a condition's pitch, pace and effect come and go with it

```roguelike
(import x/sys/web)
(import x/audio/mixer)
(import x/audio/tracker)
(import roguelike/sound sound-make sound-turn! sound-close)
(import roguelike/state player-condition! player-conditions!)
(Web listen! "127.0.0.1" 0)
(def spec-win (Web open "spec" 8 8 1))
(def spec-g (game-make (data-load "data/delve") 1 24 80))
(def spec-s (sound-make spec-g Web))
(def spec-m (obj-ref spec-s 2))
(def spec-heard
  (fn (_)
    (list (List map rest (Mixer effects spec-m)) (Mixer pitch spec-m) (Tracker pace (obj-ref spec-s 5)) (Mixer cut spec-m))))
(def spec-calm (spec-heard))
(player-condition! (game-player spec-g) 'slowed 10)
(player-condition! (game-player spec-g) 'confused 10)
(sound-turn! spec-s spec-g)
(def spec-held (spec-heard))
(def spec-sway (List ref 4 (obj-ref spec-s 24)))
(player-conditions! (game-player spec-g) ())
(sound-turn! spec-s spec-g)
(write (list spec-calm (List ref 1 spec-held) (List ref 2 spec-held)
             (List includes? '(phase 1 6 2600 55 70) (first spec-held))
             spec-sway
             (equal? spec-calm (spec-heard))))
(sound-close spec-s)
(Web close spec-win)
```
---
    (((('echo 430 42 26) ('echo 610 30 14) ('reverb 90 55 18) ('limit 92 150)) 0 100 100) -340 70 #t (15 5600) #t)

### wounds thin the music but not the heart, and hunger growls the more the emptier

```roguelike
(import x/sys/web)
(import x/audio/mixer)
(import roguelike/sound sound-make sound-turn! sound-close)
(import roguelike/state player-hp! player-hpmax! player-food!)
(Web listen! "127.0.0.1" 0)
(def spec-win (Web open "spec" 8 8 1))
(def spec-g (game-make (data-load "data/delve") 1 24 80))
(def spec-s (sound-make spec-g Web))
(def spec-p (game-player spec-g))
(def spec-thin (fn (_ m) (List find (fn (_ e) (same? (first e) 'thin)) (Mixer effects m))))
(def spec-calm (list (spec-thin (obj-ref spec-s 2)) (obj-ref spec-s 23)))
(player-hpmax! spec-p 100)
(player-hp! spec-p 10)
(player-food! spec-p 0)
(sound-turn! spec-s spec-g)
(def spec-low (list (rest (spec-thin (obj-ref spec-s 2))) (null? (spec-thin (obj-ref spec-s 25)))
                    (same? (obj-ref spec-s 2) (obj-ref spec-s 25)) (obj-ref spec-s 23)))
(player-food! spec-p 7200)
(sound-turn! spec-s spec-g)
(write (list spec-calm spec-low (obj-ref spec-s 23)))
(sound-close spec-s)
(Web close spec-win)
```
---
    ((() ()) (('phase 0 0 1000 0 -70) #t #f (("growl" 8000 45))) (("growl" 24000 45)))

### confusion sways the music's pace either way of the mix's, as the music is pumped

```roguelike
(import x/sys/web)
(import x/audio/tracker)
(import roguelike/sound sound-make sound-turn! sound-pump! sound-close)
(import roguelike/state player-condition! player-conditions!)
(Web listen! "127.0.0.1" 0)
(def spec-win (Web open "spec" 8 8 1))
(def spec-g (game-make (data-load "data/delve") 1 24 80))
(def spec-s (sound-make spec-g Web))
(player-condition! (game-player spec-g) 'confused 10)
(sound-turn! spec-s spec-g)
(def spec-t (obj-ref spec-s 5))
(def spec-paces
  ((fn (self n acc) (if (int< n 1) acc (do (Web audio-clear! (obj-ref spec-s 3)) (sound-pump! spec-s) (self (int- n 1) (pair (Tracker pace spec-t) acc)))))
   60 ()))
(player-conditions! (game-player spec-g) ())
(sound-turn! spec-s spec-g)
(def spec-least (List fold (fn (_ a b) (if (int< b a) b a)) 1000 spec-paces))
(def spec-most (List fold (fn (_ a b) (if (int< a b) b a)) 0 spec-paces))
(write (list (int< 84 spec-least) (int< spec-least 90) (int< 110 spec-most) (int< spec-most 116)
             (Tracker pace spec-t)))
(sound-close spec-s)
(Web close spec-win)
```
---
    (#t #t #t #t 100)
