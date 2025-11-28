;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Group 24 Project, Coded by Jelte
; Some comments in this file are made for my personal understanding
; Most comments are made to clarify certain program details.
; Best of luck grading
;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
globals [
  rsensor_angle
  rsensor_dist
  lsensor_angle
  lsensor_dist
  count_cars
  count_bikes
  crashed_bikes
  possible_collision
  time
  date
  circle-patches
  car_rate
  bike_rate
]

links-own [
  link_tag
]

breed [bikes bike]
breed [cars car]

turtles-own [
  speed
  rotation_angle
  tag
  tag2
  tag3
  destination
  randomizer
]

cars-own [
  display?
  leader?
  trace
  counter
  opponent
  col_angle
  in_circle?
  count_exit
]

bikes-own [
  display?
  leader?
  trace
  counter
]

patches-own[
  original_pcolor
  pcounter
  ground_property
  bike_lane?
]


to setup
  ; Setup World, importing a .bmp file and adjust settings for agents.
  ; Reset the entire model world
  clear-all
  resize-world -250 250 -250 250
  set-patch-size 0.5
  reset-ticks
  file-close-all

  if map_layout_code = 1 [
    set map_Layout "crossing_large"
  ]
  if map_layout_code = 2 [
    set map_Layout "crossing_small"
  ]
  if map_layout_code = 3 [
    set map_Layout "roundabout"
  ]

  import-pcolors (word "resources\\" map_layout ".bmp")
  ; Set all the patces ground properties based on the bitmap color
  ask patches [
    set original_pcolor pcolor set pcounter 0
  ]
  ask patches with [original_pcolor = 5.2] [
    set ground_property "street"
  ]
  ask patches with [original_pcolor = 17.5] [
    set ground_property "bike_lane"
    set bike_lane? True
  ]
  ask patches with [original_pcolor = 16.9] [
    set bike_lane? True
  ]
  ask patches with [original_pcolor = 17.1] [
    set bike_lane? True
  ]
  ask patches with [pcolor > 50 and pcolor < 65] [
    set ground_property "obstacle"
  ]
  ask patches with [ground_property = 0] [
    set ground_property "street"
  ]
  ask patches with [pcolor = white] [
    set ground_property 0
  ]
  ; Special clause to set the roundabout circle patches
  if map_layout = "roundabout" [
    ask patches with [original_pcolor = 106.5] [
      set ground_property "circle"
    ]
  ]

  ;Class Cars:
  set-default-shape cars "car top"
  ;Class Bikes:
  set-default-shape bikes "default"

  ; Set car rate and bike rate to a few ticks to avoid extreme clustering of bikes and cars at the start of the program
  set car_rate 15
  set bike_rate 10

  ; Distance to street borders, defines how close cars approach a border/middle of the street
  set rsensor_angle 30
  set rsensor_dist 25
  set lsensor_angle -60
  set lsensor_dist 45
  set crashed_bikes []
  set possible_collision []

  ; set circle patches for roundabout early to avoid lagging
  set circle-patches (patches with [ground_property = "circle"])
  ; Now this is not entirely professional for the assignment, but I want to note my struggle :)
  ; If not substituted and in the case of 8 cars on the map
  ; It would check 8 (cars) * 3 (checks) * 251001 (patches) every tick
  ; This would be 6,024,024 "if statements" for patch checking per tick
  ; So yeah, it was REALLY SLOW
end

to go
; running procedure, runs model until a maximum number of ticks is reached
  ifelse ticks < stop_counter
  [ ; IF
    move
    detect_collision
    spawn_leader
    create_bikes
    tick
  ]
  [ ; ELSE
    stop
  ]

end

to move
 ; Move procedure for car leaders. Leaders are moving dots that create a path each car follows.
 ; Cars have a rotation angle which changes with speed and follow leading dots until the adjacent
 ; leader reaches the end of the layout.
  ask cars with [leader? = True] [ ; For all cars with leader = True
    set rotation_angle (-0.40 * speed + 7) ; Set their maximum rotation angle based on speed
    spawn_car_dot  ; Create a new dot in front of the leader car
    ifelse map_layout = "roundabout" ;
      [ ; IF
        turn_roundabout
      ]
      [ ; ELSE
        turn_intersection
      ]
  ]

  ;Move procedure for bicycle leaders. Similar to car movement but with fixed rotation angle and speed
  ask bikes with [trace = 1] [
    set rotation_angle 8
    ifelse can-move? 3
      [ ; IF
        move_bike_shadow
      ]
      [ ; ELSE
        die
      ]
  ]

  if any? turtles [
    ask cars with [display? = True] [
      turn_left
      turn_right
    ]
  ]

  move_cars
  move_bikes
  brake_cars
