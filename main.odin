package main

import "core:strings"
import "im"
import rl "vendor:raylib"
import "im/rect"
import "core:os"
import "core:slice"

BACKGROUND :: im.Color{255, 255, 255, 255}
FOREGROUND :: im.Color{0, 0, 0, 255}
ERROR :: im.Color{255, 0, 0, 255}

main :: proc() {
	font := #load(`./font/IBMPlexMono-Regular.ttf`)
	im.init_renderer_memory_font("launcher", font);
	defer im.destroy_renderer();

	init_program()
	free_all(context.temp_allocator)

	s := &global_state

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

		status_bar_height := im.line_height()
		im.begin_split_y(&m, status_bar_height); {
			im.rect_draw_text(s.current_folder)
		}; im.end()

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
					draw_folder_entry({
						fullpath   = "..",
						name       = "..",
						type       = .Folder,
					}, selected_entry_idx == -1)
				}; im.end()

				if len(current_folder_entries) > 0 {
					for entry, i in current_folder_entries {
						is_selected := i == selected_entry_idx
						im.begin_split_y(&m, m + height); {
							draw_folder_entry(entry, is_selected)
						}; im.end()
					}
				} else {
					im.begin_split_y(&m, m + height); {
						im.rect_draw_textf("Empty folder")
					}; im.end()
				}
			}; im.end()
		}; im.end()

		im.begin_split_y(&m, im.height()); {
			im.rect_draw_textf("%v items", len(current_folder_entries))

			im.rect_draw_textf(" | %v saves", save_count)

			if current_error != "" {
				im.rect_draw_textf(" | ")

				im.begin(); {
					im.options().color = ERROR
					im.rect_draw_textf("%v", current_error)
				}; im.end();
			}
		}; im.end()

		folder_to_move_to := ""

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
			selected_entry_idx = len(current_folder_entries) -1
		case is_key_pressed_or_repeated(.T):
			open_terminal_here(s)
		case is_enter_pressed() || is_right_pressed():
			entry, ok := slice.get(current_folder_entries, selected_entry_idx)
			if ok {
				if entry.type == .Folder {
					folder_to_move_to = entry.fullpath
				}
			}
		case is_left_pressed():
			folder_to_move_to = ".."
		case:
			handled = false;
		}

		if folder_to_move_to != "" {
			if folder_to_move_to == ".." {
				folder_to_move_to = os.dir(s.current_folder)
			}

			if folder_to_move_to != s.current_folder {
				move_to_folder(s, strings.clone(folder_to_move_to))
				requesting_save = true
			}
		}

		if handled {
			if selected_entry_idx < -1 {
				selected_entry_idx = -1
			} else if selected_entry_idx > len(current_folder_entries) -1 {
				selected_entry_idx = len(current_folder_entries) -1
			}
		}

		free_all(context.temp_allocator)

		if requesting_save {
			requesting_save = false
			save_state()
		}

		if requesting_recomput_entries {
			requesting_recomput_entries = false
			recompute_current_folder_entries(s)
		}
	}
}

draw_folder_entry :: proc(entry: FolderEntry, selected: bool) {
	if selected {
		im.options().color = FOREGROUND
		im.clear_rect()
		im.options().color = BACKGROUND
	} else {
		im.options().color = FOREGROUND
	}

	start := im.options().cursor_x
	im.rect_draw_textf("%v", entry.name)

	im.options().cursor_x = max(im.options().cursor_x + 40, start + 400)

	switch entry.type {
	case .File:
		im.rect_draw_textf("File")
	case .Folder:
		im.rect_draw_textf("Folder")
	}

	im.options().cursor_x += 40

	if entry.name == ".." {
		im.rect_draw_textf("[<-]")
	}

	if selected && entry.type == .Folder {
		im.rect_draw_textf("[Enter] or [->]")
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
