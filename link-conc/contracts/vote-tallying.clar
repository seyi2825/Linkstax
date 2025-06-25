;; Vote Tallying Smart Contract
;; Automated, transparent vote tallying system

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-election-not-active (err u104))
(define-constant err-election-ended (err u105))
(define-constant err-election-not-ended (err u106))
(define-constant err-invalid-candidate (err u107))
(define-constant err-results-already-tallied (err u108))

;; Data Variables
(define-data-var election-active bool false)
(define-data-var election-end-block uint u0)
(define-data-var total-votes uint u0)
(define-data-var results-tallied bool false)
(define-data-var winning-candidate uint u0)
(define-data-var winning-vote-count uint u0)

;; Data Maps
(define-map candidates uint {
    name: (string-ascii 50),
    vote-count: uint,
    active: bool
})

(define-map voters principal {
    has-voted: bool,
    vote-block: uint,
    candidate-id: uint
})

(define-map election-results uint {
    candidate-id: uint,
    final-vote-count: uint,
    percentage: uint,
    rank: uint
})

;; Read-only functions

;; Get candidate information
(define-read-only (get-candidate (candidate-id uint))
    (map-get? candidates candidate-id)
)

;; Get voter information
(define-read-only (get-voter-info (voter principal))
    (map-get? voters voter)
)

;; Check if election is active
(define-read-only (is-election-active)
    (and 
        (var-get election-active)
        (< stacks-block-height (var-get election-end-block))
    )
)

;; Check if election has ended
(define-read-only (has-election-ended)
    (and 
        (var-get election-active)
        (>= stacks-block-height (var-get election-end-block))
    )
)

;; Get election status
(define-read-only (get-election-status)
    {
        active: (var-get election-active),
        end-block: (var-get election-end-block),
        current-block: stacks-block-height,
        total-votes: (var-get total-votes),
        results-tallied: (var-get results-tallied),
        winner: (var-get winning-candidate),
        winning-votes: (var-get winning-vote-count)
    }
)

;; Get final results
(define-read-only (get-election-results (candidate-id uint))
    (map-get? election-results candidate-id)
)

;; Get all candidate vote counts (for transparency)
(define-read-only (get-candidate-votes (candidate-id uint))
    (match (map-get? candidates candidate-id)
        candidate (get vote-count candidate)
        u0
    )
)

;; Public functions

;; Initialize election (owner only)
(define-public (start-election (duration-blocks uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (var-get election-active)) err-election-not-active)
        
        (var-set election-active true)
        (var-set election-end-block (+ stacks-block-height duration-blocks))
        (var-set total-votes u0)
        (var-set results-tallied false)
        (var-set winning-candidate u0)
        (var-set winning-vote-count u0)
        
        (ok true)
    )
)

;; Add candidate (owner only, before election starts)
(define-public (add-candidate (candidate-id uint) (name (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (var-get election-active)) err-election-not-active)
        
        (map-set candidates candidate-id {
            name: name,
            vote-count: u0,
            active: true
        })
        
        (ok true)
    )
)

;; Cast vote
(define-public (cast-vote (candidate-id uint))
    (let (
        (voter-info (default-to {has-voted: false, vote-block: u0, candidate-id: u0} 
                                (map-get? voters tx-sender)))
        (candidate-info (map-get? candidates candidate-id))
    )
        ;; Validation checks
        (asserts! (is-election-active) err-election-not-active)
        (asserts! (not (get has-voted voter-info)) err-already-voted)
        (asserts! (is-some candidate-info) err-invalid-candidate)
        (asserts! (get active (unwrap-panic candidate-info)) err-invalid-candidate)
        
        ;; Record vote
        (map-set voters tx-sender {
            has-voted: true,
            vote-block: stacks-block-height,
            candidate-id: candidate-id
        })
        
        ;; Update candidate vote count
        (map-set candidates candidate-id 
            (merge (unwrap-panic candidate-info) 
                   {vote-count: (+ (get vote-count (unwrap-panic candidate-info)) u1)}))
        
        ;; Update total votes
        (var-set total-votes (+ (var-get total-votes) u1))
        
        (ok true)
    )
)