end

to spawn_car_dot
  ifelse can-move? 10 ; if it can move without getting out of the map
    [ ; IF
      ask cars with [trace = 1] [
        let maxdot 12 + 2 * [speed] of myself
        ; Speed dependent to more accurately account for braking distance and collision avoidance
        if map_layout = "roundabout" [
          set maxdot 8 + 1 * [speed] of myself
          ; Reduced because on the roundabout the view distance is not that far (nor needed to be far)
          ; Furthermore, this would limit cars entering the roundabout too much
        ]

        if count cars with [trace > 1 and tag = [tag] of myself] >= maxdot [
          stop
          ; Removed check that stopped the dots generation when a collision was detected ahead because it could rarely result in cars turning 180 degrees or getting stuck
        ]

        set counter counter + 1
        hatch 1 [ ; Spawn a new car dot
          set display? False
          set leader? False
          set trace [counter] of myself
          set counter 0
          set tag [tag] of myself
          set tag3 0
          if marker = False [
            set hidden? True
          ]
        ]

        fd 8
      ]
    ]
    [ ; ELSE
      ask other cars with [tag = [who] of myself and trace > 1] [
        die
      ]
      die
      ; Kill the car, but also the followers inside / behind the car
    ]
end

to turn_roundabout
  ask cars with [trace = 1] [
    if (patch-right-and-ahead rsensor_angle rsensor_dist = nobody) or
        (patch-right-and-ahead lsensor_angle lsensor_dist = nobody) [
      stop
    ]

    ifelse any? circle-patches in-radius 40
      [ ; IF
        if (not any? circle-patches in-radius 25) and
            (in_circle? >= 0) [
          ; Face the closest blue patch, then rotate to the right 85 degrees
          ; This wil result in being slightly going left on the roundabout.
          face min-one-of circle-patches [distance myself]
          rt 85
          ifelse ([bike_lane?] of patch-right-and-ahead 50 40 = True) and
                  ([ground_property] of patch-right-and-ahead 50 40 = "street")
            [ ; IF
              ; If the exit it should take will be the next, rotate the car to turn towards this exit.
              if count_exit = false [
                set count_exit True
                set in_circle? in_circle? - 1
                if in_circle? < 0 [
                  rt 40
                ]
                stop
              ]
            ]
            [ ; ELSE
              set count_exit false
            ]
        ]
      ]
      [ ; ELSE
        ; Basic checks that check the ground property on the left and right distances
        ; Does this to correct itself to drive in the correct places.
        ; See turn-intersection
        ifelse ([ground_property] of patch-right-and-ahead rsensor_angle rsensor_dist != "street") or
                ([ground_property] of patch-right-and-ahead lsensor_angle lsensor_dist != "street")
          [ ; IF
            if ([ground_property] of patch-right-and-ahead rsensor_angle rsensor_dist != "street") [
              steer_left
            ]
            if ([ground_property] of patch-right-and-ahead lsensor_angle lsensor_dist != "street") [
              steer_right
            ]
          ]
          [ ; ELSE
            stop
          ]
      ]
  ]
end

to turn_intersection
  ask cars with [trace = 1] [
    if (patch-right-and-ahead rsensor_angle rsensor_dist = nobody) or
        (patch-right-and-ahead lsensor_angle lsensor_dist = nobody) [
      stop
    ]
    ; So it basically follows a line by checking if it has the correct distance
    ; to the left side of the road and the right side of the road.
    ; If on the left it sees grass, it steers right
    ; If on the right it sees grass, it steers left
    ; This corrects it to the perfect position on the road.
    ifelse ([ground_property] of patch-right-and-ahead rsensor_angle rsensor_dist != "street") or
            ([ground_property] of patch-right-and-ahead lsensor_angle lsensor_dist != "street")
      [ ; IF
      if ([ground_property] of patch-right-and-ahead rsensor_angle rsensor_dist != "street") [
        steer_left
      ]
      if ([ground_property] of patch-right-and-ahead lsensor_angle lsensor_dist != "street") [
        steer_right
        ]
      ]
      [ ; ELSE
        stop
      ]
  ]
