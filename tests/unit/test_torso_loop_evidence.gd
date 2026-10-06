extends TestCase

func test_closed_torso_arc_and_rejections() -> void:
	var ring := PackedVector3Array()
	for i in 33:
		var angle := (TAU-0.13)*float(i)/32
		ring.append(Vector3(cos(angle)*0.2,1.2,sin(angle)*0.2))
	assert_true(not TorsoLoopEvidence.observe(ring,0.012).is_empty(),"near-contact material arc actually encloses the torso")
	assert_true(TorsoLoopEvidence.observe(ring.slice(0,24),0.012).is_empty(),"an open sweep is not a closed loop")
	var lifted := ring.duplicate()
	for i in lifted.size(): lifted[i].y += float(i)/32*0.2
	assert_true(TorsoLoopEvidence.observe(lifted,0.012).is_empty(),"projection overlap at different heights is not closure")
	for i in ring.size(): ring[i] += Vector3(0.6,0,0)
	assert_true(TorsoLoopEvidence.observe(ring,0.012).is_empty(),"a side loop does not establish encircling the torso")
