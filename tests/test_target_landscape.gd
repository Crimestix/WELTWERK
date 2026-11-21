extends TestSuite


func test_height_and_placements_are_repeatable() -> void:
	var a := TargetLandscape.new()
	var b := TargetLandscape.new()
	for p in [Vector2(0, 0), Vector2(-80, -100), Vector2(40, 10), Vector2(-200, -250)]:
		check_equal(a.height(p.x, p.y), b.height(p.x, p.y), "gleiche Höhe bei %s" % p)
	check_equal(a.ledges(), b.ledges(), "gleiche Felsbänke")
	check_equal(a.trees().size(), b.trees().size(), "gleiche Baumzahl")


func test_lake_right_of_shore_and_meadow_left() -> void:
	var land := TargetLandscape.new()
	for z in [-120.0, -60.0, 0.0, 40.0]:
		var s := land.shore_x(z)
		check(land.height(s + 25.0, z) < -0.5, "See rechts der Uferlinie (z %d)" % z)
		check(land.height(s - 15.0, z) > 1.0, "Wiese links der Uferlinie (z %d)" % z)


func test_trees_stand_on_land_and_keep_distance() -> void:
	var land := TargetLandscape.new()
	var trees := land.trees()
	check(trees.size() >= 20, "genug Bäume (%d)" % trees.size())
	for i in trees.size():
		var p: Vector3 = (trees[i][0] as Transform3D).origin
		check(land.shore_distance(p.x, p.z) < -10.0, "Baum %d steht nicht am Wasser" % i)
		for j in range(i + 1, trees.size()):
			var q: Vector3 = (trees[j][0] as Transform3D).origin
			check(Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) >= 15.0 - 0.001, "Abstand %d–%d" % [i, j])
