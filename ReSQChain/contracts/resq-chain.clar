;; DisasterGuard - Enhanced Natural Disaster Response Smart Contract
;; Handles disaster relief management, resource tracking, and volunteer coordination

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-registered (err u103))
(define-constant err-not-active-disaster (err u104))
(define-constant err-insufficient-resources (err u105))
(define-constant err-invalid-rating (err u106))

;; Data Variables
(define-data-var minimum-donation uint u1000000) ;; In microSTX
(define-data-var total-funds uint u0)
(define-data-var severity-threshold uint u8) ;; Threshold for automatic fund release

;; Resource Types
(define-constant resource-types (list 
    "food"
    "water"
    "medical"
    "shelter"
))

;; Data Maps
(define-map disasters 
    uint 
    {
        location: (string-ascii 50),
        disaster-type: (string-ascii 20),
        severity: uint,
        active: bool,
        funds-allocated: uint,
        funds-distributed: uint,
        last-update: uint,
        warning-level: (string-ascii 10)
    }
)

(define-map resource-inventory
    {disaster-id: uint, resource-type: (string-ascii 10)}
    {
        quantity: uint,
        allocated: uint,
        needed: uint
    }
)

(define-map volunteers
    principal
    {
        name: (string-ascii 50),
        skills: (string-ascii 100),
        reputation-score: uint,
        total-missions: uint,
        verified: bool
    }
)

(define-map volunteer-ratings
    {volunteer: principal, disaster-id: uint}
    {
        rating: uint,
        feedback: (string-ascii 100)
    }
)

(define-map relief-organizations
    principal
    {
        name: (string-ascii 50),
        verified: bool,
        total-received: uint,
        resource-provider: bool
    }
)

(define-map disaster-updates
    {disaster-id: uint, timestamp: uint}
    {
        update-type: (string-ascii 20),
        content: (string-ascii 500),
        verified-by: principal
    }
)

;; Administrative Functions
(define-public (register-volunteer 
    (name (string-ascii 50))
    (skills (string-ascii 100)))
    (let
        ((caller tx-sender))
        (asserts! (is-none (map-get? volunteers caller)) err-already-registered)
        (ok (map-set volunteers
            caller
            {
                name: name,
                skills: skills,
                reputation-score: u100,
                total-missions: u0,
                verified: false
            }
        ))
    )
)

(define-public (verify-volunteer (volunteer-addr principal))
    (let
        ((volunteer (unwrap! (map-get? volunteers volunteer-addr) err-unauthorized)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set volunteers
            volunteer-addr
            (merge volunteer {verified: true})))
    )
)

;; Resource Management
(define-public (add-resources
    (disaster-id uint)
    (resource-type (string-ascii 10))
    (quantity uint))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized))
         (current-inventory (default-to 
            {quantity: u0, allocated: u0, needed: u0}
            (map-get? resource-inventory {disaster-id: disaster-id, resource-type: resource-type}))))
        (asserts! (get resource-provider org) err-unauthorized)
        (ok (map-set resource-inventory
            {disaster-id: disaster-id, resource-type: resource-type}
            (merge current-inventory
                {quantity: (+ (get quantity current-inventory) quantity)})))
    )
)

(define-public (request-resources
    (disaster-id uint)
    (resource-type (string-ascii 10))
    (quantity uint))
    (let
        ((inventory (unwrap! (map-get? resource-inventory 
            {disaster-id: disaster-id, resource-type: resource-type}) err-insufficient-resources))
         (available (- (get quantity inventory) (get allocated inventory))))
        (asserts! (>= available quantity) err-insufficient-resources)
        (ok (map-set resource-inventory
            {disaster-id: disaster-id, resource-type: resource-type}
            (merge inventory
                {allocated: (+ (get allocated inventory) quantity)})))
    )
)

;; Information Sharing
(define-public (post-disaster-update
    (disaster-id uint)
    (update-type (string-ascii 20))
    (content (string-ascii 500)))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized)))
        (asserts! (get verified org) err-unauthorized)
        (ok (map-set disaster-updates
            {disaster-id: disaster-id, timestamp: block-height}
            {
                update-type: update-type,
                content: content,
                verified-by: tx-sender
            }))
    )
)

;; Smart Emergency Response
(define-public (update-disaster-severity
    (disaster-id uint)
    (new-severity uint))
    (let
        ((disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        ;; Auto-release funds if severity exceeds threshold
        (if (and (> new-severity (var-get severity-threshold))
                 (< (get severity disaster) (var-get severity-threshold)))
            (try! (auto-release-emergency-funds disaster-id))
            true)
        (ok (map-set disasters
            disaster-id
            (merge disaster {
                severity: new-severity,
                last-update: block-height
            })))
    )
)

(define-private (auto-release-emergency-funds (disaster-id uint))
    (let
        ((disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster))
         (emergency-amount (/ (var-get total-funds) u10))) ;; 10% of total funds
        (if (> emergency-amount u0)
            (begin
                (try! (as-contract (stx-transfer? 
                    emergency-amount
                    (as-contract tx-sender)
                    contract-owner))) ;; Transfer to owner for immediate distribution
                (ok true))
            (ok false))
    )
)

;; Volunteer Rating System
(define-public (rate-volunteer
    (volunteer-addr principal)
    (disaster-id uint)
    (rating uint)
    (feedback (string-ascii 100)))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized))
         (volunteer (unwrap! (map-get? volunteers volunteer-addr) err-unauthorized)))
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        (asserts! (get verified org) err-unauthorized)
        
        ;; Update volunteer rating
        (map-set volunteer-ratings
            {volunteer: volunteer-addr, disaster-id: disaster-id}
            {
                rating: rating,
                feedback: feedback
            })
        
        ;; Update reputation score
        (ok (map-set volunteers
            volunteer-addr
            (merge volunteer {
                reputation-score: (/ (+ (* (get reputation-score volunteer) (get total-missions volunteer)) rating)
                                   (+ (get total-missions volunteer) u1)),
                total-missions: (+ (get total-missions volunteer) u1)
            })))
    )
)

;; Read-Only Functions
(define-read-only (get-resource-inventory (disaster-id uint) (resource-type (string-ascii 10)))
    (map-get? resource-inventory {disaster-id: disaster-id, resource-type: resource-type})
)

(define-read-only (get-volunteer-info (volunteer-addr principal))
    (map-get? volunteers volunteer-addr)
)

(define-read-only (get-volunteer-rating (volunteer-addr principal) (disaster-id uint))
    (map-get? volunteer-ratings {volunteer: volunteer-addr, disaster-id: disaster-id})
)

(define-read-only (get-latest-update (disaster-id uint))
    (map-get? disaster-updates {disaster-id: disaster-id, timestamp: block-height})
)

(define-read-only (get-disaster-severity-level (disaster-id uint))
    (get severity (unwrap! (map-get? disasters disaster-id) err-not-active-disaster))
)