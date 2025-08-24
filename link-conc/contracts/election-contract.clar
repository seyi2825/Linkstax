;; Election Management Smart Contract
;; Handles creation and configuration of elections with transparent parameters

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ELECTION-NOT-FOUND (err u101))
(define-constant ERR-INVALID-DATES (err u102))
(define-constant ERR-INVALID-PARAMETERS (err u103))
(define-constant ERR-ELECTION-ALREADY-STARTED (err u104))

;; Election types
(define-constant ELECTION-TYPE-SINGLE-CHOICE u1)
(define-constant ELECTION-TYPE-MULTI-CHOICE u2)

;; Data structures
(define-map elections
  { election-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    creator: principal,
    election-type: uint,
    start-block: uint,
    end-block: uint,
    max-choices: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-map election-options
  { election-id: uint, option-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 300)
  }
)

(define-map eligible-voters
  { election-id: uint, voter: principal }
  { is-eligible: bool }
)

(define-map election-stats
  { election-id: uint }
  {
    total-options: uint,
    total-eligible-voters: uint,
    votes-cast: uint
  }
)

;; Global variables
(define-data-var next-election-id uint u1)

;; Public functions

;; Create a new election
(define-public (create-election 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (election-type uint)
  (start-block uint)
  (end-block uint)
  (max-choices uint)
  (options (list 20 { title: (string-ascii 100), description: (string-ascii 300) }))
  (eligible-voter-list (list 1000 principal))
)
  (let 
    (
      (election-id (var-get next-election-id))
      (current-block stacks-block-height)
    )
    ;; Validate parameters
    (asserts! (> (len title) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> end-block start-block) ERR-INVALID-DATES)
    (asserts! (>= start-block current-block) ERR-INVALID-DATES)
    (asserts! (or (is-eq election-type ELECTION-TYPE-SINGLE-CHOICE) 
                  (is-eq election-type ELECTION-TYPE-MULTI-CHOICE)) ERR-INVALID-PARAMETERS)
    (asserts! (> (len options) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len eligible-voter-list) u0) ERR-INVALID-PARAMETERS)
    
    ;; For multi-choice elections, validate max-choices
    (if (is-eq election-type ELECTION-TYPE-MULTI-CHOICE)
      (asserts! (and (> max-choices u0) (<= max-choices (len options))) ERR-INVALID-PARAMETERS)
      true
    )
    
    ;; Create the election
    (map-set elections
      { election-id: election-id }
      {
        title: title,
        description: description,
        creator: tx-sender,
        election-type: election-type,
        start-block: start-block,
        end-block: end-block,
        max-choices: (if (is-eq election-type ELECTION-TYPE-SINGLE-CHOICE) u1 max-choices),
        is-active: true,
        created-at: current-block
      }
    )
    
    ;; Add election options
    (try! (add-election-options election-id options))
    
    ;; Add eligible voters
    (try! (add-eligible-voters election-id eligible-voter-list))
    
    ;; Update stats
    (map-set election-stats
      { election-id: election-id }
      {
        total-options: (len options),
        total-eligible-voters: (len eligible-voter-list),
        votes-cast: u0
      }
    )
    
    ;; Increment election ID for next election
    (var-set next-election-id (+ election-id u1))
    
    (ok election-id)
  )
)

;; Update election parameters (only before start)
(define-public (update-election-parameters
  (election-id uint)
  (title (string-ascii 100))
  (description (string-ascii 500))
  (start-block uint)
  (end-block uint)
)
  (let 
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-ELECTION-NOT-FOUND))
      (current-block stacks-block-height)
    )
    ;; Only creator can update
    (asserts! (is-eq tx-sender (get creator election)) ERR-NOT-AUTHORIZED)
    
    ;; Can only update before election starts
    (asserts! (< current-block (get start-block election)) ERR-ELECTION-ALREADY-STARTED)
    
    ;; Validate new parameters
    (asserts! (> (len title) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> end-block start-block) ERR-INVALID-DATES)
    (asserts! (>= start-block current-block) ERR-INVALID-DATES)
    
    ;; Update election
    (map-set elections
      { election-id: election-id }
      (merge election {
        title: title,
        description: description,
        start-block: start-block,
        end-block: end-block
      })
    )
    
    (ok true)
  )
)

;; Add eligible voters to an election
(define-public (add-eligible-voters-to-election
  (election-id uint)
  (voter-list (list 1000 principal))
)
  (let 
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-ELECTION-NOT-FOUND))
      (current-block stacks-block-height)
    )
    ;; Only creator can add voters
    (asserts! (is-eq tx-sender (get creator election)) ERR-NOT-AUTHORIZED)
    
    ;; Can only add voters before election starts
    (asserts! (< current-block (get start-block election)) ERR-ELECTION-ALREADY-STARTED)
    
    ;; Add voters
    (try! (add-eligible-voters election-id voter-list))
    
    ;; Update stats
    (let 
      (
        (current-stats (default-to 
          { total-options: u0, total-eligible-voters: u0, votes-cast: u0 }
          (map-get? election-stats { election-id: election-id })
        ))
      )
      (map-set election-stats
        { election-id: election-id }
        (merge current-stats {
          total-eligible-voters: (+ (get total-eligible-voters current-stats) (len voter-list))
        })
      )
    )
    
    (ok true)
  )
)

