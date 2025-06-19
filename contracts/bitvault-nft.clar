;; Title: BitVault NFT Protocol
;; Summary:
;; BitVault is a comprehensive NFT protocol built on Bitcoin's security layer
;; through Stacks, enabling collateralized minting, fractional ownership,
;; yield-generating staking, and seamless marketplace trading.
;;
;; Description:
;; BitVault transforms digital asset ownership by combining Bitcoin's proven
;; security with advanced DeFi primitives. Users can mint NFTs with STX
;; collateral backing, stake them for yield generation, fractionalize
;; ownership for increased liquidity, and trade on an integrated marketplace.
;; The protocol enforces minimum collateral ratios, distributes staking
;; rewards, and maintains robust access controls while leveraging Bitcoin's
;; unparalleled network effects.
;;
;; Key Features:
;; - Collateralized NFT minting with configurable ratios
;; - Yield-generating staking mechanism with block-based rewards
;; - Fractional ownership system for enhanced liquidity
;; - Integrated marketplace with protocol fee collection
;; - Comprehensive access controls and validation systems
;; - Bitcoin-secured through Stacks consensus mechanism

;; CONSTANTS & ERROR CODES

(define-constant CONTRACT-OWNER tx-sender)

;; Access Control Errors
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-TOKEN-OWNER (err u101))

;; Financial Operation Errors
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u106))

;; NFT Operation Errors
(define-constant ERR-INVALID-TOKEN (err u103))
(define-constant ERR-LISTING-NOT-FOUND (err u104))
(define-constant ERR-INVALID-PRICE (err u105))

;; Staking Operation Errors
(define-constant ERR-ALREADY-STAKED (err u107))
(define-constant ERR-NOT-STAKED (err u108))

;; Validation Errors
(define-constant ERR-INVALID-PERCENTAGE (err u109))
(define-constant ERR-INVALID-URI (err u110))
(define-constant ERR-INVALID-RECIPIENT (err u111))
(define-constant ERR-OVERFLOW (err u112))

;; PROTOCOL CONFIGURATION VARIABLES

;; Minimum collateral ratio (150% = 1.5x backing)
(define-data-var min-collateral-ratio uint u150)

;; Protocol fee in basis points (25 = 0.25%)
(define-data-var protocol-fee uint u25)

;; Total NFTs currently staked in the protocol
(define-data-var total-staked uint u0)

;; Annual yield rate in basis points (50 = 0.5%)
(define-data-var yield-rate uint u50)

;; Total supply of minted NFTs
(define-data-var total-supply uint u0)

;; DATA STORAGE MAPS

;; Core NFT metadata and state tracking
(define-map tokens
  { token-id: uint }
  {
    owner: principal,
    uri: (string-ascii 256),
    collateral: uint,
    is-staked: bool,
    stake-timestamp: uint,
    fractional-shares: uint,
  }
)

;; Active marketplace listings
(define-map token-listings
  { token-id: uint }
  {
    price: uint,
    seller: principal,
    active: bool,
  }
)

;; Fractional ownership distribution records
(define-map fractional-ownership
  {
    token-id: uint,
    owner: principal,
  }
  { shares: uint }
)

;; Staking rewards accumulation tracking
(define-map staking-rewards
  { token-id: uint }
  {
    accumulated-yield: uint,
    last-claim: uint,
  }
)

;; PRIVATE HELPER FUNCTIONS

;; Validates URI format and length constraints
(define-private (validate-uri (uri (string-ascii 256)))
  (let ((uri-len (len uri)))
    (and
      (> uri-len u0)
      (<= uri-len u256)
    )
  )
)

;; Prevents transfers to contract address
(define-private (validate-recipient (recipient principal))
  (not (is-eq recipient (as-contract tx-sender)))
)

;; Safe arithmetic addition with overflow protection
(define-private (safe-add
    (a uint)
    (b uint)
  )
  (let ((sum (+ a b)))
    (asserts! (>= sum a) ERR-OVERFLOW)
    (ok sum)
  )
)

