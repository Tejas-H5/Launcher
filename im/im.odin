// A thin immediate-mode wrapper over Raylib to proide simple drawing capabilities.
// We may want to warp something else later.
package im

import "core:fmt"
import "core:c"
import rl "vendor:raylib"
import "rect"

r: ^Renderer

Renderer :: struct {
	base_font         : Font,
	is_running        : bool,
	options_stack     : []DrawOptions,
	options_stack_idx : int,

	monitor : c.int,
}


Color :: rl.Color
Font  :: rl.Font
Rect  :: rect.Rect

// Putting them in a struct should allow us to push/pop them.
DrawOptions :: struct {
	font      : Font,
	font_size : f32,
	rect      : Rect,
	color     : Color,
	cursor_x, cursor_y : f32,

	// you need to make all required measurements yourself!
	phase: MeasureDrawPhase,
}

AmountUnit :: enum {
	Fraction,       // a fraction between 0-1. WARNING: this unit will be inconsistent for different container widths. 
					// It trips up measure_draw_phases code - the draw phase may use a narrower container, which fks it up.

	Pixel,          // an absolute value
	TextLineHeight, // The height of one line of text
}

MeasureDrawPhase :: enum {
	Draw,	 // Enables drawing
	Measure, // Disables drawing for the sake of measurement
}

// Runs a measure phase followed by a draw phase.
// The measure phase disables all drawing, so that you can measure your UI.
// The draw phase re-enables drawing. This is where you draw the UI for real, at the correct location.
// The system doesn't populate width and height for you. That's your job to do in the 'Measure' phase!
// We are doing this because we want to avoid implementing a UI layout system. :D (might lead to some stupid consequences, but I think it's fine)
measure_draw_phases :: proc(m: ^Measurer, ) -> (MeasureDrawPhase, bool) {
	// every measure_draw_phases causes UI that would have rendered itself once to render itself and all it's children twice. 
	// the time-complexity will be exponential to the 'depth' of the call tree formed by just the calls to measure_draw_phases. 
	// Shouldnt be too bad actually I dont think. but all the temporary strings getting re-allocated over and over might get us.

	if m.phase_idx == 0 {
		m.phase_idx = 1
		m.stack_idx = r.options_stack_idx

		push();
		options().phase = .Measure
		return .Measure, true
	}

	if m.phase_idx == 1 {
		m.phase_idx = 2

		pop()

		// Detect whether we've pushed or popped too many things, whle we're at it
		assert(r.options_stack_idx == m.stack_idx)

		// Ensure the measurement phase is correctly propagated.
		// Only the root-level call can re-enable draw phase
		current_phase := options().phase

		push()
		options().phase = current_phase
		return .Draw, true
	}

	pop()
	return .Measure, false
}

push_aligned_rect :: proc(rect: Rect, x_align, y_align: f32) {
	if rect == {} {
		push()
		return
	}

	curr := options().rect

	curr_width := curr.x1 - curr.x0
	rect_width := rect.x1 - rect.x0
	x0 := curr.x0 + x_align * (curr_width - rect_width)

	curr_height := curr.y1 - curr.y0
	rect_height := rect.y1 - rect.y0
	y0 := curr.y0 + y_align * (curr_height - rect_height)

	to_push := Rect{x0, y0, x0 + rect_width, y0 + rect_height}
	push_rect(to_push);
}

COLOR_RED :: Color{255,0 ,0, 255}

init_renderer :: proc(window_title: cstring, font_dir: cstring) {
	rl.InitWindow(800, 600, window_title)
	rl.SetWindowState({.WINDOW_MAXIMIZED, .WINDOW_RESIZABLE})
	rl.SetExitKey(.KEY_NULL)

	font := rl.LoadFontEx(font_dir, 128, nil, 250)

	r = new_clone(Renderer{base_font = font})
	r.options_stack = make([]DrawOptions, 64)
	r.monitor = -1
	
	rl.BeginDrawing();
}

destroy_renderer :: proc() {
	rl.CloseWindow();
	delete(r.options_stack);
	free(r)
	r = nil
}

// It's actually an iterator.
next_frame :: proc() -> bool {
	rl.EndDrawing()

	// --- frame boundary
	free_all(context.temp_allocator)

	monitor := rl.GetCurrentMonitor()
	if r.monitor != monitor {
		r.monitor = monitor
		rl.SetTargetFPS(rl.GetMonitorRefreshRate(monitor))
	}

	rl.BeginDrawing();

	r.options_stack_idx = 0;
	r.options_stack[0] = {
		font = r.base_font,
		font_size = 24,
		color = {255, 255, 255, 255},
		rect = {
			x0 = 0, y0 = 0, 
			x1 = f32(rl.GetScreenWidth()), y1 = f32(rl.GetScreenHeight()),
		}
	}

	return !rl.WindowShouldClose();
}

