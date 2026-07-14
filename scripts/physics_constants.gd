extends RefCounted
class_name PhysicsConstants
##
## Project-wide physics constants. Single source of truth for values
## that the gravity / orbit scripts all share. Each consumer script
## keeps a one-line `const X := PhysicsConstants.X` alias so its own
## call sites read identically to before, but the value lives here.
##

## Universal gravitational constant for this project. Higher = stronger
## gravity, lower = floatier feel. Was 1.0 historically; if you change
## this, planet masses / velocities in the level data will need
## re-tuning (the existing level JSON was designed for G = 1.0).
const G: float = 1.0

## Floor for distance in gravity / orbit calculations to avoid
## division-by-zero when a body is exactly at the central mass
## (degenerate but possible during a scene reload or teleport).
const MIN_DIST: float = 1.0