end

to move_cars
  ask cars with [trace = 0] [
    if (count cars with [tag = [who] of myself and trace = [counter] of myself + 1] = 0) [
      ask other cars with [tag = [who] of myself and trace > 1] [
        die
      ]
      die
      ; Kill the car, but also the followers inside / behind the car
    ]
    face one-of other cars with [tag = [who] of myself and trace = [counter] of myself + 1] ; Face the next dot in line
    if any? other cars in-radius 20 with [tag = [who] of myself and trace = [counter] of myself + 1] [
      ask other cars with [tag = [who] of myself and trace > 1 and trace <= [counter] of myself] [ ; Trailing dots
        set tag3 tag3 + 1
        set color white
        if tag3 >= 5 [
          die
        ]
      ]
      set counter counter + 1
      set opponent []
    ]

    fd speed
  ]
end

to move_bikes
  ask bikes with [trace = 0] [
    if count bikes with [tag = [who] of myself and trace = [counter] of myself + 1] = 0 [
      die
    ]
    ; Go to the next bike dot.
    face one-of other bikes with [tag = [who] of myself and trace = [counter] of myself + 1]
    if any? other bikes in-radius 5 with [tag = [who] of myself and trace = [counter] of myself + 1] [
      ask other bikes with [tag = [who] of myself and trace = [counter] of myself + 1] [
        die
      ]
      set counter counter + 1
    ]
    fd 2
  ]
end

to brake_cars
  ask cars with [trace = 0] [
    ifelse count my-links with [link_tag = 1] = 0
      [ ; IF
        accelerate
        stop
      ]
      [ ; ELSE
        if count my-links with [link_tag = 1 and end1 = myself] > 0 [
          let shortest-link min-one-of (my-links with [link_tag = 1 and end1 = myself]) [link-length]
          let dist [link-length] of shortest-link
          ; Because of multiple cars, we now need to find the shortest link, otherwise cars will not react to the correct issues.

          let safe_dist 40
          let slow_dist 80
          if map_layout = "roundabout"
            [set slow_dist 60]

          ifelse dist <= safe_dist
          [ ; IF
            brake
          ]
          [ ; ELSE
            ifelse dist < slow_dist
            [ ; IF
              clutch
              if dist < safe_dist [
                brake
              ]
            ]
            [ ; ELSE
              accelerate
            ]
          ]
        ]
      ]
  ]
end
;-------------------------------------------------------------------------------------------------------------
; Agents


to spawn_leader
  ; Spawn new cars at a random location at the edge of the layout.
  ;if any? other cars with [trace = 0][stop]
  ;if ticks mod car_rate = 0
  if (count cars with [trace = 0] < max_cars) and
     (ticks mod car_rate = 0) [
    let choice random 4  ; Assign a random spawn location within a valid place
    let spawn_x (ifelse-value
      choice = 0 [249]
      choice = 1 [-14]
      choice = 2 [-249]
                 [14])
    let spawn_y (ifelse-value
      spawn_x = 249  [14]
      spawn_x = -249 [-14]
      spawn_x = 14   [-249]
                     [250])

    ask patch spawn_x spawn_y [
      ifelse any? cars in-radius 50
        [ ; IF
          stop
        ]
        [ ; ELSE
          set count_cars count_cars + 1
          sprout-cars 1 [
            set size 43  ; approximate size of an average car ~ 4.3m
            set speed 3
            set leader? False
            set display? True
            set trace 0
            set counter 1
            set opponent []
            set randomizer random 3
            set col_angle []
            set destination one-of ["left" "no-turn" "right"]
            set heading (ifelse-value ; This is not the destination heading but the initial look direction.
              spawn_x = 249 and spawn_y = 14   [-90]
              spawn_x = -249 and spawn_y = -14 [90]
              spawn_x = 14 and spawn_y = -249  [0]
                                              [180])

            hatch 1 [
              set leader? True
              set trace 1
              set tag [who] of myself
              set counter 1
              set in_circle? (ifelse-value
                destination = "no-turn" [1]
                destination = "left" [2]
                destination = "right" [0])

              ifelse marker = true
                [ ; IF
                  set size 3 set shape "default" set color red
                ]
                [ ; ELSE
                  set hidden? True
                ]
            ]
          ]
        ]
    ]
  ]
