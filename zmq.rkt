#lang racket/base
(require ffi/unsafe
         (prefix-in c: racket/contract)
         scribble/srcdoc)
(require/doc racket/base
             scribble/manual)

(define zmq-lib (ffi-lib "libzmq"))

(define-syntax-rule (define-zmq (external internal)
                      (-> [name name/c] ...
                          result/c)
                      type)
  (begin
    (define external
      (get-ffi-obj 'internal zmq-lib type))
    (provide/doc
     [proc-doc/names
      external (c:-> name/c ... result/c)
      (name ...) ""])))

;;

; XXX Export/doc
(define-cpointer-type _context)
(define _size_t _int)
(define _uchar _uint8)

(require (for-syntax racket/base syntax/parse unstable/syntax))
(define-syntax (define-cvector-type stx)
  (syntax-parse 
   stx
   [(_ name:id _type:expr size:number)
    (with-syntax
        ([(field ...)
          (for/list ([i (in-range (syntax->datum #'size))])
            (format-id #f "f~a" i))])
      (syntax/loc stx
        (define-cstruct name
          ([field _type]
           ...))))]))
    
(define-cvector-type _ucharMAX _uchar 30)
(define-cstruct _msg
  ([content _pointer]
   [flags _uchar]
   [vsm_size _uchar]
   [vsm_data _ucharMAX]))
  
; XXX
(define (zmq-error) (error))

(define-zmq 
  [init zmq_init]
  (-> [io_threads exact-nonnegative-integer?]
      context?)
  (_fun [io_threads : _int]
        -> [context : _context/null]
        -> (or context
               (zmq-error))))

(define-zmq
  [term zmq_term]
  (-> [context context?] void)
  (_fun [context : _context]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-init zmq_msg_init]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-init-size zmq_msg_init_size]
  (-> [msg msg?] [size exact-nonnegative-integer?] void)
  (_fun _msg-pointer _size_t
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define *zmq-data* (make-hasheq))
(define (make-free-er in)
  (hash-set! *zmq-data* in #t)
  free-er)
(define (free-er out)
  (hash-remove! *zmq-data* out))

(define _zmq_free_fn (_fun _bytes _pointer -> _void))
(define-zmq
  [msg-init-data zmq_msg_init_data]
  (-> [msg msg?] [data bytes?] void)
  (_fun _msg-pointer [data : _bytes] [size : _size_t = (bytes-length data)]
        [ffn : _zmq_free_fn = (make-free-er data)] [hint : _pointer = #f]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-close zmq_msg_close]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-data-pointer zmq_msg_data]
  (-> [msg msg?] cpointer?)
  (_fun _msg-pointer -> _pointer))
(define-zmq
  [msg-size zmq_msg_size]
  (-> [msg msg?] exact-nonnegative-integer?)
  (_fun _msg-pointer -> _size_t))

; xxx export/doc
(define (msg-data m)
  (make-sized-byte-string (msg-data-pointer m) (msg-size m)))

