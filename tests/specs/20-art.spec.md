# The art
# @weight 1

A set's pictures for the windowed front-end, in `data/SET/art/*.xon`
(see `docs/graphics.md`): each tile is the art's size, unless it is
cut in nine; each pixel names a colour of the file; each tile names a
glyph or a creature of the set, or the panel or the shadow; a band
tile names a band of the set, a `(part P)` one of the pieces the
front-end puts together, and `(as OTHER)` a tile of the art; a tile's
`(frames TICKS (rows ...) ...)` and `(walk TICKS (rows ...) ...)` are
each the art's size, held TICKS a picture.


## the checker

### what is wrong with a set's art, as (NAME WHAT) for each tile

```roguelike
(def %art-prop (fn (_ t key) (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest t))))
(def %art-parts '(top face n e s w ne nw se sw out-ne out-nw out-se out-sw face-w face-e shade))
(def %art-marks '(mark-confused mark-blind mark-held mark-hasted mark-slowed mark-seeing mark-hungry mark-weak mark-fainting mark-wounded))
(def %art-poses '(attack hit dead))
(def %art-same? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
(import x/core/doors int+ int< int= str-byte-ref char->int)
(import roguelike/map map-terrain)
(def %art-mask
  (fn (_ cs)
    (Str8 join "" (List map (fn (_ b) (if (List any? (fn (_ c) (= b c)) cs) "#" ".")) (List range 0 128)))))
(def %art-inked?
  (fn (self r i w mask)
    (if (int< i w)
      ((fn (_ b) (if (int< b 128) (if (int= 35 (char->int (str-byte-ref mask b))) (self r (int+ i 1) w mask) #f) #f))
       (char->int (str-byte-ref r i)))
      #t)))
(def %art-rows
  (fn (_ n rows size chars)
    (def w (if (null? size) (Str8 length (first rows)) (first size)))
    (def h (if (null? size) (List length rows) (List ref 1 size)))
    (match ((not (= h (List length rows))) (list n "has the wrong number of rows"))
           ((not (List all? (fn (_ r) (= w (Str8 length r))) rows)) (list n "has a row of the wrong width"))
           ((not (List all? (fn (_ r) (%art-inked? r 0 w chars)) rows))
             (list n "has a pixel with no colour"))
           (#t ()))))
(def %art-frames
  (fn (_ n what fs size chars)
    (match ((not (if (number? (first fs)) (< 0 (first fs)) #f)) (list n (Str8 append "has " what " with no pace")))
           ((null? (rest fs)) (list n (Str8 append "has " what " with no pictures")))
           (#t ((fn (_ bad) (if (null? bad) () (first bad)))
                (List filter (fn (_ x) (not (null? x)))
                  (List map (fn (_ r) (if (if (pair? r) (eq? (first r) 'rows) #f) (%art-rows n (rest r) size chars) (list n "has a picture that is not rows")))
                    (rest fs))))))))
(def %art-tile
  (fn (_ t size chars known tiles bands)
    (def n (first t))
    (def rows (%art-prop t 'rows))
    (def as (%art-prop t 'as))
    (def cut (%art-prop t 'cut))
    (def band (%art-prop t 'band))
    (def part (%art-prop t 'part))
    (def light (%art-prop t 'light))
    (def flicker (%art-prop t 'flicker))
    (def frames (%art-prop t 'frames))
    (def walk (%art-prop t 'walk))
    (def pose (%art-prop t 'pose))
    (List filter (fn (_ x) (not (null? x)))
      (list
        (if (List any? (fn (_ k) (%art-same? k n)) known) () (list n "names nothing in the set"))
        (if (null? band) () (if (List any? (fn (_ b) (str=? (first b) (List ref 1 band))) bands) () (list n "names no band")))
        (if (null? part) () (if (List any? (fn (_ p) (eq? p (List ref 1 part))) %art-parts) () (list n "names no part")))
        (if (null? pose) () (if (List any? (fn (_ p) (eq? p (List ref 1 pose))) %art-poses) () (list n "names no pose")))
        (if (null? light) () (if (= 5 (List length light)) () (list n "has a light of the wrong shape")))
        (if (null? flicker) () (if (null? light) (list n "flickers with no light") ()))
        (if (null? frames) () (%art-frames n "frames" (rest frames) size chars))
        (if (null? walk) () (%art-frames n "a walk" (rest walk) size chars))
        (if (null? as) () (if (List any? (fn (_ o) (%art-same? (first o) (List ref 1 as))) tiles) () (list n "is drawn as nothing")))
        (if (null? rows) (if (null? as) (list n "has no rows") ()) (%art-rows n (rest rows) (if (null? cut) size ()) chars))))))
(def art-problems
  (fn (_ set art)
    (def size (data-one art 'size (list 16 16)))
    (def chars (%art-mask (List map (fn (_ c) (char->int (str-byte-ref (first c) 0))) (data-all art 'colour))))
    (def tiles (data-all art 'tile))
    (def known (pair 'panel (pair 'shadow (List append %art-marks (List map (fn (_ k) (List ref 1 k)) map-terrain) (List map (fn (_ g) (first g)) (data-all set 'glyph))
                                         (List map (fn (_ c) (first c)) (data-all set 'creature))))))
    (def bands (data-all set 'band))
    (List flat-map (fn (_ t) (%art-tile t size chars known tiles bands)) tiles)))
(write (art-problems (spec-set-named "delve")
  (list '(size 2 2) '(colour "a" 1 2 3)
        '(tile wall (rows "aa" "a")) '(tile floor (rows "ab" "aa")) '(tile up (rows "aa"))
        '(tile "nobody" (rows "aa" "aa")) '(tile down (as stairs)) '(tile wall (band "Nowhere") (rows "aa" "aa")) '(tile wall (part side) (rows "aa" "aa"))
        '(tile gold (light 1 2) (rows "aa" "aa")) '(tile ring (flicker 5) (rows "aa" "aa"))
        '(tile panel (cut 1 1 1 1) (rows "aaa" "aaa" "aaa"))
        '(tile food (rows "aa" "aa") (frames 0 (rows "aa" "aa"))) '(tile wand (rows "aa" "aa") (frames 2))
        '(tile scroll (rows "aa" "aa") (frames 2 (rows "aa" "aa") (rows "aa" "ab"))) '(tile potion (rows "aa" "aa") (frames 2 (rows "aa" "aa")))
        '(tile weapon (rows "aa" "aa") (walk 2)) '(tile armour (rows "aa" "aa") (walk 2 (rows "aa" "a")))
        '(tile player (pose sleep) (rows "aa" "aa")) '(tile mark-held (rows "aa" "aa")))))
```
---
    (('wall "has a row of the wrong width") ('floor "has a pixel with no colour") ('up "has the wrong number of rows") ("nobody" "names nothing in the set") ('down "is drawn as nothing") ('wall "names no band") ('wall "names no part") ('gold "has a light of the wrong shape") ('ring "flickers with no light") ('food "has frames with no pace") ('wand "has frames with no pictures") ('scroll "has a pixel with no colour") ('weapon "has a walk with no pictures") ('armour "has a row of the wrong width") ('player "names no pose"))


