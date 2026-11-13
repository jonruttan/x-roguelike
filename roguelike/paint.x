; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/paint.x -- the frame drawn: the scene's ops onto a canvas
;
; A set's art turned into pictures once, when it is loaded; then each
; turn the level drawn into a layer of its own, and each frame that
; layer, what stands on it, the light and the text drawn onto the
; screen, a 640 by 360 RGBA canvas (see docs/graphics.md).
;
; A tile form of the art gains (picture CANVAS OPAQUE?): its rows as a
; canvas, and whether every pixel of it is opaque, so it is copied
; rather than blended.  A tile drawn (as OTHER) takes OTHER's picture.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/paint)

(import x/type/vector)
(import x/gfx/canvas)
(import x/core/doors int+ int- int* int/ int% int< int= str-make str->ptr ptr-ref ptr-set!)
(import roguelike/data data-load data-all)
(import roguelike/state game-ask game-blows)
(import roguelike/frame frame-tile-size frame-view-rows frame-view-cols frame-view! frame-level-y
  frame-scene frame-light-map frame-light-cache frame-level-cache frame-named)
(import roguelike/draw draw-top draw-standing draw-overlay)

(def paint-width 640)
(def paint-height 360)

; The text is drawn at the art's scale: onto a strip at one screen
; pixel a font pixel, the strip then shown twice the size.  A letter is
; 6 wide and a line 9 high on the strip, so a strip line holds 52
; letters inside its margins.
(def %pt-scale 2)
(def %pt-strip-w (int/ paint-width %pt-scale))
(def %pt-advance 6)
(def %pt-pitch 9)
(def %pt-margin 4)
(def %pt-cols (int/ (int- %pt-strip-w (int* 2 %pt-margin)) %pt-advance))
; The messages' strip, two lines, and the standing's, three lines, in
; strip pixels.
(def %pt-top-h 21)
(def %pt-stand-h 29)
; The screen's part the level is shown in, between the two strips.
(def paint-level-y (int* %pt-scale %pt-top-h))
(def %pt-area-w paint-width)
(def %pt-area-h (int- paint-height (int* %pt-scale (int+ %pt-top-h %pt-stand-h))))
(def %pt-stand-y (int+ paint-level-y %pt-area-h))
; The zooms the level can be shown at: the view as many cells as fill
; the area at the zoom, the last cell cut where it does not divide.
(def paint-zoom-least 1)
(def paint-zoom-most 4)
(def paint-zoom-first 2)
(def %pt-cells (fn (_ px zoom) (int/ (int+ px (int- (int* frame-tile-size zoom) 1)) (int* frame-tile-size zoom))))
(def %pt-black (list 0 0 0))
(def %pt-ink (list 206 198 184))
(def %pt-glyph (list 236 228 204))
; The strips' colours: a sooty ground ruled off from the level, labels
; dim and values bright, a warning amber and a danger red.
(def %pt-hud-ground (list 26 23 20))
(def %pt-hud-rule (list 92 80 64))
(def %pt-dim (list 150 138 120))
(def %pt-bright (list 240 232 210))
(def %pt-warn (list 222 172 72))
(def %pt-bad (list 214 84 62))
(def %pt-good (list 116 170 92))
(def %pt-bar-ground (list 54 48 42))

