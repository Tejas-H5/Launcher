package main

import "core:fmt"
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
current_error := ""

init_program :: proc() {
	folder, err := os.get_executable_directory(context.allocator)
	assert(err == nil)
	move_to_folder(folder)
}

move_to_folder :: proc(folder: string) {
	update_errorf("")

	if folder == current_folder {
		return
	}

	entries, err := os.read_all_directory_by_path(folder, context.allocator);
	if err != nil {
		update_errorf("Error moving around: %v", err);
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

	can_append := true
	if len(history) > 0 {
		last_folder := history[len(history) - 1]
		if last_folder == folder {
			last := pop(&history)
			delete(last)
			can_append = false
		}
	}
	if can_append {
		append(&history, current_folder)
	}
	current_folder        = folder

	current_folder_parent = os.dir(current_folder)
}

update_errorf :: proc(format: string, args: ..any) {
	if current_error != "" { delete(current_error) }

	if format == "" {
		current_error = ""
	} else {
		current_error = fmt.aprintf(format, ..args);
	}
}

open_terminal_here :: proc() {
	update_errorf("")

	desc := os.Process_Desc{
		// command=[]string{"alacritty", "--working-directory", current_folder}
		command=[]string{"alacritty --working-directory ", current_folder}
	}
	process, err := os.process_start(desc)
	if err != nil {
		update_errorf("Error opening terminal here: %v", err);
		return
	}
}