;; CORE NFT MINTING & TRANSFER FUNCTIONS

;; Mints new NFT with STX collateral backing
(define-public (mint-nft
    (uri (string-ascii 256))
    (collateral uint)
  )
  (let (
      (token-id (+ (var-get total-supply) u1))
      (collateral-requirement (/ (* (var-get min-collateral-ratio) collateral) u100))
    )
    (asserts! (validate-uri uri) ERR-INVALID-URI)
    (asserts! (>= (stx-get-balance tx-sender) collateral-requirement)
      ERR-INSUFFICIENT-COLLATERAL
    )
    ;; Lock collateral in contract
    (try! (stx-transfer? collateral-requirement tx-sender (as-contract tx-sender)))
    ;; Register new NFT
    (map-set tokens { token-id: token-id } {
      owner: tx-sender,
      uri: uri,
      collateral: collateral,
      is-staked: false,
      stake-timestamp: u0,
      fractional-shares: u0,
    })
    (var-set total-supply token-id)
    (ok token-id)
  )
)

;; Transfers NFT ownership with comprehensive validation
(define-public (transfer-nft
    (token-id uint)
    (recipient principal)
  )
  (let ((token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN)))
    (asserts! (validate-recipient recipient) ERR-INVALID-RECIPIENT)
    (asserts! (is-eq tx-sender (get owner token)) ERR-NOT-TOKEN-OWNER)
    (asserts! (not (get is-staked token)) ERR-ALREADY-STAKED)
    (map-set tokens { token-id: token-id } (merge token { owner: recipient }))
    (ok true)
  )
)

;; MARKETPLACE TRADING FUNCTIONS

;; Lists NFT for sale on integrated marketplace
(define-public (list-nft
    (token-id uint)
    (price uint)
  )
  (let ((token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN)))
    (asserts! (> price u0) ERR-INVALID-PRICE)
    (asserts! (is-eq tx-sender (get owner token)) ERR-NOT-TOKEN-OWNER)
    (asserts! (not (get is-staked token)) ERR-ALREADY-STAKED)
    (map-set token-listings { token-id: token-id } {
      price: price,
      seller: tx-sender,
      active: true,
    })
    (ok true)
  )
)

;; Executes NFT purchase with automatic fee collection
(define-public (purchase-nft (token-id uint))
  (let (
      (listing (unwrap! (get-listing token-id) ERR-LISTING-NOT-FOUND))
      (price (get price listing))
      (seller (get seller listing))
      (fee (/ (* price (var-get protocol-fee)) u1000))
    )
    (asserts! (get active listing) ERR-LISTING-NOT-FOUND)
    ;; Execute payment transfers
    (try! (stx-transfer? price tx-sender seller))
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    ;; Transfer NFT ownership
    (try! (transfer-nft token-id tx-sender))
    ;; Deactivate listing
    (map-set token-listings { token-id: token-id } {
      price: u0,
      seller: seller,
      active: false,
    })
    (ok true)
  )
)

;; FRACTIONAL OWNERSHIP SYSTEM

;; Transfers fractional shares between addresses
(define-public (transfer-shares
    (token-id uint)
    (recipient principal)
    (share-amount uint)
  )
  (let (
      (sender-shares (unwrap! (get-fractional-shares token-id tx-sender)
        ERR-INSUFFICIENT-BALANCE
      ))
      (current-recipient-shares (default-to { shares: u0 } (get-fractional-shares token-id recipient)))
      (recipient-new-shares (unwrap! (safe-add (get shares current-recipient-shares) share-amount)
        ERR-OVERFLOW
      ))
    )
    (asserts! (validate-recipient recipient) ERR-INVALID-RECIPIENT)
    (asserts! (>= (get shares sender-shares) share-amount)
      ERR-INSUFFICIENT-BALANCE
    )
    ;; Update sender's share balance
    (map-set fractional-ownership {
      token-id: token-id,
      owner: tx-sender,
    } { shares: (- (get shares sender-shares) share-amount) }
    )
    ;; Update recipient's share balance
    (map-set fractional-ownership {
      token-id: token-id,
      owner: recipient,
    } { shares: recipient-new-shares }
    )
    (ok true)
  )
)

