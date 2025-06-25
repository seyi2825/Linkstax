;; Vote Validation Smart Contract
;; This contract handles voter registration, eligibility validation, and vote casting
;; with comprehensive security measures to prevent manipulation and ensure one vote per person

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-already-voted (err u102))
(define-constant err-voting-not-active (err u103))
(define-constant err-invalid-candidate (err u104))
(define-constant err-already-registered (err u105))
(define-constant err-self-registration-only (err u106))

;; Voting session status
(define-data-var voting-active bool false)
(define-data-var registration-active bool true)

;; Data structures
;; Registered voters map: principal -> registration info
(define-map registered-voters 
    principal 
    {
        registered-at: uint,
        is-eligible: bool
    }
)

;; Voting record map: principal -> vote info
(define-map vote-records 
    principal 
    {
        candidate-id: uint,
        voted-at: uint,
        block-height: uint
    }
)

;; Valid candidates map: candidate-id -> candidate info
(define-map valid-candidates 
    uint 
    {
        name: (string-ascii 64),
        active: bool
    }
)

;; Vote counts map: candidate-id -> vote count
(define-map vote-counts uint uint)

;; Total registered voters counter
(define-data-var total-registered uint u0)

;; Total votes cast counter
(define-data-var total-votes-cast uint u0)

;; Public functions

;; Register a voter (can only register themselves)
(define-public (register-voter)
    (begin
        (asserts! (var-get registration-active) err-voting-not-active)
        (asserts! (is-none (map-get? registered-voters tx-sender)) err-already-registered)
        
        ;; Register the voter
        (map-set registered-voters tx-sender {
            registered-at: stacks-block-height,
            is-eligible: true
        })
        
        ;; Increment total registered counter
        (var-set total-registered (+ (var-get total-registered) u1))
        
        (ok true)
    )
)

;; Cast a vote with full validation
(define-public (cast-vote (candidate-id uint))
    (let (
        (voter-info (map-get? registered-voters tx-sender))
        (existing-vote (map-get? vote-records tx-sender))
        (candidate-info (map-get? valid-candidates candidate-id))
        (current-vote-count (default-to u0 (map-get? vote-counts candidate-id)))
    )
        ;; Validation checks
        (asserts! (var-get voting-active) err-voting-not-active)
        (asserts! (is-some voter-info) err-not-registered)
        (asserts! (is-none existing-vote) err-already-voted)
        (asserts! (is-some candidate-info) err-invalid-candidate)
        
        ;; Additional eligibility check
        (asserts! (get is-eligible (unwrap-panic voter-info)) err-not-registered)
        
        ;; Record the vote
        (map-set vote-records tx-sender {
            candidate-id: candidate-id,
            voted-at: stacks-block-height,
            block-height: stacks-block-height
        })
        
        ;; Update vote count for the candidate
        (map-set vote-counts candidate-id (+ current-vote-count u1))
        
        ;; Increment total votes cast
        (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
        
        (ok true)
    )
)

;; Admin functions (owner only)

;; Add a valid candidate
(define-public (add-candidate (candidate-id uint) (name (string-ascii 64)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set valid-candidates candidate-id {
            name: name,
            active: true
        })
        
        ;; Initialize vote count to 0
        (map-set vote-counts candidate-id u0)
        
        (ok true)
    )
)

;; Start voting session
(define-public (start-voting)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set voting-active true)
        (var-set registration-active false)
        (ok true)
    )
)

;; Stop voting session
(define-public (stop-voting)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set voting-active false)
        (ok true)
    )
)

;; Enable/disable voter registration
(define-public (toggle-registration (active bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set registration-active active)
        (ok true)
    )
)

;; Revoke voter eligibility (for security purposes)
(define-public (revoke-voter-eligibility (voter principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (match (map-get? registered-voters voter)
            voter-info (map-set registered-voters voter 
                           (merge voter-info { is-eligible: false }))
            false
        )
        
        (ok true)
    )
)

;; Read-only functions

;; Check if a voter is registered and eligible
(define-read-only (is-voter-eligible (voter principal))
    (match (map-get? registered-voters voter)
        voter-info (get is-eligible voter-info)
        false
    )
)

;; Check if a voter has already voted
(define-read-only (has-voter-voted (voter principal))
    (is-some (map-get? vote-records voter))
)

;; Get voter registration info
(define-read-only (get-voter-info (voter principal))
    (map-get? registered-voters voter)
)

;; Get vote record for a voter
(define-read-only (get-vote-record (voter principal))
    (map-get? vote-records voter)
)

;; Get candidate information
(define-read-only (get-candidate-info (candidate-id uint))
    (map-get? valid-candidates candidate-id)
)

;; Get vote count for a candidate
(define-read-only (get-vote-count (candidate-id uint))
    (default-to u0 (map-get? vote-counts candidate-id))
)

;; Get voting session status
(define-read-only (get-voting-status)
    {
        voting-active: (var-get voting-active),
        registration-active: (var-get registration-active),
        total-registered: (var-get total-registered),
        total-votes-cast: (var-get total-votes-cast)
    }
)

;; Comprehensive validation function for vote casting
(define-read-only (validate-vote-eligibility (voter principal) (candidate-id uint))
    (let (
        (voter-info (map-get? registered-voters voter))
        (existing-vote (map-get? vote-records voter))
        (candidate-info (map-get? valid-candidates candidate-id))
    )
        {
            is-registered: (is-some voter-info),
            is-eligible: (match voter-info 
                         info (get is-eligible info) 
                         false),
            has-voted: (is-some existing-vote),
            voting-active: (var-get voting-active),
            valid-candidate: (is-some candidate-info),
            can-vote: (and 
                      (var-get voting-active)
                      (is-some voter-info)
                      (match voter-info info (get is-eligible info) false)
                      (is-none existing-vote)
                      (is-some candidate-info))
        }
    )
)

;; Get comprehensive voting statistics
(define-read-only (get-voting-statistics)
    {
        total-registered-voters: (var-get total-registered),
        total-votes-cast: (var-get total-votes-cast),
        voter-turnout-percentage: (if (> (var-get total-registered) u0)
                                   (/ (* (var-get total-votes-cast) u100) (var-get total-registered))
                                   u0),
        voting-active: (var-get voting-active),
        registration-active: (var-get registration-active)
    }
)