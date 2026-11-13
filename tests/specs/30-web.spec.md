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
(player-conditions! (game-player spec-g) ())
(sound-turn! spec-s spec-g)
(write (list spec-calm (List ref 1 spec-held) (List ref 2 spec-held)
             (List includes? '(phase 1 6 2600 55 70) (first spec-held))
             (equal? spec-calm (spec-heard))))
(sound-close spec-s)
(Web close spec-win)
```
---
    (((('echo 430 42 26) ('echo 610 30 14) ('reverb 90 55 18) ('limit 92 150)) 0 100 100) -340 70 #t #t)

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
