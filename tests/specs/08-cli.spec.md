# The command line
# @weight 1

roguelike/cli declares its options to the platform's Opts: what parse
accepts is what usage prints, in short and --long spellings.


## the declaration

### the usage names every option, short and long

```roguelike
(def text (Opts usage roguelike-options))
(write (List map (fn (_ s) (Str8 includes? s text)) (list "-s,--set" "-S,--seed" "-d,--data" "-V,--version" "-h,--help" "x -l roguelike --")))
```
---
    (#t #t #t #t #t #t)

### short, long and --long=value spell one option; operands pass through; an unknown option is named

```roguelike
(import x/sys/opts)
(def o1 (Opts parse roguelike-options (list "-s" "delve" "-S" "7" "play")))
(def o2 (Opts parse roguelike-options (list "--set=delve" "--seed" "7" "scores")))
(def o3 (Opts parse roguelike-options (list "-x" "play")))
(write (list (Opts value o1 "-s") (Opts value o1 "-S") (Opts operands o1)
             (Opts value o2 "-s") (Opts value o2 "-S") (Opts operands o2)
             (Opts unknown o3) (Opts on? (Opts parse roguelike-options (list "--version")) "-V")))
```
---
    ("delve" "7" ("play") "delve" "7" ("scores") "-x" #t)
