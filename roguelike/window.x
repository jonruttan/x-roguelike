; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/window.x -- the game played in a window
;
; The same game as the terminal's, drawn by roguelike/paint into a 640
; by 360 screen shown whole in an SDL window, and played with the same
; keys: a key pressed is handed to the game as the terminal would hand
; it, a letter as its string and an arrow, enter or escape by name.
; A gamepad's events become the same keys through roguelike/pad, and
; F11 or Alt-Enter switches the window to fullscreen and back.
; The screen is drawn again after every key, and about twelve times a
; second while a light flickers.  The game is heard as well as seen
; (roguelike/sound): its music is kept fed each time round the loop,
; and each turn's sounds are played as the turn is drawn.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/window)

(import x/sys/sdl)
(import x/sys/posix)
(import x/sys/gc)
(import x/type/vector)
(import x/core/doors int& int+ int- int< int= str-make str->ptr ptr-set! str-byte-ref char->int str-byte-len)
(import roguelike/state game-over game-over! game-exploring? game-exploring! game-band band-name game-place game-ask)
(import roguelike/frame frame-art)
(import roguelike/game game-key! game-explore!)
(import roguelike/paint paint-width paint-height paint-make paint-screen paint-turn! paint-frame! paint-flickers?
  paint-zoom paint-zoom! paint-animating? paint-step! paint-menu!)
(import roguelike/pad pad-make pad-key pad-event? pad-fullscreen? pad-fullscreen!)
(import roguelike/sound sound-make sound-pump! sound-collect? sound-turn! sound-volume! sound-close)
(import roguelike/menu menu-make menu-chosen menu-key)
(import roguelike/options options-names options-get options-set options-step options-line options-path options-read options-write!)

; A frame's wait while a light flickers, and the wait for a key when
; nothing moves, in microseconds.
(def %wn-frame-us 83000)
; A frame's wait while a turn's blows and steps are shown.
(def %wn-step-us 20000)
(def %wn-idle-us 10000)

; SDL's shift bits, and what a shifted key types on a US keyboard: the
; character after each unshifted one in this string.
(def %wn-shift-mod 3)

; F11, and enter with alt held, switch the window to fullscreen and back.
(def %wn-f11 1073741892)
(def %wn-alt-mod 768)

; The wall clock in milliseconds, for a held gamepad direction.
(def %wn-ms (fn (_) ((fn (_ t) (+ (* 1000 (first t)) (/ (rest t) 1000))) (Sys time-of-day))))
(def %wn-shifted "1!2@3#4$5%6^7&8*9(0)-_=+[{]}\\|;:'\",<.>/?`~")

(def %wn-char
  (fn (_ n)
    (def s (str-make 2))
    (ptr-set! (str->ptr s) 0 n 1)
    (ptr-set! (str->ptr s) 1 0 1)
    s))

