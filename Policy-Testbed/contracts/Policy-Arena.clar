;; Decentralized Policy Simulation Smart Contract
;; This contract enables creation, voting, and simulation of policy proposals

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POLICY-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-VOTING-CLOSED (err u103))
(define-constant ERR-INSUFFICIENT-STAKE (err u104))
(define-constant ERR-SIMULATION-NOT-FOUND (err u105))
(define-constant ERR-INVALID-PARAMETERS (err u106))

;; Minimum stake required to create a policy proposal
(define-constant MIN-STAKE u1000000) ;; 1 STX in microSTX

;; Policy status constants
(define-constant POLICY-ACTIVE u1)
(define-constant POLICY-PASSED u2)
(define-constant POLICY-REJECTED u3)
(define-constant POLICY-EXECUTED u4)

;; Data Variables
(define-data-var policy-counter uint u0)
(define-data-var simulation-counter uint u0)
(define-data-var governance-token principal tx-sender)

;; Policy Structure
(define-map policies 
  uint 
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    voting-start: uint,
    voting-end: uint,
    yes-votes: uint,
    no-votes: uint,
    status: uint,
    execution-block: (optional uint),
    stake-amount: uint
  }
)

;; Voting records
(define-map votes 
  {policy-id: uint, voter: principal} 
  {vote: bool, voting-power: uint, timestamp: uint}
)

;; Policy simulations
(define-map simulations 
  uint 
  {
    policy-id: uint,
    simulator: principal,
    parameters: (string-ascii 200),
    results: (string-ascii 300),
    economic-impact: int,
    social-impact: int,
    environmental-impact: int,
    timestamp: uint
  }
)

;; Voter registry and reputation
(define-map voter-registry 
  principal 
  {
    reputation: uint,
    total-votes: uint,
    correct-predictions: uint,
    stake-balance: uint
  }
)

;; Policy categories and their weights
(define-map category-weights 
  (string-ascii 50) 
  uint
)

;; Read-only functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
  (map-get? policies policy-id)
)

;; Get vote details
(define-read-only (get-vote (policy-id uint) (voter principal))
  (map-get? votes {policy-id: policy-id, voter: voter})
)

;; Get simulation details
(define-read-only (get-simulation (simulation-id uint))
  (map-get? simulations simulation-id)
)

;; Get voter reputation
(define-read-only (get-voter-info (voter principal))
  (map-get? voter-registry voter)
)

;; Get current policy counter
(define-read-only (get-policy-counter)
  (var-get policy-counter)
)

;; Get current simulation counter
(define-read-only (get-simulation-counter)
  (var-get simulation-counter)
)

;; Check if voting is active for a policy
(define-read-only (is-voting-active (policy-id uint))
  (match (map-get? policies policy-id)
    policy-data 
    (let ((current-block block-height))
      (and 
        (>= current-block (get voting-start policy-data))
        (<= current-block (get voting-end policy-data))
        (is-eq (get status policy-data) POLICY-ACTIVE)
      )
    )
    false
  )
)

;; Calculate voting power based on stake and reputation
(define-read-only (calculate-voting-power (voter principal) (stake-amount uint))
  (match (map-get? voter-registry voter)
    voter-info
    (let ((reputation (get reputation voter-info)))
      (+ stake-amount (* reputation u100))
    )
    stake-amount
  )
)

;; Public functions

;; Initialize category weights (only contract owner)
(define-public (initialize-categories)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set category-weights "economic" u100)
    (map-set category-weights "social" u80)
    (map-set category-weights "environmental" u90)
    (map-set category-weights "governance" u110)
    (map-set category-weights "infrastructure" u95)
    (ok true)
  )
)

;; Create a new policy proposal
(define-public (create-policy 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (category (string-ascii 50))
    (voting-duration uint)
    (stake-amount uint)
  )
  (let (
    (policy-id (+ (var-get policy-counter) u1))
    (voting-start (+ block-height u10)) ;; Start voting after 10 blocks
    (voting-end (+ voting-start voting-duration))
  )
    ;; Validate inputs
    (asserts! (>= stake-amount MIN-STAKE) ERR-INSUFFICIENT-STAKE)
    (asserts! (> voting-duration u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len title) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len description) u0) ERR-INVALID-PARAMETERS)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Create policy
    (map-set policies policy-id {
      creator: tx-sender,
      title: title,
      description: description,
      category: category,
      voting-start: voting-start,
      voting-end: voting-end,
      yes-votes: u0,
      no-votes: u0,
      status: POLICY-ACTIVE,
      execution-block: none,
      stake-amount: stake-amount
    })
    
    ;; Update policy counter
    (var-set policy-counter policy-id)
    
    ;; Update voter registry
    (update-voter-registry tx-sender u0 u0)
    
    (ok policy-id)
  )
)

;; Vote on a policy
(define-public (vote-on-policy 
    (policy-id uint) 
    (vote bool) 
    (stake-amount uint)
  )
  (let (
    (policy-data (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND))
    (voting-power (calculate-voting-power tx-sender stake-amount))
  )
    ;; Check if voting is active
    (asserts! (is-voting-active policy-id) ERR-VOTING-CLOSED)
    
    ;; Check if user hasn't voted already
    (asserts! (is-none (map-get? votes {policy-id: policy-id, voter: tx-sender})) ERR-ALREADY-VOTED)
    
    ;; Validate stake amount
    (asserts! (> stake-amount u0) ERR-INVALID-PARAMETERS)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Record vote
    (map-set votes {policy-id: policy-id, voter: tx-sender} {
      vote: vote,
      voting-power: voting-power,
      timestamp: block-height
    })
    
    ;; Update policy vote counts
    (if vote
      (map-set policies policy-id 
        (merge policy-data {yes-votes: (+ (get yes-votes policy-data) voting-power)})
      )
      (map-set policies policy-id 
        (merge policy-data {no-votes: (+ (get no-votes policy-data) voting-power)})
      )
    )
    
    ;; Update voter registry
    (update-voter-registry tx-sender u1 u0)
    
    (ok true)
  )
)

