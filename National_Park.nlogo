globals [
  attraction-nums              ;; number of attraction clusters
  attraction-distance          ;; distance between two attractions
  tourists-in-each-wave   ;; number of tourists visted in each iteration
  tourists-add-wave            ;; The wave of tourist that we already added in

  park-attraction-level        ;; attraction-level of the park, the higher the more likely people would like to come
  revenue                      ;; revenue earned by the park the we use to measure how good are maintianing model is

  ;; for caculation of tolerance estimation
  tolerance-list               ;; a list stores tolerance of each tourist
  tolerance-mean-prior         ;; prior claim to the mean of tolerance
  tolerance-var-prior          ;; prior claim to the variance of tolerance

  ;; as a threshold for triggering strategy
  tolerance-mean-estimation    ;; estimation for the mean of tolerance
  tolerance-var-estimation     ;; estimation for the variance of tolerance

  ;; for plot
  cumulative-considered-tourists        ;; number of tourists that considered come to the park
  cumulative-come-tourists              ;; number of tourists really present to the park

  ;; for some cleaning strategies
  close?       ;; whether the park are still open for new tourists
  cleaning?    ;; whether the cleaners are cleaning the park currently
]

patches-own [
  attraction?       ;; whehter the gird is attraction
  clean?            ;; whehter the gird is clean
]

turtles-own [
  ;; tourist own
  visited-attractions       ;; number of times that our tourist visited attraction point
  moving-speed              ;; moving speed of tourist
  morality-rate             ;; to determine how unlikey that a tourist will turn an clean cell into dirty
  time-spent                ;; number of steps that the tourist already spent in our park
  duration                  ;; timing length that the tourist plan to stay in our park
  tolerance                 ;; determine whether the tourist will present in the park if they planning to come. If tolerance is lower than 1 - attraction level, the tourist may not present.
  willingness-to-consume    ;; determine how likely people are welling to buy expensive tickets and extra services in the park

  ;; cleaner own
  cleaner?
]

;; setup everything that we need before the simulation start
to setup
  clear-all
  setup-globals
  setup-patches

  ;; only setup cleaner if strategy is open-clean or mixed-clean
  if (strategy != "close-clean")
  [ setup-cleaners ]

  setup-colors
  reset-ticks
end

;; initilize all global varibales
to setup-globals
  set attraction-nums 20
  set attraction-distance 15
  set tourists-in-each-wave 30
  set tourists-add-wave 0
  set park-attraction-level 1
  set revenue 0
  set close? false
  set cleaning? false

  set tolerance-mean-prior 0
  set tolerance-var-prior 0.05
  set tolerance-list []
  set tolerance-mean-estimation tolerance-mean-prior
  set tolerance-mean-estimation tolerance-var-prior

  set cumulative-considered-tourists 0
end

;; Initialise the park here
to setup-patches

  ask patches
  [
    set clean? true
    set attraction? false
  ]

  ;; setup the attraction pathces
  let curr-attraction 0

  ;; create the number of attractions specified
  while [ curr-attraction < attraction-nums ]
  [
    let x random-pxcor
    let y random-pycor

    ;; ensure all attraction can be displayed completely in the square grid
    if (x < (max-pxcor)) and (y < (max-pxcor)) and (x > (min-pxcor)) and (y > (min-pxcor))
    [
      ask patch x y
      [
        let overlap patches with [ distance myself < attraction-distance ]

        ;; two attractions cannot overlap with each other for a certain range
        if not any? overlap with [attraction? = true]
        [
          set attraction? true
          ;; a attraction cluster are defined as a 3*3 grid, therefore
          ;; we set its 8 neighors to attraction as well
          ask n-of 8 neighbors
          [
            set attraction? true
          ]
          set curr-attraction curr-attraction + 1
        ]
      ]
    ]
  ]
end

;; initiate the inital position of cleaner and its dedicate shape
to setup-cleaners
  if number-of-cleaners > 0
  [
    ;; create cleaners
    crt number-of-cleaners
    [
      setxy random-pxcor random-pycor    ;; allocate cleaners randomly
      set cleaner? true

      set shape "person service"
      set color red
    ]
  ]

end

;; set colors for special patches
to setup-colors
  ask patches with [attraction? = true]
  [
    set pcolor red
  ]
end