;; Tally votes (automated when election ends)
(define-public (tally-votes-alternative)
    (begin
        (asserts! (has-election-ended) err-election-not-ended)
        (asserts! (not (var-get results-tallied)) err-results-already-tallied)
        
        ;; Process results for each candidate with proper error handling
        (unwrap! (process-candidate-results-safe u1) err-not-found)
        (unwrap! (process-candidate-results-safe u2) err-not-found)
        (unwrap! (process-candidate-results-safe u3) err-not-found)
        (unwrap! (process-candidate-results-safe u4) err-not-found)
        (unwrap! (process-candidate-results-safe u5) err-not-found)
        
        ;; Find winner
        (unwrap! (determine-winner-safe) err-not-found)
        
        ;; Mark results as tallied
        (var-set results-tallied true)
        
        (ok true)
    )
)

;; Private functions

;; Process individual candidate results
(define-private (process-candidate-results (candidate-id uint))
    (match (map-get? candidates candidate-id)
        candidate-info 
        (let (
            (vote-count (get vote-count candidate-info))
            (total (var-get total-votes))
            (percentage (if (> total u0) 
                           (/ (* vote-count u100) total) 
                           u0))
        )
            (map-set election-results candidate-id {
                candidate-id: candidate-id,
                final-vote-count: vote-count,
                percentage: percentage,
                rank: u0  ;; Will be calculated separately
            })
            (ok true)
        )
        (ok true)  ;; Skip if candidate doesn't exist
    )
)

;; Determine winner (simplified - checks first 5 candidates)
(define-private (determine-winner)
    (let (
        (candidate-1-votes (get-candidate-votes u1))
        (candidate-2-votes (get-candidate-votes u2))
        (candidate-3-votes (get-candidate-votes u3))
        (candidate-4-votes (get-candidate-votes u4))
        (candidate-5-votes (get-candidate-votes u5))
        (max-votes (fold max-votes-fold 
                        (list candidate-1-votes candidate-2-votes candidate-3-votes 
                              candidate-4-votes candidate-5-votes) 
                        u0))
    )
        (var-set winning-vote-count max-votes)
        
        ;; Determine which candidate has max votes
        (if (is-eq candidate-1-votes max-votes)
            (var-set winning-candidate u1)
            (if (is-eq candidate-2-votes max-votes)
                (var-set winning-candidate u2)
                (if (is-eq candidate-3-votes max-votes)
                    (var-set winning-candidate u3)
                    (if (is-eq candidate-4-votes max-votes)
                        (var-set winning-candidate u4)
                        (var-set winning-candidate u5)
                    )
                )
            )
        )
        
        (ok true)
    )
)

;; Helper function for finding maximum votes
(define-private (max-votes-fold (current uint) (max-so-far uint))
    (if (> current max-so-far) current max-so-far)
)

;; Emergency functions (owner only)

;; End election early
(define-public (end-election-early)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (var-get election-active) err-election-not-active)
        
        (var-set election-end-block stacks-block-height)
        
        (ok true)
    )
)

;; Get comprehensive election audit trail
(define-read-only (get-audit-trail)
    {
        election-active: (var-get election-active),
        election-end-block: (var-get election-end-block),
        total-votes: (var-get total-votes),
        results-tallied: (var-get results-tallied),
        winning-candidate: (var-get winning-candidate),
        winning-vote-count: (var-get winning-vote-count),
        current-block: stacks-block-height,
        contract-owner: contract-owner
    }
)


