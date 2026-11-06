; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/dungeon.x -- a level made: rooms, the passages between, stairs
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Rooms are dropped at random where they fit, a cell apart at least, as
; many as the set asks for or as many as will fit in the tries allowed.
; Sorted left to right, each is joined to the next by a passage with one
; bend, and some to the one after that, so every room can be reached and
; a few have two ways in.  A passage carved through a room's wall leaves
; a door.  The stairs down are in a room other than the one the stairs
; up are in, when there is one.  A room is lit by a chance that falls
; with depth.  A set may ask for caves or open ground instead, below.

(module roguelike/dungeon)

(import x/type/vector)
(import x/num/random)
(import x/core/doors int/ int+ int- int< int= int& int>> obj-ref obj-set!)
(import roguelike/map
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  map-make map-rows map-cols map-rooms map-rooms! map-down map-down! map-up!
  map-tile map-set! map-in? map-passable? room-r0 room-c0 room-r1 room-c1 room-centre map-each!)

; The set's parameters, (KEY . VALUES) alist, or DEFAULT's values.
(def %dg-p
  (fn (_ params key default)
    (def p (Assoc find key params))
    (if (null? p) default (rest p))))
(def %dg-roll (fn (_ rng lo hi) (+ lo (rng int (+ 1 (- hi lo))))))

