#lang setup/infotab
(define name "ZeroMQ")
(define blurb
  (list "An FFI for ZeroMQ"))
(define scribblings '(["zmq.scrbl" (multi-page)]))
(define categories '(net io))
(define primary-file "main.rkt")
(define compile-omit-paths '())
(define release-notes 
  (list
   '(ul (li "Initial release"))))
(define repositories '("4.x"))
