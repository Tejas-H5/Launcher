package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:mem"
import "core:strings"
import "core:encoding/cbor"
import "core:encoding/json"

ItemType :: enum {
	File,
	Folder,
}

Arena :: struct {
	alloc: mem.Allocator,
	arena: mem.Arena,
}

file_picker_arena: Arena

make_arena :: proc(arena: ^Arena, bytes: int) {
	memory := make([]byte, bytes)
	mem.arena_init(&arena.arena, memory)
	// mem.arena_allocator Requires `arena` to already have a fixed position in memory,
	// so we can't return -> Arena here
	arena.alloc = mem.arena_allocator(&arena.arena)
}

// Transitioning from one folder to another requires we hold onto
// memory from the previous view while creating the next view.

FolderEntry :: struct {
	fullpath   : string,
	name       : string,
	type       : ItemType,
	bookmarked : bool,
}
current_folder_entries: []FolderEntry
current_error := ""
save_count := 0

move_to_idx_if_present :: proc(s: ^State, folder: string) -> bool {
	moved := false

	for entry, i in current_folder_entries {
		if entry.fullpath == folder {
			s.selected_entry_idx = i
			moved = true
			break
		}
	}

	return moved
}

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
	last_bookmark_idx: int,
	last_entry_idx: int,

	history: [dynamic; 256]HistoryEntry,
	bookmarked_folders: [dynamic; 256]string,
	viewing_bookmarks: bool,
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
	make_arena(&file_picker_arena, 10 * mem.Megabyte)

	// load_state()

	folder := global_state.current_folder
	if folder == "" {
		working_dir, err := os.get_executable_directory(context.allocator)
		if err != nil {
			panic("The program cannot access it's own directory. Bruh")
		}
		folder = working_dir
	}

	move_to_folder(&global_state, folder)
}

move_to_folder :: proc(s: ^State, folder: string) {
	update_errorf("")

	prev_folder := s.current_folder
	prev_selected_folder := ""
	can_append_history := prev_folder != ""
	pop_history := false
	if can_append_history {
		if len(s.history) > 0 {
			last_history := s.history[len(s.history) - 1]
			if last_history.folder == folder {
				pop_history = true
				can_append_history = false
			}
		}

		if can_append_history {
			prev_selected, ok := slice.get(current_folder_entries, s.selected_entry_idx)
			if ok {
				prev_selected_folder = strings.clone(prev_selected.fullpath)
			}
		}
	}

	s.current_folder    = folder
	s.viewing_bookmarks = false

	recompute_current_folder_entries(s)

	// store history regardless of whether updating the view worked

	if pop_history {
		// We moved somewhere that we stored the selected folder for
		last := pop(&s.history)
		move_to_idx_if_present(s, last.selected_folder)
	} else {
		// We moved out of a folder
		move_to_idx_if_present(s, s.current_folder)
	}

	if can_append_history {
		append(&s.history, HistoryEntry{
			folder = prev_folder,
			selected_folder = prev_selected_folder
		})
	}
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

toggle_bookmarked :: proc(s: ^State, folder: string) {
	idx := int(-1)
	for bookmarked_folder, i in s.bookmarked_folders {
		if bookmarked_folder == folder {
			idx = i
			break
		}
	}

	if idx != -1 {
		unordered_remove(&s.bookmarked_folders, idx)
	} else {
		append(&s.bookmarked_folders, folder)
	}

	recompute_current_folder_entries(s)
}

set_viewing_bookmarks :: proc(s: ^State, viewing_bookmarks: bool) {
	s.viewing_bookmarks = viewing_bookmarks
	requesting_save = true
	recompute_current_folder_entries(s)
}

is_bookmarked :: proc(s: ^State, fullpath: string) -> bool {
	for bookmarked_folder in s.bookmarked_folders {
		if bookmarked_folder == fullpath {
			return true
		}
	}
	return false
}

recompute_current_folder_entries :: proc(s: ^State) -> bool {
	update_errorf("")

	if s.viewing_bookmarks {
		s.last_bookmark_idx = s.selected_entry_idx
	} else {
		s.last_entry_idx = s.selected_entry_idx
	}

	arena := file_picker_arena.alloc
	if s.viewing_bookmarks {
		free_all(arena)
		current_folder_entries = make([]FolderEntry, len(s.bookmarked_folders), arena)
		for bookmarked_folder, i in s.bookmarked_folders {
			current_folder_entries[i] = FolderEntry{
				fullpath = bookmarked_folder,
				name     = os.base(bookmarked_folder),
				type     = .Folder,
				bookmarked = true,
			}
		}

		s.selected_entry_idx = s.last_bookmark_idx
		s.selected_entry_idx = clamp(s.selected_entry_idx, 0, len(current_folder_entries) - 1)
	} else {
		entries, err := os.read_all_directory_by_path(s.current_folder, context.allocator);
		defer os.file_info_slice_delete(entries, context.allocator)
		if err != nil {
			update_errorf("Error enumerating %v: %v", s.current_folder, err);
			return false
		}

		free_all(arena)
		current_folder_entries = make([]FolderEntry, len(entries), arena)
		for entry, i in entries {
			type := ItemType.File
			if entry.type == .Directory {
				type = .Folder
			}

			current_folder_entries[i] = FolderEntry{
				name     = strings.clone(entry.name, allocator=arena),
				fullpath = strings.clone(entry.fullpath, allocator=arena),
				type     = type,
				bookmarked = is_bookmarked(s, entry.fullpath),
			}
		}

		slice.sort_by(current_folder_entries[:], proc(a, b: FolderEntry) -> bool {
			get_order :: proc(entry: FolderEntry) -> int {
				switch entry.type {
				case .File: return 1;
				case .Folder: return 0;
				}
				unreachable()
			}

			return get_order(a) < get_order(b)
		});

		s.selected_entry_idx = s.last_entry_idx
		s.selected_entry_idx = clamp(s.selected_entry_idx, -1, len(current_folder_entries) - 1)
	}

	return true
}
