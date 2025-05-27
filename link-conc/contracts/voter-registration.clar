
;; title: voter-registration
;; version:
;; summary:
;; description:

;; Voter Registration Smart Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-already-registered (err u101))
(define-constant err-not-registered (err u102))
(define-constant err-invalid-status (err u103))

;; Data Variables
(define-data-var next-voter-id uint u1)

;; Data Maps
(define-map voters principal { id: uint, status: (string-ascii 20) })
(define-map voter-ids uint principal)

;; Read-only functions
(define-read-only (get-voter-info (voter principal))
  (map-get? voters voter)
)

(define-read-only (is-registered (voter principal))
  (is-some (map-get? voters voter))
)

(define-read-only (get-voter-by-id (id uint))
  (map-get? voter-ids id)
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender contract-owner)
)

;; Public functions
(define-public (register-voter (voter principal))
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    (asserts! (is-none (map-get? voters voter)) err-already-registered)
    (let
      (
        (new-id (var-get next-voter-id))
      )
      (map-set voters voter { id: new-id, status: "pending" })
      (map-set voter-ids new-id voter)
      (var-set next-voter-id (+ new-id u1))
      (ok new-id)
    )
  )
)

(define-public (verify-voter (voter principal))
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    (match (map-get? voters voter)
      voter-info (begin
        (map-set voters voter (merge voter-info { status: "verified" }))
        (ok true)
      )
      err-not-registered
    )
  )
)

(define-public (revoke-voter (voter principal))
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    (match (map-get? voters voter)
      voter-info (begin
        (map-set voters voter (merge voter-info { status: "revoked" }))
        (ok true)
      )
      err-not-registered
    )
  )
)

(define-public (update-voter-status (voter principal) (new-status (string-ascii 20)))
  (begin
    (asserts! (is-contract-owner) err-unauthorized)
    (asserts! (or (is-eq new-status "pending") (is-eq new-status "verified") (is-eq new-status "revoked")) err-invalid-status)
    (match (map-get? voters voter)
      voter-info (begin
        (map-set voters voter (merge voter-info { status: new-status }))
        (ok true)
      )
      err-not-registered
    )
  )
)

(define-public (get-voter-status)
  (match (map-get? voters tx-sender)
    voter-info (ok (get status voter-info))
    err-not-registered
  )
)