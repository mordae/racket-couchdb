#lang scribble/manual

@require[(planet cce/scheme:4:1/planet)]
@require[(for-label racket net/url)]
@require[(for-label (planet dherman/json:3:0))]
@require[(for-label (this-package-in main))]

@title{CouchDB}
@author{@(author+email "Jan Dvorak" "mordae@anilinux.org")}

CouchDB client for Racket.

@defmodule/this-package[]

Most functions in this module can raise @racket[exn:couchdb?] exceptions.

There are two special ones, that you might want to handle separately,
they are @racket[exn:couchdb:conflict?] which is raised when document
to be modified have been altered by another client and
@racket[exn:couchdb:not-found?] which is raised when given document
simply does not exist.

@defproc[(couchdb-connect (#:host host string? "localhost")
                          (#:port port exact-nonnegative-integer? 5984)
                          (#:user user (or/c string? #f) #f)
                          (#:password password (or/c string? #f) #f))
         couchdb-server?]{
 Creates CouchDB server connection information.

 In reality, this does not connect anywhere. Provided options are
 stored in newly created @racket[couchdb-server?] structure, which
 is then used for the purpose of URL construction.
}

@defproc[(couchdb-server? (value any/c)) boolean?]{
 Determines if given value is a CouchDB server information returned
 by @racket[couchdb-connect].
}

@defproc[(couchdb-db (server couchdb-server?)
                     (name string?))
         couchdb-database?]{
 Creates database connection structure.

 Result of this function is used in all database-local queries.
 It contains both the server and database name, which are used
 in URL construction.
}

@defproc[(couchdb-database? (value any/c)) boolean?]{
 Determines if given value is a CouchDB database returned by
 @racket[couchdb-db].
}

@defproc[(couchdb-info (server-or-db (or/c couchdb-server? couchdb-database?)))
         jsexpr?]{
 Returns information about server or database.
}

@defproc[(couchdb-all-dbs (server couchdb-server?))
         jsexpr?]{
 Returns list with names of all databases present on the server.
}

@defproc[(couchdb-all-docs (db couchdb-database?))
         jsexpr?]{
 Returns contents of the _all_docs special view that maps all documents in
 given database by their ids.
}

@defproc[(couchdb-uuids (server couchdb-server?)
                        (#:count count exact-nonnegative-integer? 1))
         (listof string?)]{
 Returns list of server-generated UUIDs.
}

@defproc[(couchdb-get (db couchdb-database?)
                      (id string?)
                      (#:rev rev (or/c string? (symbols 'current)) 'current)
                      (#:open-revs open-revs (or/c (symbols 'all 'current)
                                                   (listof string?)) 'current)
                      (#:revs-info? revs-info? boolean? #f)
                      (#:conflicts? conflicts? boolean? #f))
         jsexpr?]{
 Retrieves specified document from given CouchDB database.

 Consult @link["http://wiki.apache.org/couchdb/HTTP_Document_API"]{CouchDB
 documentation} for information on keyword arguments.
}

@defproc[(couchdb-put (db couchdb-database?)
                      (document jsexpr?))
         jsexpr?]{
 Stores specified document in given CouchDB database.
}

@defproc[(couchdb-update/document (db couchdb-database?)
                                  (document jsexpr?)
                                  (update-fn (-> jsexpr? jsexpr?)))
         jsexpr?]{
 Updates given document using the @racket[update-fn] and then puts it to
 the database.

 If put fails with @racket[exn:couchdb:conflict?], everything is repeated
 with current version of the document until put succeeds or raises a
 different exception.
}

@defproc[(couchdb-update (db couchdb-database?)
                         (id string?)
                         (update-fn (-> jsexpr? jsexpr?)))
         jsexpr?]{
 Same as @racket[couchdb-update/document], but document is retrieved by
 given id first.
}

@defproc[(couchdb-delete (db couchdb-database?)
                         (document jsexpr?))
         jsexpr?]{
 Deletes specified document from the CouchDB database.
}

@defproc[(couchdb-delete-db (db couchdb-database?))
         jsexpr?]{
 Deletes given database from the server.
}

@defproc[(couchdb-view (db couchdb-database?)
                       (view (list/c string? string?))
                       (#:include-docs? include-docs? boolean? #f)
                       (#:key key (or/c jsexpr? void?) (void))
                       (#:startkey startkey (or/c jsexpr? void?) (void))
                       (#:startkey-docid startkey-docid (or/c jsexpr? void?)
                                                        (void))
                       (#:endkey endkey (or/c jsexpr? void?) (void))
                       (#:endkey-docid endkey-docid (or/c jsexpr? void?) (void))
                       (#:limit limit (or/c exact-nonnegative-integer? void?)
                                      (void))
                       (#:stale stale (or/c (symbols 'ok 'update-after) void?)
                                      (void))
                       (#:descending? descending? boolean? #f)
                       (#:skip skip exact-nonnegative-integer? 0)
                       (#:group? group boolean? #f)
                       (#:group-level group-level
                         (or/c exact-nonnegative-integer? void?) (void))
                       (#:reduce? reduce? (or/c boolean? void?) (void))
                       (#:inclusive-end? inclusive-end? boolean? #t)
                       (#:update-seq? update-seq? boolean? #f))
         jsexpr?]{
 Queries a stored view.

 Consult @link["http://wiki.apache.org/couchdb/HTTP_view_API"]{CouchDB
 documentation} for information on keyword arguments.
}

@defproc[(exn:couchdb? (value any/c)) boolean?]{
 Generic CouchDB exception.
}

@defproc[(exn:couchdb:conflict? (value any/c)) boolean?]{
 Revision conflict exception.
}
@defproc[(exn:couchdb:not-found? (value any/c)) boolean?]{
 Document not found exception.
}

@; vim:set ft=scribble sw=2 ts=2 et:
