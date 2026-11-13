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
;     Start  the pause menu    Back  the actions (actions)
;
; Back opens the window's menu of every other command -- search, quaff,
; read, wear, the map of the world -- and a question that wants a
; letter, an item or a choice, is a menu of its answers (window.x).
; The right stick moves the view, a cell at a time while held, as (look
; DX DY): the window's, not the game's.
;
; X, Y, the shoulders, the triggers and the stick clicks are the
; player's to bind to other commands in the options (pad-buttons!);
; the triggers, LT and RT, do nothing until they are bound.
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
; Between the view's moves while the right stick holds it.
(def %pd-look 90)

; S with spaces after it to WIDE.
(def %pd-pad (fn (self s wide) (if (< (Str8 length s) wide) (self (Str8 append s " ") wide) s)))
; A button's NAME and what it does, TEXT, as a help line's half.
(def %pd-half
  (fn (_ name text)
    (Str8 append (%pd-pad name (if (< (Str8 length name) 7) 7 (+ (Str8 length name) 4))) text)))
; HALVES two to a line while they fit in 78 columns.
(def %pd-lines
  (fn (self halves)
    (match ((null? halves) ())
           ((null? (rest halves)) halves)
           (#t ((fn (_ both)
                  (if (< (Str8 length both) 79)
                    (pair both (self (rest (rest halves))))
                    (pair (first halves) (self (rest halves)))))
                (Str8 append (%pd-pad (first halves) 33) (first (rest halves))))))))

; What each of the gamepad's buttons does, as the game's help shows
; the keys: the lines of the help the window shows in place of the keys
; when the gamepad was used last.  SAID is the bindable buttons' (NAME .
; TEXT), each as the player has it bound, a button bound to nothing left
; out.
(def pad-help
  (fn (_ said)
    (List append
      (list "Left stick, d-pad   move, in eight directions; held, keep moving"
            "Right stick         move the view off you; any move brings it back"
            "A      pick up; go on past a message or a list"
            "B      stop asking")
      (%pd-lines (List map (fn (_ s) (%pd-half (first s) (rest s))) said))
      (list "Start  pause: options, help, save and quit"
            "Back   actions: every other command, the last one taken chosen"
            ""
            "In a menu, up and down choose, A takes and B goes back.  A question"
            "that wants a thing, such as what to quaff, is a menu of the answers."))))

; Each button's command, (BUTTON . KEY): A, B, Start and Back are the
; menus' and are always theirs; the rest are the player's to bind
; (pad-bindable), these their defaults, the triggers bound to nothing.
(def %pd-fixed
  (list (pair (lit south) ",") (pair (lit east) (lit escape))
        (pair (lit start) (lit pause)) (pair (lit back) (lit actions))))
(def pad-defaults
  (list (pair (lit west) "i") (pair (lit north) "o")
        (pair (lit left-shoulder) "<") (pair (lit right-shoulder) ">")
        (pair (lit left-trigger) ()) (pair (lit right-trigger) ())
        (pair (lit left-stick) ".") (pair (lit right-stick) "s")))
; The buttons a player binds, (BUTTON . NAME) each, in the order the
; gamepad's settings list them.
(def pad-bindable
  (list (pair (lit west) "X") (pair (lit north) "Y")
        (pair (lit left-shoulder) "LB") (pair (lit right-shoulder) "RB")
        (pair (lit left-trigger) "LT") (pair (lit right-trigger) "RT")
        (pair (lit left-stick) "Left stick click") (pair (lit right-stick) "Right stick click")))

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

