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
(import roguelike/frame frame-tile-size frame-view-rows frame-view-cols frame-level-y
  frame-scene frame-light-map frame-named)
(import roguelike/draw draw-top draw-status draw-overlay)

(def paint-width 640)
(def paint-height 360)
(def %pt-level-w (* frame-view-cols frame-tile-size))
(def %pt-level-h (* frame-view-rows frame-tile-size))
; The level is drawn at the tile's size and shown twice that.
(def %pt-zoom 2)
(def %pt-shown-w (* %pt-zoom %pt-level-w))
(def %pt-shown-h (* %pt-zoom %pt-level-h))
(def %pt-status-y (+ frame-level-y (+ %pt-shown-h 3)))
(def %pt-black (list 0 0 0))
(def %pt-ink (list 206 198 184))
(def %pt-glyph (list 236 228 204))

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

; ART-FORMS with each tile form's picture added, and for a tile that
; moves, (pictures TICKS PICTURE ...): its own rows' then each of its
; (frames TICKS (rows ...) ...), each held TICKS ticks.  A tile drawn as
; another takes the first of that one's whole, unbanded pictures.
(def paint-art
  (fn (_ art-forms)
    (def colours (data-all art-forms (lit colour)))
    (def drawn
      (List map
        (fn (_ f)
          (def rows (if (%pt-tile? f) (%pt-prop f (lit rows)) ()))
          (def frames (if (null? rows) () (%pt-prop f (lit frames))))
          (if (null? rows) f
            ((fn (_ pic)
               (List append f (list pic)
                 (if (null? frames) ()
                   (list (pair (lit pictures) (pair (first (rest frames))
                     (pair pic (List map (fn (_ r) (%pt-picture r colours)) (rest (rest frames))))))))))
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

; A one-letter string of the character with code N.
(def %pt-letter
  (fn (_ n)
    (def s (str-make 2))
    (ptr-set! (str->ptr s) 0 n 1)
    (ptr-set! (str->ptr s) 1 0 1)
    s))

; The font of the art at DIR, (letter CODE (rows ...)) each, for text!.
(def paint-font
  (fn (_ dir)
    (Canvas font
      (List map (fn (_ l) (list (%pt-letter (first l)) (rest (first (rest l)))))
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
; picture, or of its pictures the one the tick has come to, each cell
; out of step with the rest by its place.
(def %pt-pick
  (fn (_ props x y tick)
    (def ps (%pt-find props (lit pictures)))
    (if (null? ps) (%pt-find props (lit picture))
      (do (def ticks (first (rest ps)))
          (def all (rest (rest ps)))
          (def seed (int+ (int* (int/ x frame-tile-size) 7) (int* (int/ y frame-tile-size) 13)))
          (%pt-nth (int% (int/ (int+ tick seed) ticks) (%pt-length all 0)) all)))))
(def %pt-length (fn (self l n) (if (null? l) n (self (rest l) (int+ n 1)))))
; Op OP drawn on canvas C at TICK, its Y moved up by DY: a tile copied
; when its picture is opaque and blended when not, a fill in black, a
; glyph in the font in the middle of its cell.  A tile with no picture
; draws nothing.  A tile op's form is (NAME . PROPS).
(def %pt-op!
  (fn (_ c op dy font tick)
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
         (%pt-pick (rest (first more)) x (first (rest (rest op))) tick)))
      ((eq? head (lit fill)) (%pt-fill! Canvas c x y (first more) (first (rest more)) %pt-black))
      ((eq? head (lit glyph)) (%pt-text! Canvas c (int+ x 4) (int+ y 4) (first more) %pt-glyph font))
      (#t ()))))
; Each op of OPS drawn on C as %pt-op! draws it.
(def %pt-ops!
  (fn (self c ops dy font tick)
    (unless (null? ops) (do (%pt-op! c (first ops) dy font tick) (self c (rest ops) dy font tick)))))

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

; A painter: [SCREEN LAYER FONT SCENE PANEL WORK], the scene the last
; turn's, the panel the art's nine-piece picture (a tile form) or nil,
; and WORK the level drawn and lit at the tile's size before it is
; shown at the zoom.
(def paint-make
  (fn (_ font)
    (Vector of (Canvas make paint-width paint-height) (Canvas make %pt-level-w %pt-level-h) font () ()
               (Canvas make %pt-level-w %pt-level-h))))
(def paint-screen (fn (_ p) (Vector ref 0 p)))
(def %pt-over (fn (_ p) (rest (rest (Vector ref 3 p)))))

; The turn's scene of game G with art A taken, and its level drawn into
; the layer: once a turn, not a frame.
(def paint-turn!
  (fn (_ p g a)
    (def scene (frame-scene g a))
    (def layer (Vector ref 1 p))
    (Canvas fill! layer 0 0 %pt-level-w %pt-level-h %pt-black)
    (%pt-ops! layer (first (rest scene)) frame-level-y (Vector ref 2 p) 0)
    (Vector set! 3 scene p)
    (Vector set! 4 (frame-named a (lit panel) 0) p)
    p))

; TEXT in lines of at most eighty letters, broken at a space.
(def %pt-break
  (fn (self text i)
    (match ((< i 1) 80) ((str=? (Str8 sub i 1 text) " ") i) (#t (self text (- i 1))))))
(def %pt-lines
  (fn (self text)
    (if (< (Str8 length text) 81) (list text)
      ((fn (_ at) (pair (Str8 sub 0 at text) (self (Str8 sub (+ at 1) (- (Str8 length text) (+ at 1)) text))))
       (%pt-break text 80)))))
(def %pt-fit (fn (_ s) (if (< 80 (Str8 length s)) (Str8 sub 0 80 s) s)))

; LINES laid over the level on a panel at its top left: the art's
; nine-piece PANEL (a tile form) stretched round them, or a dark box
; where the set has none.  Nothing for no lines.
(def %pt-panel-dark (list 20 18 16 235))
(def %pt-overlay!
  (fn (_ s panel font lines)
    (unless (null? lines)
      (do (def shown (List take (int/ (- %pt-shown-h 16) 9) lines))
          (def w (+ 16 (* 8 (List fold (fn (_ n l) (if (< n (Str8 length l)) (Str8 length l) n)) 0 shown))))
          (def w2 (if (< paint-width w) paint-width w))
          (def h (+ 16 (* 9 (List length shown))))
          (def x 0)
          (def y frame-level-y)
          (def pic (if (null? panel) () (%pt-find (rest panel) (lit picture))))
          (def cut (if (null? panel) () (%pt-find (rest panel) (lit cut))))
          (if (if (null? pic) #t (null? cut))
            (Canvas blend! s x y (Canvas fill! (Canvas make w2 h) 0 0 w2 h %pt-panel-dark) 0 0 w2 h)
            (Canvas nine! s x y w2 h (List ref 1 pic) (List ref 1 cut) (List ref 2 cut) (List ref 3 cut) (List ref 4 cut)))
          ((fn (self l ly) (unless (null? l) (do (Canvas text! s (+ x 8) ly (%pt-fit (first l)) %pt-ink font) (self (rest l) (+ ly 9)))))
           shown (+ y 8))))))

; Frame TICK of game G drawn on the screen from the last turn's scene:
; the layer, what stands on it, the light and the glints, worked at the
; tile's size and shown at the zoom; then the messages and the
; standing.  The screen.
(def paint-frame!
  (fn (_ p g tick)
    (def s (Vector ref 0 p))
    (def font (Vector ref 2 p))
    (def over (%pt-over p))
    (def work (Vector ref 5 p))
    (Canvas copy! work 0 0 (Vector ref 1 p) 0 0 %pt-level-w %pt-level-h)
    (%pt-ops! work over frame-level-y font tick)
    (Canvas light! work 0 0 %pt-level-w %pt-level-h
      (frame-light-map (List find (fn (_ op) (eq? (first op) (lit view))) over)
                       (List filter (fn (_ op) (eq? (first op) (lit light))) over) tick)
      frame-tile-size)
    (%pt-glints! work over frame-level-y tick)
    (Canvas nine! s 0 frame-level-y %pt-shown-w %pt-shown-h work 0 0 0 0)
    (Canvas fill! s 0 0 paint-width frame-level-y %pt-black)
    (Canvas fill! s 0 (+ frame-level-y %pt-shown-h) paint-width (- paint-height (+ frame-level-y %pt-shown-h)) %pt-black)
    (def lines (%pt-lines (draw-top g)))
    (Canvas text! s 0 4 (first lines) %pt-ink font)
    (unless (null? (rest lines)) (Canvas text! s 0 13 (%pt-fit (first (rest lines))) %pt-ink font))
    (Canvas text! s 0 %pt-status-y (%pt-fit (draw-status g)) %pt-ink font)
    (%pt-overlay! s (Vector ref 4 p) font (draw-overlay g))
    s))

; Whether the last turn's scene has a light that flickers, a glint or a
; tile that moves: whether the frame changes with the tick.
(def paint-flickers?
  (fn (_ p)
    (List any? (fn (_ op) (match ((eq? (first op) (lit light)) (< 0 (List ref 7 op))) ((eq? (first op) (lit glint)) #t)
                                 ((eq? (first op) (lit tile)) (not (null? (%pt-find (rest (List ref 3 op)) (lit pictures)))))
                                 (#t #f)))
      (%pt-over p))))

(provide roguelike/paint
  paint-width paint-height paint-art paint-font paint-make paint-screen paint-turn! paint-frame! paint-flickers?)
