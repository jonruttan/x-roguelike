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
(import roguelike/state game-ask)
(import roguelike/frame frame-tile-size frame-view-rows frame-view-cols frame-view! frame-level-y
  frame-scene frame-light-map frame-named)
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
; The messages' strip, two lines, and the standing's, two lines, in
; strip pixels.
(def %pt-top-h 21)
(def %pt-stand-h 20)
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
; asked for.  A name no art draws is drawn with its letter.
(def paint-arts
  (fn (_ dir)
    (def made (Vector of ()))
    (fn (self place)
      (def hit (List find (fn (_ p) (str=? (first p) place)) (Vector ref 0 made)))
      (if (null? hit)
        ((fn (_ own)
           (def art (if (str=? place "") own (%pt-beside own (self ""))))
           (Vector set! 0 (pair (pair place art) (Vector ref 0 made)) made)
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
      ((null? mode) (%pt-cycle ps tick seed))
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
; thing's MODE (see %pt-pick), AGE the ticks since the turn was shown.
(def %pt-op!
  (fn (_ c op dy font tick age)
    (def head (first op))
    (def x (first (rest op)))
    (def y (int- (first (rest (rest op))) dy))
    (def more (rest (rest (rest op))))
    (match
      ((eq? head (lit tile))
        ((fn (_ pic)
           (unless (null? pic)
             ((if (first (rest (rest pic))) %pt-copy! %pt-blend!)
              Canvas c x y (first (rest pic)) 0 0 frame-tile-size frame-tile-size)))
         (%pt-pick (rest (first more)) x (first (rest (rest op))) tick (if (null? (rest more)) () (first (rest more))) age)))
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

; --- blows ---------------------------------------------------------------------

; A turn's blows, (blow FX FY TX TY HOW N BY-PLAYER?) ops (frame.x),
; shown over %pt-blow-frames frames after the turn: the striker lunges
; toward its target, a blow that lands flashes the target white (the
; player's) or red (a creature's), the player's kill bursts where the
; creature was, and the damage, or "miss", rises from the target.  Each
; a frame's step, by frame K.
(def %pt-blow-frames 8)
(def %pt-lunge-by (Vector of 2 4 5 3 1 0 0 0))
(def %pt-flash-by (Vector of 230 190 140 90 40 0 0 0))
(def %pt-burst-by (Vector of 1 2 4 5 6 5 3 0))
(def %pt-stamp! (method-of Canvas (lit stamp!)))
(def %pt-sign (fn (_ n) (if (int< n 0) -1 (if (int< 0 n) 1 0))))
(def %pt-blow-ops (fn (self ops) (match ((null? ops) ()) ((eq? (first (first ops)) (lit blow)) (pair (first ops) (self (rest ops)))) (#t (self (rest ops))))))

; OPS with each tile and glyph standing where a blow of BLOWS was struck
; from moved toward its target by frame K's lunge.
(def %pt-lunge
  (fn (_ ops blows k)
    (def by (Vector ref k %pt-lunge-by))
    (def step
      (fn (self op bs)
        (if (null? bs) op
          (do (def b (first bs))
              (def fx (first (rest b)))
              (def fy (first (rest (rest b))))
              (if (if (int= fx (first (rest op))) (int= fy (first (rest (rest op)))) #f)
                (pair (first op)
                  (pair (int+ fx (int* by (%pt-sign (int- (List ref 3 b) fx))))
                    (pair (int+ fy (int* by (%pt-sign (int- (List ref 4 b) fy)))) (rest (rest (rest op))))))
                (self op (rest bs)))))))
    (List map (fn (_ op) (if (match ((eq? (first op) (lit tile)) #t) ((eq? (first op) (lit glyph)) #t) (#t #f)) (step op blows) op)) ops)))

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

(def %pt-hurt-ink (list 255 90 70))
(def %pt-dealt-ink (list 255 224 110))
(def %pt-miss-ink (list 180 180 180))
(def %pt-shade-ink (list 0 0 0))

; BLOWS drawn on C at frame K over OPS, the frame's, their Y moved up
; by DY, in FONT.
(def %pt-blows!
  (fn (self c ops blows k dy font)
    (unless (null? blows)
      (do (def b (first blows))
          (def tx (List ref 3 b))
          (def ty (List ref 4 b))
          (def how (List ref 5 b))
          (def mine (List ref 7 b))
          (def y (int- ty dy))
          (unless (eq? how (lit miss))
            ((fn (_ pic)
               (if (if (null? pic) #t (if mine (eq? how (lit kill)) #f))
                 (%pt-star! c (int+ tx 8) (int+ y 8) (Vector ref k %pt-burst-by) (if mine %pt-dealt-ink %pt-hurt-ink))
                 (%pt-stamp! Canvas c tx y (first (rest pic)) 0 0 frame-tile-size frame-tile-size
                   ((fn (_ a) (if mine (list 255 255 255 a) (list 255 70 50 a))) (Vector ref k %pt-flash-by)))))
             (%pt-top-picture ops tx ty ())))
          (def s (if (eq? how (lit miss)) "miss" (Str8 str (List ref 6 b))))
          (def x (int- (int+ tx 8) (int* 4 (Str8 length s))))
          (def ny (int- y (int+ 2 (int* 2 k))))
          (%pt-text! Canvas c (int+ x 1) (int+ ny 1) s %pt-shade-ink font)
          (%pt-text! Canvas c x ny s (match ((eq? how (lit miss)) %pt-miss-ink) (mine %pt-dealt-ink) (#t %pt-hurt-ink)) font)
          (self c ops (rest blows) k dy font)))))

; Whether painter P has a turn's blows still to show.
(def paint-animating?
  (fn (_ p) (if (int< (Vector ref 9 p) %pt-blow-frames) (not (null? (%pt-blow-ops (%pt-over p)))) #f)))
; Painter P a frame on in showing the blows.
(def paint-step! (fn (_ p) (do (Vector set! 9 (int+ 1 (Vector ref 9 p)) p) p)))

; A painter: [SCREEN LAYER FONT SCENE PANEL WORK ZOOM WHERE SHOWN BLOW
; TOP STANDING], the scene the last turn's, the panel the art's
; nine-piece picture (a tile form) or nil, WORK the level drawn and lit
; at the tile's size before it is shown at ZOOM, LAYER and WORK the
; view's size; WHERE each walking thing's (WHO R . C) on the last turn,
; SHOWN the tick that turn was first shown at, or -1 before it is; BLOW
; the frame the turn's blows are shown at; TOP and STANDING the strips
; the messages and the standing are drawn on, TOP a pair: two lines and
; three.
(def paint-make
  (fn (_ font)
    (paint-zoom! (Vector of (Canvas make paint-width paint-height) () font () () () 0 () -1 %pt-blow-frames
                            (pair (Canvas make %pt-strip-w %pt-top-h) (Canvas make %pt-strip-w (int+ %pt-top-h %pt-pitch)))
                            (Canvas make %pt-strip-w %pt-stand-h))
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
; made (tile X Y PICTURE MODE): moving when WAS, the (WHO R . C) of the
; turn before, has WHO elsewhere, still otherwise.
(def %pt-modes
  (fn (_ ops was)
    (List map
      (fn (_ op)
        (if (if (eq? (first op) (lit tile)) (null? (rest (rest (rest (rest op))))) #t) op
          ((fn (_ at)
             (def before (List find (fn (_ w) (same? (first w) (first at))) was))
             (def moved (if (null? before) #f (not (if (= (first (rest before)) (first (rest at))) (= (rest (rest before)) (rest (rest at))) #f))))
             (list (lit tile) (first (rest op)) (first (rest (rest op))) (List ref 3 op) (if moved (lit moving) (lit still))))
           (List ref 4 op))))
      ops)))
; The (WHO R . C) of each walking thing's tile op of OPS.
(def %pt-where
  (fn (_ ops)
    (List map (fn (_ op) (List ref 4 op))
      (List filter (fn (_ op) (if (eq? (first op) (lit tile)) (not (null? (rest (rest (rest (rest op)))))) #f)) ops))))

; The turn's scene of game G with art A taken, and its level drawn into
; the layer: once a turn, not a frame.  Each walking thing is marked
; moving or still against where it stood on the turn before.
(def paint-turn!
  (fn (_ p g a)
    (def scene (frame-scene g a))
    (def over (rest (rest scene)))
    (def layer (Vector ref 1 p))
    (Canvas fill! layer 0 0 (%pt-level-w) (%pt-level-h) %pt-black)
    (%pt-ops! layer (first (rest scene)) frame-level-y (Vector ref 2 p) 0 0)
    (Vector set! 3 (pair (first scene) (pair (first (rest scene)) (%pt-modes over (Vector ref 7 p)))) p)
    (Vector set! 7 (%pt-where over) p)
    (Vector set! 8 -1 p)
    (Vector set! 4 (frame-named a (lit panel) 0) p)
    (Vector set! 9 0 p)
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
; top when the text needs them.  STRIPS is (TWO . THREE).
(def %pt-top!
  (fn (_ s strips font text asking?)
    (def lines (List take 3 (%pt-lines text %pt-cols)))
    (def strip (if (int< 2 (List length lines)) (rest strips) (first strips)))
    (def h (List ref 1 strip))
    (def colour (if asking? %pt-bright %pt-ink))
    (Canvas fill! strip 0 0 %pt-strip-w h %pt-hud-ground)
    (Canvas fill! strip 0 (int- h 1) %pt-strip-w 1 %pt-hud-rule)
    ((fn (self l y) (unless (null? l) (do (Canvas text! strip %pt-margin y (first l) colour font) (self (rest l) (int+ y %pt-pitch)))))
     lines 2)
    (%pt-show! s strip 0)))

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
; hit points as a bar, strength, armour, the level, and any hunger or
; condition on the second.  A spent strength is a warning.
(def %pt-bar-w 48)
(def %pt-standing!
  (fn (_ s strip font st)
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
    (%pt-show! s strip %pt-stand-y)))

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
    (def blows (if (int< k %pt-blow-frames) (%pt-blow-ops (%pt-over p)) ()))
    (def over (if (null? blows) (%pt-over p) (%pt-lunge (%pt-over p) blows k)))
    (def work (Vector ref 5 p))
    (def lw (first work))
    (def lh (first (rest work)))
    (def zoom (Vector ref 6 p))
    (Canvas copy! work 0 0 (Vector ref 1 p) 0 0 lw lh)
    (def cam (first (Vector ref 3 p)))
    (when (int< (Vector ref 8 p) 0) (Vector set! 8 tick p))
    (%pt-ops! work over frame-level-y font (int+ tick (int+ (int* (rest cam) 7) (int* (first cam) 13))) (int- tick (Vector ref 8 p)))
    (Canvas light! work 0 0 lw lh
      (frame-light-map (List find (fn (_ op) (eq? (first op) (lit view))) over)
                       (List filter (fn (_ op) (eq? (first op) (lit light))) over) tick)
      frame-tile-size)
    (%pt-glints! work over frame-level-y tick)
    (%pt-blows! work over blows k frame-level-y font)
    (Canvas nine! s 0 paint-level-y (int* zoom lw) (int* zoom lh) work 0 0 0 0)
    (%pt-top! s (Vector ref 10 p) font (draw-top g) (not (null? (game-ask g))))
    (%pt-standing! s (Vector ref 11 p) font (draw-standing g))
    (%pt-overlay! s (Vector ref 4 p) font (draw-overlay g))
    s))

; Whether the last turn's scene has a light that flickers, a glint or a
; tile that moves: whether the frame changes with the tick.
(def paint-flickers?
  (fn (_ p)
    (List any? (fn (_ op) (match ((eq? (first op) (lit light)) (< 0 (List ref 7 op))) ((eq? (first op) (lit glint)) #t)
                                 ((eq? (first op) (lit tile))
                                   ((fn (_ props) (not (if (null? (%pt-find props (lit pictures))) (null? (%pt-find props (lit walking))) #f))) (rest (List ref 3 op))))
                                 (#t #f)))
      (%pt-over p))))

(provide roguelike/paint
  paint-width paint-height paint-art paint-arts paint-font paint-make paint-screen paint-turn! paint-frame! paint-flickers?
  paint-zoom paint-zoom! paint-zoom-least paint-zoom-most paint-zoom-first paint-animating? paint-step! paint-level-y)