end

to create_bikes
; Spawn new bikes at a random location at the edge of the layout every x ticks.
  ;if ticks mod bike_rate = 0
  if (count bikes with [trace = 0] < max_bikes) and
     (ticks mod bike_rate = 0) [
    set count_bikes count_bikes + 1
    let choice random 4  ; Assign a random spawn location within a valid place
    let spawn_x (ifelse-value
      choice = 0 [250]
      choice = 1 [-70]
      choice = 2 [-250]
                 [70])
    let spawn_y (ifelse-value
      spawn_x = 250  [70]
      spawn_x = -250 [-70]
      spawn_x = 70   [-250]
                     [250])

    if map_layout = "crossing_small" [
      if spawn_x = -70 [
        set spawn_x (spawn_x + 34)
      ]
      if spawn_y = -70 [
        set spawn_y (spawn_y + 34)
      ]
      if spawn_y = 70 [
        set spawn_y (spawn_y - 34)
      ]
      if spawn_x = 70 [
        set spawn_x (spawn_x - 34)
      ]
    ]

    ask patch spawn_x spawn_y [
      ifelse any? bikes in-radius 50
        [ ; IF
          stop
        ]
        [ ; ELSE
          sprout-bikes 1 [
            set size 15
            set color blue
            set leader? False
            set display? True
            set trace 0
            set counter 1
            set shape "default"
            set randomizer random 3
            set heading (ifelse-value
                spawn_x = 250 and spawn_y > 0  [-90 + randomizer]
                spawn_x = -250 and spawn_y < 0 [90 + randomizer]
                spawn_x > 0 and spawn_y = -250 [0 + randomizer]
                                               [180 + randomizer])
            hatch 1 [
              set leader? True
              set trace 1
              set tag [who] of myself
              set counter 1
              ifelse marker = True
                [ ; IF
                  set size 3
                  set shape "dot"
                  set color blue
                ]
                [ ; ELSE
                  set hidden? True
                ]
            ]
          ]
        ]
    ]
  ]
end

to turn_right
  ; Movement procedure for car leaders. Ground property of patches serves as orientation
  ask cars with [trace = 1 and destination = "right"] [
    ifelse patch-right-and-ahead (rsensor_angle + 5) (rsensor_dist + randomizer + 20) = nobody
      [ ; IF
        stop
      ]
      [ ; ELSE
        ifelse [ground_property] of patch-right-and-ahead (rsensor_angle + 5) (rsensor_dist + randomizer + 20) != "street"
          [ ; IF
            stop
          ]
          [ ; ELSE
            ifelse [ground_property] of patch-right-and-ahead (rsensor_angle + 5) (rsensor_dist + randomizer) = "street"
              [ ; IF
                steer_right
              ]
              [ ; ELSE
                stop
              ]
          ]
      ]
  ]
end

to turn_left
  ; Movement procedure for car leaders. Ground property of patches serves as orientation
  if map_layout != "roundabout" [
    ask cars with [trace = 1 and destination = "left"] [
      ifelse patch-right-and-ahead (lsensor_angle - 5) (lsensor_dist + randomizer + 20) = nobody
      [ ; IF
        stop
      ]
      [ ; ELSE
        ifelse [ground_property] of patch-right-and-ahead (lsensor_angle - 5) (rsensor_dist + randomizer + 20) != "street"
          [ ; IF
            stop
          ]
          [ ; ELSE
            ifelse [ground_property] of patch-right-and-ahead (lsensor_angle - 5) (lsensor_dist + randomizer) = "street"
              [; IF
                steer_left
              ]
              [ ; ELSE
                stop
              ]
          ]
      ]
    ]
  ]
end

to accelerate ; Gas
  if speed < 6 [
    set speed speed + 0.07
  ]
end

to clutch ; Clutch (slow down without braking here, speed up is handled by accelerate)
  ifelse speed > 3
    [ ; IF
      set speed speed - 0.55
    ]
    [ ; ELSE
      stop
    ]
end

to brake ; Brake
  if speed > 0 [
      set speed (speed - 1.11)
    ]
  if speed < 0 [
    set speed 0
  ]
