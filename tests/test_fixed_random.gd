extends TestSuite


func test_same_seed_same_sequence() -> void:
	var a := FixedRandom.rng_of(42)
	var b := FixedRandom.rng_of(42)
	for i in 20:
		check_equal(a.randi(), b.randi(), "Zahl %d" % i)


func test_different_seed_different_sequence() -> void:
	var a := FixedRandom.rng_of(1)
	var b := FixedRandom.rng_of(2)
	check(a.randi() != b.randi() or a.randi() != b.randi(), "verschiedene Ausgangswerte geben verschiedene Folgen")


func test_derive_is_stable_and_label_dependent() -> void:
	check_equal(FixedRandom.derive(7, "Hügel"), FixedRandom.derive(7, "Hügel"), "gleiche Ableitung")
	check(FixedRandom.derive(7, "Hügel") != FixedRandom.derive(7, "Berge"), "Bezeichnung zählt")
	check(FixedRandom.derive(7, "Hügel") != FixedRandom.derive(8, "Hügel"), "Ausgangswert zählt")


func test_noise_is_repeatable() -> void:
	var a := FixedRandom.noise_of(99)
	var b := FixedRandom.noise_of(99)
	check_equal(a.get_noise_2d(12.5, -3.25), b.get_noise_2d(12.5, -3.25), "gleiches Rauschen")