;; Finalize voting and determine outcome
(define-public (finalize-policy (policy-id uint))
  (let (
    (policy-data (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND))
    (yes-votes (get yes-votes policy-data))
    (no-votes (get no-votes policy-data))
  )
    ;; Check if voting period has ended
    (asserts! (> block-height (get voting-end policy-data)) ERR-VOTING-CLOSED)
    (asserts! (is-eq (get status policy-data) POLICY-ACTIVE) ERR-NOT-AUTHORIZED)
    
    ;; Determine outcome
    (let ((new-status (if (> yes-votes no-votes) POLICY-PASSED POLICY-REJECTED)))
      (map-set policies policy-id 
        (merge policy-data {status: new-status})
      )
      
      ;; Return stake to creator if policy passed
      (if (is-eq new-status POLICY-PASSED)
        (try! (as-contract (stx-transfer? (get stake-amount policy-data) 
                                        tx-sender 
                                        (get creator policy-data))))
        true
      )
      
      (ok new-status)
    )
  )
)

;; Create a policy simulation
(define-public (create-simulation
    (policy-id uint)
    (parameters (string-ascii 200))
    (results (string-ascii 300))
    (economic-impact int)
    (social-impact int)
    (environmental-impact int)
  )
  (let ((simulation-id (+ (var-get simulation-counter) u1)))
    ;; Validate policy exists
    (asserts! (is-some (map-get? policies policy-id)) ERR-POLICY-NOT-FOUND)
    
    ;; Validate inputs
    (asserts! (> (len parameters) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len results) u0) ERR-INVALID-PARAMETERS)
    
    ;; Create simulation
    (map-set simulations simulation-id {
      policy-id: policy-id,
      simulator: tx-sender,
      parameters: parameters,
      results: results,
      economic-impact: economic-impact,
      social-impact: social-impact,
      environmental-impact: environmental-impact,
      timestamp: block-height
    })
    
    ;; Update simulation counter
    (var-set simulation-counter simulation-id)
    
    ;; Update voter registry (simulation counts as participation)
    (update-voter-registry tx-sender u0 u0)
    
    (ok simulation-id)
  )
)

;; Execute a passed policy (placeholder for actual execution logic)
(define-public (execute-policy (policy-id uint))
  (let ((policy-data (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND)))
    ;; Check if policy has passed
    (asserts! (is-eq (get status policy-data) POLICY-PASSED) ERR-NOT-AUTHORIZED)
    
    ;; Mark as executed
    (map-set policies policy-id 
      (merge policy-data {
        status: POLICY-EXECUTED,
        execution-block: (some block-height)
      })
    )
    
    ;; Reward accurate voters (simplified logic)
    ;; In a full implementation, this would analyze prediction accuracy
    
    (ok true)
  )
)

;; Update voter reputation and statistics
(define-public (update-reputation 
    (voter principal) 
    (correct-prediction bool)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (match (map-get? voter-registry voter)
      voter-info
      (let ((new-correct (if correct-prediction 
                           (+ (get correct-predictions voter-info) u1)
                           (get correct-predictions voter-info))))
        (map-set voter-registry voter
          (merge voter-info {
            reputation: (calculate-reputation 
                          (get total-votes voter-info) 
                          new-correct),
            correct-predictions: new-correct
          })
        )
      )
      false
    )
    (ok true)
  )
)

;; Private functions

;; Update voter registry helper
(define-private (update-voter-registry 
    (voter principal) 
    (vote-increment uint) 
    (correct-increment uint)
  )
  (match (map-get? voter-registry voter)
    existing-info
    (map-set voter-registry voter {
      reputation: (get reputation existing-info),
      total-votes: (+ (get total-votes existing-info) vote-increment),
      correct-predictions: (+ (get correct-predictions existing-info) correct-increment),
      stake-balance: (get stake-balance existing-info)
    })
    ;; Create new registry entry
    (map-set voter-registry voter {
      reputation: u100, ;; Starting reputation
      total-votes: vote-increment,
      correct-predictions: correct-increment,
      stake-balance: u0
    })
  )
)

;; Calculate reputation based on voting accuracy
(define-private (calculate-reputation (total-votes uint) (correct-predictions uint))
  (if (is-eq total-votes u0)
    u100 ;; Default reputation
    (let ((accuracy-ratio (/ (* correct-predictions u100) total-votes)))
      (+ u50 accuracy-ratio) ;; Base 50 + accuracy bonus
    )
  )
)

;; Get policy statistics
(define-read-only (get-policy-stats (policy-id uint))
  (match (map-get? policies policy-id)
    policy-data
    (let (
      (total-votes (+ (get yes-votes policy-data) (get no-votes policy-data)))
      (yes-percentage (if (> total-votes u0)
                        (/ (* (get yes-votes policy-data) u100) total-votes)
                        u0))
    )
      (ok {
        total-votes: total-votes,
        yes-percentage: yes-percentage,
        status: (get status policy-data),
        category: (get category policy-data)
      })
    )
    ERR-POLICY-NOT-FOUND
  )
)

;; Emergency functions (contract owner only)

;; Pause contract (emergency)
(define-data-var contract-paused bool false)

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)