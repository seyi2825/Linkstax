;; Election Manager Smart Contract
;; Handles creation and configuration of elections with transparent parameters

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_ELECTION_ID (err u101))
(define-constant ERR_INVALID_DURATION (err u102))
(define-constant ERR_INVALID_DATES (err u103))
(define-constant ERR_ELECTION_EXISTS (err u104))
(define-constant ERR_INVALID_VOTING_OPTIONS (err u105))
(define-constant ERR_INVALID_ELECTION_TYPE (err u106))

;; Election types
(define-constant ELECTION_TYPE_SINGLE_CHOICE u1)
(define-constant ELECTION_TYPE_MULTI_CHOICE u2)

;; Data Variables
(define-data-var next-election-id uint u1)
(define-data-var total-elections uint u0)

;; Election data structure
(define-map elections
  { election-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    election-type: uint,
    start-block: uint,
    end-block: uint,
    voting-options: (list 20 (string-ascii 100)),
    max-choices: uint,
    eligible-voters: (list 100 principal),
    is-public: bool,
    created-at: uint,
    is-active: bool
  }
)

;; Election metadata for additional configuration
(define-map election-metadata
  { election-id: uint }
  {
    minimum-participation: uint,
    require-registration: bool,
    allow-vote-changes: bool,
    results-visibility: uint, ;; 1: immediate, 2: after-end, 3: manual-reveal
    voting-power-equal: bool
  }
)

;; Authorized election creators
(define-map authorized-creators
  { creator: principal }
  { authorized: bool }
)

;; Election statistics
(define-map election-stats
  { election-id: uint }
  {
    total-votes: uint,
    unique-voters: uint,
    participation-rate: uint
  }
)

;; Private Functions

;; Validate election dates
(define-private (is-valid-election-period (start-block uint) (end-block uint))
  (and 
    (> start-block stacks-block-height)
    (> end-block start-block)
    (>= (- end-block start-block) u144) ;; Minimum 1 day (144 blocks)
  )
)

;; Validate voting options
(define-private (is-valid-voting-options (options (list 20 (string-ascii 100))))
  (and 
    (>= (len options) u2) ;; At least 2 options
    (<= (len options) u20) ;; Maximum 20 options
  )
)

;; Validate election type
(define-private (is-valid-election-type (election-type uint))
  (or 
    (is-eq election-type ELECTION_TYPE_SINGLE_CHOICE)
    (is-eq election-type ELECTION_TYPE_MULTI_CHOICE)
  )
)

;; Check if caller is authorized to create elections
(define-private (is-authorized-creator (creator principal))
  (or 
    (is-eq creator CONTRACT_OWNER)
    (default-to false (get authorized (map-get? authorized-creators { creator: creator })))
  )
)

;; Public Functions

;; Create a new election
(define-public (create-election 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (election-type uint)
  (start-block uint)
  (end-block uint)
  (voting-options (list 20 (string-ascii 100)))
  (max-choices uint)
  (eligible-voters (list 100 principal))
  (is-public bool)
)
  (let 
    (
      (election-id (var-get next-election-id))
      (current-block stacks-block-height)
    )
    ;; Validate inputs
    (asserts! (is-authorized-creator tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-valid-election-period start-block end-block) ERR_INVALID_DATES)
    (asserts! (is-valid-voting-options voting-options) ERR_INVALID_VOTING_OPTIONS)
    (asserts! (is-valid-election-type election-type) ERR_INVALID_ELECTION_TYPE)
    (asserts! (is-none (map-get? elections { election-id: election-id })) ERR_ELECTION_EXISTS)
    
    ;; Validate max-choices based on election type
    (asserts! 
      (if (is-eq election-type ELECTION_TYPE_SINGLE_CHOICE)
        (is-eq max-choices u1)
        (and (>= max-choices u1) (<= max-choices (len voting-options)))
      ) 
      ERR_INVALID_ELECTION_TYPE
    )
    
    ;; Store election data
    (map-set elections
      { election-id: election-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        election-type: election-type,
        start-block: start-block,
        end-block: end-block,
        voting-options: voting-options,
        max-choices: max-choices,
        eligible-voters: eligible-voters,
        is-public: is-public,
        created-at: current-block,
        is-active: true
      }
    )
    
    ;; Initialize election statistics
    (map-set election-stats
      { election-id: election-id }
      {
        total-votes: u0,
        unique-voters: u0,
        participation-rate: u0
      }
    )
    
    ;; Update counters
    (var-set next-election-id (+ election-id u1))
    (var-set total-elections (+ (var-get total-elections) u1))
    
    (ok election-id)
  )
)

