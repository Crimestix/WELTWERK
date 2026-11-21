extends TestSuite


func test_generate_is_repeatable() -> void:
	var a := Heightfield.generate(5, 64.0, 2.0)
	var b := Heightfield.generate(5, 64.0, 2.0)
	check_equal(a.heights, b.heights, "gleicher Ausgangswert → gleiches Gelände")
	check_equal(a.seed_value, 5, "Ausgangswert bleibt erkennbar")


func test_different_seed_gives_different_terrain() -> void:
	var a := Heightfield.generate(5, 64.0, 2.0)
	var b := Heightfield.generate(6, 64.0, 2.0)
	check(a.heights != b.heights, "anderer Ausgangswert → anderes Gelände")


func test_grid_layout() -> void:
	var field := Heightfield.generate(1, 100.0, 2.0)
	check_equal(field.columns, 51, "Spalten")
	check_equal(field.rows, 51, "Zeilen")
	check_near(field.size().x, 100.0, 0.001, "Breite")
	check_near(field.origin.x, -50.0, 0.001, "liegt mittig")


func test_height_at_matches_grid_points_and_interpolates() -> void:
	var field := Heightfield.new(3, 3, 1.0)
	field.set_height(0, 0, 0.0)
	field.set_height(1, 0, 10.0)
	field.set_height(0, 1, 20.0)
	field.set_height(1, 1, 30.0)
	# Rasterpunkt (0,0) liegt bei Welt (-1, -1).
	check_near(field.height_at(-1.0, -1.0), 0.0, 0.0001, "Ecke")
	check_near(field.height_at(0.0, -1.0), 10.0, 0.0001, "Nachbar in x")
	check_near(field.height_at(-0.5, -0.5), 15.0, 0.0001, "Mitte der Zelle")
	check_near(field.height_at(-50.0, -50.0), 0.0, 0.0001, "außerhalb = Randhöhe")


func test_hand_edit_overrides_generated_height() -> void:
	var field := Heightfield.generate(3, 20.0, 1.0)
	field.set_height(10, 10, 99.0)
	check_near(field.height_at(0.0, 0.0), 99.0, 0.0001, "von Hand gesetzte Höhe gilt")


func test_flat_normal_points_up() -> void:
	var field := Heightfield.new(5, 5, 1.0)
	var n := field.normal_at(2, 2)
	check_near(n.y, 1.0, 0.0001, "ebene Fläche zeigt nach oben")


func test_raycast_hits_ground() -> void:
	var field := Heightfield.generate(11, 200.0, 1.0)
	var hit: Variant = field.raycast(Vector3(3.0, 300.0, -7.0), Vector3(0.2, -1.0, 0.1))
	check(hit != null, "Strahl trifft")
	if hit != null:
		var p: Vector3 = hit
		check_near(p.y, field.height_at(p.x, p.z), 0.05, "Treffer liegt auf dem Gelände")


func test_raycast_misses_when_pointing_up() -> void:
	var field := Heightfield.generate(11, 50.0, 1.0)
	check(field.raycast(Vector3(0.0, 200.0, 0.0), Vector3.UP, 500.0) == null, "Strahl nach oben trifft nicht")