end

to steer_right
  set rotation_angle (-0.4 * speed + 7)
  rt rotation_angle
end

to steer_left
  set rotation_angle (-0.4 * speed + 7)
  rt rotation_angle * -1
end

to move_bike_shadow
; Move leading dots alongside the street / bike-lane and create a set of dots alongside the track.
  ask bikes with [trace = 1] [
    if patch-right-and-ahead 10 15 = nobody or patch-right-and-ahead -10 15 = nobody [
      stop
    ]
    ifelse ([bike_lane?] of patch-right-and-ahead 10 15 != True) or
           ([bike_lane?] of patch-right-and-ahead -10 15 != True)
      [ ; IF
        if ([bike_lane?] of patch-right-and-ahead -10 15 != True) and
           ([bike_lane?] of patch-right-and-ahead 10 15 != True) [
          rt -8
        ]
        if [bike_lane?] of patch-right-and-ahead -10 15 != True [
          rt 8
        ]
        if [bike_lane?] of patch-right-and-ahead 10 15 != True [
          rt -8
        ]
      ]
      [ ; ELSE
        if patch-right-and-ahead 0 40 = nobody [
          stop
        ]
      ]
  ]

  if any? bikes with [trace = 1] [
    ask bikes with [trace = 1] [
      if count bikes with [trace > 1 and tag = [tag] of myself] >= 15 [
        stop
      ]
      set counter counter + 1
      hatch 1 [
        set display? False
        set leader? False
        set trace [counter] of myself
        set counter 0
        set tag [tag] of myself
        if marker = False [
          set hidden? True
        ]
      ]
      fd 4
    ]
  ]
end

