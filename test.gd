extends MainLoop

func _iteration(delta):
	var gdn = GDNative.new()
	gdn.library = load("res://test.tres")
	gdn.initialize()
	gdn.terminate()
	return true
