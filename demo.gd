extends Node3D
## Drives the demo: swings the camera slowly round the water and back over a
## 4 second loop, so the preview starts and ends on the same frame. The water
## animates itself from TIME and needs no script. Leave this file out of your
## own project.

const LOOP_SECONDS := 4.0
const FOCUS := Vector3(0.0, -0.4, -2.0)
const RADIUS := 12.5
const HEIGHT := 5.0
const START_ANGLE := deg_to_rad(35.0)
const SWING := deg_to_rad(5.0)


var _time := 0.0
