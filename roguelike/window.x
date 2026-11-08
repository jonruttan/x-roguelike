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
; second while a light flickers.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(module roguelike/window)

(import x/sys/sdl)
(import x/sys/posix)
(import x/sys/gc)
(import x/type/vector)
(import x/core/doors int& int+ int< int= str-make str->ptr ptr-set! str-byte-ref char->int str-byte-len)
(import roguelike/state game-over game-over! game-exploring? game-exploring! game-band band-name)
(import roguelike/frame frame-art)
(import roguelike/game game-key! game-explore!)
(import roguelike/paint paint-width paint-height paint-make paint-screen paint-turn! paint-frame! paint-flickers?
  paint-zoom paint-zoom!)
(import roguelike/pad pad-make pad-key pad-event? pad-fullscreen? pad-fullscreen!)

; A frame's wait while a light flickers, and the wait for a key when
; nothing moves, in microseconds.
(def %wn-frame-us 83000)
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

; The art for game G's band, from cache A, [FORMS BAND ART PAD]: made again
; only when the band changes.
(def %wn-art
  (fn (_ a g)
    (def b ((fn (_ b) (if (null? b) () (band-name b))) (game-band g)))
    (unless (if (null? (Vector ref 2 a)) #f
              ((fn (_ was) (if (str? b) (if (str? was) (str=? b was) #f) (null? was))) (Vector ref 1 a)))
      (do (Vector set! 1 b a) (Vector set! 2 (frame-art (Vector ref 0 a) b) a)))
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

; Game G played in window WIN with art A and painter P until it ends or
; the window is closed; a closed window saves the game.  A gamepad's
; events go to its state, the fourth of A, and come back as keys.
(def %wn-loop
  (fn (self g a p win tick)
    (def pad (Vector ref 3 a))
    (def ev (Sdl poll))
    (def key (if (if (null? ev) #f (eq? (first ev) (lit key-down)))
               (window-key (List ref 1 ev) (List ref 2 ev))
               (pad-key pad ev (%wn-ms))))
    (def e (if (pad-event? ev) () ev))
    (match
      ((not (null? (game-over g))) ())
      ((if (null? e) #f (if (eq? (first e) (lit quit)) #t (eq? (first e) (lit close))))
        (game-over! g (lit saved)))
      ((eq? key (lit fullscreen))
        (do (pad-fullscreen! pad (not (pad-fullscreen? pad)))
            (Sdl fullscreen! win (pad-fullscreen? pad))
            (Sdl show! win (List ref 2 (paint-screen p)))
            (self g a p win tick)))
      ; + or = shows the level larger, - smaller: the window's, not the
      ; game's, so no turn passes.
      ((not (int= 0 (%wn-zoom-step key)))
        (do (paint-zoom! p (int+ (paint-zoom p) (%wn-zoom-step key)))
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (self g a p win tick)))
      ; The frame goes on screen before the heap is collected: the
      ; collect's cost comes after the key's answer, not before it.
      ((not (null? key))
        (do (if (game-exploring? g) (game-exploring! g ()) (game-key! g key))
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (self g a p win tick)))
      ; Any other event -- a resize, the window shown again -- may have
      ; lost what was presented: the frame is presented again.
      ((not (null? e)) (do (Sdl show! win (List ref 2 (paint-screen p))) (self g a p win tick)))
      ; A gamepad event that is no key yet: the next one at once.
      ((not (null? ev)) (self g a p win tick))
      ((game-exploring? g)
        (do (game-explore! g)
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g tick)))
            (Heap collect)
            (Sys usleep 30000)
            (self g a p win tick)))
      ((paint-flickers? p)
        (do (Sys usleep %wn-frame-us)
            (Sdl show! win (List ref 2 (paint-frame! p g (+ tick 1))))
            (Heap collect)
            (self g a p win (+ tick 1))))
      (#t (do (Sys usleep %wn-idle-us) (self g a p win tick))))))

; The zoom KEY asks for: 1 for + or =, -1 for -, 0 for any other.
(def %wn-zoom-step
  (fn (_ key)
    (if (str? key) (match ((str=? key "+") 1) ((str=? key "=") 1) ((str=? key "-") -1) (#t 0)) 0)))

; Game G played in a window, its art from FORMS (from paint-art) and
; FONT (from paint-font), at SCALE times the screen's size, the level
; shown at ZOOM, nil for the painter's first: nil, or what was raised
; while it was played, the window closed either way.
(def window-play
  (fn (_ g forms font scale zoom)
    (def a (Vector of forms () () (pad-make)))
    (def win (Sdl scaling! (Sdl open "x-roguelike" paint-width paint-height scale) (lit fit)))
    (def failed
      (guard (e e)
        (do (def p (paint-make font))
            (unless (null? zoom) (paint-zoom! p zoom))
            (paint-turn! p g (%wn-art a g))
            (Sdl show! win (List ref 2 (paint-frame! p g 0)))
            (%wn-loop g a p win 0)
            ())))
    (Sdl close win)
    failed))

(provide roguelike/window window-key window-play)
