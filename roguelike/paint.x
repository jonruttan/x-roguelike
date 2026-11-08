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
(import x/core/doors int+ int* int/ int< int= str-make str->ptr ptr-ref ptr-set!)
(import roguelike/data data-load data-all)
(import roguelike/frame frame-tile-size frame-view-rows frame-view-cols frame-level-y
  frame-scene frame-light-map frame-named)
(import roguelike/draw draw-top draw-status draw-overlay)

(def paint-width 640)
(def paint-height 360)
(def %pt-level-w (* frame-view-cols frame-tile-size))
(def %pt-level-h (* frame-view-rows frame-tile-size))
(def %pt-black (list 0 0 0))
(def %pt-ink (list 206 198 184))

; The property KEY of PROPS, or nil.
(def %pt-find (fn (_ props key) (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) props)))
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

; ART-FORMS with each tile form's picture added; a tile drawn as
; another takes the first of that one's whole, unbanded pictures.
(def paint-art
  (fn (_ art-forms)
    (def colours (data-all art-forms (lit colour)))
    (def drawn
      (List map
        (fn (_ f)
          (def rows (if (%pt-tile? f) (%pt-prop f (lit rows)) ()))
          (if (null? rows) f
            ((fn (_ c) (List append f (list (list (lit picture) c (%pt-opaque? c)))))
             (Canvas rows (rest rows) colours))))
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
        (if (null? other) f (List append f (list (%pt-prop other (lit picture))))))
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

; Op OP drawn on canvas C, its Y moved up by DY: a tile copied when its
; picture is opaque and blended when not, a fill in black.  A tile with
; no picture draws nothing.  A tile op's form is (NAME . PROPS).
(def %pt-op!
  (fn (_ c op dy)
    (def head (first op))
    (match
      ((eq? head (lit tile))
        ((fn (_ pic)
           (unless (null? pic)
             (if (List ref 2 pic)
               (Canvas copy! c (List ref 1 op) (- (List ref 2 op) dy) (List ref 1 pic) 0 0 frame-tile-size frame-tile-size)
               (Canvas blend! c (List ref 1 op) (- (List ref 2 op) dy) (List ref 1 pic) 0 0 frame-tile-size frame-tile-size))))
         (%pt-find (rest (List ref 3 op)) (lit picture))))
      ((eq? head (lit fill))
        (Canvas fill! c (List ref 1 op) (- (List ref 2 op) dy) (List ref 3 op) (List ref 4 op) %pt-black))
      (#t ()))))

; A painter: [SCREEN LAYER FONT SCENE PANEL], the scene the last
; turn's and the panel the art's nine-piece picture (a tile form), or nil.
(def paint-make
  (fn (_ font)
    (Vector of (Canvas make paint-width paint-height) (Canvas make %pt-level-w %pt-level-h) font () ())))
(def paint-screen (fn (_ p) (Vector ref 0 p)))
(def %pt-over (fn (_ p) (rest (rest (Vector ref 3 p)))))

; The turn's scene of game G with art A taken, and its level drawn into
; the layer: once a turn, not a frame.
(def paint-turn!
  (fn (_ p g a)
    (def scene (frame-scene g a))
    (def layer (Vector ref 1 p))
    (Canvas fill! layer 0 0 %pt-level-w %pt-level-h %pt-black)
    (List for-each (fn (_ op) (%pt-op! layer op frame-level-y)) (first (rest scene)))
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
      (do (def shown (List take (int/ (- %pt-level-h 16) 9) lines))
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
; the layer, what stands on it, the light, the messages and the
; standing.  The screen.
(def paint-frame!
  (fn (_ p g tick)
    (def s (Vector ref 0 p))
    (def font (Vector ref 2 p))
    (def over (%pt-over p))
    (Canvas copy! s 0 frame-level-y (Vector ref 1 p) 0 0 %pt-level-w %pt-level-h)
    (List for-each (fn (_ op) (%pt-op! s op 0)) over)
    (Canvas light! s 0 frame-level-y %pt-level-w %pt-level-h
      (frame-light-map (List find (fn (_ op) (eq? (first op) (lit view))) over)
                       (List filter (fn (_ op) (eq? (first op) (lit light))) over) tick)
      frame-tile-size)
    (Canvas fill! s 0 0 paint-width frame-level-y %pt-black)
    (Canvas fill! s 0 (+ frame-level-y %pt-level-h) paint-width (- paint-height (+ frame-level-y %pt-level-h)) %pt-black)
    (def lines (%pt-lines (draw-top g)))
    (Canvas text! s 0 4 (first lines) %pt-ink font)
    (unless (null? (rest lines)) (Canvas text! s 0 13 (%pt-fit (first (rest lines))) %pt-ink font))
    (Canvas text! s 0 340 (%pt-fit (draw-status g)) %pt-ink font)
    (%pt-overlay! s (Vector ref 4 p) font (draw-overlay g))
    s))

; Whether the last turn's scene has a light that flickers: whether the
; frame changes with the tick.
(def paint-flickers?
  (fn (_ p)
    (List any? (fn (_ op) (if (eq? (first op) (lit light)) (< 0 (List ref 7 op)) #f)) (%pt-over p))))

(provide roguelike/paint
  paint-width paint-height paint-art paint-font paint-make paint-screen paint-turn! paint-frame! paint-flickers?)
