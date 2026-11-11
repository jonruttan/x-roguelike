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
