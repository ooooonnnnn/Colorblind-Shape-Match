static func get_random_background_color(base_color: Color) -> Color:
	# מגריל את הבהירות (Value) בין חשוך למואר
	var random_v = randf_range(0.3, 0.9) 
	# מגריל את הרוויה (Saturation) בין דהוי לרווי
	var random_s = randf_range(0.4, 0.8) 
	
	# מחזיר צבע חדש שמבוסס על אותו גוון בדיוק, אבל עם תאורה ורוויה שונה
	return Color.from_hsv(base_color.h, random_s, random_v)