;; The main update procedure for the model
to go
  ;; update attraction based on the ratio of dirty patches
  update-attraction
  update-tourists

  ifelse (strategy != "close-clean") or (cleaning? = true)
  [
    update-cleaners
  ]
  [
    ; the cost for on-call for close-clean strategy
    set revenue revenue - 0.01 * hourly-wages * number-of-cleaners
  ]


  ;; we only consider to add new wave of tourists every 4 hours
  ;; to reflect the real world case
  if ticks mod 4 = 0
  [
    if (not close?)
    [
      add-new-tourists
      update-belief
    ]

    set tourists-add-wave tourists-add-wave + 1
  ]

  update-strategy

  ;; when there is no tourist, stop the simulation
  if (count turtles with [cleaner? = false] = 0) and tourists-add-wave >= tourist-wave
  [
    stop
  ]

  tick
end

;; update attraction level based on proportion
to update-attraction
  let proportion 3 * (1 - (count patches with [ clean? = true ] - count patches with [ attraction? = true ]) / (count patches with [ attraction? = false ]))
  set park-attraction-level 1 - (e ^ (2 * proportion) - 1) / (e ^ (2 * proportion) + 1)
  print (word "proportion level is: " proportion )
  print (word "attraction level is: " park-attraction-level)
end

;; update our belief of few estimated variable
to update-belief
  update-tolerance
end

;; update our estimation of local mean tolerance
to update-tolerance
  ifelse length tolerance-list > 0
  [
    let sample-var variance tolerance-list   ;; caculating current variance of tolerance
    let sample-mean mean tolerance-list      ;; caculating current mean of tolerance

    let d sample-var ^ 2 + tolerance-var-prior ^ 2

    set tolerance-var-estimation sample-var ^ 2 * tolerance-var-prior ^ 2 / d                                                ;; estimate variance of tolerance
    set tolerance-mean-estimation ((sample-var ^ 2) * sample-mean + (tolerance-var-prior ^ 2) * tolerance-mean-prior) / d    ;; estimate mean of tolerance

    set tolerance-var-prior tolerance-var-estimation
    set tolerance-mean-prior tolerance-mean-estimation
  ]
  [
    ;do nothing at the moment
  ]
end

;; update our choosen strategy state in this procedure based on our belief
to update-strategy
  ;; close-clean strategy
  if strategy = "close-clean"
  [
    ifelse close? = false
    [
      if whether-close   ;; determine whether to close
      [
        set close? true
        set cleaning? true

        setup-cleaners    ;; allocate cleaners
      ]
    ]
    [
      ;; we cleaned all the rubbish
      if count patches with [clean? = false] = 0
      [
        ask turtles with [clean? = true]
        [
          die     ;; move out all cleaners
        ]

        set close? false
        set cleaning? false
      ]
    ]
  ]
  ;; mixed-clean strategy
  if strategy = "mixed-clean"
  [
    ifelse close? = false
    [
      if whether-close   ;; determine whether to close
      [
        set close? true
        set cleaning? true
      ]
    ]
    [
      ;; close to clean all rubbish
      if count patches with [clean? = false] = 0
      [
        set close? false
        set cleaning? true
      ]
    ]
  ]
end

;; report true if we think it is the right time to close the park
to-report whether-close
  if ticks < 10
  [report false]

  ifelse 1 - park-attraction-level > (tolerance-mean-estimation - 0.05 * 0.842)
  [report true]
  [report false]
end

;; update our cleaner state based on
;; differnt cleaning strategy for differntn situation
to update-cleaners
  ask turtles with [cleaner? = true ]
  [
    ;; doing a BFS to find a dirty cell with specific range
    if count patches with [clean? = false] > 0
    [

      let found? false
      let d 3           ;; the distance that our cleaners can sensing currently

      ;; searching for the rubbish nearby
      while [found? = false]
      [
        let near one-of patches with [ distance myself < d and clean? = false ]

        ;; finds rubbish
        if near != nobody
        [
          move-to near
          set found? true

          ;; clean rubbish nearby
          ask patches with [ distance myself < 3 and clean? = false]
          [
            set clean? true
            set pcolor black
          ]
        ]

        ;; under open-clean strategy or mixed-clean strategy, the clean can only sensing the distance up to 8
        if d >= 8 and (strategy = "open-clean" or (strategy = "mixed-clean" and close? = false))
        [
          rt random-float 360
          fd 5                      ;; increase the farthest distance that clearners can arrive
          set found? true
        ]

        set d d + 1      ;; increase cleaning range
      ]
    ]
  ]

  ;; pay our cleaners
  set revenue revenue - number-of-cleaners * hourly-wages
