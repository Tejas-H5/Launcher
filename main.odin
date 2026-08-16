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
entry_idx: int
folder_to_move_to: string = ""

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

	entry_idx = 0
	for entry, i in entries {
		if entry.fullpath == current_folder {
			entry_idx = i
			break
		}
	}

	if len(current_entries) > 0 {
		os.file_info_slice_delete(current_entries, context.allocator)
	}
	current_entries       = entries
	if current_folder != "" {
		delete(current_folder)
	}
	current_folder        = folder
	current_folder_parent = os.dir(current_folder)
}

main :: proc() {
	im.init_renderer("Terminal", "./font/IBMPlexMono-Regular.ttf");
	defer im.destroy_renderer();

	folder, err := os.get_executable_directory(context.allocator)
	assert(err == nil)
	move_to_folder(folder)

	// TODO: Do this in our code
	rl.SetExitKey(.ESCAPE)

	for im.next_frame() {
		// do rendering
		im.options().color = BACKGROUND
		im.clear_rect()

		directory_row("..", .Directory, current_folder_parent, entry_idx == -1)
		for entry, i in current_entries {
			directory_row(entry.name, entry.type, entry.fullpath, i == entry_idx)
		}

		if folder_to_move_to != "" {
			move_to_folder(strings.clone(folder_to_move_to))
			folder_to_move_to = ""
		}

		if is_down_pressed() {
			entry_idx = min(len(current_entries) - 1, entry_idx + 1)
		}

		if is_up_pressed() {
			entry_idx = max(-1, entry_idx - 1)
		}
	}
}

directory_row :: proc(name: string, type: os.File_Type, dir: string, selected: bool) {
	im.push_rect_top_split(1.4, .TextLineHeight); {
		if selected {
			im.options().color = FOREGROUND
			im.clear_rect()
			im.options().color = BACKGROUND
		} else {
			im.options().color = FOREGROUND
		}
		im.options().font_size = 30

		start := im.options().cursor_x

		im.rect_draw_textf("%v", name)

		im.options().cursor_x += 40
		if (im.options().cursor_x < start + 200) {
			im.options().cursor_x = start + 200
		}
		im.rect_draw_textf("%v", type)

		if selected && type == .Directory {
			im.options().cursor_x += 40
			im.rect_draw_textf("[Enter]")

			if is_enter_pressed() {
				folder_to_move_to = dir
			}
		}
	}; im.pop();
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

is_enter_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.ENTER)
}

is_back_pressed :: proc() -> bool {
	return rl.IsKeyPressed(.ESCAPE)
}
