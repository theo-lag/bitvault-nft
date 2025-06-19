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