;; YIELD-GENERATING STAKING SYSTEM

;; Stakes NFT to begin earning block-based yields
(define-public (stake-nft (token-id uint))
  (let ((token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN)))
    (asserts! (is-eq tx-sender (get owner token)) ERR-NOT-TOKEN-OWNER)
    (asserts! (not (get is-staked token)) ERR-ALREADY-STAKED)
    ;; Update staking status
    (map-set tokens { token-id: token-id }
      (merge token {
        is-staked: true,
        stake-timestamp: stacks-block-height,
      })
    )
    ;; Initialize rewards tracking
    (map-set staking-rewards { token-id: token-id } {
      accumulated-yield: u0,
      last-claim: stacks-block-height,
    })
    (var-set total-staked (+ (var-get total-staked) u1))
    (ok true)
  )
)

;; Unstakes NFT and claims final rewards
(define-public (unstake-nft (token-id uint))
  (let ((token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN)))
    (asserts! (is-eq tx-sender (get owner token)) ERR-NOT-TOKEN-OWNER)
    (asserts! (get is-staked token) ERR-NOT-STAKED)
    ;; Claim accumulated rewards before unstaking
    (try! (claim-staking-rewards token-id))
    ;; Update staking status
    (map-set tokens { token-id: token-id }
      (merge token {
        is-staked: false,
        stake-timestamp: u0,
      })
    )
    (var-set total-staked (- (var-get total-staked) u1))
    (ok true)
  )
)

;; READ-ONLY QUERY FUNCTIONS

;; Retrieves complete NFT metadata and state
(define-read-only (get-token-info (token-id uint))
  (map-get? tokens { token-id: token-id })
)

;; Retrieves active marketplace listing details
(define-read-only (get-listing (token-id uint))
  (map-get? token-listings { token-id: token-id })
)

;; Retrieves fractional ownership information
(define-read-only (get-fractional-shares
    (token-id uint)
    (owner principal)
  )
  (map-get? fractional-ownership {
    token-id: token-id,
    owner: owner,
  })
)

;; Retrieves staking rewards accumulation data
(define-read-only (get-staking-rewards (token-id uint))
  (map-get? staking-rewards { token-id: token-id })
)

;; Calculates current staking rewards based on blocks elapsed
(define-read-only (calculate-rewards (token-id uint))
  (let (
      (token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN))
      (rewards (unwrap! (get-staking-rewards token-id) ERR-NOT-STAKED))
      (blocks-staked (- stacks-block-height (get stake-timestamp token)))
      (yield-per-block (/ (var-get yield-rate) u52560)) ;; Approximate blocks per year
      (new-rewards (* blocks-staked yield-per-block))
    )
    (ok (+ (get accumulated-yield rewards) new-rewards))
  )
)

;; PRIVATE REWARD DISTRIBUTION FUNCTIONS

;; Claims and distributes accumulated staking rewards
(define-private (claim-staking-rewards (token-id uint))
  (let (
      (rewards (unwrap! (calculate-rewards token-id) ERR-NOT-STAKED))
      (token (unwrap! (get-token-info token-id) ERR-INVALID-TOKEN))
    )
    (asserts! (get is-staked token) ERR-NOT-STAKED)
    ;; Reset rewards counter
    (map-set staking-rewards { token-id: token-id } {
      accumulated-yield: u0,
      last-claim: stacks-block-height,
    })
    ;; Distribute STX rewards to token owner
    (as-contract (stx-transfer? rewards (as-contract tx-sender) (get owner token)))
  )
)
