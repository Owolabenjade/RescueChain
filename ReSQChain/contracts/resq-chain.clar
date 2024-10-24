;; ResQChain - Enhanced Natural Disaster Response Smart Contract
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
(define-constant err-not-found (err u107))
(define-constant err-invalid-input (err u108))
(define-constant err-invalid-resource-type (err u109))
(define-constant err-invalid-update-type (err u110))

;; Data validation constants
(define-constant max-name-length u50)
(define-constant max-skills-length u100)
(define-constant max-content-length u500)
(define-constant max-feedback-length u100)
(define-constant min-rating u1)
(define-constant max-rating u5)

;; Data Maps
(define-map disasters uint {
    name: (string-ascii 50),
    location: (string-ascii 100),
    severity: uint,
    active: bool,
    start-time: uint,
    last-update: uint
})

(define-map relief-organizations principal {
    name: (string-ascii 50),
    verified: bool,
    resource-provider: bool,
    rating: uint
})

(define-map volunteers principal {
    name: (string-ascii 50),
    skills: (string-ascii 100),
    verified: bool,
    reputation-score: uint,
    total-missions: uint
})

(define-map resource-inventory {disaster-id: uint, resource-type: (string-ascii 7)} {
    quantity: uint,
    allocated: uint,
    needed: uint
})

(define-map disaster-updates {disaster-id: uint, timestamp: uint} {
    update-type: (string-ascii 9),
    content: (string-ascii 500),
    verified-by: principal
})

(define-map volunteer-ratings {volunteer: principal, disaster-id: uint} {
    rating: uint,
    feedback: (string-ascii 100)
})

;; Valid resource types as a list of string literals
(define-constant valid-resource-types (list 
    "food"
    "water"
    "medical"
    "shelter"
))

;; Valid update types as a list of string literals - adjusted length to 9 characters
(define-constant valid-update-types (list
    "status"    ;; 6 chars
    "emergency" ;; 9 chars
    "resource"  ;; 8 chars
    "volunteer" ;; 9 chars
    "warning"   ;; 7 chars
))

;; Data Variables
(define-data-var minimum-donation uint u1000000) ;; In microSTX
(define-data-var total-funds uint u0)
(define-data-var severity-threshold uint u8) ;; Threshold for automatic fund release

;; Input validation functions
(define-private (validate-string-length (str (string-ascii 500)) (max-len uint))
    (let ((str-len (len str)))
        (and (> str-len u0) (<= str-len max-len))
    )
)

(define-private (validate-resource-type (resource-type (string-ascii 7)))
    (is-some (index-of valid-resource-types resource-type))
)

(define-private (validate-update-type (update-type (string-ascii 9)))
    (is-some (index-of valid-update-types update-type))
)

(define-private (validate-disaster-id (disaster-id uint))
    (match (map-get? disasters disaster-id)
        disaster (get active disaster)
        false
    )
)

(define-private (validate-volunteer (volunteer-addr principal))
    (match (map-get? volunteers volunteer-addr)
        volunteer (get verified volunteer)
        false
    )
)

;; Resource Management
(define-public (add-resources
    (disaster-id uint)
    (resource-type (string-ascii 7))
    (quantity uint))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized))
         (disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster))
         (current-inventory (default-to 
            {quantity: u0, allocated: u0, needed: u0}
            (map-get? resource-inventory {disaster-id: disaster-id, resource-type: resource-type}))))
        (asserts! (get resource-provider org) err-unauthorized)
        (asserts! (get active disaster) err-not-active-disaster)
        (asserts! (validate-resource-type resource-type) err-invalid-resource-type)
        (asserts! (> quantity u0) err-invalid-amount)
        (ok (map-set resource-inventory
            {disaster-id: disaster-id, resource-type: resource-type}
            (merge current-inventory
                {quantity: (+ (get quantity current-inventory) quantity)})))
    )
)

(define-public (request-resources
    (disaster-id uint)
    (resource-type (string-ascii 7))
    (quantity uint))
    (let
        ((inventory (unwrap! (map-get? resource-inventory 
            {disaster-id: disaster-id, resource-type: resource-type}) err-insufficient-resources))
         (disaster (unwrap! (map-get? disasters disaster-id) err-not-active-disaster))
         (available (- (get quantity inventory) (get allocated inventory))))
        (asserts! (get active disaster) err-not-active-disaster)
        (asserts! (validate-resource-type resource-type) err-invalid-resource-type)
        (asserts! (>= available quantity) err-insufficient-resources)
        (ok (map-set resource-inventory
            {disaster-id: disaster-id, resource-type: resource-type}
            (merge inventory
                {allocated: (+ (get allocated inventory) quantity)})))
    )
)

;; Information Sharing function with additional validation
(define-public (post-disaster-update
    (disaster-id uint)
    (update-type (string-ascii 9))
    (content (string-ascii 500)))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized)))
        (asserts! (get verified org) err-unauthorized)
        (asserts! (validate-disaster-id disaster-id) err-not-active-disaster)
        (asserts! (validate-update-type update-type) err-invalid-update-type)
        (asserts! (validate-string-length content max-content-length) err-invalid-input)
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
        (try! (if (and (> new-severity (var-get severity-threshold))
                 (< (get severity disaster) (var-get severity-threshold)))
            (auto-release-emergency-funds disaster-id)
            (ok true)))
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

;; Modified Volunteer Rating System with additional validation
(define-public (rate-volunteer
    (volunteer-addr principal)
    (disaster-id uint)
    (rating uint)
    (feedback (string-ascii 100)))
    (let
        ((org (unwrap! (map-get? relief-organizations tx-sender) err-unauthorized)))
        ;; Input validation
        (asserts! (get verified org) err-unauthorized)
        (asserts! (validate-volunteer volunteer-addr) err-unauthorized)
        (asserts! (validate-disaster-id disaster-id) err-not-active-disaster)
        (asserts! (and (>= rating min-rating) (<= rating max-rating)) err-invalid-rating)
        (asserts! (validate-string-length feedback max-feedback-length) err-invalid-input)
        
        (let ((volunteer (unwrap! (map-get? volunteers volunteer-addr) err-unauthorized)))
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
)

;; Read-Only Functions
(define-read-only (get-resource-inventory (disaster-id uint) (resource-type (string-ascii 7)))
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
    (match (map-get? disasters disaster-id)
        disaster (ok (get severity disaster))
        err-not-found
    )
)

;; Helper function to check if disaster exists
(define-read-only (is-active-disaster (disaster-id uint))
    (match (map-get? disasters disaster-id)
        disaster (get active disaster)
        false
    )
)