end

to update-tourists
  ask turtles with [cleaner? = false]
  [
    move
  ]
end

;; we update our non-cleaner turtles in this procedure
to move
  ;; remove tourist if they already spent enough time in the park
  if time-spent > duration
  [
    die
  ]

  ;; make the patch dirty depending on morality-rate
  ;; note that attraction cell cannot become dirty
  if [ attraction? ] of patch-here = false and (random-float 1 > morality-rate)
  [
    set pcolor yellow
    ask patch-here
    [
      set clean? false
    ]
  ]

  rt random-float 360
  fd moving-speed

  ;; if the destination is dirty, we skip it and do a BFS which
  ;; select a nearest random point that is clean
  if [ clean? ] of patch-here = false
  [
    let found? false
    let d 1

    while [found? = false or d < 3]
    [
      let near one-of patches with [ distance myself < d and attraction? = true ]

      if near != nobody
      [
        move-to near
        set found? true
      ]

      set d d + 1
    ]

    ;; if no clean cell within distance of d of the destination, we quit earlier
    if d >= 3
    [
      die
    ]
  ]


  ;; attraction can be triggered if the tourist in the attraction cell or just near it
  let near patches with [ distance myself < 2 ]

  if [ attraction? ] of patch-here = true or any? near with [ attraction? = true ]
  [
    set visited-attractions visited-attractions + 1

    if (ticket-price / 80 < willingness-to-consume) [
      set revenue (revenue + ticket-price * 1.25)
    ]
  ]

  set time-spent time-spent + 1
end

;; The procedure we used to add new tourists
to add-new-tourists

  if tourists-add-wave < tourist-wave
  [
    set cumulative-considered-tourists cumulative-considered-tourists + tourists-in-each-wave
    set cumulative-come-tourists cumulative-come-tourists + tourists-in-each-wave

    ;; create tourists in each iteration
    crt tourists-in-each-wave
    [
      ;; set up initial location, cannot be init on attraction cluster and dirty cell
      let init-locataion patches with [ clean? = true and attraction? = false ]
      move-to one-of init-locataion

      set shape "person"
      set color white
      set cleaner? false

      ;; set up moving speed
      set moving-speed 1 + 2 * random 3

      ;; set up time related variables
      set time-spent 0
      set duration 3 + random 3

      ;; set up moral, tolerance and willingness rate of each tourist
      set-moral
      set-tolerance
      set-willingness

      ;; set up figure for the number of attraction that visited by the current tourist
      set visited-attractions 0
    ]

    ask turtles with [ time-spent = 0 and cleaner? = false ]
    [
      ;; determine whether new tourists come or not
      ifelse (1 - tolerance > park-attraction-level) or (ticket-price / 100 > willingness-to-consume)
      [
        set cumulative-come-tourists cumulative-come-tourists - 1
        die
      ]
      [
        set revenue revenue + ticket-price
        ;; add the coming tourist's tolerance to our known collection
        set tolerance-list lput tolerance tolerance-list
      ]
    ]
  ]

end

;; set up moral rate for the tourist to determine the probabilities of throwing rubbish
to set-moral

  let moral random-normal mean-moral 0.1

  if moral > 1
  [
    set moral 1
  ]

  if moral < 0.5
  [
    set moral 0.5
  ]

  set morality-rate moral
end

;; set up tolerance rate for the tourist to determine whether they come/leave the park
to set-tolerance

  set tolerance random-normal mean-tolerance 0.05

  if tolerance < 0.01
  [
    set tolerance 0.01
  ]
  if tolerance > 0.35
  [
    set tolerance 0.35
  ]
end

