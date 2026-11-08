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
(import x/core/doors str-make ptr-set! ptr-ref str->ptr int* int+ int< int/ obj-make obj-ref obj-set!)

; --- terrain -----------------------------------------------------------------

; A cell's byte is its terrain: what the cell is, never how it looks.
; Each kind has a name; the kind it is a sort of, or nil; whether a
; creature can stand on it; and whether it stops sight.  How a kind
; looks is a front-end's business: one with no look for a kind gives it
; the look of the kind it is a sort of (roguelike/draw, for the
; terminal).
(def tile-rock 0)
(def tile-floor 1)
(def tile-wall 2)
(def tile-door 3)
(def tile-passage 4)
(def tile-down 5)
(def tile-up 6)
(def tile-water 7)
(def tile-pillar 8)
(def tile-fall 9)
(def tile-dressed 10)
(def tile-hedge 11)
(def tile-gate 12)
(def tile-thicket 13)
(def tile-edge 14)
(def tile-bog 15)
(def tile-scar 16)

; (CODE NAME SORT-OF PASSABLE? OPAQUE?) for every kind.
(def map-terrain
  (list (list tile-rock (lit rock) () #f #t)
        (list tile-floor (lit floor) () #t #f)
        (list tile-wall (lit wall) () #f #t)
        (list tile-door (lit door) () #t #f)
        (list tile-passage (lit passage) () #t #f)
        (list tile-down (lit down) () #t #f)
        (list tile-up (lit up) () #t #f)
        ; Deep water: a pool, a river, a channel.  Seen across, not
        ; crossed.
        (list tile-water (lit water) () #f #f)
        ; Coal left standing to hold the roof, and a roof come down.
        (list tile-pillar (lit pillar) (lit wall) #f #t)
        (list tile-fall (lit fall) (lit wall) #f #t)
        ; Stone dressed and laid without mortar: the well-keepers' work.
        (list tile-dressed (lit dressed) (lit wall) #f #t)
        ; A field's hedge, and the gate in it.
        (list tile-hedge (lit hedge) (lit wall) #f #t)
        (list tile-gate (lit gate) (lit door) #t #f)
        ; Trees and scrub grown thick.
        (list tile-thicket (lit thicket) (lit wall) #f #t)
        ; A gritstone edge or a boulder off it.
        (list tile-edge (lit edge) (lit wall) #f #t)
        ; Wet ground that bears a foot.
        (list tile-bog (lit bog) (lit floor) #t #f)
        ; A limestone scar: a cliff of bare rock.
        (list tile-scar (lit scar) (lit wall) #f #t)))
(def map-kinds 17)

; Each kind's passable and opaque flags in a vector by code, read through
; the object doors: sight asks a cell thousands of times a turn.
(def %mp-flags
  (fn (_ k)
    (def v (Vector make map-kinds #f))
    (List for-each (fn (_ t) (Vector set! (first t) (List ref k t) v)) map-terrain)
    v))
(def %mp-passable (%mp-flags 3))
(def %mp-opaque (%mp-flags 4))

; A level is a vector: 0 rows, 1 columns, 2 the tiles, 3 the seen flags,
; 4 the visible flags, 5 the rooms, 6 the stairs down (R . C), 7 the
; stairs up, 8 the named places, (NAME R0 C0 R1 C1) each, walls and
; all.  Its slots are read through the object doors, not the class: a
; cell's flag is asked for thousands of times a turn.
(def %mp-get (fn (_ m k) (obj-ref m (int+ k 1))))
(def %mp-put! (fn (_ m k x) (obj-set! m (int+ k 1) x)))
(def map-rows (fn (_ m) (%mp-get m 0)))
(def map-cols (fn (_ m) (%mp-get m 1)))
(def map-rooms (fn (_ m) (%mp-get m 5)))
(def map-rooms! (fn (_ m rooms) (%mp-put! m 5 rooms)))
(def map-down (fn (_ m) (%mp-get m 6)))
(def map-down! (fn (_ m at) (%mp-put! m 6 at)))
(def map-up (fn (_ m) (%mp-get m 7)))
(def map-up! (fn (_ m at) (%mp-put! m 7 at)))
(def map-places (fn (_ m) (%mp-get m 8)))
(def map-places! (fn (_ m places) (%mp-put! m 8 places)))
; The named place R C lies in, (NAME R0 C0 R1 C1), or nil.
(def map-place-at
  (fn (_ m r c)
    (List find (fn (_ p) (if (< (List ref 1 p) (+ r 1)) (if (< r (+ (List ref 3 p) 1)) (if (< (List ref 2 p) (+ c 1)) (< c (+ (List ref 4 p) 1)) #f) #f) #f))
      (map-places m))))

(def %mp-zero!
  (fn (self p i n) (when (int< i n) (do (ptr-set! p i 0 1) (self p (int+ i 1) n)))))
(def %mp-buffer
  (fn (_ n) (def s (str-make n)) (%mp-zero! (str->ptr s) 0 n) s))

(def map-make
  (fn (_ rows cols)
    (def m (Vector make 9 ()))
    (%mp-put! m 0 rows)
    (%mp-put! m 1 cols)
    (Vector set! 2 (%mp-buffer (int* rows cols)) m)
    (Vector set! 3 (%mp-buffer (int* rows cols)) m)
    (Vector set! 4 (%mp-buffer (int* rows cols)) m)
    m))

(def %mp-off (fn (_ m r c) (int+ (int* r (%mp-get m 1)) c)))
(def map-in?
  (fn (_ m r c)
    (match ((int< r 0) #f) ((int< c 0) #f) ((int< r (map-rows m)) (int< c (map-cols m))) (#t #f))))

(def map-tile
  (fn (_ m r c) (if (map-in? m r c) (ptr-ref (str->ptr (%mp-get m 2)) (%mp-off m r c) 1) tile-rock)))
(def map-set!
  (fn (_ m r c t) (when (map-in? m r c) (ptr-set! (str->ptr (%mp-get m 2)) (%mp-off m r c) t 1))))

(def %mp-flag
  (fn (_ m k r c) (if (map-in? m r c) (= (ptr-ref (str->ptr (Vector ref k m)) (%mp-off m r c) 1) 1) #f)))
(def %mp-flag!
  (fn (_ m k r c v) (when (map-in? m r c) (ptr-set! (str->ptr (Vector ref k m)) (%mp-off m r c) v 1))))
(def map-seen? (fn (_ m r c) (%mp-flag m 3 r c)))
(def map-seen! (fn (_ m r c) (%mp-flag! m 3 r c 1)))
(def map-visible? (fn (_ m r c) (%mp-flag m 4 r c)))

; Whether a creature can stand on tile T.
(def map-passable? (fn (_ t) (obj-ref %mp-passable (int+ t 1))))
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
    (%mp-zero! (str->ptr (%mp-get m 4)) 0 (int* (map-rows m) (map-cols m)))
    (map-each! (- r 1) (- c 1) (+ r 1) (+ c 1) (fn (_ rr cc) (%mp-mark! m rr cc)))
    (def room (map-room-at m r c))
    (when (if (null? room) #f (room-lit? room))
      (map-each! (room-r0 room) (room-c0 room) (room-r1 room) (room-c1 room) (fn (_ rr cc) (%mp-mark! m rr cc))))))

; Whether tile T stops sight.
(def map-opaque? (fn (_ t) (obj-ref %mp-opaque (int+ t 1))))

; Every cell of M a creature can stand on that cannot be walked to from
; R0 C0, a step at a time across a side, made FILL.  The cells are
; walked by their offsets, the ones reached marked in a buffer of their
; own, so a level costs no list a cell.
(def map-fill-unreached!
  (fn (_ m r0 c0 fill)
    (def cols (map-cols m))
    (def n (int* (map-rows m) cols))
    (def t (str->ptr (%mp-get m 2)))
    (def seen-buf (%mp-buffer n))
    (def seen (str->ptr seen-buf))
    (def open? (fn (_ i) (if (= (ptr-ref seen i 1) 0) (obj-ref %mp-passable (int+ (ptr-ref t i 1) 1)) #f)))
    (def push (fn (_ i s) (if (open? i) (do (ptr-set! seen i 1 1) (pair i s)) s)))
    (def flood
      (fn (self s)
        (unless (null? s)
          (do (def i (first s))
              (def c (- i (int* (int/ i cols) cols)))
              (def s1 (if (int< i cols) (rest s) (push (- i cols) (rest s))))
              (def s2 (if (int< (int+ i cols) n) (push (int+ i cols) s1) s1))
              (def s3 (if (int< 0 c) (push (- i 1) s2) s2))
              (self (if (int< c (- cols 1)) (push (int+ i 1) s3) s3))))))
    (def start (%mp-off m r0 c0))
    (ptr-set! seen start 1 1)
    (flood (list start))
    ((fn (self i)
       (when (int< i n)
         (do (when (open? i) (ptr-set! t i fill 1))
             (self (int+ i 1)))))
     0)
    ()))

(def %mp-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %mp-max (fn (_ a b) (if (< a b) b a)))
; NUM/DEN to the nearest integer, halves away from zero.
(def %mp-round (fn (_ num den) (int/ (+ num (if (< num 0) (- 0 (int/ den 2)) (int/ den 2))) den)))
; Whether the cells strictly between R0 C0 and R1 C1 are all clear: a
; line stepped a cell at a time along its longer axis.
(def %mp-clear?
  (fn (_ m r0 c0 r1 c1)
    (def dr (- r1 r0))
    (def dc (- c1 c0))
    (def n (%mp-max (%mp-abs dr) (%mp-abs dc)))
    ((fn (self i)
       (match ((not (< i n)) #t)
              ((map-opaque? (map-tile m (+ r0 (%mp-round (* dr i) n)) (+ c0 (%mp-round (* dc i) n)))) #f)
              (#t (self (+ i 1)))))
     1)))

; The lines of sight within RADIUS on a map COLS wide: for each cell DR
; DC from the eye, (DR DC DELTA . OFFSETS), DELTA the cell's distance
; along the buffer and OFFSETS the cells strictly between, stepped as
; %mp-clear? steps them, each as its distance.  They depend on nothing
; else, so they are made once and kept against the last RADIUS and
; COLS asked for.
(def %mp-rays-made (Vector of () ()))
(def %mp-rays
  (fn (_ radius cols)
    (def key (Vector ref 0 %mp-rays-made))
    (if (if (null? key) #f (if (= (first key) radius) (= (rest key) cols) #f))
      (Vector ref 1 %mp-rays-made)
      (do (def span (List range (- 0 radius) (+ radius 1)))
          (def ray
            (fn (_ dr dc)
              (def n (%mp-max (%mp-abs dr) (%mp-abs dc)))
              (pair dr (pair dc (pair (+ (* dr cols) dc)
                (List map (fn (_ i) (+ (* (%mp-round (* dr i) n) cols) (%mp-round (* dc i) n)))
                  (if (< n 2) () (List range 1 n))))))))
          (def rays (List flat-map (fn (_ dr) (List map (fn (_ dc) (ray dr dc)) span)) span))
          (Vector set! 0 (pair radius cols) %mp-rays-made)
          (Vector set! 1 rays %mp-rays-made)
          rays))))
; Whether none of the cells at OFFSETS from BASE in tiles T is opaque.
(def %mp-ray-clear?
  (fn (self t base offs)
    (match ((null? offs) #t)
           ((obj-ref %mp-opaque (int+ (ptr-ref t (int+ base (first offs)) 1) 1)) #f)
           (#t (self t base (rest offs))))))

; What is in view from R C within RADIUS: every cell a clear line
; reaches, the walls at the edge of sight included.  Everything else
; leaves view.  The lines are %mp-rays', the same %mp-clear? walks.
(def map-light-radius!
  (fn (_ m r c radius)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def t (str->ptr (%mp-get m 2)))
    (def seen (str->ptr (%mp-get m 3)))
    (def vis (str->ptr (%mp-get m 4)))
    (def base (int+ (int* r cols) c))
    (%mp-zero! vis 0 (int* rows cols))
    ((fn (self l)
       (unless (null? l)
         (do (def ray (first l))
             (def rr (int+ r (first ray)))
             (def cc (int+ c (first (rest ray))))
             (def more (rest (rest ray)))
             (when (if (int< rr 0) #f (if (int< cc 0) #f (if (int< rr rows) (int< cc cols) #f)))
               (when (%mp-ray-clear? t base (rest more))
                 ((fn (_ i) (ptr-set! vis i 1 1) (ptr-set! seen i 1 1)) (int+ base (first more)))))
             (self (rest l)))))
     (%mp-rays radius cols))))

; --- drawing -----------------------------------------------------------------

; Row R's cells as glyph bytes into BUF: BYTES the glyph of each tile
; code, a blank for a cell not yet seen.  A walk of the buffers, no
; call a cell.  Answers whether any cell of the row has been seen.
(def map-row-glyphs!
  (fn (_ m r bytes buf)
    (def cols (map-cols m))
    (def t (str->ptr (%mp-get m 2)))
    (def seen (str->ptr (%mp-get m 3)))
    (def out (str->ptr buf))
    (def base (int* r cols))
    ((fn (self c any?)
       (if (int< c cols)
         (if (= (ptr-ref seen (int+ base c) 1) 1)
           (do (ptr-set! out c (obj-ref bytes (int+ (ptr-ref t (int+ base c) 1) 1)) 1) (self (int+ c 1) #t))
           (do (ptr-set! out c 32 1) (self (int+ c 1) any?)))
         any?))
     0 #f)))

; The first column from C on row R that is in view, or the column count.
(def map-visible-next
  (fn (_ m r c)
    (def cols (map-cols m))
    (def vis (str->ptr (%mp-get m 4)))
    (def base (int* r cols))
    ((fn (self c) (if (if (int< c cols) (not (= (ptr-ref vis (int+ base c) 1) 1)) #f) (self (int+ c 1)) c)) c)))

; The column after the run of cells in view from C on row R.
(def map-visible-run
  (fn (_ m r c)
    (def cols (map-cols m))
    (def vis (str->ptr (%mp-get m 4)))
    (def base (int* r cols))
    ((fn (self c) (if (if (int< c cols) (= (ptr-ref vis (int+ base c) 1) 1) #f) (self (int+ c 1)) c)) c)))

; A cell's look, for a front-end that gives some kinds a look of their
; own: -1 if not seen, else twice its kind's class in CLASSES, a vector
; by tile code, and one more if in view.
(def map-look
  (fn (_ m r c classes)
    (def i (int+ (int* r (map-cols m)) c))
    (if (= (ptr-ref (str->ptr (%mp-get m 3)) i 1) 1)
      (int+ (int* 2 (obj-ref classes (int+ (ptr-ref (str->ptr (%mp-get m 2)) i 1) 1)))
            (ptr-ref (str->ptr (%mp-get m 4)) i 1))
      -1)))

; The column after the run of cells from C on row R with C's look.
(def map-look-run
  (fn (_ m r c classes)
    (def cols (map-cols m))
    (def t (str->ptr (%mp-get m 2)))
    (def seen (str->ptr (%mp-get m 3)))
    (def vis (str->ptr (%mp-get m 4)))
    (def base (int* r cols))
    (def look
      (fn (_ i)
        (if (= (ptr-ref seen i 1) 1)
          (int+ (int* 2 (obj-ref classes (int+ (ptr-ref t i 1) 1))) (ptr-ref vis i 1))
          -1)))
    (def k (look (int+ base c)))
    ((fn (self c) (if (if (int< c cols) (= (look (int+ base c)) k) #f) (self (int+ c 1)) c)) (int+ c 1))))

; Every cell seen: a map scroll's doing.
(def map-reveal!
  (fn (_ m)
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c) (unless (= (map-tile m r c) tile-rock) (map-seen! m r c))))))

(provide roguelike/map
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  tile-water tile-pillar tile-fall tile-dressed tile-hedge tile-gate tile-thicket tile-edge tile-bog tile-scar
  map-terrain map-kinds map-look map-look-run
  map-make map-rows map-cols map-rooms map-rooms! map-down map-down! map-up map-up! map-places map-places! map-place-at
  map-in? map-tile map-set! map-seen? map-seen! map-visible? map-passable? map-walkable?
  room-r0 room-c0 room-r1 room-c1 room-lit? room-covers? room-inside? room-centre map-room-at
  map-each! map-opaque? map-light! map-light-radius! map-row-glyphs! map-visible-next map-visible-run
  map-reveal! map-fill-unreached!)
