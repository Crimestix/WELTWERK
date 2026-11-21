extends TestSuite


func test_landscape_and_placements_are_repeatable() -> void:
	var a := StyleLandscape.build()
	var b := StyleLandscape.build()
	check_equal(a.heights, b.heights, "gleiche Landschaft")
	check_equal(StyleLandscape.trees(a), StyleLandscape.trees(b), "gleiche Bäume")
	check_equal(StyleLandscape.rocks(a), StyleLandscape.rocks(b), "gleiche Felsen")


func test_trees_keep_distance_and_stand_on_ground() -> void:
	var field := StyleLandscape.build()
	var trees := StyleLandscape.trees(field)
	check(trees.size() >= 15, "genug Bäume in der Gruppe (%d)" % trees.size())
	for i in trees.size():
		var p := trees[i].origin
		check(field.height_at(p.x, p.z) > 0.0, "Baum %d steht nicht im Wasser" % i)
		for j in range(i + 1, trees.size()):
			var q := trees[j].origin
			check(Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) >= 4.5 - 0.001, "Abstand %d–%d" % [i, j])


func test_lake_is_below_and_hill_above_water() -> void:
	var field := StyleLandscape.build()
	check(field.height_at(StyleLandscape.LAKE.x, StyleLandscape.LAKE.y) < -3.0, "See ist tief")
	check(field.height_at(StyleLandscape.HILL.x, StyleLandscape.HILL.y) > 12.0, "Hügel ist hoch")
