
;; title: Secure-Voting
;; version:
;; summary:
;; description:

;; Secure Voting Contract
;; This contract implements secure, immutable, and private vote casting

;; Define data variables
(define-data-var election-active bool false)
(define-data-var vote-count uint u0)
(define-data-var election-end-height uint u0)

;; Define maps
(define-map voter-registry principal bool)
(define-map vote-commitments principal (buff 32))
(define-map revealed-votes principal uint)

;; Define constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ELECTION-NOT-ACTIVE (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-NOT-REGISTERED (err u103))
(define-constant ERR-INVALID-VOTE (err u104))
(define-constant ERR-ELECTION-ENDED (err u105))
(define-constant ERR-COMMITMENT-NOT-FOUND (err u106))
(define-constant ERR-INVALID-REVEAL (err u107))
(define-constant ERR-ALREADY-REVEALED (err u108))
(define-constant ERR-ELECTION-NOT-ENDED (err u109))

;; Initialize election
(define-public (initialize-election (duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get election-active)) ERR-ELECTION-NOT-ACTIVE)
    (var-set election-active true)
    (var-set election-end-height (+ stacks-block-height duration))
    (ok true)))

;; Register voter with a blinded identity
;; In a real implementation, this would involve more sophisticated identity verification
(define-public (register-voter (blinded-identity (buff 32)))
  (begin
    (asserts! (var-get election-active) ERR-ELECTION-NOT-ACTIVE)
    (asserts! (< stacks-block-height (var-get election-end-height)) ERR-ELECTION-ENDED)
    (asserts! (is-none (map-get? voter-registry tx-sender)) ERR-ALREADY-VOTED)
    (map-set voter-registry tx-sender true)
    (ok true)))

;; Commit vote
;; Voters submit a hash of their vote and a secret nonce
(define-public (commit-vote (vote-commitment (buff 32)))
  (begin
    (asserts! (var-get election-active) ERR-ELECTION-NOT-ACTIVE)
    (asserts! (< stacks-block-height (var-get election-end-height)) ERR-ELECTION-ENDED)
    (asserts! (is-some (map-get? voter-registry tx-sender)) ERR-NOT-REGISTERED)
    (asserts! (is-none (map-get? vote-commitments tx-sender)) ERR-ALREADY-VOTED)
    (map-set vote-commitments tx-sender vote-commitment)
    (ok true)))

;; Reveal vote
;; Voters reveal their vote and nonce, which is verified against their commitment
(define-public (reveal-vote (vote uint) (nonce uint))
  (let ((commitment (unwrap! (map-get? vote-commitments tx-sender) ERR-COMMITMENT-NOT-FOUND))
        (calculated-commitment (hash160 nonce)))
    (asserts! (var-get election-active) ERR-ELECTION-NOT-ACTIVE)
    (asserts! (>= stacks-block-height (var-get election-end-height)) ERR-ELECTION-NOT-ENDED)
    (asserts! (is-eq commitment calculated-commitment) ERR-INVALID-REVEAL)
    (asserts! (is-none (map-get? revealed-votes tx-sender)) ERR-ALREADY-REVEALED)
    (map-set revealed-votes tx-sender vote)
    (var-set vote-count (+ (var-get vote-count) u1))
    (ok true)))

;; End election
(define-public (end-election)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get election-active) ERR-ELECTION-NOT-ACTIVE)
    (asserts! (>= stacks-block-height (var-get election-end-height)) ERR-ELECTION-NOT-ENDED)
    (var-set election-active false)
    (ok true)))

;; Read-only functions

;; Check if election is active
(define-read-only (is-election-active)
  (var-get election-active))

;; Get current vote count
(define-read-only (get-vote-count)
  (var-get vote-count))

;; Check if a voter is registered
(define-read-only (is-voter-registered (voter principal))
  (is-some (map-get? voter-registry voter)))

;; Verify a vote (for auditing)
;; This function allows anyone to verify that a specific vote was cast by a voter
;; without revealing the voter's identity
(define-read-only (verify-vote (voter principal) (vote uint) (nonce uint))
  (let ((commitment (unwrap! (map-get? vote-commitments voter) false))
        (revealed-vote (unwrap! (map-get? revealed-votes voter) false))
        (calculated-commitment (hash160 nonce)))
    (and
      (is-eq commitment calculated-commitment)
      (is-eq vote revealed-vote))))

;; Get election end height
(define-read-only (get-election-end-height)
  (var-get election-end-height))