options :: proc() -> ^DrawOptions {
	return &r.options_stack[r.options_stack_idx]
}

push :: proc() {
	r.options_stack_idx += 1
	assert(r.options_stack_idx < len(r.options_stack))
	r.options_stack[r.options_stack_idx] = r.options_stack[r.options_stack_idx - 1]
}

push_rect :: proc(rect: Rect) {
	push();
	options().rect = rect
}

pop :: proc() {
	if r.options_stack_idx > 0 {
		r.options_stack_idx -= 1
	}
}

clear_rect :: proc() {
	o := options()

	if o.phase == .Draw {
		rl.DrawRectangle(
			c.int(o.rect.x0), 
			c.int(o.rect.y0),
			c.int(o.rect.x1 - o.rect.x0),
			c.int(o.rect.y1 - o.rect.y0),
			o.color
		)
	}
}

is_word_wrap_boundary :: proc(str: string, pos: int) -> bool {
	return str[pos] == ' '
}

// A lot of the string -> cstring conversion shenanigans I've had to do to draw text with raylib
// have resulted in a bunch of temporary allocations that I feel were not  necessary to begin with.
// Additionally, instead of pushing to a temp allocator and freeing at the end of the frame, why not just 
// constantly reset the temp allocator in each function? it's not compatible with other kinds of temp-allocator
// use-cases that are truly temporary in nature though. 

rect_draw_textf :: proc(format: string, args: ..any) -> (f32, f32) {
	if len(args) == 0 {
		return rect_draw_text(format)
	}

	str := fmt.tprintf(format, ..args)
	return rect_draw_text(str)
}

// Draws some text inside the current rectangle, with wrapping and clipping overflow
rect_draw_text :: proc(text: string) -> (f32, f32) {
	o := options()

	width  := o.rect.x1 - o.rect.x0
	height := o.rect.y1 - o.rect.y0

	start := 0
	for start < len(text) {
		end := start
		defer start = end

		if o.cursor_y > height {
			break
		}

		for end < len(text) {
			is_word_wrap := is_word_wrap_boundary(text, end)
			end += 1
			if is_word_wrap {
				break
			}
		}

		// TODO: figure out how to not use temp allocator yet again
		cstr := fmt.ctprint(text[start:end])

		text_width := rl.MeasureTextEx(o.font, cstr, o.font_size, 0).x
		cursor_x_next := o.cursor_x + text_width
		if cursor_x_next > width {
			// Wrap the text
			o.cursor_x = 0
			o.cursor_y += o.font_size
		}

		x := o.rect.x0 + o.cursor_x
		y := o.rect.y0 + o.cursor_y
		if o.phase == .Draw {
			// TODO: figure out how to make the text we render here actually look nice
			rl.DrawTextEx(o.font, cstr, {x, y}, o.font_size, 0, o.color)
		}

		o.cursor_x += text_width
	}

	return o.cursor_x, o.cursor_y
}

to_pixels :: proc(amount: f32, unit: AmountUnit, proportional_size: f32) -> (result: f32) {
	switch unit {
	case .Fraction:
		result = proportional_size * amount
	case .Pixel:
		result = amount
	case .TextLineHeight:
		result = options().font_size * amount
	}
	return
}

push_rect_left_split :: proc(amount: f32, unit: AmountUnit) {
	o := options()

	offset := to_pixels(amount, unit, o.rect.x1 - o.rect.x0);
	m := o.rect.x0 + offset

	to_push := o.rect
	to_push.x1 = m

	o.rect.x0 = m

	push_rect(to_push)
}

push_rect_right_split :: proc(amount: f32, unit: AmountUnit) {
	o := options()

	offset := to_pixels(amount, unit, o.rect.x1 - o.rect.x0);
	m := o.rect.x1 - offset

	to_push := o.rect
	to_push.x0 = m

	o.rect.x1 = m

	push_rect(to_push)
}

push_rect_top_split :: proc(amount: f32, unit: AmountUnit) {
	o := options()

	offset := to_pixels(amount, unit, o.rect.y1 - o.rect.y0);
	m := o.rect.y0 + offset

	to_push := o.rect
	to_push.y1 = m

	o.rect.y0 = m

	push_rect(to_push)
}

push_rect_bottom_split :: proc(amount: f32, unit: AmountUnit) {
	o := options()

	offset := to_pixels(amount, unit, o.rect.y1 - o.rect.y0);
	m := o.rect.y1 - offset

	to_push := o.rect
	to_push.y0 = m

	o.rect.y1 = m

	push_rect(to_push)
}

rect_dims :: proc(o: ^DrawOptions) -> (f32, f32) {
	rect := o.rect
	
	width  := rect.x1 - rect.x0
	height := rect.y1 - rect.y0

	return width, height
}

lerp :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * t
}

Measurer :: struct {
	stack_idx : int,
	phase_idx : int,
}
