; # x-roguelike -- a roguelike on x-lang
;
; ## lib/roguelike/run.x -- the entry
;
; @description `x -l roguelike -- [OPTIONS] [play | scores]`.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The module roguelike/run.  x.sh boots the dialect bundle.xon declares, arms
; the bundle's lib/ with import-path!, imports this module and then calls its
; main.
(module roguelike/run)
(import roguelike/base roguelike-main)

(set! %lang-name "roguelike")
(set! %repl-prompt "roguelike> ")

; The operands: what follows the "--" after the launcher's own options.
; x-os's launcher passes the engine's own flags ahead of them, with no
; "--" between; they are left out, so `x -l roguelike` there is a REPL too.
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))

(def main
  (fn (_)
    (let ((ops (%operands (rest (Sys args (lit program))))))
      (unless (null? ops) (Sys exit (roguelike-main ops))))))

(provide roguelike/run main)