;; Updated private functions that can return errors
(define-private (process-candidate-results-safe (candidate-id uint))
    (match (map-get? candidates candidate-id)
        candidate-info 
        (let (
            (vote-count (get vote-count candidate-info))
            (total (var-get total-votes))
            (percentage (if (> total u0) 
                           (/ (* vote-count u100) total) 
                           u0))
        )
            (map-set election-results candidate-id {
                candidate-id: candidate-id,
                final-vote-count: vote-count,
                percentage: percentage,
                rank: u0
            })
            (ok true)
        )
        err-not-found  ;; Return error if candidate doesn't exist
    )
)

(define-private (determine-winner-safe)
    (let (
        (candidate-1-votes (get-candidate-votes u1))
        (candidate-2-votes (get-candidate-votes u2))
        (candidate-3-votes (get-candidate-votes u3))
        (candidate-4-votes (get-candidate-votes u4))
        (candidate-5-votes (get-candidate-votes u5))
        (max-votes (fold max-votes-fold 
                        (list candidate-1-votes candidate-2-votes candidate-3-votes 
                              candidate-4-votes candidate-5-votes) 
                        u0))
    )
        ;; Only proceed if there are actual votes
        (asserts! (> max-votes u0) err-not-found)
        
        (var-set winning-vote-count max-votes)
        
        ;; Determine which candidate has max votes
        (if (is-eq candidate-1-votes max-votes)
            (var-set winning-candidate u1)
            (if (is-eq candidate-2-votes max-votes)
                (var-set winning-candidate u2)
                (if (is-eq candidate-3-votes max-votes)
                    (var-set winning-candidate u3)
                    (if (is-eq candidate-4-votes max-votes)
                        (var-set winning-candidate u4)
                        (var-set winning-candidate u5)
                    )
                )
            )
        )
        
        (ok true)
    )
)

;; Even better approach: Dynamic candidate processing
(define-public (tally-votes-dynamic)
    (begin
        (asserts! (has-election-ended) err-election-not-ended)
        (asserts! (not (var-get results-tallied)) err-results-already-tallied)
        
        ;; Process all candidates dynamically
        (let (
            (total-votes-cast (var-get total-votes))
            (candidate-ids (list u1 u2 u3 u4 u5))  ;; In practice, this would be dynamic
        )
            ;; Process each candidate
            (map process-candidate-with-total candidate-ids)
            
            ;; Find winner from all candidates
            (determine-winner-from-candidates candidate-ids)
            
            ;; Mark results as tallied
            (var-set results-tallied true)
            
            (ok true)
        )
    )
)

;; Helper function for dynamic processing
(define-private (process-candidate-with-total (candidate-id uint))
    (match (map-get? candidates candidate-id)
        candidate-info 
        (let (
            (vote-count (get vote-count candidate-info))
            (total (var-get total-votes))
            (percentage (if (> total u0) 
                           (/ (* vote-count u100) total) 
                           u0))
        )
            (map-set election-results candidate-id {
                candidate-id: candidate-id,
                final-vote-count: vote-count,
                percentage: percentage,
                rank: u0
            })
        )
        false  ;; Return false if candidate doesn't exist
    )
)

;; Helper function to determine winner from a list of candidates
(define-private (determine-winner-from-candidates (candidate-ids (list 5 uint)))
    (let (
        (vote-counts (map get-candidate-votes candidate-ids))
        (max-votes (fold max-votes-fold vote-counts u0))
        (winner-id (find-candidate-with-votes candidate-ids max-votes))
    )
        (var-set winning-vote-count max-votes)
        (var-set winning-candidate winner-id)
    )
)

;; Helper to find candidate ID with specific vote count
(define-private (find-candidate-with-votes (candidate-ids (list 5 uint)) (target-votes uint))
    (fold find-winner-fold candidate-ids u0)
)

;; Fold function to find winner
(define-private (find-winner-fold (candidate-id uint) (current-winner uint))
    (if (and (is-eq current-winner u0) 
             (is-eq (get-candidate-votes candidate-id) (var-get winning-vote-count)))
        candidate-id
        current-winner
    )
)