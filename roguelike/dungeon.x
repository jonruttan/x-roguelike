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
; with depth.

(module roguelike/dungeon)

(import x/type/vector)
(import x/num/random)
(import x/core/doors int/)
(import roguelike/map
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  map-make map-rows map-cols map-rooms map-rooms! map-down! map-up!
  map-tile map-set! room-r0 room-c0 room-r1 room-c1 room-centre map-each!)

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
    (match ((< r 1) #f) ((< c 1) #f) ((< r (- (map-rows m) 1)) (< c (- (map-cols m) 1))) (#t #f))))
(def %dg-steps (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))
; CELLS holds (COUNT . CARVED) in its one slot.
(def %dg-carve-floor!
  (fn (_ m r c cells)
    (when (= (map-tile m r c) tile-rock)
      (do (map-set! m r c tile-floor)
          (Vector set! 0 (pair (+ 1 (first (Vector ref 0 cells))) (pair (pair r c) (rest (Vector ref 0 cells)))) cells)))))
(def %dg-walk!
  (fn (self rng m r c cells want)
    (when (< (first (Vector ref 0 cells)) want)
      (do (%dg-carve-floor! m r c cells)
          (def from (if (< (rng int 100) 2) (rng choice (rest (Vector ref 0 cells))) (pair r c)))
          (def d (rng choice %dg-steps))
          (def nr (+ (first from) (first d)))
          (def nc (+ (rest from) (rest d)))
          (if (%dg-inside? m nr nc) (self rng m nr nc cells want) (self rng m (first from) (rest from) cells want))))))

(def %dg-around
  (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))
(def %dg-beside-floor?
  (fn (_ m r c)
    (List any? (fn (_ d) (= (map-tile m (+ r (first d)) (+ c (rest d))) tile-floor)) %dg-around)))
(def %dg-wall-up!
  (fn (_ m)
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c)
        (when (if (= (map-tile m r c) tile-rock) (%dg-beside-floor? m r c) #f) (map-set! m r c tile-wall))))))

(def %dg-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %dg-max (fn (_ a b) (if (< a b) b a)))
(def %dg-dist (fn (_ a b) (%dg-max (%dg-abs (- (first a) (first b))) (%dg-abs (- (rest a) (rest b))))))
; The farthest from FROM of TRIES cells drawn from CARVED.
(def %dg-farthest
  (fn (self rng carved from tries best bestd)
    (if (= tries 0) best
      ((fn (_ at)
         (if (< bestd (%dg-dist at from)) (self rng carved from (- tries 1) at (%dg-dist at from))
           (self rng carved from (- tries 1) best bestd)))
       (rng choice carved)))))

(def %dg-caves!
  (fn (_ rng m params)
    (def cells (Vector of (pair 0 ())))
    (def want (int/ (* (* (map-rows m) (map-cols m)) (first (%dg-p params (lit cave-fill) (list 40)))) 100))
    (%dg-walk! rng m (int/ (map-rows m) 2) (int/ (map-cols m) 2) cells want)
    (%dg-wall-up! m)
    (def carved (rest (Vector ref 0 cells)))
    (def up (rng choice carved))
    (map-rooms! m ())
    (%dg-stairs! m up (%dg-farthest rng carved up 40 up 0))))

; A level of ROWS by COLS at DEPTH, by PARAMS: rooms, or caves with
; (level-style caves).
(def dungeon-generate
  (fn (_ rng rows cols depth params)
    (def m (map-make rows cols))
    (if (eq? (first (%dg-p params (lit level-style) (list (lit rooms)))) (lit caves))
      (%dg-caves! rng m params)
      (%dg-rooms! rng m depth params))))

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
