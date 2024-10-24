;; DisasterGuard - Natural Disaster Response Smart Contract
;; Handles disaster relief fund management and resource allocation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-registered (err u103))
(define-constant err-not-active-disaster (err u104))

;; Data Variables
(define-data-var minimum-donation uint u1000000) ;; In microSTX
(define-data-var total-funds uint u0)

;; Data Maps
(define-map disasters 
    uint 
    {
        location: (string-ascii 50),
        disaster-type: (string-ascii 20),
        severity: uint,
        active: bool,
        funds-allocated: uint,
        funds-distributed: uint
    }
)

(define-map relief-organizations
    principal
    {
        name: (string-ascii 50),
        verified: bool,
        total-received: uint
    }
)

(define-map disaster-claims
    {disaster-id: uint, org: principal}
    {
        amount: uint,
        status: (string-ascii 10),
        timestamp: uint
    }
)

;; Administrative Functions
(define-public (register-relief-organization (org-name (string-ascii 50)))
    (let
        ((caller tx-sender))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (get-organization-info caller)) err-already-registered)
        (ok (map-set relief-organizations
            caller
            {
                name: org-name,
                verified: true,
                total-received: u0
            }
        ))
    )
)

;; Disaster Management
(define-public (declare-disaster 
    (disaster-id uint)
    (location (string-ascii 50))
    (type (string-ascii 20))
    (severity uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set disasters
            disaster-id
            {
                location: location,
                disaster-type: type,
                severity: severity,
                active: true,
                funds-allocated: u0,
                funds-distributed: u0
            }
        ))
    )
)

;; Funding Functions
(define-public (donate-to-disaster-fund (disaster-id uint))
    (let
        ((amount (stx-get-balance tx-sender))
         (disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster)))
        (asserts! (>= amount (var-get minimum-donation)) err-invalid-amount)
        (asserts! (get active disaster) err-not-active-disaster)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set total-funds (+ (var-get total-funds) amount))
        (map-set disasters
            disaster-id
            (merge disaster {funds-allocated: (+ (get funds-allocated disaster) amount)}))
        (ok true)
    )
)

;; Relief Distribution
(define-public (request-relief-funds 
    (disaster-id uint)
    (amount uint))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized))
         (disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster)))
        (asserts! (get verified org) err-unauthorized)
        (asserts! (get active disaster) err-not-active-disaster)
        (asserts! (<= amount (- (get funds-allocated disaster) (get funds-distributed disaster))) err-invalid-amount)
        
        (map-set disaster-claims
            {disaster-id: disaster-id, org: tx-sender}
            {
                amount: amount,
                status: "pending",
                timestamp: block-height
            })
        (ok true)
    )
)

(define-public (approve-relief-request 
    (disaster-id uint)
    (org principal))
    (let
        ((claim (unwrap! (map-get? disaster-claims {disaster-id: disaster-id, org: org}) err-unauthorized))
         (disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster))
         (org-info (unwrap! (map-get? relief-organizations org) err-unauthorized)))
        
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (as-contract (stx-transfer? (get amount claim) (as-contract tx-sender) org)))
        
        ;; Update organization info
        (map-set relief-organizations
            org
            (merge org-info {total-received: (+ (get total-received org-info) (get amount claim))}))
        
        ;; Update disaster info
        (map-set disasters
            disaster-id
            (merge disaster {funds-distributed: (+ (get funds-distributed disaster) (get amount claim))}))
        
        ;; Update claim status
        (map-set disaster-claims
            {disaster-id: disaster-id, org: org}
            (merge claim {status: "approved"}))
        
        (ok true)
    )
)

;; Read-Only Functions
(define-read-only (get-disaster-info (disaster-id uint))
    (map-get? disasters disaster-id)
)

(define-read-only (get-organization-info (org principal))
    (map-get? relief-organizations org)
)

(define-read-only (get-claim-info (disaster-id uint) (org principal))
    (map-get? disaster-claims {disaster-id: disaster-id, org: org})
)

(define-read-only (get-total-funds)
    (ok (var-get total-funds))
)