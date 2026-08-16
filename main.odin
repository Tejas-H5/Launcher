package main

import "core:strings"
import "im"
import rl "vendor:raylib"
import "im/rect"
import "core:os"

BACKGROUND :: im.Color{255, 255, 255, 255}
FOREGROUND :: im.Color{0, 0, 0, 255}
ERROR :: im.Color{255, 0, 0, 255}

main :: proc() {
	im.init_renderer("Terminal", "./font/IBMPlexMono-Regular.ttf");
	defer im.destroy_renderer();

	init_program()

	for im.next_frame() {
		if is_close_pressed() {
			break
		}

		im.options().color = BACKGROUND
		im.clear_rect()

		im.options().color = FOREGROUND
		im.options().font_size = 30

		// m could become a part of im somehow??
		m := im.rect().y0
		im.begin_split_y(&m, im.height()); {
			im.rect_draw_text("history")
			for path, i in history {
				if i > 0 {
					im.rect_draw_text(" -> ")
				}
				im.rect_draw_text(path)
			}
			m = im.options().cursor_y + im.line_height()
		}; im.end()

		status_bar_height := im.line_height()

		im.begin_split_y(&m, im.height() - status_bar_height); {
			im.clip_rect()

			im.begin(); {
				scroll_point := im.height() / 2
				scroll_to_item := f32(selected_entry_idx) * im.line_height()
				if scroll_to_item > scroll_point {
					im.options().rect.y0 = im.options().rect.y0 - scroll_to_item + scroll_point
				}

				m := im.rect().y0
				height := im.line_height()
				im.begin_split_y(&m, m + height); {
					directory_row("..", .Directory, current_folder_parent, selected_entry_idx == -1)
				}; im.end()

				for entry, i in current_entries {
					im.begin_split_y(&m, m + height); {
						directory_row(entry.name, entry.type, entry.fullpath, i == selected_entry_idx)
					}; im.end()
				}
			}; im.end()
		}; im.end()

		im.begin_split_y(&m, im.height()); {
			im.rect_draw_textf("%v items | ", len(current_entries))

			if current_error != "" {
				im.options().color = ERROR
				im.rect_draw_textf("%v", current_error)
			}
		}; im.end()

		if is_back_pressed() {
			if len(history) > 0 {
				// NOTE: Revisiting the last visited folder will
				// automatically pop it from the history, so we don't
				// need to do that here
				folder_to_move_to = history[len(history) - 1]
			}
		}

		if folder_to_move_to != "" {
			move_to_folder(strings.clone(folder_to_move_to))
			folder_to_move_to = ""
		}

		handled := true
		switch {
		case is_down_pressed():
			selected_entry_idx += 1
		case is_up_pressed():
			selected_entry_idx -= 1
		case is_page_down_pressed():
			selected_entry_idx += 10
		case is_page_up_pressed():
			selected_entry_idx -= 10
		case is_home_pressed():
			selected_entry_idx = -1
		case is_end_pressed():
			selected_entry_idx = len(current_entries) -1
		case is_key_pressed_or_repeated(.T):
			open_terminal_here()
		case:
			handled = false;
		}

		if handled {
			if selected_entry_idx < -1 {
				selected_entry_idx = -1
			} else if selected_entry_idx > len(current_entries) -1 {
				selected_entry_idx = len(current_entries) -1
			}
		}
	}
}

directory_row :: proc(name: string, type: os.File_Type, dir: string, selected: bool) {
	if selected {
		im.options().color = FOREGROUND
		im.clear_rect()
		im.options().color = BACKGROUND
	} else {
		im.options().color = FOREGROUND
	}

	start := im.options().cursor_x
	im.rect_draw_textf("%v", name)

	im.options().cursor_x = max(im.options().cursor_x + 40, start + 400)

	im.rect_draw_textf("%v", type)

	im.options().cursor_x += 40

	if name == ".." {
		im.rect_draw_textf("[<-]")

		if is_left_pressed() {
			folder_to_move_to = current_folder_parent
		} 
	}

	if selected && type == .Directory {
		im.rect_draw_textf("[Enter] or [->]")

		if is_enter_pressed() || is_right_pressed() {
			folder_to_move_to = dir
		}
	}
}

is_key_pressed_or_repeated :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}

is_up_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.K) || is_key_pressed_or_repeated(.UP)
}

is_left_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.H) || is_key_pressed_or_repeated(.LEFT)
}

is_right_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.L) || is_key_pressed_or_repeated(.RIGHT)
}

is_down_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.J) || is_key_pressed_or_repeated(.DOWN)
}

is_home_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.HOME)
}

is_end_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.END)
}

is_page_down_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.PAGE_DOWN)
}

is_page_up_pressed :: proc() -> bool {
	return is_key_pressed_or_repeated(.PAGE_UP)
}

is_enter_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.ENTER)
}

is_close_pressed :: proc() -> bool {
	return rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.W)
}

is_back_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.ESCAPE)
}
