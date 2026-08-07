class_name LeviathanRig
extends RefCounted

# Poses the skeleton baked by tools/leviathan_rig_bake.gd. Kept apart from
# leviathan.gd so the render probe in tools/ drives the creature with exactly the
# same motion the sequence does, instead of a lookalike that can drift from it.
#
# The swim is a travelling yaw wave down the spine. The head bone is the root and
# is never posed: the sequence aims the maw at the sun every frame, so the wave
# has to run backwards from a fixed head and whip the tail, not sway the skull.

const SWIM_FREQUENCY := 0.32
# How far the wave has travelled by the time it reaches the next joint. A whole
# body holding slightly under half a wavelength is what reads as a swimming fish
# rather than a rope being shaken.
const SWIM_PHASE_LAG := 0.8
const SWIM_HEAD_YAW := 0.05
const SWIM_TAIL_YAW := 0.38
# The tail also lags in the vertical, which keeps the body off a perfectly flat
# plane and stops the silhouette going to a straight line edge on.
const SWIM_PITCH := 0.035
const SWIM_PITCH_FREQUENCY := 0.21

const JAW_MAX_ANGLE := deg_to_rad(62.0)
const LURE_BOB := deg_to_rad(6.0)
const LURE_FREQUENCY := 0.47

var _skeleton: Skeleton3D
var _jaw := -1
var _lure := -1
var _spine := PackedInt32Array()


func _init(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_jaw = skeleton.find_bone("Jaw")
	_lure = skeleton.find_bone("Lure")
	var segment := 1
	while true:
		var bone := skeleton.find_bone("Spine%d" % segment)
		if bone < 0:
			break
		_spine.append(bone)
		segment += 1
	assert(_jaw >= 0 and _lure >= 0 and not _spine.is_empty())


func apply(elapsed: float, maw_open: float, presence: float) -> void:
	var swell := smoothstep(0.0, 1.0, presence)
	var phase := TAU * elapsed * SWIM_FREQUENCY
	for i in _spine.size():
		# Joints near the head barely move and the tail carries the stroke, which
		# is what puts the thrust at the back of the body.
		var along := float(i + 1) / float(_spine.size())
		var yaw := lerpf(SWIM_HEAD_YAW, SWIM_TAIL_YAW, pow(along, 1.6))
		var pitch := SWIM_PITCH * along
		_skeleton.set_bone_pose_rotation(_spine[i], Quaternion(Vector3.UP,
				yaw * swell * sin(phase - float(i + 1) * SWIM_PHASE_LAG))
			* Quaternion(Vector3.RIGHT,
				pitch * swell * sin(TAU * elapsed * SWIM_PITCH_FREQUENCY - float(i + 1) * SWIM_PHASE_LAG)))

	# The mandible hangs forward of its hinge, so a positive turn about the bone's
	# own X drops the chin and opens the mouth.
	_skeleton.set_bone_pose_rotation(_jaw, Quaternion(Vector3.RIGHT, maw_open * JAW_MAX_ANGLE))
	_skeleton.set_bone_pose_rotation(_lure, Quaternion(Vector3.RIGHT,
			LURE_BOB * swell * sin(TAU * elapsed * LURE_FREQUENCY)))


func rest() -> void:
	_skeleton.reset_bone_poses()


# Where a point of the undeformed mesh ends up under the current pose. The
# lantern is a light rather than geometry, so it has to be carried by hand or it
# stays behind while the stalk it hangs off swings.
func lantern_position(rest_point: Vector3) -> Vector3:
	return _skeleton.get_bone_global_pose(_lure) * (_skeleton.get_bone_global_rest(_lure).affine_inverse() * rest_point)
