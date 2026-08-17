package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:mem"
import "core:strings"
import "core:encoding/cbor"
import "core:encoding/json"

current_entries: []os.File_Info
current_error := ""
save_count := 0

HistoryEntry :: struct {
	folder: string,
	selected_folder: string,
}

delete_history_entry :: proc(history: HistoryEntry) {
	delete(history.folder)
	delete(history.selected_folder)
}

// This will eventually be persisted
State :: struct {
	current_folder: string,
	selected_entry_idx: int,
	history: [dynamic; 256]HistoryEntry,
}

global_state: State
SAVE_FILE :: "./save.bin"
SAVE_FILE_JSON :: "./save.json"

requesting_save: bool

// Frees the temp allocator btw
save_state :: proc(temp_allocator := context.temp_allocator) {
	file, err := os.open(SAVE_FILE, {.Write, .Create, .Trunc});
	defer os.close(file)
	if err != nil {
		update_errorf("Error opening savefile for writing: %v", err)
		return
	}

	fmt.println("before saved")
	for entry, i in global_state.history {
		fmt.println(i, entry.folder)
	}

	w := os.to_writer(file)
	marshall_err := cbor.marshal_into_writer(w, global_state, temp_allocator=temp_allocator)
	if marshall_err != nil {
		update_errorf("Error saving state: %v", marshall_err)
		return
	}
	defer free_all(temp_allocator)

	fmt.println("saved")
	for entry, i in global_state.history {
		fmt.println(i, entry.folder)
	}

	{
		fmt.println("but reflect says:")
		file, err := os.open(SAVE_FILE_JSON, {.Write, .Create, .Trunc});
		defer os.close(file)
		assert(err == nil)

		w := os.to_writer(file)
		opts := json.Marshal_Options {
			pretty = true
		}
		json.marshal_to_writer(w, global_state, &opts)
	}

	save_count += 1
}

// Frees the temp allocator btw
load_state :: proc(temp_allocator := context.temp_allocator) {
	file, err := os.open(SAVE_FILE, {.Read})
	defer os.close(file)
	if err == .Not_Exist {
		return
	}
	if err != nil {
		update_errorf("Error loading save: %v", os.error_string(err))
		return
	}

	r := os.to_reader(file)
	cbor.unmarshal_from_reader(r, &global_state, temp_allocator=temp_allocator)
	free_all(temp_allocator)
}

init_program :: proc() {
	load_state()

	folder := global_state.current_folder
	if folder == "" {
		working_dir, err := os.get_executable_directory(context.allocator)
		if err != nil {
			panic("The program cannot access it's own directory. Bruh")
		}
		folder = working_dir
	}

	global_state.current_folder = ""
	move_to_folder(&global_state, folder)
}

move_to_folder :: proc(s: ^State, folder: string) {
	update_errorf("")

	if folder == s.current_folder {
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


	old_entries := current_entries
	old_entries_selected_entry_idx := s.selected_entry_idx
	defer if len(old_entries) > 0 {
		os.file_info_slice_delete(old_entries, context.allocator)
	}

	s.selected_entry_idx = 0
	current_entries = entries

	move_to_idx_if_present :: proc(s: ^State, entries: []os.File_Info, folder: string) -> bool {
		moved := false

		for entry, i in entries {
			if entry.fullpath == folder {
				s.selected_entry_idx = i
				moved = true
				break
			}
		}

		return moved
	}
	moved := move_to_idx_if_present(s, entries, s.current_folder)

	if s.current_folder != "" {
		can_append := true
		if len(s.history) > 0 {
			last_history_entry := s.history[len(s.history) - 1]
			if last_history_entry.folder == folder {
				pop(&s.history)
				defer delete_history_entry(last_history_entry)

				can_append = false
				move_to_idx_if_present(s, entries, last_history_entry.selected_folder)
			}
		}

		if can_append {
			selected_folder := ""
			if len(old_entries) > 0 {
				if old_entries_selected_entry_idx >= 0 && old_entries_selected_entry_idx < len(old_entries) {
					selected_folder = strings.clone(old_entries[old_entries_selected_entry_idx].fullpath)
				}
			}

			append(&s.history, HistoryEntry{
				folder          = s.current_folder,
				selected_folder = selected_folder,
			})
		} else {
			delete(s.current_folder)
		}
	}
	s.current_folder = folder
}

update_errorf :: proc(format: string, args: ..any) {
	delete(current_error)

	if format == "" {
		current_error = ""
	} else {
		current_error = fmt.aprintf(format, ..args);
	}
}

open_terminal_here :: proc(s: ^State) {
	update_errorf("")

	desc := os.Process_Desc{
		command=[]string{"alacritty", "--working-directory", s.current_folder}
	}
	process, err := os.process_start(desc)
	if err != nil {
		update_errorf("Error opening terminal here: %v", os.error_string(err));
		return
	}
}