; The character code CODE types with shift held.
(def %wn-shift
  (fn (_ code)
    (def n (str-byte-len %wn-shifted))
    (def at (fn (_ i) (char->int (str-byte-ref %wn-shifted i))))
    (if (if (int< 96 code) (int< code 123) #f) (- code 32)
      ((fn (self i) (match ((int< n (int+ i 2)) code) ((int= (at i) code) (at (int+ i 1))) (#t (self (int+ i 2))))) 0))))

; The art for game G's place and band, from cache A, [ARTS KEY ART PAD]:
; ARTS answers a place's art (see window-play), KEY is "PLACE/BAND" of
; the art made last, made again only when either changes.
(def %wn-art
  (fn (_ a g)
    (def place (game-place g))
    (def b ((fn (_ b) (if (null? b) () (band-name b))) (game-band g)))
    (def key (Str8 append place "/" (if (str? b) b "")))
    (unless (if (null? (Vector ref 2 a)) #f (str=? key (Vector ref 1 a)))
      (do (Vector set! 1 key a) (Vector set! 2 (frame-art ((Vector ref 0 a) place) b) a)))
    (Vector ref 2 a)))

(def %wn-named
  (list (pair (Sdl key (lit up)) (lit up)) (pair (Sdl key (lit down)) (lit down))
        (pair (Sdl key (lit left)) (lit left)) (pair (Sdl key (lit right)) (lit right))
        (pair 13 (lit enter)) (pair 27 (lit escape)) (pair 8 (lit backspace))))

; The game's key for SDL keycode CODE with modifiers MOD, or nil for a
; key the game has no use for.
(def window-key
  (fn (_ code mod)
    (if (if (= code %wn-f11) #t (if (= code 13) (not (= 0 (int& mod %wn-alt-mod))) #f)) (lit fullscreen)
    (if (if (int< 31 code) (int< code 127) #f)
      (%wn-char (if (= 0 (int& mod %wn-shift-mod)) code (%wn-shift code)))
      ((fn (_ hit) (if (null? hit) () (rest hit))) (List find (fn (_ e) (= (first e) code)) %wn-named))))))

; The window's cache A: [ARTS KEY ART PAD SOUND OPTIONS PAD?], ARTS KEY
; and ART for %wn-art, the gamepad's state, the game's sound or nil, the
; options (roguelike/options), and whether the last key came from the
; gamepad, so the prompts show its buttons.

; The next event and the key it is, (EVENT . KEY): a gamepad's events
; go to its state and come back as keys.  Whether the key came from the
; gamepad is kept in A.
(def %wn-input
  (fn (_ a)
    (def ev (Sdl poll))
    (def typed? (if (null? ev) #f (eq? (first ev) (lit key-down))))
    (def key (if typed? (window-key (List ref 1 ev) (List ref 2 ev)) (pad-key (Vector ref 3 a) ev (%wn-ms))))
    (unless (null? key) (Vector set! 6 (not typed?) a))
    (pair ev key)))
(def %wn-closed? (fn (_ e) (if (null? e) #f (if (eq? (first e) (lit quit)) #t (eq? (first e) (lit close))))))

; The options of A put to work on window WIN, painter P and game G: the
; zoom, fullscreen and how loud the sound is; then kept.
(def %wn-apply!
  (fn (_ a p g win)
    (def o (Vector ref 5 a))
    (def pad (Vector ref 3 a))
    (unless (int= (paint-zoom p) (options-get o (lit zoom)))
      (do (paint-zoom! p (options-get o (lit zoom))) (paint-turn! p g (%wn-art a g))))
    (unless (eq? (pad-fullscreen? pad) (int= 1 (options-get o (lit fullscreen))))
      (do (pad-fullscreen! pad (int= 1 (options-get o (lit fullscreen))))
          (Sdl fullscreen! win (pad-fullscreen? pad))))
    (sound-volume! (Vector ref 4 a) (options-get o (lit music)) (options-get o (lit effects)))
    (guard (e ()) (options-write! o (options-path)))))
(def %wn-option! (fn (_ a name v) (Vector set! 5 (options-set (Vector ref 5 a) name v) a)))

; What the foot of a menu says, as the gamepad's buttons or the keys,
; whichever was used last: ((NAME . WHAT) ...).
(def %wn-prompts
  (fn (_ a values?)
    (def pad? (Vector ref 6 a))
    (List append
      (list (pair (if pad? "A" "Enter") "Choose") (pair (if pad? "B" "Esc") "Back"))
      (if values? (list (pair (if pad? "<>" "Left Right") "Change")) ()))))

; Menu M over game G until a key answers it: what menu-key answered, or
; close when the window is closed.  HEADING, TITLE? and VALUES? as
; paint-menu! and %wn-prompts take them; LINES makes the items' text.
(def %wn-menu
  (fn (self g a p win m heading title? values? lines)
    (def show! (fn (_) (Sdl show! win (List ref 2 (paint-menu! p g heading title? (lines) (menu-chosen m) (%wn-prompts a values?) (Vector ref 6 a))))))
    (sound-pump! (Vector ref 4 a))
    (def in (%wn-input a))
    (def ev (first in))
    (def key (rest in))
    (def e (if (pad-event? ev) () ev))
    (def act (if (null? key) () (menu-key m key)))
    (match
      ((%wn-closed? e) (lit close))
      ((eq? key (lit fullscreen))
        (do (%wn-option! a (lit fullscreen) (if (pad-fullscreen? (Vector ref 3 a)) 0 1)) (%wn-apply! a p g win) (show!)
            (self g a p win m heading title? values? lines)))
      ((not (null? act)) act)
      ((not (null? key)) (do (show!) (self g a p win m heading title? values? lines)))
      ((not (null? e)) (do (show!) (self g a p win m heading title? values? lines)))
      ((not (null? ev)) (self g a p win m heading title? values? lines))
      (#t (do (Sys usleep %wn-idle-us)
              (when (sound-collect? (Vector ref 4 a)) (Heap collect))
              (self g a p win m heading title? values? lines))))))

; The options screen over game G until it is left: each option changed
; with left and right, a switch with enter as well, each change put to
; work at once.  Close when the window is closed, else nil.
(def %wn-options
  (fn (self g a p win m)
    (def lines (fn (_) (List append (List map (fn (_ n) (options-line (Vector ref 5 a) n)) options-names) (list "Back"))))
    (Sdl show! win (List ref 2 (paint-menu! p g "Options" #f (lines) (menu-chosen m) (%wn-prompts a #t) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m "Options" #f #t lines))
    (def step!
      (fn (_ name dir)
        (Vector set! 5 (options-step (Vector ref 5 a) name dir) a)
        (%wn-apply! a p g win)
        (self g a p win m)))
    (match
      ((eq? act (lit close)) act)
      ((eq? act (lit back)) ())
      ((eq? (first act) (lit change)) (if (eq? (first (rest act)) (lit back)) (self g a p win m) (step! (first (rest act)) (rest (rest act)))))
      ((eq? (rest act) (lit back)) ())
      (#t (step! (rest act) 1)))))
(def %wn-options-menu (fn (_) (menu-make (List append (List map (fn (_ n) (pair n "")) options-names) (list (pair (lit back) ""))))))

; The pause over game G: back to it, the options, the keys, or the game
; saved and left.  Close when the window is closed, else nil.
(def %wn-pause
  (fn (self g a p win m)
    (def items (List map rest (Vector ref 0 m)))
    (Sdl show! win (List ref 2 (paint-menu! p g "Paused" #f items (menu-chosen m) (%wn-prompts a #f) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m "Paused" #f #f (fn (_) items)))
    (def id (if (pair? act) (rest act) ()))
    (match
      ((eq? act (lit close)) act)
      ((eq? act (lit back)) ())
      ((not (eq? (first act) (lit take))) (self g a p win m))
      ((eq? id (lit resume)) ())
      ((eq? id (lit options)) (if (eq? (%wn-options g a p win (%wn-options-menu)) (lit close)) (lit close) (self g a p win m)))
      ((eq? id (lit keys)) (do (game-key! g "?") ()))
      (#t (do (game-over! g (lit saved)) ())))))
(def %wn-pause-items
  (list (pair (lit resume) "Back to the game") (pair (lit options) "Options")
        (pair (lit keys) "Keys") (pair (lit leave) "Save and quit")))

; Game G played in window WIN with art A and painter P until it ends or
; the window is closed; a closed window saves the game.  Escape, when
; nothing is being asked, or a gamepad's Start, pauses it.
(def %wn-loop
  (fn (self g a p win tick)
    (def pad (Vector ref 3 a))
    (def snd (Vector ref 4 a))
    (sound-pump! snd)
    (def in (%wn-input a))
    (def ev (first in))
    (def key (rest in))
    (def e (if (pad-event? ev) () ev))
    (match
      ((not (null? (game-over g))) ())
      ((%wn-closed? e) (game-over! g (lit saved)))
      ((eq? key (lit fullscreen))
        (do (%wn-option! a (lit fullscreen) (if (pad-fullscreen? pad) 0 1))
            (%wn-apply! a p g win)
            (Sdl show! win (List ref 2 (paint-screen p)))
            (self g a p win tick)))
      ((if (eq? key (lit pause)) #t (if (eq? key (lit escape)) (null? (game-ask g)) #f))
        (do (when (eq? (%wn-pause g a p win (menu-make %wn-pause-items)) (lit close)) (game-over! g (lit saved)))
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (self g a p win tick)))
      ; + or = shows the level larger, - smaller: the window's, not the
      ; game's, so no turn passes.
      ((not (int= 0 (%wn-zoom-step key)))
        (do (%wn-option! a (lit zoom) (int+ (paint-zoom p) (%wn-zoom-step key)))
            (%wn-apply! a p g win)
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (self g a p win tick)))
      ; The frame goes on screen before the heap is collected: the
      ; collect's cost comes after the key's answer, not before it.
      ((not (null? key))
        (do (if (game-exploring? g) (game-exploring! g ()) (game-key! g key))
            (sound-turn! snd g)
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (self g a p win tick)))
      ; Any other event -- a resize, the window shown again -- may have
      ; lost what was presented: the frame is presented again.
      ((not (null? e)) (do (Sdl show! win (List ref 2 (paint-screen p))) (self g a p win tick)))
      ; A gamepad event that is no key yet: the next one at once.
      ((not (null? ev)) (self g a p win tick))
      ; Exploring steps on without waiting for each step to be shown.
      ((game-exploring? g)
        (do (game-explore! g)
            (sound-turn! snd g)
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (Sys usleep 30000)
            (self g a p win tick)))
      ; A turn's blows and steps shown a frame at a time, before anything
      ; else moves; a key pressed meanwhile is taken at once.
      ((paint-animating? p)
        (do (Sys usleep %wn-step-us)
            (paint-step! p)
            (Sdl show! win (List ref 2 (paint-frame! p g (+ tick 1))))
            (self g a p win (+ tick 1))))
      ((paint-flickers? p)
        (do (Sys usleep %wn-frame-us)
            (Sdl show! win (List ref 2 (paint-frame! p g (+ tick 1))))
            (Heap collect)
            (self g a p win (+ tick 1))))
      (#t (do (Sys usleep %wn-idle-us)
              (when (sound-collect? snd) (Heap collect))
              (self g a p win tick))))))

; The zoom KEY asks for: 1 for + or =, -1 for -, 0 for any other.
(def %wn-zoom-step
  (fn (_ key)
    (if (str? key) (match ((str=? key "+") 1) ((str=? key "=") 1) ((str=? key "-") -1) (#t 0)) 0)))

; The title screen over game G, the game a new one starts with, until
; one is chosen: (play . G) for the game to play -- SAVED, or G when
; there is none or a new one is asked for, made by FRESH when G is
; SAVED -- or nil to leave.  TITLE is the set's.
(def %wn-title
  (fn (self g saved fresh a p win m title)
    (def items (List map rest (Vector ref 0 m)))
    (Sdl show! win (List ref 2 (paint-menu! p g title #t items (menu-chosen m) (%wn-prompts a #f) (Vector ref 6 a))))
    (def act (%wn-menu g a p win m title #t #f (fn (_) items)))
    (def id (if (pair? act) (rest act) ()))
    (match
      ((eq? act (lit close)) ())
      ((not (pair? act)) (self g saved fresh a p win m title))
      ((not (eq? (first act) (lit take))) (self g saved fresh a p win m title))
      ((eq? id (lit continue)) (pair (lit play) g))
      ((eq? id (lit new))
        (if (null? saved) (pair (lit play) g)
          (do (def n (fresh))
              (sound-close (Vector ref 4 a))
              (Vector set! 4 (sound-make n) a)
              (%wn-apply! a p n win)
              (paint-turn! p n (%wn-art a n))
              (pair (lit play) n))))
      ((eq? id (lit options))
        (if (eq? (%wn-options g a p win (%wn-options-menu)) (lit close)) ()
          (self g saved fresh a p win m title)))
      (#t ()))))

; A game played in a window: the title screen first, over the game a
; new one would start with, offering the game SAVED (nil for none),
; a new one from FRESH, the options, or leaving.  The art from ARTS and
; FONT (from paint-font), at SCALE times the screen's size, the level
; at ZOOM, nil for the options'.  ARTS takes a place, "" for the set
; the game began on or a region's name (game-place), and answers that
; place's art (from paint-art), so each region is drawn with its own
; set's pictures; TITLE heads the title screen.  Answers (G . FAILED):
; the game played, nil when none was, and nil or what was raised while
; it was played, the window closed either way.
(def window-play
  (fn (_ saved fresh arts font scale zoom title)
    (def o (options-read (options-path)))
    (def a (Vector of arts "" () (pad-make) () (if (null? zoom) o (options-set o (lit zoom) zoom)) #f))
    (def win (Sdl scaling! (Sdl open title paint-width paint-height scale) (lit fit)))
    (def played (Vector of ()))
    (def failed
      (guard (e e)
        (do (def p (paint-make font))
            (def g (if (null? saved) (fresh) saved))
            (Vector set! 4 (sound-make g) a)
            (paint-zoom! p (options-get (Vector ref 5 a) (lit zoom)))
            (paint-turn! p g (%wn-art a g))
            (%wn-apply! a p g win)
            (def chosen
              (%wn-title g saved fresh a p win
                (menu-make (List append (if (null? saved) () (list (pair (lit continue) "Continue")))
                             (list (pair (lit new) "New game") (pair (lit options) "Options") (pair (lit quit) "Quit"))))
                title))
            (unless (null? chosen)
              (do (Vector set! 0 (rest chosen) played)
                  (paint-turn! p (rest chosen) (%wn-art a (rest chosen)))
                  (Sdl show! win (List ref 2 (paint-frame! p (rest chosen) 0)))
                  (%wn-loop (rest chosen) a p win 0)))
            ())))
    (sound-close (Vector ref 4 a))
    (Sdl close win)
    (pair (Vector ref 0 played) failed)))

(provide roguelike/window window-key window-play)
