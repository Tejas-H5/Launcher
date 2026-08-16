package main

import "core:strings"
import "im"
import "core:fmt"
import rl "vendor:raylib"
import "im/rect"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:mem"

current_folder := ""
current_folder_parent := ""
current_entries: []os.File_Info
selected_entry_idx: int
folder_to_move_to: string = ""

history: [dynamic]string

BACKGROUND :: im.Color{255, 255, 255, 255}
FOREGROUND :: im.Color{0, 0, 0, 255}

move_to_folder :: proc(folder: string) {
	if folder == current_folder {
		return
	}

	entries, err := os.read_all_directory_by_path(folder, context.allocator);
	if err != nil {
		// TODO: present error to user
		return
	}

	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {
		get_order :: proc(i: os.File_Info) -> int {
			if i.type == .Regular {
				return  1
			}
			return 0
		}

		return get_order(a) < get_order(b)
	});

	selected_entry_idx = 0
	for entry, i in entries {
		if entry.fullpath == current_folder {
			selected_entry_idx = i
			break
		}
	}

	if len(current_entries) > 0 {
		os.file_info_slice_delete(current_entries, context.allocator)
	}
	current_entries       = entries

	append(&history, current_folder)
	current_folder        = folder

	current_folder_parent = os.dir(current_folder)
}

main :: proc() {
	im.init_renderer("Terminal", "./font/IBMPlexMono-Regular.ttf");
	defer im.destroy_renderer();

	folder, err := os.get_executable_directory(context.allocator)
	assert(err == nil)
	move_to_folder(folder)

	for im.next_frame() {
		if is_close_pressed() {
			break
		}

		im.options().color = BACKGROUND
		im.clear_rect()

		im.options().color = FOREGROUND
		im.options().font_size = 30

		m := im.rect().y0

		im.begin_split_y(&m, im.line_height()); {
			im.clip_rect()
			im.rect_draw_text("history")
			for path, i in history {
				if i > 0 {
					im.rect_draw_text(" -> ")
				}
				im.rect_draw_text(path)
			}
		}; im.end()

		im.begin_split_y(&m, im.height()); {
			m := im.rect().y0
			im.begin_split_y(&m, im.line_height()); {
				directory_row("..", .Directory, current_folder_parent, selected_entry_idx == -1)
			}; im.end()
			for entry, i in current_entries {
				im.begin_split_y(&m, im.line_height()); {
					directory_row(entry.name, entry.type, entry.fullpath, i == selected_entry_idx)
				}; im.end()
			}
		}; im.end()

		if folder_to_move_to != "" {
			move_to_folder(strings.clone(folder_to_move_to))
			folder_to_move_to = ""
		}

		handled := true
		if is_down_pressed() {
			selected_entry_idx += 1
		} else if is_up_pressed() {
			selected_entry_idx -= 1
		} else if is_page_down_pressed() {
			selected_entry_idx += 10
		} else if is_page_up_pressed() {
			selected_entry_idx -= 10
		} else if is_home_pressed() {
			selected_entry_idx = -1
		} else if (is_end_pressed()) {
			selected_entry_idx = len(current_entries) -1
		} else {
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

	if selected && type == .Directory {
		im.options().cursor_x += 40
		im.rect_draw_textf("[Enter]")

		if is_enter_pressed() {
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
