; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/map.x -- a level's cells: tiles, what has been seen, what is lit
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A level is a grid of tiles, a byte a cell in one buffer, with two
; more buffers of flags: whether the cell has been seen, and whether it
; is in view now.  The rooms are kept as rectangles, (R0 C0 R1 C1 LIT),
; the walls included.  Lighting is by room: standing in a lit room, or in
; its doorway, shows the whole room; anywhere else shows the cells
; around.  What has been seen stays on the map, drawn as remembered.

(module roguelike/map)

(import x/type/vector)
(import x/core/doors str-make ptr-set! ptr-ref str->ptr int* int+ int< int/)

(def tile-rock 0)
(def tile-floor 1)
(def tile-wall 2)
(def tile-door 3)
(def tile-passage 4)
(def tile-down 5)
(def tile-up 6)

; A level is a vector: 0 rows, 1 columns, 2 the tiles, 3 the seen flags,
; 4 the visible flags, 5 the rooms, 6 the stairs down (R . C), 7 the
; stairs up.
(def map-rows (fn (_ m) (Vector ref 0 m)))
(def map-cols (fn (_ m) (Vector ref 1 m)))
(def map-rooms (fn (_ m) (Vector ref 5 m)))
(def map-rooms! (fn (_ m rooms) (Vector set! 5 rooms m)))
(def map-down (fn (_ m) (Vector ref 6 m)))
(def map-down! (fn (_ m at) (Vector set! 6 at m)))
(def map-up (fn (_ m) (Vector ref 7 m)))
(def map-up! (fn (_ m at) (Vector set! 7 at m)))

(def %mp-zero!
  (fn (self p i n) (when (int< i n) (do (ptr-set! p i 0 1) (self p (int+ i 1) n)))))
(def %mp-buffer
  (fn (_ n) (def s (str-make n)) (%mp-zero! (str->ptr s) 0 n) s))

(def map-make
  (fn (_ rows cols)
    (def m (Vector make 8 ()))
    (Vector set! 0 rows m)
    (Vector set! 1 cols m)
    (Vector set! 2 (%mp-buffer (int* rows cols)) m)
    (Vector set! 3 (%mp-buffer (int* rows cols)) m)
    (Vector set! 4 (%mp-buffer (int* rows cols)) m)
    m))

(def %mp-off (fn (_ m r c) (int+ (int* r (Vector ref 1 m)) c)))
(def map-in?
  (fn (_ m r c)
    (match ((int< r 0) #f) ((int< c 0) #f) ((int< r (map-rows m)) (int< c (map-cols m))) (#t #f))))

(def map-tile
  (fn (_ m r c) (if (map-in? m r c) (ptr-ref (str->ptr (Vector ref 2 m)) (%mp-off m r c) 1) tile-rock)))
(def map-set!
  (fn (_ m r c t) (when (map-in? m r c) (ptr-set! (str->ptr (Vector ref 2 m)) (%mp-off m r c) t 1))))

(def %mp-flag
  (fn (_ m k r c) (if (map-in? m r c) (= (ptr-ref (str->ptr (Vector ref k m)) (%mp-off m r c) 1) 1) #f)))
(def %mp-flag!
  (fn (_ m k r c v) (when (map-in? m r c) (ptr-set! (str->ptr (Vector ref k m)) (%mp-off m r c) v 1))))
(def map-seen? (fn (_ m r c) (%mp-flag m 3 r c)))
(def map-seen! (fn (_ m r c) (%mp-flag! m 3 r c 1)))
(def map-visible? (fn (_ m r c) (%mp-flag m 4 r c)))

; Whether a creature can stand on tile T.
(def map-passable? (fn (_ t) (match ((= t tile-rock) #f) ((= t tile-wall) #f) (#t #t))))
(def map-walkable? (fn (_ m r c) (map-passable? (map-tile m r c))))

; --- rooms -------------------------------------------------------------------

(def room-r0 (fn (_ room) (List ref 0 room)))
(def room-c0 (fn (_ room) (List ref 1 room)))
(def room-r1 (fn (_ room) (List ref 2 room)))
(def room-c1 (fn (_ room) (List ref 3 room)))
(def room-lit? (fn (_ room) (List ref 4 room)))
(def %mp-between? (fn (_ lo x hi) (if (< x lo) #f (not (< hi x)))))
; Whether R C is within ROOM, walls included.
(def room-covers?
  (fn (_ room r c)
    (if (%mp-between? (room-r0 room) r (room-r1 room)) (%mp-between? (room-c0 room) c (room-c1 room)) #f)))
; Whether R C is on ROOM's floor.
(def room-inside?
  (fn (_ room r c)
    (if (%mp-between? (+ (room-r0 room) 1) r (- (room-r1 room) 1))
      (%mp-between? (+ (room-c0 room) 1) c (- (room-c1 room) 1)) #f)))
(def room-centre
  (fn (_ room)
    (pair (+ (room-r0 room) (int/ (- (room-r1 room) (room-r0 room)) 2))
          (+ (room-c0 room) (int/ (- (room-c1 room) (room-c0 room)) 2)))))
; The room R C is in, walls and doorways included, or nil.
(def map-room-at (fn (_ m r c) (List find (fn (_ room) (room-covers? room r c)) (map-rooms m))))

; F called with each R C of the rectangle R0 C0 to R1 C1, inclusive.
(def %mp-cols! (fn (self c c1 r f) (unless (< c1 c) (do (f r c) (self (+ c 1) c1 r f)))))
(def %mp-rows! (fn (self r r1 c0 c1 f) (unless (< r1 r) (do (%mp-cols! c0 c1 r f) (self (+ r 1) r1 c0 c1 f)))))
(def map-each! (fn (_ r0 c0 r1 c1 f) (%mp-rows! r0 r1 c0 c1 f)))

; --- lighting ----------------------------------------------------------------

(def %mp-mark! (fn (_ m r c) (%mp-flag! m 4 r c 1) (%mp-flag! m 3 r c 1)))

; What is in view from R C: the cells around it, and the whole of a lit
; room it is in.  Everything else leaves view.
(def map-light!
  (fn (_ m r c)
    (%mp-zero! (str->ptr (Vector ref 4 m)) 0 (int* (map-rows m) (map-cols m)))
    (map-each! (- r 1) (- c 1) (+ r 1) (+ c 1) (fn (_ rr cc) (%mp-mark! m rr cc)))
    (def room (map-room-at m r c))
    (when (if (null? room) #f (room-lit? room))
      (map-each! (room-r0 room) (room-c0 room) (room-r1 room) (room-c1 room) (fn (_ rr cc) (%mp-mark! m rr cc))))))

; Every cell seen: a map scroll's doing.
(def map-reveal!
  (fn (_ m)
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c) (unless (= (map-tile m r c) tile-rock) (map-seen! m r c))))))

(provide roguelike/map
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  map-make map-rows map-cols map-rooms map-rooms! map-down map-down! map-up map-up!
  map-in? map-tile map-set! map-seen? map-seen! map-visible? map-passable? map-walkable?
  room-r0 room-c0 room-r1 room-c1 room-lit? room-covers? room-inside? room-centre map-room-at
  map-each! map-light! map-reveal!)
