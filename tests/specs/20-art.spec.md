# The art
# @weight 1

A set's pictures for the windowed front-end, in `data/SET/art/*.xon`
(see `docs/graphics.md`): each tile is the art's size, unless it is
cut in nine; each pixel names a colour of the file; each tile names a
glyph or a creature of the set, or the panel or the shadow; a band
tile names a band of the set, a `(part P)` one of the pieces the
front-end puts together, and `(as OTHER)` a tile of the art.


## the checker

### what is wrong with a set's art, as (NAME WHAT) for each tile

```roguelike
(def %art-prop (fn (_ t key) (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest t))))
(def %art-parts '(top face n e w ne nw se sw face-w face-e shade))
(def %art-same? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
(def %art-rows
  (fn (_ n rows size chars)
    (def w (if (null? size) (Str8 length (first rows)) (first size)))
    (def h (if (null? size) (List length rows) (List ref 1 size)))
    (match ((not (= h (List length rows))) (list n "has the wrong number of rows"))
           ((not (List all? (fn (_ r) (= w (Str8 length r))) rows)) (list n "has a row of the wrong width"))
           ((not (List all? (fn (_ r) (List all? (fn (_ i) (List any? (fn (_ c) (str=? c (Str8 sub i 1 r))) chars)) (List range 0 w))) rows))
             (list n "has a pixel with no colour"))
           (#t ()))))
(def %art-tile
  (fn (_ t size chars known tiles bands)
    (def n (first t))
    (def rows (%art-prop t 'rows))
    (def as (%art-prop t 'as))
    (def cut (%art-prop t 'cut))
    (def band (%art-prop t 'band))
    (def part (%art-prop t 'part))
    (List filter (fn (_ x) (not (null? x)))
      (list
        (if (List any? (fn (_ k) (%art-same? k n)) known) () (list n "names nothing in the set"))
        (if (null? band) () (if (List any? (fn (_ b) (str=? (first b) (List ref 1 band))) bands) () (list n "names no band")))
        (if (null? part) () (if (List any? (fn (_ p) (eq? p (List ref 1 part))) %art-parts) () (list n "names no part")))
        (if (null? as) () (if (List any? (fn (_ o) (%art-same? (first o) (List ref 1 as))) tiles) () (list n "is drawn as nothing")))
        (if (null? rows) (if (null? as) (list n "has no rows") ()) (%art-rows n (rest rows) (if (null? cut) size ()) chars))))))
(def art-problems
  (fn (_ set art)
    (def size (data-one art 'size (list 16 16)))
    (def chars (List map (fn (_ c) (first c)) (data-all art 'colour)))
    (def tiles (data-all art 'tile))
    (def known (pair 'panel (pair 'shadow (List append (List map (fn (_ g) (first g)) (data-all set 'glyph))
                                         (List map (fn (_ c) (first c)) (data-all set 'creature))))))
    (List flat-map (fn (_ t) (%art-tile t size chars known tiles (data-all set 'band))) tiles)))
(write (art-problems (spec-set-named "delve")
  (list '(size 2 2) '(colour "a" 1 2 3)
        '(tile wall (rows "aa" "a")) '(tile floor (rows "ab" "aa")) '(tile up (rows "aa"))
        '(tile "nobody" (rows "aa" "aa")) '(tile down (as stairs)) '(tile wall (band "Nowhere") (rows "aa" "aa")) '(tile wall (part side) (rows "aa" "aa"))
        '(tile panel (cut 1 1 1 1) (rows "aaa" "aaa" "aaa")))))
```
---
    (('wall "has a row of the wrong width") ('floor "has a pixel with no colour") ('up "has the wrong number of rows") ("nobody" "names nothing in the set") ('down "is drawn as nothing") ('wall "names no band") ('wall "names no part"))


## the sets

### delve's art is whole

```roguelike
(def art (data-load "data/delve/art"))
(write (list (art-problems (spec-set-named "delve") art) (List length (data-all art 'tile))))
```
---
    (() 45)
