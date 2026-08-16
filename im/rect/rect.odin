package rect

Rect :: struct {
	x0, y0, x1, y1: f32,
}

width :: proc(r: Rect) -> f32 {
	return r.x1 - r.x0
}

height :: proc(r: Rect) -> f32 {
	return r.y1 - r.y0
}
