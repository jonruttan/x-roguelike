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

; A level of ROWS by COLS at DEPTH, by PARAMS: (rooms LO HI), (room-size
; WLO WHI HLO HHI), (lit PERCENT STEP), the percent a room is lit at
; depth 1 and what that gains a level.
(def dungeon-generate
  (fn (_ rng rows cols depth params)
    (def m (map-make rows cols))
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
    (map-set! m (first up) (rest up) tile-up)
    (map-set! m (first down) (rest down) tile-down)
    (map-up! m up)
    (map-down! m down)
    m))

; A random floor cell of a random room of M that FREE? allows, or nil
; after a hundred tries.
(def dungeon-spot
  (fn (self rng m free? tries)
    (if (= tries 0) ()
      ((fn (_ at)
         (if (if (= (map-tile m (first at) (rest at)) tile-floor) (free? (first at) (rest at)) #f) at
           (self rng m free? (- tries 1))))
       (%dg-spot rng (rng choice (map-rooms m)))))))

(provide roguelike/dungeon dungeon-generate dungeon-spot)
