;; glownest-tracker
;; 
;; This contract manages personal wellness data tracking and achievement rewards for the
;; GlowNest Wellness Tracker platform. It enables users to securely record, update, and access
;; their personal health metrics while maintaining full ownership and privacy of their data.
;; 
;; The contract also implements an achievement system that rewards users for reaching wellness
;; milestones and consistent healthy habits.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-DATA (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-DATE-IN-FUTURE (err u103))
(define-constant ERR-ACHIEVEMENT-EXISTS (err u104))
(define-constant ERR-NO-METRICS-RECORDED (err u105))
(define-constant ERR-GOAL-NOT-FOUND (err u106))

;; Constants
(define-constant SLEEP-MIN-MINS u0)
(define-constant SLEEP-MAX-MINS u1440) ;; 24 hours in minutes
(define-constant HYDRATION-MIN-ML u0)
(define-constant HYDRATION-MAX-ML u10000) ;; 10 liters in ml
(define-constant MINDFULNESS-MIN-MINS u0)
(define-constant MINDFULNESS-MAX-MINS u1440) ;; 24 hours in minutes

;; Data structures

;; Wellness metrics for a specific day
(define-map daily-metrics 
  { user: principal, date: uint }
  {
    sleep-minutes: uint,
    hydration-ml: uint,
    mindfulness-minutes: uint,
    last-updated: uint
  }
)

;; User's personal wellness goals
(define-map user-goals
  { user: principal }
  {
    sleep-minutes-goal: uint,
    hydration-ml-goal: uint,
    mindfulness-minutes-goal: uint,
    last-updated: uint
  }
)

;; User achievements
(define-map user-achievements
  { user: principal, achievement-id: uint }
  {
    title: (string-ascii 50),
    description: (string-ascii 200),
    date-earned: uint,
    points: uint
  }
)

;; Achievement definitions
(define-map achievement-definitions
  { achievement-id: uint }
  {
    title: (string-ascii 50),
    description: (string-ascii 200),
    points: uint,
    type: (string-ascii 20) ;; "sleep", "hydration", "mindfulness", or "streak"
  }
)

;; User's achievement points total
(define-map user-points
  { user: principal }
  { total-points: uint }
)

;; Data to track user streaks
(define-map user-streaks
  { user: principal }
  {
    current-streak-days: uint,
    longest-streak-days: uint,
    last-activity-date: uint
  }
)

;; Private functions

;; Validate daily metrics are within acceptable ranges
(define-private (validate-metrics (sleep-minutes uint) (hydration-ml uint) (mindfulness-minutes uint))
  (and
    (and (>= sleep-minutes SLEEP-MIN-MINS) (<= sleep-minutes SLEEP-MAX-MINS))
    (and (>= hydration-ml HYDRATION-MIN-ML) (<= hydration-ml HYDRATION-MAX-ML))
    (and (>= mindfulness-minutes MINDFULNESS-MIN-MINS) (<= mindfulness-minutes MINDFULNESS-MAX-MINS))
  )
)

;; Get current block time
(define-private (get-current-time)
  (unwrap-panic (get-block-info? time u0))
)

;; Convert date to epoch time (expects date as YYYYMMDD)
(define-private (date-to-epoch (date uint))
  ;; This is a simplified version - a real implementation would do proper date conversion
  ;; For the purposes of this contract, we'll use the date format directly
  date
)

;; Check if a date is in the future
(define-private (is-date-in-future (date uint))
  (> (date-to-epoch date) (get-current-time))
)

;; Update user streak information
(define-private (update-streak (user principal) (date uint))
  (let (
    (current-streak (default-to 
      { current-streak-days: u0, longest-streak-days: u0, last-activity-date: u0 } 
      (map-get? user-streaks { user: user })))
    (yesterday (- date u1))
  )
    (if (= (get last-activity-date current-streak) yesterday)
      ;; Consecutive day, increment streak
      (let (
        (new-streak-days (+ (get current-streak-days current-streak) u1))
        (new-longest-streak (max (get longest-streak-days current-streak) new-streak-days))
      )
        (map-set user-streaks 
          { user: user }
          {
            current-streak-days: new-streak-days,
            longest-streak-days: new-longest-streak,
            last-activity-date: date
          }
        )
        ;; Check if any streak achievements should be awarded
        (try! (check-streak-achievements user new-streak-days))
        (ok true)
      )
      ;; Not consecutive, reset streak
      (begin
        (map-set user-streaks 
          { user: user }
          {
            current-streak-days: u1,
            longest-streak-days: (get longest-streak-days current-streak),
            last-activity-date: date
          }
        )
        (ok true)
      )
    )
  )
)

;; Check if user has met goals for the day and award achievements
(define-private (check-daily-achievements (user principal) (metrics { sleep-minutes: uint, hydration-ml: uint, mindfulness-minutes: uint }))
  (let (
    (user-goal (default-to 
      { sleep-minutes-goal: u0, hydration-ml-goal: u0, mindfulness-minutes-goal: u0, last-updated: u0 } 
      (map-get? user-goals { user: user })))
  )
    ;; If goals are set and met, check for achievements
    (if (and (> (get sleep-minutes-goal user-goal) u0) 
             (>= (get sleep-minutes metrics) (get sleep-minutes-goal user-goal)))
      (try! (award-achievement user u1)) ;; Sleep goal achievement
      true
    )
    
    (if (and (> (get hydration-ml-goal user-goal) u0) 
             (>= (get hydration-ml metrics) (get hydration-ml-goal user-goal)))
      (try! (award-achievement user u2)) ;; Hydration goal achievement
      true
    )
    
    (if (and (> (get mindfulness-minutes-goal user-goal) u0) 
             (>= (get mindfulness-minutes metrics) (get mindfulness-minutes-goal user-goal)))
      (try! (award-achievement user u3)) ;; Mindfulness goal achievement
      true
    )
    
    (ok true)
  )
)

