#lang racket/base
(require ffi/unsafe
         (prefix-in c: racket/contract)
         scribble/srcdoc)
(require/doc racket/base
             scribble/manual)

(define zmq-lib (ffi-lib "libzmq"))

(define-syntax-rule (define-zmq* (external internal) type)
  (define external
    (get-ffi-obj 'internal zmq-lib type)))
(define-syntax-rule (define-zmq (external internal)
                      (-> [name name/c] ...
                          result/c)
                      type)
  (begin
    (define-zmq* (external internal) type)
    (provide/doc
     [proc-doc/names
      external (c:-> name/c ... result/c)
      (name ...) ""])))

;;

; XXX Export/doc
(define-cpointer-type _context)
(define-cpointer-type _socket)

(define-syntax-rule (define-zmq-symbols _type type?
                      [sym = num] ...)
  (begin 
    (define _type
      (_enum (append '[sym = num] ...) _int))
    (define type?
      (c:symbols 'sym ...))))

(define-zmq-symbols _socket-type socket-type?
  [PAIR = 0]
  [PUB = 1]
  [SUB = 2]
  [REQ = 3]
  [REP = 4]
  [XREQ = 5]
  [XREP = 6]
  [PULL = 7]
  [PUSH = 8])
(define-zmq-symbols _option-name option-name?
  [HWM = 1]
  [SWAP = 3]
  [AFFINITY = 4]
  [IDENTITY = 5]
  [SUBSCRIBE = 6]
  [UNSUBSCRIBE = 7]
  [RATE = 8]
  [RECOVERY_IVL = 9]
  [MCAST_LOOP = 10]
  [SNDBUF = 11]
  [RCVBUF = 12]
  [RCVMORE = 13])

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

;; Context
(define-zmq 
  [context zmq_init]
  (-> [io_threads exact-nonnegative-integer?]
      context?)
  (_fun [io_threads : _int]
        -> [context : _context/null]
        -> (or context
               (zmq-error))))

(define-zmq
  [context-close! zmq_term]
  (-> [context context?] void)
  (_fun [context : _context]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

;; Message
(define-zmq
  [msg-init! zmq_msg_init]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-init-size! zmq_msg_init_size]
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
  [msg-init-data! zmq_msg_init_data]
  (-> [msg msg?] [data bytes?] void)
  (_fun _msg-pointer [data : _bytes] [size : _size_t = (bytes-length data)]
        [ffn : _zmq_free_fn = (make-free-er data)] [hint : _pointer = #f]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-close! zmq_msg_close]
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

(define-zmq
  [msg-copy! zmq_msg_copy]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-move! zmq_msg_move]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

;; Socket
(define-zmq
  [socket zmq_socket]
  (-> [ctxt context?] [type socket-type?] socket?)
  (_fun _context _socket-type
        -> [sock : _socket] -> (unless sock (zmq-error))))
(define-zmq
  [socket-close! zmq_close]
  (-> [socket socket?] void)
  (_fun _socket
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-syntax (define-zmq-socket-options stx)
  (syntax-case stx ()
    [(_ [external internal]
        ([_type after type? opt ...] ...)
        (byte-opt ...))
     (with-syntax ([(_type-external ...) (generate-temporaries #'(_type ...))])
       (syntax/loc stx
         (begin
           (define-zmq* [_type-external internal]
             (_fun _socket _option-name 
                   [option-value : (_ptr o _type)]
                   [option-size : (_ptr o _size_t)]
                   -> [err : _int]
                   -> (if (zero? err)
                          option-value
                          (zmq-error))))
           ...
           (define-zmq* [byte-external internal]
             (_fun _socket _option-name
                   [option-value : (_bytes o 255)]
                   [option-size : (_ptr o _size_t)]
                   -> [err : _int]
                   -> (if (zero? err)
                          (subbytes option-value 0 option-size)
                          (zmq-error))))
           (define (external sock opt-name)
             (case opt-name
               [(opt ...) (after (_type-external sock opt-name))]
               ...
               [(byte-opt ...) (byte-external sock opt-name)]))
           (provide/doc
            [proc-doc/names
             external (c:-> socket? option-name? (c:or/c type? ... bytes?))
             (socket option-name) ""]))))]))

(define-zmq-socket-options
  [socket-option zmq_getsockopt]
  ([_int64 zero? boolean? 
           RCVMORE MCAST_LOOP]
   [_int64 (λ (x) x) exact-integer?
           SWAP RATE RECOVERY_IVL]
   [_uint64 (λ (x) x) exact-nonnegative-integer?
            HWM AFFINITY SNDBUF RCVBUF])
  (IDENTITY))
