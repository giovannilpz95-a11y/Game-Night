-- Tag for table decorations drawn as UI that turn in place (Color Clash's direction ring).
-- The server tags an invisible plate whose SurfaceGui holds a Frame named "Spin" and sets
-- the plate's "SpinSpeed" attribute (degrees a second, + clockwise seen from above); each
-- client turns the frame (client/Table3D/Spinner).
return {
	TAG = "GameNightSpin",
}
