#lang racket
;
; CouchDB interface.
;

; Our dependencies.
(require net/url
         net/head
         net/uri-codec
         net/base64
         (planet dherman/json:3:0))

; CouchDB server specification.
(define-struct/contract
  couchdb-server ((host string?)
                  (port exact-nonnegative-integer?)
                  (user (or/c string? false?))
                  (password (or/c string? false?))))

; Database specification.
(define-struct/contract
  couchdb-database ((server couchdb-server?)
                    (name string?)))

; Our exceptions.
(define-struct (exn:couchdb exn) (error url doc))
(define-struct (exn:couchdb:not-found exn:couchdb) ())
(define-struct (exn:couchdb:conflict exn:couchdb) ())

; Exception map.
(define exn-map (hash "not_found" make-exn:couchdb:not-found
                      "conflict"  make-exn:couchdb:conflict))

; Export functions that already have contracts defined.
(provide
  couchdb-server?
  couchdb-database?
  exn:couchdb?
  exn:couchdb:conflict?
  exn:couchdb:not-found?)

; Exports functions with contracts.
(provide (contract-out
           (couchdb-connect (->* ()
                                 (#:host string?
                                  #:port exact-nonnegative-integer?
                                  #:user (or/c string? #f)
                                  #:password (or/c string? #f))
                                 couchdb-server?))

           (couchdb-db (-> couchdb-server?
                           string?
                           couchdb-database?))

           (couchdb-info (-> (or/c couchdb-server? couchdb-database?)
                             jsexpr?))

           (couchdb-all-dbs (-> couchdb-server?
                                jsexpr?))

           (couchdb-all-docs (-> couchdb-database?
                                 jsexpr?))

           (couchdb-uuids (->* (couchdb-server?)
                               (#:count exact-nonnegative-integer?)
                               (listof string?)))

           (couchdb-get (->* (couchdb-database?
                              string?)
                             (#:rev (or/c string?
                                          (symbols 'current))
                              #:open-revs (or/c (symbols 'all 'current)
                                                (listof string?))
                              #:revs-info? boolean?
                              #:conflicts? boolean?)
                             jsexpr?))

           (couchdb-put (-> couchdb-database?
                            jsexpr?
                            jsexpr?))

           (couchdb-update (-> couchdb-database?
                               string?
                               (-> jsexpr? jsexpr?)
                               jsexpr?))

           (couchdb-update/document (-> couchdb-database?
                                        jsexpr?
                                        (-> jsexpr? jsexpr?)
                                        jsexpr?))

           (couchdb-delete (-> couchdb-database?
                               jsexpr?
                               jsexpr?))

           (couchdb-delete-db (-> couchdb-database?
                                  jsexpr?))

           (couchdb-view (->* (couchdb-database?
                               (list/c string? string?))
                              (#:include-docs? boolean?
                               #:key (or/c jsexpr? void?)
                               #:startkey (or/c jsexpr? void?)
                               #:startkey-docid (or/c jsexpr? void?)
                               #:endkey (or/c jsexpr? void?)
                               #:endkey-docid (or/c jsexpr? void?)
                               #:limit (or/c exact-nonnegative-integer? void?)
                               #:stale (or/c (symbols 'ok 'update-after) void?)
                               #:descending? boolean?
                               #:skip exact-nonnegative-integer?
                               #:group? boolean?
                               #:group-level (or/c exact-nonnegative-integer?
                                                   void?)
                               #:reduce? (or/c boolean? void?)
                               #:inclusive-end? boolean?
                               #:update-seq? boolean?)
                              jsexpr?))))

;
; Creates new CouchDB connection.
;
; In reality, this merely sets up a strucure with info for
; each connection done through it.
;
(define (couchdb-connect #:host (host "localhost")
                         #:port (port 5984)
                         #:user (user #f)
                         #:password (password #f))
  (make-couchdb-server host port user password))

;
; Select specific CouchDB database to perform CRUD on.
;
(define (couchdb-db server name)
  (make-couchdb-database server name))

; Creates server-relative URL from given components.
(define (make-server-url server path (query null))
  (make-url "http"
            (couchdb-server-user server)
            (couchdb-server-host server)
            (couchdb-server-port server)
            #t
            (map (lambda (c) (make-path/param c null)) path)
            query
            #f))

; Creates database-relative URL from given components.
(define (make-database-url db path (query null))
  (make-server-url (couchdb-database-server db)
                   (cons (couchdb-database-name db) path)
                   query))

; Creates database-relative view URL from (design-document-name view-name).
(define (make-view-url db view (query null))
  (let ((design (car view))
        (view   (cadr view)))
  (make-database-url db (list "_design" design "_view" view) query)))

; Encodes open_revs argument.
(define (encode-open-revs open-revs)
  (if (symbol? open-revs)
    (symbol->string open-revs)
    (jsexpr->json open-revs)))

; Raise proper exception.
(define (raise-error ccm doc method url)
  (let* ((error (hash-ref doc 'error))
         (reason (string-append "CouchDB " method " " (url->string url)
                                "\n        " error
                                ": " (hash-ref doc 'reason))))
    (if (hash-has-key? exn-map error)
      (raise ((hash-ref exn-map error) reason ccm error url doc))
      (raise (make-exn:couchdb reason ccm error url doc)))))

; Returns #t if document contains only error description.
(define (error-document? doc)
  (and (hash? doc)
       (= (hash-count doc) 2)
       (hash-has-key? doc 'error)
       (hash-has-key? doc 'reason)))

; Retrieves given URL.
(define (get-url url (header null))
  (let* ((port (get-pure-port url header #:redirections 1))
         (doc (read-json port)))
    (if (error-document? doc)
      (raise-error (current-continuation-marks) doc "GET" url)
      doc)))

; Stores datum on given URL.
(define (put-url url data (header null))
  (let* ((port (put-pure-port url data header))
         (doc (read-json port)))
    (if (error-document? doc)
      (raise-error (current-continuation-marks) doc "PUT" url)
      doc)))

; Deletes given URL.
(define (delete-url url (header null))
  (let* ((port (delete-pure-port url header))
         (doc (read-json port)))
    (if (error-document? doc)
      (raise-error (current-continuation-marks) doc "DELETE" url)
      doc)))

; Checks that character is an allowed base64 string character.
(define (base64-character? char)
  (or (and (char>=? char #\A)
           (char<=? char #\Z))
      (and (char>=? char #\a)
           (char<=? char #\z))
      (and (char>=? char #\0)
           (char<=? char #\9))
      (char=? char #\=)
      (char=? char #\/)))

; Base64-encodes UTF-8 string.
(define (base64-encode/string str)
  (list->string
    (filter base64-character?
            (string->list
              (bytes->string/utf-8
                (base64-encode
                  (string->bytes/utf-8 str)))))))

; Creates headers for HTTP Basic authentication if provided in the
; given server-or-db structure.
(define (auth-header server-or-db)
  (define-values (login password)
    (if (couchdb-server? server-or-db)
      (values (couchdb-server-user server-or-db)
              (couchdb-server-password server-or-db))
      (let ((server (couchdb-database-server server-or-db)))
        (values (couchdb-server-user server)
                (couchdb-server-password server)))))
  (if (and login password)
    (list (string-append "Authorization: Basic "
                         (base64-encode/string
                           (string-append login ":" password))))
    null))

;
; Returns server MOTD & info document or database info,
; dependending on the type of supplied argument.
;
(define (couchdb-info server-or-db)
  (if (couchdb-server? server-or-db)
    (let ((url (make-server-url server-or-db null)))
      (get-url url (auth-header server-or-db)))
    (let ((url (make-database-url server-or-db null)))
      (get-url url (auth-header server-or-db)))))

;
; Deletes given database.
;
(define (couchdb-delete-db db)
  (let* ((url (make-database-url db null)))
    (delete-url url (auth-header db))))

;
; Returns list of all databases.
;
(define (couchdb-all-dbs server)
  (let* ((url (make-server-url server (list "_all_dbs"))))
    (get-url url (auth-header server))))

;
; Returns contents of the _all_docs special view that maps
; all documents in database by their ids.
;
(define (couchdb-all-docs db)
  (let* ((url (make-database-url db (list "_all_docs"))))
    (get-url url (auth-header db))))

;
; Returns list of server-generated UUIDs.
;
(define (couchdb-uuids server #:count (count 1))
  (let* ((url (make-server-url server (list "_uuids")
                               `((count . ,(number->string count))))))
    (hash-ref (get-url url (auth-header server)) 'uuids)))

;
; Returns document associated with given ID from given database.
;
(define (couchdb-get db id
                     #:rev (rev 'current)
                     #:open-revs (open-revs 'current)
                     #:revs-info? (revs-info? #f)
                     #:conflicts? (conflicts? #f))

  ; Parameter list.
  (define params null)

  ; Adds new parameter.
  (define (add-param name value)
    (set! params (cons (cons name value) params)))

  ; Include revision if not 'current
  (or (equal? rev 'current)
      (add-param 'rev rev))

  ; Include open_revs if 'all or list of names.
  (or (equal? open-revs 'current)
      (add-param 'open_revs (encode-open-revs open-revs)))

  ; Include revs_info if true.
  (and revs-info?
       (add-param 'revs_info "true"))

  ; Include conflicts if true.
  (and conflicts?
       (add-param 'conflicts "true"))

  ; Perform the request and return result.
  (let* ((url (make-database-url db (list id) params)))
    (get-url url (auth-header db))))

;
; Stores new document or revision in the database.
;
(define (couchdb-put db document)
  (let* ((id  (hash-ref document '_id))
         (url (make-database-url db (list id))))
    (put-url url
             (string->bytes/utf-8 (jsexpr->json document))
             (auth-header db))))

;
; Updates given document using the update-fn and then
; puts it to the database.
;
; If put fails with exn:couchdb:conflict?, everything is repeated.
;
(define (couchdb-update/document db document update-fn)
  (let loop ((current document))
    (with-handlers* ((exn:couchdb:conflict?
                       (lambda (exn)
                         (loop (couchdb-get db (hash-ref current '_id))))))
      (couchdb-put db (update-fn current)))))

;
; Same as couchdb-update/document, but document is retrieved by id first.
;
(define (couchdb-update db id update-fn)
  (couchdb-update/document db (couchdb-get db id) update-fn))

;
; Deletes given document from the database.
;
(define (couchdb-delete db document)
  (let* ((id  (hash-ref document '_id))
         (rev (hash-ref document '_rev))
         (url (make-database-url db (list id) `((rev . ,rev)))))
    (delete-url url (auth-header db))))

(define (couchdb-view db view #:include-docs? (include-docs? #f)
                              #:key (key (void))
                              #:startkey (startkey (void))
                              #:startkey-docid (startkey-docid (void))
                              #:endkey (endkey (void))
                              #:endkey-docid (endkey-docid (void))
                              #:limit (limit (void))
                              #:stale (stale (void))
                              #:descending? (descending? #f)
                              #:skip (skip 0)
                              #:group? (group? #f)
                              #:group-level (group-level (void))
                              #:reduce? (reduce? (void))
                              #:inclusive-end? (inclusive-end? #t)
                              #:update-seq? (update-seq? #f))
  ; Parameters for the request.
  (define params null)

  ; Adds new parameter.
  (define (add-param name value)
    (set! params (cons (cons name value) params)))

  ; Shall we include document bodies?
  (and include-docs?
       (add-param 'include_docs "true"))

  ; Key, if defined.
  (or (void? key)
      (add-param 'key (jsexpr->json key)))

  ; Starting key, if defined.
  (or (void? startkey)
      (add-param 'startkey (jsexpr->json startkey)))

  ; Starting key's document id, if defined.
  (or (void? startkey-docid)
      (add-param 'startkey_docid (jsexpr->json startkey-docid)))

  ; Ending key, if defined.
  (or (void? endkey)
      (add-param 'endkey (jsexpr->json endkey)))

  ; Ending key's document id, if defined.
  (or (void? endkey-docid)
      (add-param 'endkey_docid (jsexpr->json endkey-docid)))

  ; Limit, if defined.
  (or (void? limit)
      (add-param 'limit (number->string limit)))

  ; Stale view handling, if defined.
  (or (void? stale)
      (add-param 'stale (if (equal? stale 'ok) "ok" "update_after")))

  ; Reverse output order?
  (and descending?
       (add-param 'descending "true"))

  ; Number of items to skip.
  (and (> skip 0)
       (add-param 'skip (number->string skip)))

  ; Grouping, if enabled.
  (and group?
       (add-param 'group "true"))

  ; Grouping level, if enabled.
  (or (void? group-level)
      (add-param 'group_level (number->string group-level)))

  ; Reduce toggle, if defined.
  (or (void? reduce?)
      (add-param 'reduce (if reduce? "true" "false")))

  ; Inclusive end, if disabled.
  (or inclusive-end?
      (add-param 'inclusive_end "false"))

  ; Include sequence number?
  (and update-seq?
       (add-param 'update_seq "true"))

  (let* ((url (make-view-url db view params)))
    (get-url url (auth-header db))))

; vim:set ts=2 sw=2 et:
