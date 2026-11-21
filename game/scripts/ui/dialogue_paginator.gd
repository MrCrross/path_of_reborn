class_name DialoguePaginator
extends RefCounted

## Actual glyph shaping, shared by the display and regression checks.
## Page boundaries preserve the source text, including punctuation/newlines.
static func paginate(text: String, font: Font, font_size: int, width: float, max_lines: int = 3) -> Array[String]:
	var pages: Array[String] = []
	var remaining: String = text.strip_edges()
	var height: float = font.get_height(font_size) * max_lines
	while not remaining.is_empty():
		var low: int = 1
		var high: int = remaining.length()
		var best: int = 1
		while low <= high:
			var middle: int = floori((low + high) * 0.5)
			var measured: Vector2 = font.get_multiline_string_size(remaining.left(middle), HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
			if measured.y <= height + 0.1:
				best = middle
				low = middle + 1
			else:
				high = middle - 1
		if best < remaining.length():
			var boundary: int = remaining.rfind(" ", best)
			var newline: int = remaining.rfind("\n", best)
			boundary = maxi(boundary, newline)
			if boundary > 0:
				best = boundary
		pages.append(remaining.left(best).strip_edges())
		remaining = remaining.substr(best).strip_edges()
	return pages