;; Deactivate an election (only creator)
(define-public (deactivate-election (election-id uint))
  (let 
    (
      (election (unwrap! (map-get? elections { election-id: election-id }) ERR-ELECTION-NOT-FOUND))
    )
    ;; Only creator can deactivate
    (asserts! (is-eq tx-sender (get creator election)) ERR-NOT-AUTHORIZED)
    
    ;; Update election status
    (map-set elections
      { election-id: election-id }
      (merge election { is-active: false })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get election details
(define-read-only (get-election (election-id uint))
  (map-get? elections { election-id: election-id })
)

;; Get election options - Fixed version
(define-read-only (get-election-options (election-id uint))
  (match (map-get? election-stats { election-id: election-id })
    some-stats (build-options-list election-id (get total-options some-stats))
    (list)
  )
)

;; Check if voter is eligible
(define-read-only (is-voter-eligible (election-id uint) (voter principal))
  (default-to false 
    (get is-eligible 
      (map-get? eligible-voters { election-id: election-id, voter: voter })
    )
  )
)

;; Get election statistics
(define-read-only (get-election-stats (election-id uint))
  (map-get? election-stats { election-id: election-id })
)

;; Check if election is active and within voting period
(define-read-only (is-election-active (election-id uint))
  (match (map-get? elections { election-id: election-id })
    some-election 
      (and 
        (get is-active some-election)
        (>= stacks-block-height (get start-block some-election))
        (<= stacks-block-height (get end-block some-election))
      )
    false
  )
)

;; Get current election ID counter
(define-read-only (get-next-election-id)
  (var-get next-election-id)
)

;; Private functions

;; Helper function to add election options
(define-private (add-election-options 
  (election-id uint) 
  (options (list 20 { title: (string-ascii 100), description: (string-ascii 300) }))
)
  (let 
    (
      (result (fold add-single-option options { election-id: election-id, option-id: u0, success: true }))
    )
    (if (get success result)
      (ok true)
      (err u999)
    )
  )
)

;; Helper function to add a single option
(define-private (add-single-option 
  (option { title: (string-ascii 100), description: (string-ascii 300) })
  (acc { election-id: uint, option-id: uint, success: bool })
)
  (if (get success acc)
    (begin
      (map-set election-options
        { election-id: (get election-id acc), option-id: (get option-id acc) }
        option
      )
      {
        election-id: (get election-id acc),
        option-id: (+ (get option-id acc) u1),
        success: true
      }
    )
    acc
  )
)

;; Helper function to add eligible voters
(define-private (add-eligible-voters 
  (election-id uint) 
  (voters (list 1000 principal))
)
  (let 
    (
      (result (fold add-single-voter voters { election-id: election-id, success: true }))
    )
    (if (get success result)
      (ok true)
      (err u998)
    )
  )
)

;; Helper function to add a single voter
(define-private (add-single-voter 
  (voter principal)
  (acc { election-id: uint, success: bool })
)
  (if (get success acc)
    (begin
      (map-set eligible-voters
        { election-id: (get election-id acc), voter: voter }
        { is-eligible: true }
      )
      acc
    )
    acc
  )
)

;; Helper function to build options list iteratively
(define-private (build-options-list (election-id uint) (total-options uint))
  (let 
    (
      (option-0 (map-get? election-options { election-id: election-id, option-id: u0 }))
      (option-1 (map-get? election-options { election-id: election-id, option-id: u1 }))
      (option-2 (map-get? election-options { election-id: election-id, option-id: u2 }))
      (option-3 (map-get? election-options { election-id: election-id, option-id: u3 }))
      (option-4 (map-get? election-options { election-id: election-id, option-id: u4 }))
      (option-5 (map-get? election-options { election-id: election-id, option-id: u5 }))
      (option-6 (map-get? election-options { election-id: election-id, option-id: u6 }))
      (option-7 (map-get? election-options { election-id: election-id, option-id: u7 }))
      (option-8 (map-get? election-options { election-id: election-id, option-id: u8 }))
      (option-9 (map-get? election-options { election-id: election-id, option-id: u9 }))
      (option-10 (map-get? election-options { election-id: election-id, option-id: u10 }))
      (option-11 (map-get? election-options { election-id: election-id, option-id: u11 }))
      (option-12 (map-get? election-options { election-id: election-id, option-id: u12 }))
      (option-13 (map-get? election-options { election-id: election-id, option-id: u13 }))
      (option-14 (map-get? election-options { election-id: election-id, option-id: u14 }))
      (option-15 (map-get? election-options { election-id: election-id, option-id: u15 }))
      (option-16 (map-get? election-options { election-id: election-id, option-id: u16 }))
      (option-17 (map-get? election-options { election-id: election-id, option-id: u17 }))
      (option-18 (map-get? election-options { election-id: election-id, option-id: u18 }))
      (option-19 (map-get? election-options { election-id: election-id, option-id: u19 }))
    )
    (if (<= total-options u1)
      (list option-0)
      (if (<= total-options u2)
        (list option-0 option-1)
        (if (<= total-options u3)
          (list option-0 option-1 option-2)
          (if (<= total-options u4)
            (list option-0 option-1 option-2 option-3)
            (if (<= total-options u5)
              (list option-0 option-1 option-2 option-3 option-4)
              (if (<= total-options u10)
                (list option-0 option-1 option-2 option-3 option-4 option-5 option-6 option-7 option-8 option-9)
                (if (<= total-options u15)
                  (list option-0 option-1 option-2 option-3 option-4 option-5 option-6 option-7 option-8 option-9 option-10 option-11 option-12 option-13 option-14)
                  (list option-0 option-1 option-2 option-3 option-4 option-5 option-6 option-7 option-8 option-9 option-10 option-11 option-12 option-13 option-14 option-15 option-16 option-17 option-18 option-19)
                )
              )
            )
          )
        )
      )
    )
  )
)