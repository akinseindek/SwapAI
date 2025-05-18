;; SwapAI: AI-based Cross-Chain Asset Swap Contract
;; This contract facilitates asset swaps across different blockchain networks

(define-data-var contract-owner principal tx-sender)
(define-data-var fee-percentage uint u100) ;; Represented as basis points (100 = 1%)
(define-data-var min-fee uint u1000000) ;; Minimum fee in microSTX
(define-data-var is-paused bool false)

;; Asset structure
(define-map assets 
  { asset-id: (string-ascii 32) }
  {
    chain-id: (string-ascii 10),
    token-address: (string-ascii 42),
    decimals: uint,
    is-active: bool
  }
)

;; User registry
(define-map users 
  { user-id: principal }
  {
    reputation-score: uint,
    total-volume: uint,
    is-verified: bool,
    last-activity: uint
  }
)

;; Swap requests
(define-map swap-requests
  { request-id: (string-ascii 36) }
  {
    initiator: principal,
    source-asset: (string-ascii 32),
    target-asset: (string-ascii 32),
    amount: uint,
    min-return: uint,
    status: (string-ascii 10),
    timestamp: uint,
    executor: (optional principal),
    execution-timestamp: (optional uint),
    execution-tx: (optional (string-ascii 66))
  }
)

;; Error codes
(define-constant ERR_UNAUTHORIZED u1001)
(define-constant ERR_INVALID_PARAMS u1002)
(define-constant ERR_NOT_FOUND u1003)
(define-constant ERR_ALREADY_EXISTS u1004)
(define-constant ERR_PAUSED u1005)
(define-constant ERR_INSUFFICIENT_FUNDS u1006)

;; Helper functions - MOVED BEFORE execute-swap
(define-private (get-executor-reputation (executor principal))
  (match (map-get? users { user-id: executor })
    user (get reputation-score user)
    u0
  )
)

(define-private (update-executor-reputation (executor principal) (change uint))
  (match (map-get? users { user-id: executor })
    user (map-set users 
          { user-id: executor }
          (merge user { 
            reputation-score: (+ (get reputation-score user) change),
            last-activity: block-height
          }))
    (map-set users
      { user-id: executor }
      {
        reputation-score: u100,
        total-volume: u0,
        is-verified: false,
        last-activity: block-height
      }
    )
  )
)

(define-private (adjust-confidence-score (base-score uint) (reputation uint))
  (let (
    (reputation-factor (/ (* reputation u10) u1000))  ;; Scale reputation to 0-10 range
    (adjusted-score (+ base-score (* reputation-factor u5)))  ;; Add up to 5 points based on reputation
  )
    (if (> adjusted-score u100)
      u100
      adjusted-score
    )
  )
)

(define-private (verify-cross-chain-proof 
  (proof (string-ascii 128)) 
  (chain-identifier (string-ascii 10))
  (token-address (string-ascii 42))
  (amount uint)
  (user principal)
)
  ;; In a real implementation, this would verify cryptographic proofs
  ;; For this example, we're using a simplified check
  (match (slice? proof u0 u10)
    extracted-id (is-eq extracted-id chain-identifier)
    false  ;; If slice? returns none, verification fails
  )
)

(define-private (calculate-dynamic-fee 
  (amount uint) 
  (fee-bp uint) 
  (minimum-fee uint)
  (confidence-score uint)
  (source-chain (string-ascii 10))
  (target-chain (string-ascii 10))
)
  (let (
    ;; Base fee calculation
    (base-fee (/ (* amount fee-bp) u10000))
    
    ;; Adjust fee based on confidence score (lower confidence = higher fee)
    (confidence-factor (- u100 confidence-score))
    (confidence-adjustment (/ (* base-fee confidence-factor) u100))
    
    ;; Adjust fee based on chain complexity
    (chain-complexity-fee (if (is-eq source-chain target-chain)
                            u0  ;; Same chain = no extra fee
                            (/ base-fee u10)))  ;; Cross-chain = +10% fee
    
    ;; Calculate total fee
    (total-fee (+ base-fee confidence-adjustment chain-complexity-fee))
  )
    ;; Ensure minimum fee
    (if (< total-fee minimum-fee)
      minimum-fee
      total-fee
    )
  )
)

;; Admin functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (ok (var-set contract-owner new-owner))
  )
)

(define-public (set-fee-percentage (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (<= new-fee u1000) (err ERR_INVALID_PARAMS)) ;; Max 10%
    (ok (var-set fee-percentage new-fee))
  )
)

(define-public (toggle-pause)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (ok (var-set is-paused (not (var-get is-paused))))
  )
)

;; Asset management
(define-public (register-asset 
  (asset-id (string-ascii 32)) 
  (asset-chain-id (string-ascii 10)) 
  (token-address (string-ascii 42))
  (decimals uint)
)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
    (asserts! (is-none (map-get? assets { asset-id: asset-id })) (err ERR_ALREADY_EXISTS))
    
    (ok (map-set assets 
      { asset-id: asset-id }
      {
        chain-id: asset-chain-id,
        token-address: token-address,
        decimals: decimals,
        is-active: true
      }
    ))
  )
)