;; Check if user has earned streak-based achievements
(define-private (check-streak-achievements (user principal) (streak-days uint))
  (cond
    ((>= streak-days u7) (try! (award-achievement user u4))) ;; 7-day streak achievement
    ((>= streak-days u30) (try! (award-achievement user u5))) ;; 30-day streak achievement
    ((>= streak-days u90) (try! (award-achievement user u6))) ;; 90-day streak achievement
    (true true)
  )
  (ok true)
)

;; Award achievement to user if they don't already have it
(define-private (award-achievement (user principal) (achievement-id uint))
  (let (
    (achievement-exists (is-some (map-get? user-achievements { user: user, achievement-id: achievement-id })))
    (achievement-def (map-get? achievement-definitions { achievement-id: achievement-id }))
  )
    (if (or achievement-exists (is-none achievement-def))
      (ok true) ;; Already awarded or definition doesn't exist
      (let (
        (achievement (unwrap-panic achievement-def))
        (points (get points achievement))
        (current-time (get-current-time))
      )
        ;; Record the achievement
        (map-set user-achievements
          { user: user, achievement-id: achievement-id }
          {
            title: (get title achievement),
            description: (get description achievement),
            date-earned: current-time,
            points: points
          }
        )
        
        ;; Update total points
        (let (
          (user-point-data (default-to { total-points: u0 } (map-get? user-points { user: user })))
          (new-total (+ (get total-points user-point-data) points))
        )
          (map-set user-points
            { user: user }
            { total-points: new-total }
          )
        )
        
        (ok true)
      )
    )
  )
)

;; Read-only functions

;; Get a user's wellness metrics for a specific date
(define-read-only (get-daily-metrics (user principal) (date uint))
  (match (map-get? daily-metrics { user: user, date: date })
    metrics (ok metrics)
    ERR-USER-NOT-FOUND
  )
)

;; Get a user's personal wellness goals
(define-read-only (get-user-goals (user principal))
  (match (map-get? user-goals { user: user })
    goals (ok goals)
    ERR-GOAL-NOT-FOUND
  )
)

;; Get all achievements for a user
(define-read-only (get-user-achievements (user principal))
  (ok (map-get? user-points { user: user }))
)

;; Get details for a specific achievement
(define-read-only (get-achievement-details (achievement-id uint))
  (match (map-get? achievement-definitions { achievement-id: achievement-id })
    details (ok details)
    (err u404) ;; Not found
  )
)

;; Get a user's current streak information
(define-read-only (get-user-streak (user principal))
  (match (map-get? user-streaks { user: user })
    streak (ok streak)
    (ok { current-streak-days: u0, longest-streak-days: u0, last-activity-date: u0 })
  )
)

;; Check if a user has a specific achievement
(define-read-only (has-achievement (user principal) (achievement-id uint))
  (is-some (map-get? user-achievements { user: user, achievement-id: achievement-id }))
)

;; Get a user's total achievement points
(define-read-only (get-user-points (user principal))
  (default-to { total-points: u0 } (map-get? user-points { user: user }))
)

;; Public functions

;; Record or update wellness metrics for a specific date
(define-public (record-metrics (date uint) (sleep-minutes uint) (hydration-ml uint) (mindfulness-minutes uint))
  (let (
    (user tx-sender)
    (current-time (get-current-time))
  )
    ;; Validate inputs
    (asserts! (validate-metrics sleep-minutes hydration-ml mindfulness-minutes) ERR-INVALID-DATA)
    (asserts! (not (is-date-in-future date)) ERR-DATE-IN-FUTURE)
    
    ;; Record metrics
    (map-set daily-metrics
      { user: user, date: date }
      {
        sleep-minutes: sleep-minutes,
        hydration-ml: hydration-ml,
        mindfulness-minutes: mindfulness-minutes,
        last-updated: current-time
      }
    )
    
    ;; Update streak and check for achievements
    (try! (update-streak user date))
    (try! (check-daily-achievements user 
      { 
        sleep-minutes: sleep-minutes, 
        hydration-ml: hydration-ml, 
        mindfulness-minutes: mindfulness-minutes 
      }))
    
    (ok true)
  )
)

;; Set personal wellness goals
(define-public (set-goals (sleep-minutes-goal uint) (hydration-ml-goal uint) (mindfulness-minutes-goal uint))
  (let (
    (user tx-sender)
    (current-time (get-current-time))
  )
    ;; Validate inputs
    (asserts! (validate-metrics sleep-minutes-goal hydration-ml-goal mindfulness-minutes-goal) ERR-INVALID-DATA)
    
    ;; Set goals
    (map-set user-goals
      { user: user }
      {
        sleep-minutes-goal: sleep-minutes-goal,
        hydration-ml-goal: hydration-ml-goal,
        mindfulness-minutes-goal: mindfulness-minutes-goal,
        last-updated: current-time
      }
    )
    
    (ok true)
  )
)

;; Initialize achievement definitions (admin only function)
;; In a production environment, this would be restricted to contract owner
(define-public (init-achievement (achievement-id uint) (title (string-ascii 50)) 
                                (description (string-ascii 200)) (points uint) 
                                (type (string-ascii 20)))
  (begin
    ;; In production, add authorization check: (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
    (map-set achievement-definitions
      { achievement-id: achievement-id }
      {
        title: title,
        description: description,
        points: points,
        type: type
      }
    )
    (ok true)
  )
)