;; set up willingness-to-consume rate for the tourist to determine the probabilities of different tourists to consume in the park
to set-willingness

  set willingness-to-consume random-normal mean-willingness-to-consume 0.1

  if willingness-to-consume > 0.9
  [
    set willingness-to-consume 0.9
  ]
  if willingness-to-consume < 0.1
  [
    set willingness-to-consume 0.1
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
217
21
1033
838
-1
-1
8.0
1
10
1
1
1
0
1
1
1
-50
50
-50
50
0
0
1
hours
30.0

BUTTON
61
29
135
67
NIL
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
63
105
134
145
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
22
230
194
263
tourist-wave
tourist-wave
0
100
100.0
1
1
NIL
HORIZONTAL

BUTTON
57
171
139
204
auto-go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
20
279
192
312
mean-moral
mean-moral
0.7
1
0.9
0.01
1
NIL
HORIZONTAL

PLOT
5
437
205
587
# of visited attraction
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [visited-attractions] of turtles"

SLIDER
21
332
193
365
mean-tolerance
mean-tolerance
0.01
0.2
0.15
0.01
1
NIL
HORIZONTAL

PLOT
6
626
206
776
Attraction Level
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"attraction level" 1.0 0 -16777216 true "" "plot park-attraction-level"

PLOT
1060
426
1279
592
# tourists
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot cumulative-considered-tourists"
"pen-1" 1.0 0 -13345367 true "" "plot cumulative-come-tourists"

PLOT
1316
622
1538
795
# of Real time tourists
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -5825686 true "" "plot tourists-in-each-wave"
"pen-1" 1.0 0 -13791810 true "" "plot count turtles with [ time-spent = 0 and cleaner? = false ]"

SLIDER
20
385
195
418
ticket-price
ticket-price
20
100
40.0
1
1
NIL
HORIZONTAL

PLOT
1316
425
1538
591
revenue
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot revenue"

SLIDER
1037
116
1251
149
mean-willingness-to-consume
mean-willingness-to-consume
0.1
0.8
0.6
0.01
1
NIL
HORIZONTAL

SLIDER
1042
181
1249
214
number-of-cleaners
number-of-cleaners
0
30
18.0
1
1
NIL
HORIZONTAL

SLIDER
1043
253
1249
286
hourly-wages
hourly-wages
20
60
20.0
1
1
NIL
HORIZONTAL

CHOOSER
1049
334
1187
379
strategy
strategy
"open-clean" "close-clean" "mixed-clean"
1

MONITOR
1322
348
1379
393
wave
tourists-add-wave
17
1
11

PLOT
1058
622
1281
798
proportion of coming tourists
NIL
NIL
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot cumulative-come-tourists / (cumulative-considered-tourists + 1)"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

person service
false
0
Polygon -7500403 true true 180 195 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285
Polygon -1 true false 120 90 105 90 60 195 90 210 120 150 120 195 180 195 180 150 210 210 240 195 195 90 180 90 165 105 150 165 135 105 120 90
Polygon -1 true false 123 90 149 141 177 90
Rectangle -7500403 true true 123 76 176 92
Circle -7500403 true true 110 5 80
Line -13345367 false 121 90 194 90
Line -16777216 false 148 143 150 196
Rectangle -16777216 true false 116 186 182 198
Circle -1 true false 152 143 9
Circle -1 true false 152 166 9
Rectangle -16777216 true false 179 164 183 186
Polygon -2674135 true false 180 90 195 90 183 160 180 195 150 195 150 135 180 90
Polygon -2674135 true false 120 90 105 90 114 161 120 195 150 195 150 135 120 90
Polygon -2674135 true false 155 91 128 77 128 101
Rectangle -16777216 true false 118 129 141 140
Polygon -2674135 true false 145 91 172 77 172 101

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="all_lower_open" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;open-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_lower_closed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;close-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="2" step="2" last="20"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_lower_mixed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;mixed-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_high_open" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;open-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_high_mixed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;mixed-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_high_closed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;close-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="60"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="2" step="2" last="20"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_med_closed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;close-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="2" step="2" last="20"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_med_open" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;open-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="all_med_mixed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;mixed-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="high_to_med_mixed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;mixed-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="high_to_med_open" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;open-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="1" step="1" last="5"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="high_to_med_closed" repetitions="3" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>revenue</metric>
    <metric>cumulative-come-tourists / (cumulative-considered-tourists + 1)</metric>
    <enumeratedValueSet variable="mean-willingness-to-consume">
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="hourly-wages">
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="strategy">
      <value value="&quot;close-clean&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ticket-price">
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-moral">
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tourist-wave">
      <value value="100"/>
    </enumeratedValueSet>
    <steppedValueSet variable="number-of-cleaners" first="2" step="2" last="20"/>
    <enumeratedValueSet variable="mean-tolerance">
      <value value="0.15"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