(define-public (deactivate-asset (asset-id (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
    
    (match (map-get? assets { asset-id: asset-id })
      asset (ok (map-set assets 
                { asset-id: asset-id }
                (merge asset { is-active: false })))
      (err ERR_NOT_FOUND)
    )
  )
)

;; User management
(define-public (register-user)
  (begin
    (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
    (asserts! (is-none (map-get? users { user-id: tx-sender })) (err ERR_ALREADY_EXISTS))
    
    (ok (map-set users
      { user-id: tx-sender }
      {
        reputation-score: u100,
        total-volume: u0,
        is-verified: false,
        last-activity: block-height
      }
    ))
  )
)

;; Swap request creation
(define-public (create-swap-request
  (request-id (string-ascii 36))
  (source-asset (string-ascii 32))
  (target-asset (string-ascii 32))
  (amount uint)
  (min-return uint)
)
  (begin
    (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
    (asserts! (is-some (map-get? assets { asset-id: source-asset })) (err ERR_NOT_FOUND))
    (asserts! (is-some (map-get? assets { asset-id: target-asset })) (err ERR_NOT_FOUND))
    (asserts! (> amount u0) (err ERR_INVALID_PARAMS))
    (asserts! (is-none (map-get? swap-requests { request-id: request-id })) (err ERR_ALREADY_EXISTS))
    
    ;; Update user activity
    (match (map-get? users { user-id: tx-sender })
      user (map-set users 
            { user-id: tx-sender }
            (merge user { last-activity: block-height }))
      (map-set users
        { user-id: tx-sender }
        {
          reputation-score: u100,
          total-volume: u0,
          is-verified: false,
          last-activity: block-height
        }
      )
    )
    
    ;; Create swap request
    (ok (map-set swap-requests
      { request-id: request-id }
      {
        initiator: tx-sender,
        source-asset: source-asset,
        target-asset: target-asset,
        amount: amount,
        min-return: min-return,
        status: "PENDING",
        timestamp: block-height,
        executor: none,
        execution-timestamp: none,
        execution-tx: none
      }
    ))
  )
)

;; Execute swap with AI-based price optimization and cross-chain verification
(define-public (execute-swap
  (request-id (string-ascii 36))
  (return-amount uint)
  (execution-tx (string-ascii 66))
  (ai-confidence-score uint)
  (cross-chain-proof (string-ascii 128))
)
  (let (
    (request (unwrap! (map-get? swap-requests { request-id: request-id }) (err ERR_NOT_FOUND)))
    (source-asset (unwrap! (map-get? assets { asset-id: (get source-asset request) }) (err ERR_NOT_FOUND)))
    (target-asset (unwrap! (map-get? assets { asset-id: (get target-asset request) }) (err ERR_NOT_FOUND)))
    (initiator (get initiator request))
    (min-return (get min-return request))
    (amount (get amount request))
    (status (get status request))
    (fee-bp (var-get fee-percentage))
    (min-fee-amount (var-get min-fee))
    (executor-reputation (get-executor-reputation tx-sender))
    (adjusted-confidence-score (adjust-confidence-score ai-confidence-score executor-reputation))
  )
    (begin
      ;; Validate request state
      (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
      (asserts! (is-eq status "PENDING") (err ERR_INVALID_PARAMS))
      
      ;; Validate return amount meets minimum
      (asserts! (>= return-amount min-return) (err ERR_INVALID_PARAMS))
      
      ;; Validate AI confidence score
      (asserts! (>= adjusted-confidence-score u70) (err ERR_INVALID_PARAMS))
      
      ;; Verify cross-chain proof
      (asserts! (verify-cross-chain-proof 
                  cross-chain-proof 
                  (get chain-id source-asset) 
                  (get token-address source-asset)
                  amount
                  initiator) 
                (err ERR_INVALID_PARAMS))
      
      ;; Calculate fee
      (let (
        (fee-amount (calculate-dynamic-fee 
                      amount 
                      fee-bp 
                      min-fee-amount 
                      adjusted-confidence-score
                      (get chain-id source-asset)
                      (get chain-id target-asset)))
        (final-return-amount (- return-amount fee-amount))
      )
        (begin
          ;; Update swap request status
          (map-set swap-requests
            { request-id: request-id }
            (merge request {
              status: "COMPLETED",
              executor: (some tx-sender),
              execution-timestamp: (some block-height),
              execution-tx: (some execution-tx)
            })
          )
          
          ;; Update executor reputation
          (update-executor-reputation tx-sender u1)
          
          ;; Update user volume - fixed version with unwrap!
          (unwrap! 
            (match (map-get? users { user-id: initiator })
              user (begin
                     (map-set users 
                       { user-id: initiator }
                       (merge user { 
                         total-volume: (+ (get total-volume user) amount),
                         last-activity: block-height
                       }))
                     (ok true))
              (err ERR_NOT_FOUND))
            (err ERR_NOT_FOUND))
          
          ;; Emit swap completion event
          (print {
            event: "swap-completed",
            request-id: request-id,
            initiator: initiator,
            executor: tx-sender,
            source-asset: (get source-asset request),
            target-asset: (get target-asset request),
            amount: amount,
            return-amount: final-return-amount,
            fee: fee-amount,
            confidence-score: adjusted-confidence-score
          })
          
          (ok final-return-amount)
        )
      )
    )
  )
)

;; =========================================================
;; LOYALTY PROGRAM & REPUTATION-BASED DISCOUNTS
;; =========================================================

;; Loyalty tiers
(define-constant TIER_BRONZE u0)
(define-constant TIER_SILVER u1)
(define-constant TIER_GOLD u2)
(define-constant TIER_PLATINUM u3)

;; Tier thresholds (in total volume)
(define-constant TIER_SILVER_THRESHOLD u10000000000)   ;; 10,000 tokens
(define-constant TIER_GOLD_THRESHOLD u100000000000)    ;; 100,000 tokens
(define-constant TIER_PLATINUM_THRESHOLD u1000000000000) ;; 1,000,000 tokens

;; Tier discounts (in basis points)
(define-constant TIER_BRONZE_DISCOUNT u0)     ;; 0% discount
(define-constant TIER_SILVER_DISCOUNT u100)   ;; 1% discount
(define-constant TIER_GOLD_DISCOUNT u250)     ;; 2.5% discount
(define-constant TIER_PLATINUM_DISCOUNT u500) ;; 5% discount

;; Track successful swaps per user
(define-map user-swap-stats
  { user-id: principal }
  {
    successful-swaps: uint,
    last-swap-height: uint,
    consecutive-months: uint,
    loyalty-points: uint,
    last-point-claim: uint
  }
)

;; Update user swap statistics after successful swap
(define-public (update-user-swap-stats (user-principal principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR_UNAUTHORIZED))
    
    (let (
      (current-stats (default-to 
                      { successful-swaps: u0, last-swap-height: u0, consecutive-months: u0, loyalty-points: u0, last-point-claim: u0 } 
                      (map-get? user-swap-stats { user-id: user-principal })))
      (new-successful-swaps (+ (get successful-swaps current-stats) u1))
      (blocks-since-last-swap (if (> (get last-swap-height current-stats) u0)
                                (- block-height (get last-swap-height current-stats))
                                u0))
      (monthly-blocks u4380) ;; ~30 days of blocks
      (consecutive-months (if (< blocks-since-last-swap (* monthly-blocks u2))
                            (+ (get consecutive-months current-stats) u1)
                            u1))
      (loyalty-points (+ (get loyalty-points current-stats) 
                        (+ u10 (* consecutive-months u5))))
    )
      (ok (map-set user-swap-stats
        { user-id: user-principal }
        {
          successful-swaps: new-successful-swaps,
          last-swap-height: block-height,
          consecutive-months: consecutive-months,
          loyalty-points: loyalty-points,
          last-point-claim: (get last-point-claim current-stats)
        }
      ))
    )
  )
)

;; Redeem loyalty points for additional fee discount
(define-public (redeem-loyalty-points (points-to-redeem uint) (discount-type (string-ascii 10)))
  (let (
    (stats (default-to 
            { successful-swaps: u0, last-swap-height: u0, consecutive-months: u0, loyalty-points: u0, last-point-claim: u0 } 
            (map-get? user-swap-stats { user-id: tx-sender })))
    (available-points (get loyalty-points stats))
    (min-redemption-period u1440) ;; Minimum blocks between redemptions (approximately 10 days)
    (redemption-multiplier (if (is-eq discount-type "premium") u12 u10)) ;; Premium redemptions give 20% more value
    (effective-discount (* points-to-redeem redemption-multiplier))
    (last-claim-height (get last-point-claim stats))
  )
    (begin
      (asserts! (not (var-get is-paused)) (err ERR_PAUSED))
      (asserts! (<= points-to-redeem available-points) (err ERR_INVALID_PARAMS))
      (asserts! (>= points-to-redeem u100) (err ERR_INVALID_PARAMS))
      (asserts! (or (is-eq last-claim-height u0) (>= (- block-height last-claim-height) min-redemption-period)) (err ERR_INVALID_PARAMS))
      
      ;; Log the redemption event
      (print {
        event: "loyalty-points-redeemed",
        user: tx-sender,
        points-redeemed: points-to-redeem,
        discount-type: discount-type,
        effective-discount: effective-discount
      })
      
      (ok (map-set user-swap-stats
        { user-id: tx-sender }
        (merge stats {
          loyalty-points: (- available-points points-to-redeem),
          last-point-claim: block-height
        })
      ))
    )
  )
)