## the sets

### delve's art is whole

```roguelike
(def art (data-load "data/delve/art"))
(write (list (art-problems (spec-set-named "delve") art) (List length (data-all art 'tile))))
```
---
    (() 225)

### classic's art is whole

```roguelike
(def art (data-load "data/classic/art"))
(write (list (art-problems (spec-set-named "classic") art) (List length (data-all art 'tile))))
```
---
    (() 70)

### kettle's art is whole

```roguelike
(def art (data-load "data/kettle/art"))
(write (list (art-problems (spec-set-named "kettle") art) (List length (data-all art 'tile))))
```
---
    (() 159)

### town's art is whole, the town's walls, setts and roofs with it

```roguelike
(def art (data-load "data/town/art"))
(write (list (art-problems (spec-set-named "town") art) (List length (data-all art 'tile))))
```
---
    (() 66)


## the font

### every printable letter, each eight rows of eight

```roguelike
(def letters (data-all (data-load "art") 'letter))
(write (list (List length letters)
             (List all? (fn (_ c) (List any? (fn (_ l) (= (first l) c)) letters)) (List range 32 127))
             (List all? (fn (_ l) (= 9 (List length (List ref 1 l)))) letters)
             (List all? (fn (_ l) (List all? (fn (_ r) (= 8 (Str8 length r))) (rest (List ref 1 l)))) letters)))
```
---
    (95 #t #t #t)
