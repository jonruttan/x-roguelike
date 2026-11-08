; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/pad.x -- the game played with a gamepad
;
; A gamepad's events from (Sdl poll) turned into the keys the game
; already takes.  The left stick and the d-pad move in eight
; directions, as the arrows and y u b n do, and repeat while held; the
; buttons are the commands a game is mostly played with:
;
;     A  pick up            B  stop asking (escape)
;     X  the pack           Y  explore
;     LB go up (<)          RB go down (>)
;     left stick click  rest (.)      right stick click  search (s)
;     Start  the keys (?)   Back  the map of the world (m)
;
; A command that asks for a thing -- quaff, read, wear -- is still a
; key on the keyboard.
;
; A direction moves once it has held for a moment, so a stick pushed to
; a diagonal crosses no straight direction on the way there, and again
; at a steady rate while it is held.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/pad)

(import x/type/vector)

; How far a stick goes before it points, and how far back before it
; stops: out of 32767, apart so a stick resting on the line does not
; flicker between the two.
(def %pd-on 16384)
(def %pd-off 8192)

; In milliseconds: a direction's wait before its first move, before
; its second, and between the rest.
(def %pd-settle 40)
(def %pd-first 260)
(def %pd-rate 120)

(def %pd-buttons
  (list (pair (lit south) ",") (pair (lit east) (lit escape))
        (pair (lit west) "i") (pair (lit north) "o")
        (pair (lit left-shoulder) "<") (pair (lit right-shoulder) ">")
        (pair (lit left-stick) ".") (pair (lit right-stick) "s")
        (pair (lit start) "?") (pair (lit back) "m")))

; The game's key for a step of DX across and DY down, each -1, 0 or 1.
(def %pd-dirs
  (list (pair (pair 0 -1) (lit up)) (pair (pair 0 1) (lit down))
        (pair (pair -1 0) (lit left)) (pair (pair 1 0) (lit right))
        (pair (pair -1 -1) "y") (pair (pair 1 -1) "u")
        (pair (pair -1 1) "b") (pair (pair 1 1) "n")))

(def %pd-dir
  (fn (_ dx dy)
    ((fn (_ hit) (if (null? hit) () (rest hit)))
     (List find (fn (_ e) (if (= (first (first e)) dx) (= (rest (first e)) dy) #f)) %pd-dirs))))

; A pad's state: [STICK-X STICK-Y DPAD HELD NEXT FIRST? FULLSCREEN?],
; the stick's two directions, the d-pad buttons down, the direction
; held, when it next moves, whether that is its first move, and whether
; the window is fullscreen.
(def pad-make (fn (_) (Vector of 0 0 () () 0 #t #f)))

(def pad-fullscreen? (fn (_ s) (Vector ref 6 s)))
(def pad-fullscreen! (fn (_ s on) (Vector set! 6 on s)))

; Whether event E came from a gamepad.
(def pad-event?
  (fn (_ e)
    (if (null? e) #f
      (if (List find (fn (_ k) (eq? k (first e))) (lit (pad-down pad-up pad-axis pad-added pad-removed))) #t #f))))

; A stick's direction for axis value V, where it pointed WAS.
(def %pd-axis
  (fn (_ v was)
    (match ((< %pd-on v) 1) ((< v (- 0 %pd-on)) -1)
           ((if (< v %pd-off) (< (- 0 %pd-off) v) #f) 0)
           (#t was))))

(def %pd-dpad-dir
  (fn (_ held)
    (def on? (fn (_ b) (if (List find (fn (_ h) (eq? h b)) held) 1 0)))
    (%pd-dir (- (on? (lit dpad-right)) (on? (lit dpad-left)))
             (- (on? (lit dpad-down)) (on? (lit dpad-up))))))

; The direction the pad points: the stick's, else the d-pad's.
(def %pd-pointing
  (fn (_ s)
    ((fn (_ stick) (if (null? stick) (%pd-dpad-dir (Vector ref 2 s)) stick))
     (%pd-dir (Vector ref 0 s) (Vector ref 1 s)))))

; Whether keys A and B are the same: nil, a name, or a letter.
(def %pd-same?
  (fn (_ a b)
    (match ((null? a) (null? b)) ((null? b) #f)
           ((str? a) (if (str? b) (str=? a b) #f))
           (#t (eq? a b)))))

; Event E taken into pad state S.
(def %pd-take!
  (fn (_ s e)
    (def what (if (null? e) () (first e)))
    ; (quit) and (close) have no second element.
    (def name (if (null? e) () (if (null? (rest e)) () (first (rest e)))))
    (match
      ((eq? what (lit pad-axis))
        (match ((eq? name (lit left-x)) (Vector set! 0 (%pd-axis (List ref 2 e) (Vector ref 0 s)) s))
               ((eq? name (lit left-y)) (Vector set! 1 (%pd-axis (List ref 2 e) (Vector ref 1 s)) s))
               (#t ())))
      ((eq? what (lit pad-down))
        (Vector set! 2 (pair name (List filter (fn (_ h) (not (eq? h name))) (Vector ref 2 s))) s))
      ((eq? what (lit pad-up))
        (Vector set! 2 (List filter (fn (_ h) (not (eq? h name))) (Vector ref 2 s)) s))
      (#t ()))))

; The game's key for event E -- nil when there is none -- from pad
; state S at NOW milliseconds, the state moved on.  E may be nil, or an
; event from anywhere: a held direction moves when its time comes
; whatever arrives.
(def pad-key
  (fn (_ s e now)
    (%pd-take! s e)
    (def button
      (if (if (null? e) #f (eq? (first e) (lit pad-down)))
        ((fn (_ hit) (if (null? hit) () (rest hit)))
         (List find (fn (_ b) (eq? (first b) (List ref 1 e))) %pd-buttons))
        ()))
    (def pointing (%pd-pointing s))
    (unless (%pd-same? pointing (Vector ref 3 s))
      (do (Vector set! 3 pointing s)
          (Vector set! 4 (+ now %pd-settle) s)
          (Vector set! 5 #t s)))
    (match
      ((not (null? button)) button)
      ((null? pointing) ())
      ((< now (Vector ref 4 s)) ())
      (#t (do (Vector set! 4 (+ now (if (Vector ref 5 s) %pd-first %pd-rate)) s)
              (Vector set! 5 #f s)
              pointing)))))

(provide roguelike/pad pad-make pad-key pad-event? pad-fullscreen? pad-fullscreen!)