to detect_collision
 ; Detect possible collisions by checking if any leading tracks interfere with each other.
 ; If so, create a marker and calculate distance to this marker.
 ; If cars are close, they start to press the clutch and eventually brake to avoid a collision.
 ; When cars are further away, the car goes from full brake to a slow going speed by using the clutch.
 ; If enough space is there, the cars use gas.

  ask cars with [trace = 0] [
    ask my-links [
      die
    ]
  ]

  ask cars with [trace > 1] [
    ; This part checks for possible collitions.
    ifelse (map_layout != "roundabout" and ; On a crossing, allow cars that spawned first (lower tag number) to go first
            any? cars with [tag < [tag] of myself
                            and trace > 0
                            and [tag3] of myself = 0
                            ] in-radius 15)
        or (map_layout = "roundabout" and ; Before a roundabout (coords more than 85 and trace less than 22) follow first-come first-serve
            any? cars with [tag != [tag] of myself and
                            trace > 0 and
                            (abs([pxcor] of turtle [tag] of myself) >= 85 or
                            abs([pycor] of turtle [tag] of myself) >= 85)
                            and tag3 != 0
                            and [tag3] of myself = 0
                            and [trace] of myself < 22
                            ] in-radius 15)
        or (map_layout = "roundabout" and ; Very close to roundabout, cars on the roundabout have priority
            any? cars with [tag != [tag] of myself and
                            trace > 0 and
                            (abs([pxcor] of turtle tag) < 85 and
                            abs([pycor] of turtle tag) < 85) and
                            (abs([pxcor] of turtle [tag] of myself) >= 85 or
                            abs([pycor] of turtle [tag] of myself) >= 85)
                            and [tag3] of myself = 0
                            and [trace] of myself < 27
                            ] in-radius 15)
        or (map_layout = "roundabout" and ; On the roundabout itself, let any car it sees go first (because it can't never see behind itself)
            any? cars with [tag != [tag] of myself and
                            trace > 1 and
                            (abs([pxcor] of turtle [tag] of myself) < 85 and
                            abs([pycor] of turtle [tag] of myself) < 85) and
                            (abs([pxcor] of turtle tag) < 85 and
                            abs([pycor] of turtle tag) < 85)
                            and tag3 != 0
                            and [tag3] of myself = 0
                            ] in-radius 15)
        or (any? bikes with [tag != [tag] of myself ; Always give priority to bikes
                             and trace > 0
                             and [tag3] of myself = 0
                             ] in-radius 10)
      [ ; IF
        set tag2 "collision"
        set possible_collision
        lput who possible_collision
        set opponent []
        set opponent [tag] of turtles with [tag != [tag] of myself] in-radius 10
        set opponent
        remove-duplicates opponent
      ]
      [ ; ELSE
        set tag2 0
        if marker = False [
          set hidden? True
        ]
      ]
  ]

  ask cars with [trace > 1] [
    ifelse tag2 = "collision"
      [ ; IF
        set shape "x"
        ask car tag [
          set opponent [opponent] of myself
        ]
        if marker = False [
          set hidden? True
        ]
        create-link-from car tag [ ; Visual identifier of possible collision
          set color blue
          set link_tag 1
          if marker = False [
            set hidden? True
          ]
        ]
      ]
      [ ; ELSE
        set shape "dot"
        set size 3
        ask car tag [
          let i 0
          while [i < length opponent] [
            if turtle item i opponent != nobody [
              if not any? turtles with [tag2 = "collision" and tag = [who] of myself] [
                set opponent
                remove item i opponent opponent
              ]
            ]
            set i i + 1
          ]
        ]
      ]
  ]

  ask cars with [empty? opponent = False and trace = 0] [
    let i 0
    while [i < length opponent] [
      if turtle item i opponent != nobody [
        ifelse turtle item i opponent = cars
          [ ; IF
            create-link-to turtle item i opponent [
              set link_tag 3
              set color orange
              if marker = False [
                set hidden? True
              ]
            ]
          ]
          [ ; ELSE
            create-link-to turtle item i opponent [
              set link_tag 4
              set color red
              if marker = False [
                set hidden? True
              ]
            ]
          ]
      ]
      set i i + 1
    ]
    if count my-links with [link_tag = 4] > 0 [
      set col_angle
      lput round ([link-heading] of one-of my-links with [link_tag = 4] - heading) col_angle
    ]
  ]

  set possible_collision
  remove-duplicates possible_collision
end
;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
@#$#@#$#@
GRAPHICS-WINDOW
170
10
671
520
-1
-1
0.5
1
10
1
1
1
0
0
0
1
-250
250
-250
250
1
1
1
ticks
30.0

BUTTON
5
450
165
483
NIL
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

BUTTON
5
390
165
423
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
5
484
165
517
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

SWITCH
675
145
800
178
marker
marker
0
1
-1000

CHOOSER
675
220
800
265
map_Layout
map_Layout
"crossing_large" "crossing_small" "roundabout"
2

MONITOR
5
40
165
85
NIL
count_cars
17
1
11

MONITOR
5
86
165
131
NIL
count_bikes
17
1
11

MONITOR
5
130
103
175
Possible Collisions
length possible_collision
1
1
11

INPUTBOX
675
35
800
95
stop_counter
10000.0
1
0
Number

TEXTBOX
10
20
155
38
Monitor:
12
0.0
1

TEXTBOX
680
15
830
33
Settings:
12
0.0
1

TEXTBOX
5
370
120
388
Start/Stop:
12
0.0
1

TEXTBOX
5
425
125
446
Press Setup to reset model or after changing layout
9
0.0
1

TEXTBOX
675
100
800
131
Stop counter determines the amount of ticks after which the model will stop running.
9
0.0
1

TEXTBOX
680
185
795
206
Toggle on/off markers for line of sight and collisions.
9
0.0
1

TEXTBOX
675
270
795
295
Choose layout. Reset after changes.
9
0.0
1

SLIDER
170
525
400
558
max_cars
max_cars
0
13
5.0
1
1
NIL
HORIZONTAL

SLIDER
440
525
670
558
max_bikes
max_bikes
0
15
5.0
1
1
NIL
HORIZONTAL

SLIDER
675
305
800
338
map_layout_code
map_layout_code
0
3
0.0
1
1
NIL
HORIZONTAL

TEXTBOX
680
350
795
441
Map Layout Code Selector is there for easier analysis. \n0 = Uses the map layout selector\n1 = Large Crossing\n2 = Small Crossing\n3 = Roundabout
10
0.0
1

@#$#@#$#@
# Traffic Simulation Model (Group 24)
Coded in full by Jelte Dijkmans
## WHAT IS IT?

This model simulates traffic dynamics between cars and bicycles. Traffic participants traverse different kinds of crossroad layouts while tracking line of sight to others to avoid collisions.
This model allows for multiple types of intersections, supplied in the resources folder. 

## HOW IT WORKS

Agents traverse the intersections by comparing the own position to street / bike-lane borders or obstacles. They constantly correct their direction to keep lane and reach a preset destination. 
Further, cars have accelerate and break methods to avoid collisions with bicycles and other cars.
Agents are capable to project their own future position to other traffic participants to allow collision forecasting. 
In the small and large crossings, the cars take a first-come first-serve approach.
In the roundabout, cars already on the roundabout have priority over incoming cars. 
Bicycles always have priority over cars, and in this model serve as a measure of congestion.

## HOW TO USE IT

Select a desired layout and choose the maximal amount of cars and bikes that can be on the road at a time. Then press setup to initialize the model.
Press go (forever) to let the simulation run until it reaches the given amount of ticks. 

## BEHAVIORSPACE
There is one experiment in behaviorspace, named Sim_Traffic.
It uses the following values:
Stop Counter: 10000 ticks
Max Bikes: 0 - 15 in steps of 3
Max Cars: 1 - 13 in steps of 2
Map Layout Code: 1, 2, 3
This is 126 runs for all combinations.

## REFERENCES
This model was based off of a model that checks chance for accidents on different types of intersections with one car and a low amount of bikes at a time.
On this model, multiple cars were added, their intersectioning logic was made, and a lot of rewriting / optimalization was done to make the code run at a decent speed.


Vincent Franke (2021, August 05). “Agent-based Line-of-Sight Simulation for safer Crossings (Short Paper - Netlogo Model)” (Version 1.0.0). CoMSES Computational Model Library. Retrieved from: https://www.comses.net/codebases/751f7ab5-33e1-412a-abae-86288e424d35/releases/1.0.0/
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

bike
false
1
Line -7500403 false 163 183 228 184
Circle -7500403 false false 213 184 22
Circle -7500403 false false 156 187 16
Circle -16777216 false false 28 148 95
Circle -16777216 false false 24 144 102
Circle -16777216 false false 174 144 102
Circle -16777216 false false 177 148 95
Polygon -2674135 true true 75 195 90 90 98 92 97 107 192 122 207 83 215 85 202 123 211 133 225 195 165 195 164 188 214 188 202 133 94 116 82 195
Polygon -2674135 true true 208 83 164 193 171 196 217 85
Polygon -2674135 true true 165 188 91 120 90 131 164 196
Line -7500403 false 159 173 170 219
Line -7500403 false 155 172 166 172
Line -7500403 false 166 219 177 219
Polygon -16777216 true false 187 92 198 92 208 97 217 100 231 93 231 84 216 82 201 83 184 85
Polygon -7500403 true true 71 86 98 93 101 85 74 81
Rectangle -16777216 true false 75 75 75 90
Polygon -16777216 true false 70 87 70 72 78 71 78 89
Circle -7500403 false false 153 184 22
Line -7500403 false 159 206 228 205

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

car top
true
0
Polygon -7500403 true true 151 8 119 10 98 25 86 48 82 225 90 270 105 289 150 294 195 291 210 270 219 225 214 47 201 24 181 11
Polygon -16777216 true false 210 195 195 210 195 135 210 105
Polygon -16777216 true false 105 255 120 270 180 270 195 255 195 225 105 225
Polygon -16777216 true false 90 195 105 210 105 135 90 105
Polygon -1 true false 205 29 180 30 181 11
Line -7500403 false 210 165 195 165
Line -7500403 false 90 165 105 165
Polygon -16777216 true false 121 135 180 134 204 97 182 89 153 85 120 89 98 97
Line -16777216 false 210 90 195 30
Line -16777216 false 90 90 105 30
Polygon -1 true false 95 29 120 30 119 11

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
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Sim_Traffic" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count_cars</metric>
    <enumeratedValueSet variable="stop_counter">
      <value value="10000"/>
    </enumeratedValueSet>
    <steppedValueSet variable="max_bikes" first="0" step="3" last="15"/>
    <enumeratedValueSet variable="marker">
      <value value="false"/>
    </enumeratedValueSet>
    <steppedValueSet variable="map_layout_code" first="1" step="1" last="3"/>
    <steppedValueSet variable="max_cars" first="1" step="2" last="13"/>
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
1
@#$#@#$#@