; The property KEY of PROPS, or nil: a plain walk, as the ops below,
; since a List send costs a few hundred objects and a turn draws
; thousands of ops.
(def %pt-find
  (fn (self props key)
    (match ((null? props) ()) ((if (pair? (first props)) (eq? (first (first props)) key) #f) (first props))
           (#t (self (rest props) key)))))
; Of a whole form, (tile NAME . PROPS).
(def %pt-prop (fn (_ f key) (%pt-find (rest (rest f)) key)))
(def %pt-tile? (fn (_ f) (if (pair? f) (eq? (first f) (lit tile)) #f)))

; --- the art ----------------------------------------------------------------

; Whether every one of canvas C's pixels is opaque.
(def %pt-opaque?
  (fn (_ c)
    (def p (str->ptr (List ref 2 c)))
    (def n (int* (first c) (List ref 1 c)))
    ((fn (self i) (match ((int= i n) #t) ((int< (ptr-ref p (int+ (int* i 4) 3) 1) 255) #f) (#t (self (int+ i 1))))) 0)))

; The picture of ROWS, a (rows ...) form, in COLOURS: (picture CANVAS
; OPAQUE?).
(def %pt-picture
  (fn (_ rows colours)
    ((fn (_ c) (list (lit picture) c (%pt-opaque? c))) (Canvas rows (rest rows) colours))))

; ART-FORMS with each tile form's picture added; for a tile that moves,
; (pictures TICKS PICTURE ...): its own rows' then each of its (frames
; TICKS (rows ...) ...), each held TICKS ticks; and for one that walks,
; (walking TICKS PICTURE ...): each of its (walk TICKS (rows ...) ...).
; A tile drawn as another takes the first of that one's whole, unbanded
; pictures.
(def paint-art
  (fn (_ art-forms)
    (def colours (data-all art-forms (lit colour)))
    (def cycle (fn (_ head form pics) (pair head (pair (first (rest form)) pics))))
    (def drawn
      (List map
        (fn (_ f)
          (def rows (if (%pt-tile? f) (%pt-prop f (lit rows)) ()))
          (def frames (if (null? rows) () (%pt-prop f (lit frames))))
          (def walk (if (null? rows) () (%pt-prop f (lit walk))))
          (def each (fn (_ form) (List map (fn (_ r) (%pt-picture r colours)) (rest (rest form)))))
          (if (null? rows) f
            ((fn (_ pic)
               (List append f (list pic)
                 (if (null? frames) () (list (cycle (lit pictures) frames (pair pic (each frames)))))
                 (if (null? walk) () (list (cycle (lit walking) walk (each walk))))))
             (%pt-picture rows colours))))
        art-forms))
    (def whole
      (fn (_ name)
        (List find (fn (_ f) (if (%pt-tile? f)
                                (if (eq? (List ref 1 f) name)
                                  (if (null? (%pt-prop f (lit part)))
                                    (if (null? (%pt-prop f (lit band))) (not (null? (%pt-prop f (lit picture)))) #f) #f) #f) #f))
          drawn)))
    (List map
      (fn (_ f)
        (def as (if (%pt-tile? f) (%pt-prop f (lit as)) ()))
        (def other (if (null? as) () (whole (List ref 1 as))))
        (if (null? other) f
          (List append f (list (%pt-prop other (lit picture)))
            ((fn (_ ps) (if (null? ps) () (list ps))) (%pt-prop other (lit pictures))))))
      drawn)))

; Whether tile names A and B are one name: a glyph's symbol or a
; creature's string.
(def %pt-same-name? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
; The painted art OWN, then each tile of the painted art OUTER whose
; name OWN draws nothing of: a region's own ground in front, and the
; world's people and things it carries in drawn as the world draws
; them.
(def %pt-beside
  (fn (_ own outer)
    (def names (List map (fn (_ f) (List ref 1 f)) (List filter %pt-tile? own)))
    (List append own
      (List filter (fn (_ f) (if (%pt-tile? f) (not (List any? (fn (_ n) (%pt-same-name? n (List ref 1 f))) names)) #f))
        outer))))

; The art of each place of the set at DIR, as a function of the place:
; "" the set's own art/; a region (see data.x) the art/ of its set
; beside DIR, with the set's own art behind it for any name it does
; not draw.  Each is read and painted (paint-art) the first time it is
; asked for, and what the reading left behind is collected.  A name no
; art draws is drawn with its letter.
(def paint-arts
  (fn (_ dir)
    (def made (Vector of ()))
    (fn (self place)
      (def hit (List find (fn (_ p) (str=? (first p) place)) (Vector ref 0 made)))
      (if (null? hit)
        ((fn (_ own)
           (def art (if (str=? place "") own (%pt-beside own (self ""))))
           (Vector set! 0 (pair (pair place art) (Vector ref 0 made)) made)
           (Heap collect)
           art)
         (paint-art (guard (e ()) (data-load (Str8 append (if (str=? place "") dir (Str8 append dir "/../" place)) "/art")))))
        (rest hit)))))

; A one-letter string of the character with code N.
(def %pt-letter
  (fn (_ n)
    (def s (str-make 2))
    (ptr-set! (str->ptr s) 0 n 1)
    (ptr-set! (str->ptr s) 1 0 1)
    s))

; The font of the art at DIR, (letter CODE (rows ...)) each, for text!:
; each letter's columns 1 to 6, its ink and one clear, so letters sit a
; column apart, not three.
(def paint-font
  (fn (_ dir)
    (Canvas font
      (List map (fn (_ l) (list (%pt-letter (first l)) (List map (fn (_ r) (Str8 sub 1 %pt-advance r)) (rest (first (rest l))))))
        (data-all (data-load dir) (lit letter))))))

; --- drawing ------------------------------------------------------------------

; The canvas methods the ops call, resolved once.
(def %pt-copy! (method-of Canvas (lit copy!)))
(def %pt-blend! (method-of Canvas (lit blend!)))
(def %pt-fill! (method-of Canvas (lit fill!)))
(def %pt-text! (method-of Canvas (lit text!)))
; The Nth of L.
(def %pt-nth (fn (self n l) (if (int= n 0) (first l) (self (int- n 1) (rest l)))))
; The picture of PROPS, a tile's, at TICK for the cell at X Y: its one
; picture, or of its pictures one by how the tile moves.  TICK comes
; moved on by the camera's place (paint-frame!), so a cell's step holds
; as the view scrolls; each cell is out of step with the rest by its
; place.  MODE is nil for the ground, whose pictures go round in turn;
; for a thing that walks, moving when it moved on the last turn, still
; otherwise.  A thing moving, for one round of its pictures after the
; turn (AGE the ticks since that turn was first shown), goes round its
; walk (walking ...), or its pictures where it has no walk, in step; a
; thing still, or done moving, holds its first picture and now and
; then, at no beat, shows another for a while.
(def %pt-pick
  (fn (_ props x y tick mode age)
    (def ps (%pt-find props (lit pictures)))
    (def ws (if (eq? mode (lit moving)) (%pt-find props (lit walking)) ()))
    (def seed (int+ (int* (int/ x frame-tile-size) 7) (int* (int/ y frame-tile-size) 13)))
    (match
      ((if (null? ws) #f (int< age (%pt-round ws))) (%pt-cycle ws tick seed))
      ((null? ps) (%pt-find props (lit picture)))
      ((if (null? mode) #t (eq? mode (lit mark))) (%pt-cycle ps tick seed))
      ((if (eq? mode (lit moving)) (int< age (%pt-round ps)) #f) (%pt-cycle ps tick seed))
      (#t (%pt-fidget ps tick seed)))))
(def %pt-length (fn (self l n) (if (null? l) n (self (rest l) (int+ n 1)))))
; The ticks of one round of PS, (HEAD TICKS PICTURE ...).
(def %pt-round (fn (_ ps) (int* (first (rest ps)) (%pt-length (rest (rest ps)) 0))))
; Of PS, the picture TICK has come to, going round in turn from SEED.
(def %pt-cycle
  (fn (_ ps tick seed)
    (def all (rest (rest ps)))
    (%pt-nth (int% (int/ (int+ tick seed) (first (rest ps))) (%pt-length all 0)) all)))
; Of PS, its first picture, or for about one stretch of TICKS in five
; another of them, the stretches picked by a hash of the stretch and
; SEED, so a crowd standing about fidgets each at its own odd moments.
(def %pt-fidget
  (fn (_ ps tick seed)
    (def all (rest (rest ps)))
    (def n (%pt-length all 0))
    (def stretch (int/ (int+ tick (int* seed 5)) (first (rest ps))))
    (def h (int% (int* (int+ (int* stretch 7919) (int* seed 104729)) 31337) 1009))
    (if (if (int< 1 n) (int< (int% h 100) 22) #f) (%pt-nth (int+ 1 (int% h (int- n 1))) all) (first all))))
; Op OP drawn on canvas C at TICK, its Y moved up by DY: a tile copied
; when its picture is opaque and blended when not, a fill in black, a
; glyph in the font in the middle of its cell.  A tile with no picture
; draws nothing.  A tile op's form is (NAME . PROPS), then a walking
; thing's MODE (see %pt-pick) and the (DX . DY) it is drawn off its
; cell by (see %pt-motion), AGE the ticks since the turn was shown.
(def %pt-op!
  (fn (_ c op dy font tick age)
    (def head (first op))
    (def x (first (rest op)))
    (def y (int- (first (rest (rest op))) dy))
    (def more (rest (rest (rest op))))
    (match
      ((eq? head (lit tile))
        ((fn (_ pic shift)
           (unless (null? pic)
             ((if (first (rest (rest pic))) %pt-copy! %pt-blend!)
              Canvas c (if (pair? shift) (int+ x (first shift)) x) (if (pair? shift) (int+ y (rest shift)) y)
              (first (rest pic)) 0 0 frame-tile-size frame-tile-size)))
         (%pt-pick (rest (first more)) x (first (rest (rest op))) tick (if (null? (rest more)) () (first (rest more))) age)
         (if (null? (rest more)) () (if (null? (rest (rest more))) () (first (rest (rest more)))))))
      ((eq? head (lit fill)) (%pt-fill! Canvas c x y (first more) (first (rest more)) %pt-black))
      ((eq? head (lit glyph)) (%pt-text! Canvas c (int+ x 5) (int+ y 4) (first more) %pt-glyph font))
      (#t ()))))
; Each op of OPS drawn on C as %pt-op! draws it.
(def %pt-ops!
  (fn (self c ops dy font tick age)
    (unless (null? ops) (do (%pt-op! c (first ops) dy font tick age) (self c (rest ops) dy font tick age)))))

; A glint op, (glint X Y SEED GOLD?), drawn on C at TICK, its Y moved
; up by DY: a star near the cell's top right that grows and shrinks
; over five of every twenty frames, gold for gold and pale otherwise.
(def %pt-star (Vector of 1 2 3 2 1))
(def %pt-gold (list 255 224 110))
(def %pt-pale (list 236 244 255))
(def %pt-glint!
  (fn (_ c op dy tick)
    (def more (rest (rest (rest op))))
    (def k (int% (int+ tick (first more)) 20))
    (when (int< k 5)
      (do (def n (Vector ref k %pt-star))
          (def x (int+ (first (rest op)) 11))
          (def y (int+ (int- (first (rest (rest op))) dy) 4))
          (def colour (if (first (rest more)) %pt-gold %pt-pale))
          (%pt-fill! Canvas c x y 1 1 (list 255 255 255))
          ((fn (self i)
             (when (int< i n)
               (do (%pt-fill! Canvas c (int- x i) y 1 1 colour) (%pt-fill! Canvas c (int+ x i) y 1 1 colour)
                   (%pt-fill! Canvas c x (int- y i) 1 1 colour) (%pt-fill! Canvas c x (int+ y i) 1 1 colour)
                   (self (int+ i 1)))))
           1)))))
(def %pt-glints!
  (fn (self c ops dy tick)
    (unless (null? ops)
      (do (when (eq? (first (first ops)) (lit glint)) (%pt-glint! c (first ops) dy tick))
          (self c (rest ops) dy tick)))))

; A sleep op, (sleep X Y SEED), drawn on C at TICK in FONT, its Y moved
; up by DY: two small z letters drifting up and right from the
; sleeper's head, each round twenty-four ticks, fading as they rise,
; out of step with every other sleeper's.
(def %pt-sleep-ink (Vector of (list 214 230 255) (list 170 190 225) (list 120 136 170)))
(def %pt-sleep!
  (fn (_ c op dy tick font)
    (def x (List ref 1 op))
    (def y (int- (List ref 2 op) dy))
    (def t (int% (int+ tick (List ref 3 op)) 24))
    (List for-each
      (fn (_ j)
        (def u (int% (int+ t (int* j 12)) 24))
        (when (int< u 18)
          (%pt-text! Canvas c (int+ x (int+ 6 (int/ u 4))) (int- (int+ y 2) (int/ u 3)) "z"
            (Vector ref (int/ u 6) %pt-sleep-ink) font)))
      (list 0 1))))
(def %pt-sleeps!
  (fn (self c ops dy tick font)
    (unless (null? ops)
      (do (when (eq? (first (first ops)) (lit sleep)) (%pt-sleep! c (first ops) dy tick font))
          (self c (rest ops) dy tick font)))))

; --- blows ---------------------------------------------------------------------

; A turn's blows, (blow FX FY TX TY HOW N BY-PLAYER? WHAT UNSEEN?) ops
; (frame.x), shown over %pt-blow-frames frames after the turn: the
; striker lunges toward its target, a blow that lands flashes the
; target white (the player's) or red (a creature's), the player's kill
; bursts where the creature was, and the damage, or "miss", rises from
; the target.  A blow with WHAT, what flew, has no lunge: WHAT flies
; from the striker to the target over %pt-flight-frames frames first,
; and the rest follows.  One UNSEEN stirs the air where it came from.
; Each a frame's step, by frame K.
(def %pt-blow-frames 8)
(def %pt-flight-frames 4)
; The frame blow B's landing is shown from.
(def %pt-start (fn (_ b) (if (null? (List ref 8 b)) 0 %pt-flight-frames)))
; The frame after the last of BLOWS is shown.
(def %pt-blows-end
  (fn (_ blows) (List fold (fn (_ n b) ((fn (_ e) (if (int< n e) e n)) (int+ (%pt-start b) %pt-blow-frames))) 0 blows)))

; What flew in blow B, (blow FX FY TX TY HOW N BY-PLAYER? WHAT), drawn
; on C at frame K of its flight, its Y moved up by DY: a stone and its
; dust, a bolt's streak of light, a gout of flame swelling as it goes.
(def %pt-stone (list 196 182 152))
(def %pt-stone-edge (list 52 44 36))
(def %pt-stone-dust (list 130 118 100))
(def %pt-bolt (list 130 210 255))
(def %pt-bolt-core (list 255 255 255))
(def %pt-flame (list 230 92 24))
(def %pt-flame-mid (list 255 160 50))
(def %pt-flame-core (list 255 236 140))

; A round blob of radius R at X Y on C in COLOUR: rows narrowing from
; the middle, a diamond with its corners filled.
(def %pt-blob!
  (fn (_ c x y r colour)
    ((fn (self i)
       (when (int< i (int+ r 1))
         (do (def w (int- r (int/ i 2)))
             (%pt-fill! Canvas c (int- x w) (int- y i) (int+ 1 (int* 2 w)) 1 colour)
             (%pt-fill! Canvas c (int- x w) (int+ y i) (int+ 1 (int* 2 w)) 1 colour)
             (self (int+ i 1)))))
     0)))

; A line of pixels from A to B, (X . Y) each, on C in COLOUR.
(def %pt-line!
  (fn (_ c a b colour)
    (def dx (int- (first b) (first a)))
    (def dy (int- (rest b) (rest a)))
    (def n ((fn (_ x y) (if (int< x y) y x)) (if (int< dx 0) (int- 0 dx) dx) (if (int< dy 0) (int- 0 dy) dy)))
    ((fn (self i)
       (when (int< i (int+ n 1))
         (do (%pt-fill! Canvas c (int+ (first a) (if (int= n 0) 0 (int/ (int* dx i) n)))
                                 (int+ (rest a) (if (int= n 0) 0 (int/ (int* dy i) n))) 1 1 colour)
             (self (int+ i 1)))))
     0)))

(def %pt-missile!
  (fn (_ c b k dy)
    (def fx (int+ (List ref 1 b) 8))
    (def fy (int+ (int- (List ref 2 b) dy) 8))
    (def dx (int- (List ref 3 b) (List ref 1 b)))
    (def dyy (int- (List ref 4 b) (List ref 2 b)))
    (def at (fn (_ i) (pair (int+ fx (int/ (int* dx i) %pt-flight-frames)) (int+ fy (int/ (int* dyy i) %pt-flight-frames)))))
    (def head (at (int+ k 1)))
    (def tail (at k))
    (def mid (pair (int/ (int+ (first head) (first tail)) 2) (int/ (int+ (rest head) (rest tail)) 2)))
    (def what (List ref 8 b))
    (match
      ((eq? what (lit bolt))
        (do (%pt-line! c tail head %pt-bolt)
            (%pt-blob! c (first head) (rest head) 1 %pt-bolt-core)))
      ((eq? what (lit breath))
        (do (%pt-blob! c (first tail) (rest tail) (int+ k 1) %pt-flame)
            (%pt-blob! c (first mid) (rest mid) (int+ k 2) %pt-flame)
            (%pt-blob! c (first head) (rest head) (int+ k 3) %pt-flame-mid)
            (%pt-blob! c (first head) (rest head) (int+ 1 (int/ k 2)) %pt-flame-core)))
      (#t
        (do (%pt-fill! Canvas c (first tail) (rest tail) 1 1 %pt-stone-dust)
            (%pt-fill! Canvas c (first mid) (rest mid) 1 1 %pt-stone-dust)
            (%pt-blob! c (first head) (rest head) 2 %pt-stone-edge)
            (%pt-blob! c (first head) (rest head) 1 %pt-stone))))))
(def %pt-lunge-by (Vector of 2 4 5 4 2 1 0 0))
(def %pt-flash-by (Vector of 230 190 140 90 40 0 0 0))
(def %pt-burst-by (Vector of 1 2 4 5 6 5 3 0))
(def %pt-stamp! (method-of Canvas (lit stamp!)))
(def %pt-sign (fn (_ n) (if (int< n 0) -1 (if (int< 0 n) 1 0))))
(def %pt-blow-ops (fn (self ops) (match ((null? ops) ()) ((eq? (first (first ops)) (lit blow)) (pair (first ops) (self (rest ops)))) (#t (self (rest ops))))))

; A thing that stepped glides from the cell it left over
; %pt-glide-frames frames, what is left of the way in sixteenths each
; frame: quick off the mark, slowing, a pixel past and back.
(def %pt-glide-frames 5)
(def %pt-glide-by (Vector of 11 6 2 -1 0))

; The (DX . DY) the striker standing at X Y is moved toward its target
; by frame K of BLOWS, or nil when no blow was struck from there.
(def %pt-lunge-at
  (fn (self x y blows k)
    (match
      ((null? blows) ())
      ((if (int= x (List ref 1 (first blows))) (int= y (List ref 2 (first blows))) #f)
        ((fn (_ b by) (pair (int* by (%pt-sign (int- (List ref 3 b) x))) (int* by (%pt-sign (int- (List ref 4 b) y)))))
         (first blows) (Vector ref k %pt-lunge-by)))
      (#t (self x y (rest blows) k)))))

; OPS as frame KB of BLOWS and frame KG of the glide move them: each
; walking thing's tile op, (tile X Y PICTURE MODE FROM), made (tile X Y
; PICTURE MODE (DX . DY)), the pixels it is drawn off its cell by, the
; way back to FROM still to go and its lunge; a glyph standing where a
; blow was struck from moved by its lunge.  The cell stays the op's, so
; a picture keeps the variant of its cell while it moves.  While POSED,
; the turn's blows still shown, a tile op with a pose, (tile X Y PICTURE
; MODE FROM POSED), is drawn as POSED, going round its pictures.
(def %pt-motion
  (fn (_ ops blows kb kg posed)
    (def gb (if (int< kg %pt-glide-frames) (Vector ref kg %pt-glide-by) 0))
    (def lb (fn (_ x y) (if (int< kb %pt-blow-frames) (%pt-lunge-at x y blows kb) ())))
    (List map
      (fn (_ op)
        (def x (List ref 1 op))
        (def y (List ref 2 op))
        (def pose (if posed (int< 6 (List length op)) #f))
        (match
          ((if (eq? (first op) (lit tile)) (not (null? (rest (rest (rest (rest op)))))) #f)
            ((fn (_ from lunge)
               (list (lit tile) x y (if pose (List ref 6 op) (List ref 3 op)) (if pose (lit mark) (List ref 4 op))
                     (pair (int+ (if (null? from) 0 (int/ (int* gb (first from)) 16)) (if (null? lunge) 0 (first lunge)))
                           (int+ (if (null? from) 0 (int/ (int* gb (rest from)) 16)) (if (null? lunge) 0 (rest lunge))))))
             (List ref 5 op) (lb x y)))
          ((eq? (first op) (lit glyph))
            ((fn (_ lunge) (if (null? lunge) op (pair (lit glyph) (pair (int+ x (first lunge)) (pair (int+ y (rest lunge)) (rest (rest (rest op))))))))
             (lb x y)))
          (#t op)))
      ops)))

; The picture of the last tile of OPS at X Y, what is drawn on top
; there, or nil.
(def %pt-top-picture
  (fn (self ops x y found)
    (if (null? ops) found
      (self (rest ops) x y
        ((fn (_ op)
           (if (if (eq? (first op) (lit tile)) (if (int= x (first (rest op))) (int= y (first (rest (rest op)))) #f) #f)
             ((fn (_ pic) (if (null? pic) found pic)) (%pt-find (rest (first (rest (rest (rest op))))) (lit picture)))
             found))
         (first ops))))))

; A star of arms N at X Y on C in COLOUR.
(def %pt-star!
  (fn (_ c x y n colour)
    (%pt-fill! Canvas c x y 1 1 colour)
    ((fn (self i)
       (when (int< i (int+ n 1))
         (do (%pt-fill! Canvas c (int- x i) y 1 1 colour) (%pt-fill! Canvas c (int+ x i) y 1 1 colour)
             (%pt-fill! Canvas c x (int- y i) 1 1 colour) (%pt-fill! Canvas c x (int+ y i) 1 1 colour)
             (self (int+ i 1)))))
     1)))

; Where a blow comes from no one drawn, the air stirs: a pale ring
; widening from the striker's cell, radius by frame, gone by the end.
(def %pt-stir-ink (list 170 205 225))
(def %pt-stir-by (Vector of 2 3 4 5 6 7 0 0))
; A ring of radius R at X Y on C, a diamond's outline; none at 0.
(def %pt-stir!
  (fn (_ c x y r)
    (unless (int= r 0)
      (do (%pt-line! c (pair (int- x r) y) (pair x (int- y r)) %pt-stir-ink)
          (%pt-line! c (pair x (int- y r)) (pair (int+ x r) y) %pt-stir-ink)
          (%pt-line! c (pair (int+ x r) y) (pair x (int+ y r)) %pt-stir-ink)
          (%pt-line! c (pair x (int+ y r)) (pair (int- x r) y) %pt-stir-ink)))))

(def %pt-hurt-ink (list 255 90 70))
(def %pt-dealt-ink (list 255 224 110))
(def %pt-miss-ink (list 180 180 180))
(def %pt-shade-ink (list 0 0 0))

; BLOWS drawn on C at frame K over OPS, the frame's, their Y moved up
; by DY, in FONT: what flew still in flight, the rest each at its own
; frame since it landed.
(def %pt-blows!
  (fn (self c ops blows k dy font)
    (unless (null? blows)
      (do (def b (first blows))
          (def j (int- k (%pt-start b)))
          (match
            ((int< j 0) (%pt-missile! c b k dy))
            ((int< j %pt-blow-frames) (%pt-landed! c ops b j dy font))
            (#t ()))
          (self c ops (rest blows) k dy font)))))
(def %pt-landed!
  (fn (_ c ops b k dy font)
    (def tx (List ref 3 b))
    (def ty (List ref 4 b))
    (def how (List ref 5 b))
    (def mine (List ref 7 b))
    (def y (int- ty dy))
    (when (if (int< 9 (List length b)) (List ref 9 b) #f)
      (%pt-stir! c (int+ (List ref 1 b) 8) (int+ (int- (List ref 2 b) dy) 8) (Vector ref k %pt-stir-by)))
    (unless (eq? how (lit miss))
      ((fn (_ pic)
         (if (if (null? pic) #t (if mine (eq? how (lit kill)) #f))
           (%pt-star! c (int+ tx 8) (int+ y 8) (Vector ref k %pt-burst-by) (if mine %pt-dealt-ink %pt-hurt-ink))
           (%pt-stamp! Canvas c tx y (first (rest pic)) 0 0 frame-tile-size frame-tile-size
             ((fn (_ a) (if mine (list 255 255 255 a) (list 255 70 50 a))) (Vector ref k %pt-flash-by)))))
       (%pt-top-picture ops tx ty ())))
    ; A touch, or a blow that did no harm, writes nothing.
    (unless (if (eq? how (lit miss)) #f (int< (List ref 6 b) 1))
      (do (def s (if (eq? how (lit miss)) "miss" (Str8 str (List ref 6 b))))
          (def x (int- (int+ tx 8) (int* 4 (Str8 length s))))
          (def ny (int- y (int+ 2 (int* 2 k))))
          (%pt-text! Canvas c (int+ x 1) (int+ ny 1) s %pt-shade-ink font)
          (%pt-text! Canvas c x ny s (match ((eq? how (lit miss)) %pt-miss-ink) (mine %pt-dealt-ink) (#t %pt-hurt-ink)) font)))))

; Whether painter P has a turn's blows, or a step, still to show.
(def paint-animating?
  (fn (_ p)
    (match
      ((int< (Vector ref 9 p) (%pt-blows-end (%pt-blow-ops (%pt-over p)))) #t)
      ((int< (Vector ref 12 p) %pt-glide-frames) (List any? %pt-stepped? (%pt-over p)))
      (#t #f))))
; Whether OP is a walking thing's tile op come from another cell.
(def %pt-stepped?
  (fn (_ op) (if (eq? (first op) (lit tile)) (if (int< 5 (List length op)) (pair? (List ref 5 op)) #f) #f)))
; Painter P a frame on in showing the blows and the steps.
(def paint-step!
  (fn (_ p) (do (Vector set! 9 (int+ 1 (Vector ref 9 p)) p) (Vector set! 12 (int+ 1 (Vector ref 12 p)) p) p)))

; A painter: [SCREEN LAYER FONT SCENE PANEL WORK ZOOM WHERE SHOWN BLOW
; TOP STANDING GLIDE CHART TOP-KEY TOP-DRAWN STANDING-KEY LIGHT LEVEL
; BLOWS], the scene the last turn's, the panel the art's nine-piece
; picture (a tile form) or nil, WORK the level drawn and lit at the
; tile's size before it is shown at ZOOM, LAYER and WORK the view's
; size; WHERE each walking thing's (WHO R . C) on the last turn, SHOWN
; the tick that turn was first shown at, or -1 before it is; BLOW the
; frame the turn's blows are shown at; TOP and STANDING the strips the
; messages and the standing are drawn on, TOP a pair: two lines and
; three; GLIDE the frame the turn's steps are shown at; CHART the
; turn's chart, (CANVAS . OP), or nil; TOP-KEY what the top strip was
; last drawn with, (TEXT . ASKING?), and TOP-DRAWN the strip it was
; drawn on; STANDING-KEY what the standing was last drawn with; LIGHT
; the light map's cache (frame-light-cache); LEVEL the level's
; (frame-level-cache); BLOWS the game's blows last drawn (game-blows).
(def paint-make
  (fn (_ font)
    (paint-zoom! (Vector of (Canvas make paint-width paint-height) () font () () () 0 () -1 %pt-blow-frames
                            (pair (Canvas make %pt-strip-w %pt-top-h) (Canvas make %pt-strip-w (int+ %pt-top-h %pt-pitch)))
                            (Canvas make %pt-strip-w %pt-stand-h) %pt-glide-frames () () () () (frame-light-cache) (frame-level-cache) ())
                 paint-zoom-first)))
(def paint-screen (fn (_ p) (Vector ref 0 p)))
(def %pt-over (fn (_ p) (rest (rest (Vector ref 3 p)))))
(def paint-zoom (fn (_ p) (Vector ref 6 p)))

; Painter P set to show the level at ZOOM, held to the zooms there are:
; the view, the frame's, made as many cells as fill the area, and the
; layer and work made its size.  The next turn painted draws the level
; anew.  P.
(def paint-zoom!
  (fn (_ p zoom)
    (def z (if (int< zoom paint-zoom-least) paint-zoom-least (if (int< paint-zoom-most zoom) paint-zoom-most zoom)))
    (frame-view! (%pt-cells %pt-area-h z) (%pt-cells %pt-area-w z))
    (Vector set! 1 (Canvas make (%pt-level-w) (%pt-level-h)) p)
    (Vector set! 5 (Canvas make (%pt-level-w) (%pt-level-h)) p)
    (Vector set! 6 z p)
    p))
(def %pt-level-w (fn (_) (int* (frame-view-cols) frame-tile-size)))
(def %pt-level-h (fn (_) (int* (frame-view-rows) frame-tile-size)))

; Of OPS, each walking thing's tile op, (tile X Y PICTURE (WHO R . C)),
; made (tile X Y PICTURE MODE FROM): moving when WAS, the (WHO R . C) of
; the turn before, has WHO elsewhere, still otherwise; FROM the pixels
; (DX . DY) to the cell it stepped from, or nil when it did not step
; there from a cell beside it.  A mark, (tile X Y PICTURE (WHO R . C)
; mark), is made MODE mark: it moves with WHO and goes round its
; pictures.  A blow's pose, (tile X Y PICTURE (WHO R . C) (pose POSED)),
; is made (tile X Y PICTURE MODE FROM POSED).
(def %pt-modes
  (fn (_ ops was)
    (List map
      (fn (_ op)
        (if (if (eq? (first op) (lit tile)) (null? (rest (rest (rest (rest op))))) #t) op
          ((fn (_ at)
             (def before (List find (fn (_ w) (same? (first w) (first at))) was))
             (def dr (if (null? before) 0 (int- (first (rest before)) (first (rest at)))))
             (def dc (if (null? before) 0 (int- (rest (rest before)) (rest (rest at)))))
             (def moved (not (if (int= dr 0) (int= dc 0) #f)))
             (def beside (if (int< (int* dr dr) 2) (int< (int* dc dc) 2) #f))
             (def kind (if (int< 5 (List length op)) (List ref 5 op) ()))
             (List append
               (list (lit tile) (first (rest op)) (first (rest (rest op))) (List ref 3 op)
                     (match ((eq? kind (lit mark)) (lit mark)) (moved (lit moving)) (#t (lit still)))
                     (if (if moved beside #f) (pair (int* dc frame-tile-size) (int* dr frame-tile-size)) ()))
               (if (pair? kind) (list (List ref 1 kind)) ())))
           (List ref 4 op))))
      ops)))
; The (WHO R . C) of each walking thing's tile op of OPS.
(def %pt-where
  (fn (_ ops)
    (List map (fn (_ op) (List ref 4 op))
      (List filter (fn (_ op) (if (eq? (first op) (lit tile)) (not (null? (rest (rest (rest (rest op)))))) #f)) ops))))

; The turn's scene of game G with art A taken, and its level drawn into
; the layer: once a turn, not a frame.  Each walking thing is marked
; moving or still against where it stood on the turn before.  A turn's
; blows are shown once: drawn again for the same blows, as after a key
; the game did not take, they are shown at their end.
(def paint-turn!
  (fn (_ p g a)
    (def scene (frame-scene (Vector ref 18 p) g a))
    (def over (rest (rest scene)))
    (def layer (Vector ref 1 p))
    (Canvas fill! layer 0 0 (%pt-level-w) (%pt-level-h) %pt-black)
    (%pt-ops! layer (first (rest scene)) frame-level-y (Vector ref 2 p) 0 0)
    (Vector set! 3 (pair (first scene) (pair (first (rest scene)) (%pt-modes over (Vector ref 7 p)))) p)
    (Vector set! 7 (%pt-where over) p)
    (Vector set! 8 -1 p)
    (Vector set! 4 (frame-named a (lit panel) 0) p)
    (Vector set! 9 (if (same? (game-blows g) (Vector ref 19 p)) (%pt-blows-end (%pt-blow-ops (%pt-over p))) 0) p)
    (Vector set! 19 (game-blows g) p)
    (Vector set! 12 0 p)
    (Vector set! 13 ((fn (_ op) (if (null? op) () (%pt-chart op))) (List find (fn (_ op) (eq? (first op) (lit chart))) over)) p)
    p))

; The turn's scene drawn again for a view moved by a drag: as
; paint-turn! draws it, its blows and steps not shown again.
(def paint-view!
  (fn (_ p g a)
    (paint-turn! p g a)
    (Vector set! 9 (%pt-blows-end (%pt-blow-ops (%pt-over p))) p)
    (Vector set! 12 %pt-glide-frames p)
    p))

; TEXT in lines of at most N letters, broken at a space.
(def %pt-break
  (fn (self text i n)
    (match ((< i 1) n) ((str=? (Str8 sub i 1 text) " ") i) (#t (self text (- i 1) n)))))
(def %pt-lines
  (fn (self text n)
    (if (< (Str8 length text) (+ n 1)) (list text)
      ((fn (_ at) (pair (Str8 sub 0 at text) (self (Str8 sub (+ at 1) (- (Str8 length text) (+ at 1)) text) n)))
       (%pt-break text n n)))))
(def %pt-fit (fn (_ s n) (if (< n (Str8 length s)) (Str8 sub 0 n s) s)))

; Strip STRIP shown on screen S at Y, at the text's scale.
(def %pt-show!
  (fn (_ s strip y)
    (Canvas nine! s 0 y paint-width (int* %pt-scale (List ref 1 strip)) strip 0 0 0 0)))

; The messages, or the question asked, on the top strip, the ground
; ruled off from the level below: two lines, or three over the level's
; top when the text needs them.  STRIPS is (TWO . THREE).  The strip
; drawn.
(def %pt-top!
  (fn (_ strips font text asking?)
    (def lines (List take 3 (%pt-lines text %pt-cols)))
    (def strip (if (int< 2 (List length lines)) (rest strips) (first strips)))
    (def h (List ref 1 strip))
    (def colour (if asking? %pt-bright %pt-ink))
    (Canvas fill! strip 0 0 %pt-strip-w h %pt-hud-ground)
    (Canvas fill! strip 0 (int- h 1) %pt-strip-w 1 %pt-hud-rule)
    ((fn (self l y) (unless (null? l) (do (Canvas text! strip %pt-margin y (first l) colour font) (self (rest l) (int+ y %pt-pitch)))))
     lines 2)
    strip))

; LABEL dim then VALUE in COLOUR, on STRIP at X Y: the x after them.
(def %pt-pair!
  (fn (_ strip x y label value colour font)
    (Canvas text! strip x y label %pt-dim font)
    (def vx (int+ x (int* %pt-advance (int+ (Str8 length label) 1))))
    (Canvas text! strip vx y value colour font)
    (int+ vx (int* %pt-advance (int+ (Str8 length value) 2)))))

; The colour of HP out of MAX: good above half, a warning above a
; quarter, danger below.
(def %pt-hp-colour
  (fn (_ hp max)
    (match ((int< max (int* 2 hp)) %pt-good) ((int< max (int* 4 hp)) %pt-warn) (#t %pt-bad))))

; The standing on its strip: the place and the gold on the first line;
; hit points as a bar, strength, armour, the level, and any condition
; on the second; the gauges, food and the lamp, on the third.  A spent
; strength is a warning.
(def %pt-bar-w 48)
; The gauges along the standing's third line from X: each its label,
; a bar of what is left and the percentage, coloured by its level.
(def %pt-gauges!
  (fn (self strip x y gauges font)
    (unless (null? gauges)
      (do (def label (first (first gauges)))
          (def percent (List ref 1 (first gauges)))
          (def level (List ref 2 (first gauges)))
          (def colour (match ((int< level 1) %pt-good) ((int< level 2) %pt-warn) (#t %pt-bad)))
          (Canvas text! strip x y label (if (int< level 1) %pt-dim colour) font)
          (def bx (int+ x (int* %pt-advance (int+ (Str8 length label) 1))))
          (Canvas fill! strip bx (int+ y 1) %pt-bar-w 5 %pt-bar-ground)
          (Canvas fill! strip bx (int+ y 1) (int/ (int* %pt-bar-w percent) 100) 5 colour)
          (def text (Str8 append (Str8 str percent) "%"))
          (def tx (int+ bx (int+ %pt-bar-w %pt-advance)))
          (Canvas text! strip tx y text (if (int< level 1) %pt-bright colour) font)
          (self strip (int+ tx (int* %pt-advance (int+ (Str8 length text) 2))) y (rest gauges) font)))))
(def %pt-standing!
  (fn (_ strip font st)
    (def place (List ref 0 st))
    (def depth (List ref 1 st))
    (def hp (List ref 2 st))
    (def hpmax (List ref 3 st))
    (def gold (Str8 str (List ref 4 st)))
    (def strength (List ref 5 st))
    (def strmax (List ref 6 st))
    (def warnings (List ref 9 st))
    (def y1 2)
    (def y2 (int+ 2 %pt-pitch))
    (def right (int- %pt-strip-w %pt-margin))
    (Canvas fill! strip 0 0 %pt-strip-w %pt-stand-h %pt-hud-ground)
    (Canvas fill! strip 0 0 %pt-strip-w 1 %pt-hud-rule)
    (Canvas text! strip %pt-margin y1
      (%pt-fit (match ((null? depth) place)
                      ((str=? place "") (Str8 append "Level " (Str8 str depth)))
                      (#t (Str8 append place ", level " (Str8 str depth))))
               (int- %pt-cols (int+ 6 (Str8 length gold))))
      %pt-bright font)
    (%pt-pair! strip (int- right (int* %pt-advance (int+ 5 (Str8 length gold)))) y1 "Gold" gold %pt-bright font)
    (def colour (%pt-hp-colour hp hpmax))
    (Canvas text! strip %pt-margin y2 "HP" %pt-dim font)
    (def bx (int+ %pt-margin (int* 3 %pt-advance)))
    (Canvas fill! strip bx (int+ y2 1) %pt-bar-w 5 %pt-bar-ground)
    (Canvas fill! strip bx (int+ y2 1) (int/ (int* %pt-bar-w (if (int< hp 0) 0 hp)) (if (int< hpmax 1) 1 hpmax)) 5 colour)
    (def tx (int+ bx (int+ %pt-bar-w %pt-advance)))
    (def hpt (Str8 append (Str8 str hp) "/" (Str8 str hpmax)))
    (Canvas text! strip tx y2 hpt colour font)
    (def x1 (int+ tx (int* %pt-advance (int+ (Str8 length hpt) 2))))
    (def x2 (%pt-pair! strip x1 y2 "Str" (if (int< strength strmax) (Str8 append (Str8 str strength) "/" (Str8 str strmax)) (Str8 str strength))
                       (if (int< strength strmax) %pt-warn %pt-bright) font))
    (def x3 (%pt-pair! strip x2 y2 "Arm" (Str8 str (List ref 7 st)) %pt-bright font))
    (def x4 (%pt-pair! strip x3 y2 "Lv" (Str8 str (List ref 8 st)) %pt-bright font))
    (Canvas text! strip x4 y2 (%pt-fit warnings (int/ (int- right x4) %pt-advance)) %pt-warn font)
    (%pt-gauges! strip %pt-margin (int+ y2 %pt-pitch) (List ref 10 st) font)))

; LINES laid over the level on a panel at its top left: the art's
; nine-piece PANEL (a tile form) stretched round them, or a dark box
; where the set has none.  Drawn at the text's scale when the lines fit
; the level's area so, else at the screen's.  Nothing for no lines.
(def %pt-panel-dark (list 20 18 16 235))
(def %pt-overlay!
  (fn (_ s panel font lines)
    (unless (null? lines)
      (do (def widest (List fold (fn (_ n l) (if (< n (Str8 length l)) (Str8 length l) n)) 0 lines))
          (def scale (if (if (int< (int* (List length lines) %pt-pitch) (int- (int/ %pt-area-h %pt-scale) 16))
                             (int< (int* widest %pt-advance) (int- %pt-strip-w 16)) #f)
                       %pt-scale 1))
          (def room-w (int/ paint-width scale))
          (def shown (List take (int/ (- (int/ %pt-area-h scale) 16) %pt-pitch) lines))
          (def w (int+ 16 (int* %pt-advance widest)))
          (def w2 (if (int< room-w w) room-w w))
          (def h (int+ 16 (int* %pt-pitch (List length shown))))
          (def c (Canvas make w2 h))
          (def pic (if (null? panel) () (%pt-find (rest panel) (lit picture))))
          (def cut (if (null? panel) () (%pt-find (rest panel) (lit cut))))
          (if (if (null? pic) #t (null? cut))
            (Canvas fill! c 0 0 w2 h %pt-panel-dark)
            (Canvas nine! c 0 0 w2 h (List ref 1 pic) (List ref 1 cut) (List ref 2 cut) (List ref 3 cut) (List ref 4 cut)))
          ((fn (self l ly) (unless (null? l) (do (Canvas text! c 8 ly (%pt-fit (first l) (int/ (int- w2 16) %pt-advance)) %pt-ink font) (self (rest l) (+ ly %pt-pitch)))))
           shown 8)
          (Canvas nine! s 0 paint-level-y (int* scale w2) (int* scale h) c 0 0 0 0)))))

; Frame TICK of game G drawn on the screen from the last turn's scene:
; the layer, what stands on it, the light and the glints, worked at the
; tile's size and shown at the zoom; then the messages and the
; standing.  The screen.
(def paint-frame!
  (fn (_ p g tick)
    (def s (Vector ref 0 p))
    (def font (Vector ref 2 p))
    (def k (Vector ref 9 p))
    (def blows ((fn (_ all) (if (int< k (%pt-blows-end all)) all ())) (%pt-blow-ops (%pt-over p))))
    ; Only a blow in hand lunges.
    (def over (%pt-motion (%pt-over p) (List filter (fn (_ b) (null? (List ref 8 b))) blows) k (Vector ref 12 p)
                              (not (null? blows))))
    (def work (Vector ref 5 p))
    (def lw (first work))
    (def lh (first (rest work)))
    (def zoom (Vector ref 6 p))
    (Canvas copy! work 0 0 (Vector ref 1 p) 0 0 lw lh)
    (def cam (first (Vector ref 3 p)))
    (when (int< (Vector ref 8 p) 0) (Vector set! 8 tick p))
    ; The camera may sit past the map's top or left edge; moved on by a
    ; screenful so the tick a tile steps by is never below zero.
    (%pt-ops! work over frame-level-y font (int+ tick (int+ (int* (int+ (rest cam) 128) 7) (int* (int+ (first cam) 128) 13))) (int- tick (Vector ref 8 p)))
    (Canvas light! work 0 0 lw lh
      (frame-light-map (Vector ref 17 p) (List find (fn (_ op) (eq? (first op) (lit view))) over)
                       (List filter (fn (_ op) (eq? (first op) (lit light))) over) tick)
      frame-tile-size)
    (%pt-glints! work over frame-level-y tick)
    (%pt-sleeps! work over frame-level-y tick font)
    (%pt-blows! work over blows k frame-level-y font)
    (Canvas nine! s 0 paint-level-y (int* zoom lw) (int* zoom lh) work 0 0 0 0)
    (%pt-chart! s (Vector ref 13 p) cam zoom tick)
    ; A strip is drawn again only when what it shows has changed.
    ((fn (_ key)
       (unless (equal? key (Vector ref 14 p))
         (do (Vector set! 15 (%pt-top! (Vector ref 10 p) font (first key) (rest key)) p)
             (Vector set! 14 key p))))
     (pair (draw-top g) (not (null? (game-ask g)))))
    (%pt-show! s (Vector ref 15 p) 0)
    ((fn (_ st)
       (unless (equal? st (Vector ref 16 p))
         (do (%pt-standing! (Vector ref 11 p) font st)
             (Vector set! 16 st p))))
     (draw-standing g))
    (%pt-show! s (Vector ref 11 p) %pt-stand-y)
    (%pt-overlay! s (Vector ref 4 p) font (draw-overlay g))
    s))

; --- the chart ----------------------------------------------------------------

; The whole level, small, in the level's bottom right corner: a cell
; %pt-chart-cell pixels square in a rim a pixel wide, each cell in the
; ink of what is known of it (frame-chart's codes), the creatures shown
; red, the player blinking white.
(def %pt-chart-cell 2)
(def %pt-chart-gap 6)
(def %pt-chart-inks
  (Vector of (list 10 9 8 200) (list 70 62 52 235) (list 112 102 86 245) (list 130 118 100 245)
             (list 196 182 156 255) (list 255 224 110 255) (list 170 196 255 255) (list 168 112 64 255)
             (list 96 200 176 255)))
(def %pt-chart-rim (list 92 80 64 255))
(def %pt-chart-who (list 230 80 60 255))
(def %pt-chart-me (list 255 255 255 255))

; The chart's colours by character for Canvas rows: a code's digit, r
; the rim, w a creature.
(def %pt-chart-colours
  (List append (list (pair "r" %pt-chart-rim) (pair "w" %pt-chart-who))
    (List map (fn (_ i) (pair (Str8 str i) (Vector ref i %pt-chart-inks))) (List range 0 9))))

; The chart of chart op OP, (chart ROWS COLS BYTES (PR . PC) ((R . C)
; ...)), made once a turn a pixel a cell in its rim, as rows of
; characters: (CANVAS . OP).  It is drawn %pt-chart-cell times larger.
(def %pt-chart
  (fn (_ op)
    (def rows (List ref 1 op))
    (def cols (List ref 2 op))
    (def bp (str->ptr (List ref 3 op)))
    (def w (int+ cols 2))
    (def h (int+ rows 2))
    (def buf (str-make (int+ 1 (int* w h))))
    (def out (str->ptr buf))
    (def r-ch (char->int (str-byte-ref "r" 0)))
    (def zero (char->int (str-byte-ref "0" 0)))
    ((fn (self j y x)
       (when (int< j (int* w h))
         (do (ptr-set! out j
               (if (match ((int= y 0) #t) ((int= y (int- h 1)) #t) ((int= x 0) #t) ((int= x (int- w 1)) #t) (#t #f))
                 r-ch
                 (int+ zero (ptr-ref bp (int+ (int* (int- y 1) cols) (int- x 1)) 1)))
               1)
             (if (int= (int+ x 1) w) (self (int+ j 1) (int+ y 1) 0) (self (int+ j 1) y (int+ x 1))))))
     0 0 0)
    (List for-each (fn (_ at) (ptr-set! out (int+ (int* (int+ (first at) 1) w) (int+ (rest at) 1)) (char->int (str-byte-ref "w" 0)) 1))
      (List ref 5 op))
    (pair (Canvas rows (List map (fn (_ y) (Str8 sub (int* y w) w buf)) (List range 0 h)) %pt-chart-colours) op)))

; Whether Q, (X . Y), lies in the rectangle X Y W H.
(def %pt-inside?
  (fn (_ q x y w h)
    (if (int< (first q) x) #f (if (int< (rest q) y) #f (if (int< (first q) (int+ x w)) (int< (rest q) (int+ y h)) #f)))))

; The chart CH, (CANVAS . OP) or nil, drawn on screen S under camera
; CAM at ZOOM and TICK: in the corner unless a creature shown stands
; under it there; and, for each creature shown whose middle is off the
; level's area, a red pointer toward it, and a white one toward the
; player when the view is dragged off it.
(def %pt-chart!
  (fn (_ s ch cam zoom tick)
    (unless (null? ch)
      (do (def op (rest ch))
          (def t (int* frame-tile-size zoom))
          (def at (List ref 4 op))
          ; The view's middle, where the pointers point from.
          (def x0 (int+ (int* t (int/ (frame-view-cols) 2)) (int/ t 2)))
          (def y0 (int+ paint-level-y (int+ (int* t (int/ (frame-view-rows) 2)) (int/ t 2))))
          (def place (fn (_ q) (pair (int+ (int* t (int- (rest q) (rest cam))) (int/ t 2))
                                     (int+ paint-level-y (int+ (int* t (int- (first q) (first cam))) (int/ t 2))))))
          (def places (List map place (List ref 5 op)))
          (def off? (fn (_ q) (not (%pt-inside? q 0 paint-level-y paint-width %pt-area-h))))
          (def w (int+ 2 (int* %pt-chart-cell (List ref 2 op))))
          (def h (int+ 2 (int* %pt-chart-cell (List ref 1 op))))
          (def cx (int- paint-width (int+ w %pt-chart-gap)))
          (def cy (int- %pt-stand-y (int+ h %pt-chart-gap)))
          (unless (List any? (fn (_ q) (%pt-inside? q cx cy w h)) places)
            (do (Canvas nine! s cx cy w h (first ch) 1 1 1 1)
                (when (int< (int% tick 8) 5)
                  (%pt-fill! Canvas s (int+ cx (int+ 1 (int* %pt-chart-cell (rest at)))) (int+ cy (int+ 1 (int* %pt-chart-cell (first at))))
                    %pt-chart-cell %pt-chart-cell %pt-chart-me))))
          (List for-each (fn (_ q) (when (off? q) (%pt-pointer! s x0 y0 q tick %pt-pointer-ink))) places)
          ((fn (_ q) (when (off? q) (%pt-pointer! s x0 y0 q tick %pt-pointer-me))) (place at))))))

; A pointer on screen S from X0 Y0, the view's middle, toward Q, (X .
; Y), off the level's area: an arrowhead in INK %pt-pointer-in pixels
; inside the area's edge where the line to Q leaves it, nodding toward
; Q.
(def %pt-pointer-in 12)
(def %pt-pointer-ink (list 230 80 60))
(def %pt-pointer-me (list 240 236 224))
(def %pt-nod (Vector of 0 1 2 1))
(def %pt-abs (fn (_ n) (if (int< n 0) (int- 0 n) n)))
(def %pt-least (fn (_ a b) (if (int< a b) a b)))
; Of the way (D . E), D's part of the nearest of the eight ways, in
; tenths: 10, 7 on a diagonal, or 0, signed.
(def %pt-unit
  (fn (_ d e)
    (def a (%pt-abs d))
    (def b (%pt-abs e))
    (if (int< (int* a 5) (int* b 2)) 0 (int* (%pt-sign d) (if (int< (int* b 5) (int* a 2)) 10 7)))))
; The share of D, in 1024ths, that takes O to LO or HI the way D goes.
(def %pt-reach
  (fn (_ d lo hi o)
    (match ((int< 0 d) (int/ (int* (int- hi o) 1024) d)) ((int< d 0) (int/ (int* (int- lo o) 1024) d)) (#t 1024))))
(def %pt-pointer!
  (fn (_ s x0 y0 q tick ink)
    (def dx (int- (first q) x0))
    (def dy (int- (rest q) y0))
    (def f (%pt-least (%pt-least 1024 (%pt-reach dx %pt-pointer-in (int- paint-width %pt-pointer-in) x0))
                      (%pt-reach dy (int+ paint-level-y %pt-pointer-in) (int- %pt-stand-y %pt-pointer-in) y0)))
    (def ux (%pt-unit dx dy))
    (def uy (%pt-unit dy dx))
    (def nod (Vector ref (int% (int/ tick 2) 4) %pt-nod))
    (def x (int+ (int+ x0 (int/ (int* dx f) 1024)) (int/ (int* ux nod) 10)))
    (def y (int+ (int+ y0 (int/ (int* dy f) 1024)) (int/ (int* uy nod) 10)))
    (%pt-arrow! s x y ux uy 1 %pt-black)
    (%pt-arrow! s x y ux uy 0 ink)))

; An arrowhead on S at X Y pointing along (UX . UY), in tenths, grown by
; G pixels all round, in INK: its tip 5 pixels ahead, its base 3 behind
; and 10 across.  A row at a time.
(def %pt-arrow!
  (fn (_ s x y ux uy g ink)
    (def r (int+ 6 (int* 2 g)))
    (def tip (int+ 50 (int* 14 g)))
    (def base (int- -30 (int* 10 g)))
    (List for-each
      (fn (_ v)
        (def us (List filter
                  (fn (_ u)
                    (def a (int+ (int* u ux) (int* v uy)))
                    (if (int< a base) #f
                      (if (int< tip a) #f (not (int< (int* (int- tip a) 5) (int* (%pt-abs (int- (int* v ux) (int* u uy))) 8))))))
                  (List range (int- 0 r) (int+ r 1))))
        (unless (null? us)
          (%pt-fill! Canvas s (int+ x (first us)) (int+ y v) (int+ 1 (int- (List last us) (first us))) 1 ink)))
      (List range (int- 0 r) (int+ r 1)))))

; --- menus --------------------------------------------------------------------

; The level dimmed behind a menu: a dark, mostly opaque picture stretched
; over the screen.
(def %pt-veil (Canvas fill! (Canvas make 3 3) 0 0 3 3 (list 8 7 6 210)))
(def %pt-text-w (fn (_ s) (int* %pt-advance (Str8 length s))))

; TEXT on a strip of its own, shown on screen S centred at Y, SCALE
; times the font's size, in COLOUR.
(def %pt-big!
  (fn (_ s font text y scale colour)
    (def w (int+ 2 (%pt-text-w text)))
    (def c (Canvas make w (int+ 2 %pt-pitch)))
    (Canvas text! c 1 1 text colour font)
    (Canvas nine! s (int/ (int- paint-width (int* scale w)) 2) y (int* scale w) (int* scale (int+ 2 %pt-pitch)) c 0 0 0 0)))

; A pad button's or a key's name drawn as a prompt on strip C at X Y: a
; pad's A and B on their own colours, the way the buttons are; a key in
; brackets.  The x after it.
(def %pt-badge-ink
  (fn (_ name)
    (match ((str=? name "A") %pt-good) ((str=? name "B") %pt-bad) ((str=? name "X") (list 92 132 210)) ((str=? name "Y") %pt-warn) (#t %pt-dim))))
(def %pt-badge-w (fn (_ name pad?) (if pad? (int+ 4 (%pt-text-w name)) (%pt-text-w (Str8 append "[" name "]")))))
(def %pt-badge!
  (fn (_ c x y name pad? font)
    (if pad?
      (do (Canvas fill! c x (int- y 1) (%pt-badge-w name #t) (int+ %pt-pitch 1) (%pt-badge-ink name))
          (Canvas text! c (int+ x 2) y name %pt-hud-ground font))
      (Canvas text! c x y (Str8 append "[" name "]") %pt-bright font))
    (int+ x (%pt-badge-w name pad?))))

; A menu over game G's level, on painter P's screen: HEADING large, at
; the title's size when TITLE?; LINES, the CHOSEN one bright and
; marked; and along the foot each of PROMPTS, (NAME . WHAT), the
; button or key NAME and what it does, drawn as a pad's buttons when
; PAD?.  The screen.
(def paint-menu!
  (fn (_ p g heading title? lines chosen prompts pad?)
    (def s (paint-frame! p g 0))
    (def font (Vector ref 2 p))
    (Canvas nine! s 0 0 paint-width paint-height %pt-veil 1 1 1 1)
    ; The ground over the messages, the third line's too (%pt-top!).
    (Canvas fill! s 0 0 paint-width (int* %pt-scale (int+ %pt-top-h %pt-pitch)) %pt-hud-ground)
    (Canvas fill! s 0 %pt-stand-y paint-width (int- paint-height %pt-stand-y) %pt-hud-ground)
    (%pt-big! s font heading 72 (if title? 6 4) %pt-bright)
    (def row (int+ %pt-pitch 4))
    (def top (if title? 170 130))
    ; As many items as fit above the foot, the chosen one among them:
    ; a long list is shown a window at a time, a mark at an end that
    ; has more past it.
    (def room (int/ (int- (int- paint-height (int* %pt-scale (int+ %pt-pitch 8))) top) (int* %pt-scale row)))
    (def all (List length lines))
    (def from
      (if (int< room all)
        ((fn (_ f) (if (int< f 0) 0 (if (int< (int- all room) f) (int- all room) f))) (int- chosen (int/ room 2)))
        0))
    (def shown (List take room (List drop from lines)))
    (def n (List length shown))
    (def c (Canvas make %pt-strip-w (int* n row)))
    ; The items a column, its left edge where the widest is centred; the
    ; chosen one marked before it.
    (def widest (List fold (fn (_ w l) (if (int< w (%pt-text-w l)) (%pt-text-w l) w)) 0 lines))
    (def x0 (int/ (int- %pt-strip-w widest) 2))
    ((fn (self l i)
       (unless (null? l)
         (do (when (int= (int+ i from) chosen) (Canvas text! c (int- x0 (int* 2 %pt-advance)) (int+ 2 (int* i row)) ">" %pt-warn font))
             (Canvas text! c x0 (int+ 2 (int* i row)) (first l) (if (int= (int+ i from) chosen) %pt-bright %pt-dim) font)
             (self (rest l) (int+ i 1)))))
     shown 0)
    (when (int< 0 from) (Canvas text! c (int+ x0 (int+ widest %pt-advance)) 2 "^" %pt-dim font))
    (when (int< (int+ from n) all) (Canvas text! c (int+ x0 (int+ widest %pt-advance)) (int+ 2 (int* (int- n 1) row)) "v" %pt-dim font))
    (Canvas nine! s 0 top paint-width (int* %pt-scale (int* n row)) c 0 0 0 0)
    (def foot (Canvas make %pt-strip-w (int+ %pt-pitch 4)))
    (def width
      (List fold (fn (_ x pr) (int+ x (int+ (%pt-badge-w (first pr) pad?) (int+ %pt-advance (int+ (%pt-text-w (rest pr)) (int* 2 %pt-advance))))))
        0 prompts))
    (List fold
      (fn (_ x pr)
        (def after (int+ %pt-advance (%pt-badge! foot x 2 (first pr) pad? font)))
        (Canvas text! foot after 2 (rest pr) %pt-ink font)
        (int+ after (int+ (%pt-text-w (rest pr)) (int* 2 %pt-advance))))
      (int/ (int- %pt-strip-w width) 2) prompts)
    (%pt-show! s foot (int- paint-height (int* %pt-scale (int+ %pt-pitch 8))))
    s))

; Whether the last turn's scene has a light that flickers, a glint, a
; sleeper or a tile that moves: whether the frame changes with the tick.
(def paint-flickers?
  (fn (_ p)
    (List any? (fn (_ op) (match ((eq? (first op) (lit light)) (< 0 (List ref 7 op))) ((eq? (first op) (lit glint)) #t) ((eq? (first op) (lit sleep)) #t)
                                 ((eq? (first op) (lit tile))
                                   ((fn (_ props) (not (if (null? (%pt-find props (lit pictures))) (null? (%pt-find props (lit walking))) #f))) (rest (List ref 3 op))))
                                 (#t #f)))
      (%pt-over p))))

(provide roguelike/paint
  paint-width paint-height paint-art paint-arts paint-font paint-make paint-screen paint-turn! paint-view! paint-frame! paint-flickers?
  paint-zoom paint-zoom! paint-zoom-least paint-zoom-most paint-zoom-first paint-animating? paint-step! paint-level-y
  paint-menu!)