; Whether rooms A and B touch or overlap, a cell's margin kept.
(def %dg-apart?
  (fn (_ a b)
    (match ((< (+ (room-r1 a) 1) (room-r0 b)) #t)
           ((< (+ (room-r1 b) 1) (room-r0 a)) #t)
           ((< (+ (room-c1 a) 1) (room-c0 b)) #t)
           ((< (+ (room-c1 b) 1) (room-c0 a)) #t)
           (#t #f))))
(def %dg-fits? (fn (_ room rooms) (List all? (fn (_ other) (%dg-apart? room other)) rooms)))

; A room at random within ROWS by COLS: SIZE is (WLO WHI HLO HHI), the
; floor's extent.
(def %dg-try
  (fn (_ rng rows cols size lit)
    (def w (%dg-roll rng (List ref 0 size) (List ref 1 size)))
    (def h (%dg-roll rng (List ref 2 size) (List ref 3 size)))
    (def r0 (%dg-roll rng 0 (- rows (+ h 3))))
    (def c0 (%dg-roll rng 0 (- cols (+ w 3))))
    (list r0 c0 (+ r0 (+ h 1)) (+ c0 (+ w 1)) lit)))

(def %dg-place
  (fn (self rng rows cols size lit? want tries rooms)
    (match
      ((= (List length rooms) want) rooms)
      ((= tries 0) rooms)
      (#t ((fn (_ room)
             (self rng rows cols size lit? want (- tries 1) (if (%dg-fits? room rooms) (pair room rooms) rooms)))
           (%dg-try rng rows cols size (lit?)))))))

; ROOMS by their left edge, an insertion sort.
(def %dg-insert
  (fn (self room l)
    (match ((null? l) (list room))
           ((< (room-c0 room) (room-c0 (first l))) (pair room l))
           (#t (pair (first l) (self room (rest l)))))))
(def %dg-sort (fn (self l acc) (if (null? l) acc (self (rest l) (%dg-insert (first l) acc)))))

; --- carving -----------------------------------------------------------------

(def %dg-carve-room!
  (fn (_ m room)
    (map-each! (room-r0 room) (room-c0 room) (room-r1 room) (room-c1 room)
      (fn (_ r c)
        (map-set! m r c
          (match ((= r (room-r0 room)) tile-wall) ((= r (room-r1 room)) tile-wall)
                 ((= c (room-c0 room)) tile-wall) ((= c (room-c1 room)) tile-wall)
                 (#t tile-floor)))))))

; A passage cell at R C: rock becomes passage, a wall becomes a door, and
; a room's floor or an earlier passage is left as it is.
(def %dg-carve!
  (fn (_ m r c)
    (def t (map-tile m r c))
    (match ((= t tile-rock) (map-set! m r c tile-passage))
           ((= t tile-wall) (map-set! m r c tile-door))
           (#t ()))))
(def %dg-step (fn (_ a b) (match ((< a b) 1) ((< b a) -1) (#t 0))))
(def %dg-hline!
  (fn (self m r c c1)
    (%dg-carve! m r c)
    (unless (= c c1) (self m r (+ c (%dg-step c c1)) c1))))
(def %dg-vline!
  (fn (self m r c r1)
    (%dg-carve! m r c)
    (unless (= r r1) (self m (+ r (%dg-step r r1)) c r1))))

; A passage from room A's centre to room B's, bending once, the way of
; the bend by a coin.
(def %dg-join!
  (fn (_ m rng a b)
    (def p (room-centre a))
    (def q (room-centre b))
    (if (rng bool)
      (do (%dg-hline! m (first p) (rest p) (rest q)) (%dg-vline! m (first p) (rest q) (first q)))
      (do (%dg-vline! m (first p) (rest p) (first q)) (%dg-hline! m (first q) (rest p) (rest q))))))

(def %dg-chain!
  (fn (self m rng rooms)
    (unless (null? (rest rooms))
      (do (%dg-join! m rng (first rooms) (List ref 1 rooms))
          (when (if (null? (rest (rest rooms))) #f (rng bool))
            (%dg-join! m rng (first rooms) (List ref 2 rooms)))
          (self m rng (rest rooms))))))

; A random floor cell of ROOM.
(def %dg-spot
  (fn (_ rng room)
    (pair (%dg-roll rng (+ (room-r0 room) 1) (- (room-r1 room) 1))
          (%dg-roll rng (+ (room-c0 room) 1) (- (room-c1 room) 1)))))

; A level of rooms: (rooms LO HI), (room-size WLO WHI HLO HHI), (lit
; PERCENT STEP), the percent a room is lit at depth 1 and what that gains
; a level.
(def %dg-rooms!
  (fn (_ rng m depth params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def want (%dg-roll rng (List ref 0 (%dg-p params (lit rooms) (list 6 9))) (List ref 1 (%dg-p params (lit rooms) (list 6 9)))))
    (def lit-pct (+ (List ref 0 (%dg-p params (lit lit) (list 95 -4)))
                    (* (- depth 1) (List ref 1 (%dg-p params (lit lit) (list 95 -4))))))
    (def rooms (%dg-sort (%dg-place rng rows cols (%dg-p params (lit room-size) (list 4 12 3 6))
                                    (fn (_) (< (rng int 100) lit-pct)) want 200 ())
                         ()))
    (List for-each (fn (_ room) (%dg-carve-room! m room)) rooms)
    (%dg-chain! m rng rooms)
    (map-rooms! m rooms)
    (def up (%dg-spot rng (first rooms)))
    (def down (%dg-spot rng (if (null? (rest rooms)) (first rooms) (List ref (%dg-roll rng 1 (- (List length rooms) 1)) rooms))))
    (%dg-stairs! m up down)))

(def %dg-stairs!
  (fn (_ m up down)
    (map-set! m (first up) (rest up) tile-up)
    (map-set! m (first down) (rest down) tile-down)
    (map-up! m up)
    (map-down! m down)
    m))

; --- caves -------------------------------------------------------------------

; A cave: walkers carve floor from the middle, each step a random way,
; now and then jumping to a cell already carved, until (cave-fill
; PERCENT) of the level is floor; then every rock cell beside floor is
; wall.  A cave has no rooms, so it is lit by sight, (view N).

(def %dg-inside?
  (fn (_ m r c)
    (match ((int< r 1) #f) ((int< c 1) #f) ((int< r (int- (map-rows m) 1)) (int< c (int- (map-cols m) 1))) (#t #f))))

; CELLS is a vector of the carved cells, (R . C), COUNT of them so far;
; a pick from it is one draw, where a pick from a list walks it twice.
(def %dg-cell (fn (_ cells i) (obj-ref cells (int+ i 1))))
(def %dg-pick (fn (_ rng cells count) (%dg-cell cells (rng int count))))

; A draw costs a fifth of a millisecond, so the walk spends one on
; fifteen steps: BITS holds what is left of a 30-bit draw, two bits a
; way, LEFT the ways still in it.  JUMP counts the steps to the next
; jump, drawn from 0 to 99 after each, one step in fifty on average.
; The walk stops once CELLS is full.
(def %dg-draw-span 1073741824)
(def %dg-walk!
  (fn (self rng m r c cells count want bits left jump)
    (match
      ((not (int< count want)) ())
      ((int= (map-tile m r c) tile-rock)
        (do (map-set! m r c tile-floor)
            (obj-set! cells (int+ count 1) (pair r c))
            (self rng m r c cells (int+ count 1) want bits left jump)))
      ((int= left 0) (self rng m r c cells count want (rng int %dg-draw-span) 15 jump))
      ((int= jump 0)
        (do (def at (%dg-pick rng cells count))
            (self rng m (first at) (rest at) cells count want bits left (rng int 100))))
      (#t
        (do (def way (int& bits 3))
            (def nr (match ((int= way 0) (int- r 1)) ((int= way 1) (int+ r 1)) (#t r)))
            (def nc (match ((int= way 2) (int- c 1)) ((int= way 3) (int+ c 1)) (#t c)))
            (if (%dg-inside? m nr nc)
              (self rng m nr nc cells count want (int>> bits 2) (int- left 1) (int- jump 1))
              (self rng m r c cells count want (int>> bits 2) (int- left 1) (int- jump 1))))))))

; Every rock cell beside a carved one is wall.
(def %dg-around
  (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))
(def %dg-wall-around!
  (fn (self m r c ds)
    (unless (null? ds)
      (do (def wr (int+ r (first (first ds))))
          (def wc (int+ c (rest (first ds))))
          (when (int= (map-tile m wr wc) tile-rock) (map-set! m wr wc tile-wall))
          (self m r c (rest ds))))))
(def %dg-wall-up!
  (fn (self m cells i)
    (when (int< 0 i)
      (do (def at (%dg-cell cells (int- i 1)))
          (%dg-wall-around! m (first at) (rest at) %dg-around)
          (self m cells (int- i 1))))))

(def %dg-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %dg-max (fn (_ a b) (if (< a b) b a)))
(def %dg-dist (fn (_ a b) (%dg-max (%dg-abs (- (first a) (first b))) (%dg-abs (- (rest a) (rest b))))))
; The farthest from FROM of TRIES cells drawn from the COUNT in CELLS.
(def %dg-farthest
  (fn (self rng cells count from tries best bestd)
    (if (= tries 0) best
      ((fn (_ at)
         (if (< bestd (%dg-dist at from)) (self rng cells count from (- tries 1) at (%dg-dist at from))
           (self rng cells count from (- tries 1) best bestd)))
       (%dg-pick rng cells count)))))

(def %dg-caves!
  (fn (_ rng m params)
    (def want (int/ (* (* (map-rows m) (map-cols m)) (first (%dg-p params (lit cave-fill) (list 40)))) 100))
    (def cells (Vector make want ()))
    (%dg-walk! rng m (int/ (map-rows m) 2) (int/ (map-cols m) 2) cells 0 want 0 0 (rng int 100))
    (%dg-wall-up! m cells want)
    (def up (%dg-pick rng cells want))
    (map-rooms! m ())
    (%dg-stairs! m up (%dg-farthest rng cells want up 40 up 0))))

; --- open ground -------------------------------------------------------------

; Open ground: every cell floor, then (clumps LO HI) clumps of wall,
; each a walk of (clump-size LO HI) steps from a cell within the
; border, so the outermost ring stays floor and every edge can be
; walked to from every other; a pocket of floor a clump closes is
; filled in.  No rooms and no stairs: a screen is left by its edges.

(def %dg-four (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))
(def %dg-clump!
  (fn (self rng m r c k)
    (when (< 0 k)
      (do (when (%dg-inside? m r c) (map-set! m r c tile-wall))
          (def d (rng choice %dg-four))
          (self rng m (+ r (first d)) (+ c (rest d)) (- k 1))))))

; Every floor cell that cannot be walked to from the corner made wall.
(def %dg-pockets!
  (fn (_ m)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def seen (Vector make (* rows cols) #f))
    (def at (fn (_ r c) (+ (* r cols) c)))
    (def step?
      (fn (_ r c)
        (match ((not (map-in? m r c)) #f)
               ((Vector ref (at r c) seen) #f)
               ((not (map-passable? (map-tile m r c))) #f)
               (#t (do (Vector set! (at r c) #t seen) #t)))))
    (def flood
      (fn (self stack)
        (unless (null? stack)
          (do (def r (first (first stack)))
              (def c (rest (first stack)))
              (def next (List filter (fn (_ p) (step? (first p) (rest p)))
                          (list (pair (- r 1) c) (pair (+ r 1) c) (pair r (- c 1)) (pair r (+ c 1)))))
              (self (List append next (rest stack)))))))
    (Vector set! (at 0 0) #t seen)
    (flood (list (pair 0 0)))
    (map-each! 0 0 (- rows 1) (- cols 1)
      (fn (_ r c) (when (if (= (map-tile m r c) tile-floor) (not (Vector ref (at r c) seen)) #f) (map-set! m r c tile-wall))))))

(def %dg-open!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (map-each! 0 0 (- rows 1) (- cols 1) (fn (_ r c) (map-set! m r c tile-floor)))
    (def clumps (%dg-p params (lit clumps) (list 6 12)))
    (def size (%dg-p params (lit clump-size) (list 8 24)))
    ((fn (self n)
       (when (< 0 n)
         (do (%dg-clump! rng m (%dg-roll rng 1 (- rows 2)) (%dg-roll rng 1 (- cols 2)) (%dg-roll rng (first size) (List ref 1 size)))
             (self (- n 1)))))
     (%dg-roll rng (first clumps) (List ref 1 clumps)))
    (%dg-pockets! m)
    (map-rooms! m ())
    m))

; A level of ROWS by COLS at DEPTH, by PARAMS: rooms, or caves with
; (level-style caves), or open ground with (level-style open).  With
; (stairs up) the stairs down are floor: a level with a way back and
; none on.
(def dungeon-generate
  (fn (_ rng rows cols depth params)
    (def m (map-make rows cols))
    (def style (first (%dg-p params (lit level-style) (list (lit rooms)))))
    (match ((eq? style (lit caves)) (%dg-caves! rng m params))
           ((eq? style (lit open)) (%dg-open! rng m params))
           (#t (%dg-rooms! rng m depth params)))
    (def down (map-down m))
    (when (if (null? down) #f (eq? (first (%dg-p params (lit stairs) (list (lit both)))) (lit up)))
      (do (map-set! m (first down) (rest down) tile-floor) (map-down! m ())))
    m))

; A random floor cell of M that FREE? allows -- of a random room, or
; anywhere on a level without rooms -- or nil after TRIES tries.
(def dungeon-spot
  (fn (self rng m free? tries)
    (if (= tries 0) ()
      ((fn (_ at)
         (if (if (= (map-tile m (first at) (rest at)) tile-floor) (free? (first at) (rest at)) #f) at
           (self rng m free? (- tries 1))))
       (if (null? (map-rooms m)) (pair (rng int (map-rows m)) (rng int (map-cols m)))
         (%dg-spot rng (rng choice (map-rooms m))))))))

(provide roguelike/dungeon dungeon-generate dungeon-spot)
