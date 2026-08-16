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

// Putting them in a struct should allow us to begin/pop them.
DrawOptions :: struct {
	font      : Font,
	font_size : f32,
	line_height_scale: f32,
	rect      : Rect,
	color     : Color,
	cursor_x, cursor_y : f32,
	is_scissor : bool,
}

begin_aligned_rect :: proc(rect: Rect, x_align, y_align: f32) {
	if rect == {} {
		begin()
		return
	}

	curr := options().rect

	curr_width := curr.x1 - curr.x0
	rect_width := rect.x1 - rect.x0
	x0 := curr.x0 + x_align * (curr_width - rect_width)

	curr_height := curr.y1 - curr.y0
	rect_height := rect.y1 - rect.y0
	y0 := curr.y0 + y_align * (curr_height - rect_height)

	to_begin := Rect{x0, y0, x0 + rect_width, y0 + rect_height}
	begin_rect(to_begin);
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
		line_height_scale = 1.3,
		color = {255, 255, 255, 255},
		rect = {
			x0 = 0, y0 = 0, 
			x1 = f32(rl.GetScreenWidth()), y1 = f32(rl.GetScreenHeight()),
		},
	}

	return !rl.WindowShouldClose();
}

options :: proc() -> ^DrawOptions {
	return &r.options_stack[r.options_stack_idx]
}

width :: proc() -> f32 {
	o := options()
	return rect.width(o.rect);
}

height :: proc() -> f32 {
	o := options()
	return rect.height(o.rect);
}

rect :: proc() -> Rect {
	o := options()
	return o.rect
}

begin :: proc() {
	r.options_stack_idx += 1
	assert(r.options_stack_idx < len(r.options_stack))
	r.options_stack[r.options_stack_idx] = r.options_stack[r.options_stack_idx - 1]

	// Some things shouldn't be inherited.
	options().is_scissor = false
}

begin_rect :: proc(rect: Rect) {
	begin();
	options().rect = rect
}

clip_rect :: proc() {
	o := options()
	if !o.is_scissor {
		o.is_scissor = true
		rl.BeginScissorMode(
			c.int(o.rect.x0),
			c.int(o.rect.y0),
			c.int(o.rect.x1 - o.rect.x0),
			c.int(o.rect.y1 - o.rect.y0),
		)
	}
}

end :: proc() {
	if options().is_scissor {
		rl.EndScissorMode()
	}

	if r.options_stack_idx > 0 {
		r.options_stack_idx -= 1
	}
}

clear_rect :: proc() {
	o := options()

	rl.DrawRectangle(
		c.int(o.rect.x0), 
		c.int(o.rect.y0),
		c.int(o.rect.x1 - o.rect.x0),
		c.int(o.rect.y1 - o.rect.y0),
		o.color
	)
}

is_word_wrap_boundary :: proc(str: string, pos: int) -> bool {
	return str[pos] == ' '
}

// A lot of the string -> cstring conversion shenanigans I've had to do to draw text with raylib
// have resulted in a bunch of temporary allocations that I feel were not  necessary to begin with.
// Additionally, instead of begining to a temp allocator and freeing at the end of the frame, why not just 
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
		// TODO: figure out how to make the text we render here actually look nice
		rl.DrawTextEx(o.font, cstr, {x, y}, o.font_size, 0, o.color)

		o.cursor_x += text_width
	}

	return o.cursor_x, o.cursor_y
}

begin_split_x :: proc(x0: ^f32, x1: f32) {
	rect := options().rect
	rect.x0 = x0^
	rect.x1 = x1

	x0^ = x1

	begin_rect(rect);
}

begin_split_y :: proc(y0: ^f32, y1: f32) {
	rect := options().rect
	rect.y0 = y0^
	rect.y1 = y1

	y0^ = y1

	begin_rect(rect);
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

line_height :: proc() -> f32 {
	return options().font_size * options().line_height_scale
}