;; Configure additional election metadata
(define-public (configure-election-metadata
  (election-id uint)
  (minimum-participation uint)
  (require-registration bool)
  (allow-vote-changes bool)
  (results-visibility uint)
  (voting-power-equal bool)
)
  (let 
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR_INVALID_ELECTION_ID))
    )
    ;; Only election creator can configure metadata
    (asserts! (is-eq tx-sender (get creator election)) ERR_UNAUTHORIZED)
    
    ;; Store metadata
    (map-set election-metadata
      { election-id: election-id }
      {
        minimum-participation: minimum-participation,
        require-registration: require-registration,
        allow-vote-changes: allow-vote-changes,
        results-visibility: results-visibility,
        voting-power-equal: voting-power-equal
      }
    )
    
    (ok true)
  )
)

;; Authorize a new election creator
(define-public (authorize-creator (creator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-creators { creator: creator } { authorized: true })
    (ok true)
  )
)

;; Revoke election creator authorization
(define-public (revoke-creator-authorization (creator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set authorized-creators { creator: creator } { authorized: false })
    (ok true)
  )
)

;; Deactivate an election (only by creator or contract owner)
(define-public (deactivate-election (election-id uint))
  (let 
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR_INVALID_ELECTION_ID))
    )
    (asserts! 
      (or 
        (is-eq tx-sender (get creator election))
        (is-eq tx-sender CONTRACT_OWNER)
      ) 
      ERR_UNAUTHORIZED
    )
    
    (map-set elections
      { election-id: election-id }
      (merge election { is-active: false })
    )
    
    (ok true)
  )
)

;; Read-only Functions (Transparent access to election parameters)

;; Get election details
(define-read-only (get-election (election-id uint))
  (map-get? elections { election-id: election-id })
)

;; Get election metadata
(define-read-only (get-election-metadata (election-id uint))
  (map-get? election-metadata { election-id: election-id })
)

;; Get election statistics
(define-read-only (get-election-stats (election-id uint))
  (map-get? election-stats { election-id: election-id })
)

;; Get all election IDs (for transparency)
(define-read-only (get-total-elections)
  (var-get total-elections)
)

;; Check if election is active and within voting period
(define-read-only (is-election-active (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election 
    (and 
      (get is-active election)
      (>= stacks-block-height (get start-block election))
      (<= stacks-block-height (get end-block election))
    )
    false
  )
)

;; Check if election is in setup phase (before start)
(define-read-only (is-election-in-setup (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election 
    (and 
      (get is-active election)
      (< stacks-block-height (get start-block election))
    )
    false
  )
)

;; Check if election has ended
(define-read-only (has-election-ended (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election (> stacks-block-height (get end-block election))
    false
  )
)

;; Get election type description
(define-read-only (get-election-type-description (election-type uint))
  (if (is-eq election-type ELECTION_TYPE_SINGLE_CHOICE)
    "Single Choice"
    (if (is-eq election-type ELECTION_TYPE_MULTI_CHOICE)
      "Multi Choice"
      "Unknown"
    )
  )
)

;; Check if a principal is eligible to vote
(define-read-only (is-eligible-voter (election-id uint) (voter principal))
  (match (map-get? elections { election-id: election-id })
    election 
    (or 
      (get is-public election)
      (is-some (index-of (get eligible-voters election) voter))
    )
    false
  )
)

;; Get election voting options
(define-read-only (get-voting-options (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election (some (get voting-options election))
    none
  )
)

;; Check if creator is authorized
(define-read-only (is-creator-authorized (creator principal))
  (is-authorized-creator creator)
)

;; Get election duration in blocks
(define-read-only (get-election-duration (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election (some (- (get end-block election) (get start-block election)))
    none
  )
)

;; Get remaining time for election (in blocks)
(define-read-only (get-remaining-time (election-id uint))
  (match (map-get? elections { election-id: election-id })
    election 
    (if (<= stacks-block-height (get end-block election))
      (some (- (get end-block election) stacks-block-height))
      (some u0)
    )
    none
  )
)