; A pad's state: [STICK-X STICK-Y DPAD HELD NEXT FIRST? FULLSCREEN?
; LOOK-X LOOK-Y LOOKING LOOK-NEXT BUTTONS LT RT], the left stick's two
; directions, the d-pad buttons down, the direction held, when it next
; moves, whether that is its first move, whether the window is
; fullscreen; the right stick's two directions, the way it holds the
; view, and when the view next moves; each button's command, (BUTTON .
; KEY); and whether each trigger is pulled.
(def pad-make (fn (_) (Vector of 0 0 () () 0 #t #f 0 0 () 0 (List append %pd-fixed pad-defaults) #f #f)))

; Pad state S with the bindable buttons' commands BOUND, ((BUTTON .
; KEY) ...), the defaults for any not there.
(def pad-buttons!
  (fn (_ s bound)
    (Vector set! 11
      (List append %pd-fixed
        (List map (fn (_ d) ((fn (_ hit) (if (null? hit) d hit)) (List find (fn (_ b) (eq? (first b) (first d))) bound))) pad-defaults))
      s)))

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
    (def name (if (pad-event? e) (List ref 1 e) ()))
    (match
      ((eq? what (lit pad-axis))
        (match ((eq? name (lit left-x)) (Vector set! 0 (%pd-axis (List ref 2 e) (Vector ref 0 s)) s))
               ((eq? name (lit left-y)) (Vector set! 1 (%pd-axis (List ref 2 e) (Vector ref 1 s)) s))
               ((eq? name (lit right-x)) (Vector set! 7 (%pd-axis (List ref 2 e) (Vector ref 7 s)) s))
               ((eq? name (lit right-y)) (Vector set! 8 (%pd-axis (List ref 2 e) (Vector ref 8 s)) s))
               (#t ())))
      ((eq? what (lit pad-down))
        (Vector set! 2 (pair name (List filter (fn (_ h) (not (eq? h name))) (Vector ref 2 s))) s))
      ((eq? what (lit pad-up))
        (Vector set! 2 (List filter (fn (_ h) (not (eq? h name))) (Vector ref 2 s)) s))
      (#t ()))))

; The trigger event E pulled, left-trigger or right-trigger, as a
; button pressed: once it goes past %pd-on, and not again until it has
; come back under %pd-off.  Nil for any other event.
(def %pd-pulled!
  (fn (_ s e)
    (def name (if (null? e) () (if (eq? (first e) (lit pad-axis)) (List ref 1 e) ())))
    (def k (match ((eq? name (lit left-trigger)) 12) ((eq? name (lit right-trigger)) 13) (#t ())))
    (if (null? k) ()
      ((fn (_ v was)
         (match ((if (< %pd-on v) (not was) #f) (do (Vector set! k #t s) name))
                ((< v %pd-off) (do (Vector set! k #f s) ()))
                (#t ())))
       (List ref 2 e) (Vector ref k s)))))

; The game's key for event E -- nil when there is none -- from pad
; state S at NOW milliseconds, the state moved on.  E may be nil, or an
; event from anywhere: a held direction moves when its time comes
; whatever arrives.
(def pad-key
  (fn (_ s e now)
    (def pulled (%pd-pulled! s e))
    (%pd-take! s e)
    (def pressed (if (if (null? e) #f (eq? (first e) (lit pad-down))) (List ref 1 e) pulled))
    (def button
      (if (null? pressed) ()
        ((fn (_ hit) (if (null? hit) () (rest hit)))
         (List find (fn (_ b) (eq? (first b) pressed)) (Vector ref 11 s)))))
    (def pointing (%pd-pointing s))
    (unless (%pd-same? pointing (Vector ref 3 s))
      (do (Vector set! 3 pointing s)
          (Vector set! 4 (+ now %pd-settle) s)
          (Vector set! 5 #t s)))
    (def looking (if (if (= 0 (Vector ref 7 s)) (= 0 (Vector ref 8 s)) #f) () (pair (Vector ref 7 s) (Vector ref 8 s))))
    (unless (equal? looking (Vector ref 9 s))
      (do (Vector set! 9 looking s)
          (Vector set! 10 now s)))
    (match
      ((not (null? button)) button)
      ((not (null? pointing))
        (if (< now (Vector ref 4 s)) ()
          (do (Vector set! 4 (+ now (if (Vector ref 5 s) %pd-first %pd-rate)) s)
              (Vector set! 5 #f s)
              pointing)))
      ((null? looking) ())
      ((< now (Vector ref 10 s)) ())
      (#t (do (Vector set! 10 (+ now %pd-look) s)
              (list (lit look) (first looking) (rest looking)))))))

(provide roguelike/pad pad-make pad-key pad-event? pad-fullscreen? pad-fullscreen! pad-help pad-defaults pad-bindable pad-buttons!)
