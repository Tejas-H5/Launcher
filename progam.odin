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
selected_entry_idx: int
current_error := ""
save_count := 0

move_to_idx_if_present :: proc(s: ^State, folder: string) -> bool {
	moved := false

	for entry, i in current_folder_entries {
		if entry.fullpath == folder {
			selected_entry_idx = i
			moved = true
			break
		}
	}

	return moved
}

// This will eventually be persisted
State :: struct {
	current_folder: string,
	last_bookmark_idx: int,
	last_entry_idx: int,

	bookmarked_folders: [dynamic; 256]string,
	viewing_bookmarks: bool,
}

global_state: State
SAVE_FILE :: "./save.bin"
SAVE_FILE_JSON :: "./save.json"

requesting_save: bool
requesting_recomput_entries: bool

// Frees the temp allocator btw
save_state :: proc(temp_allocator := context.temp_allocator) {
	file, err := os.open(SAVE_FILE, {.Write, .Create, .Trunc});
	defer os.close(file)
	if err != nil {
		update_errorf("Error opening savefile for writing: %v", err)
		return
	}

	w := os.to_writer(file)
	marshall_err := cbor.marshal_into_writer(w, global_state, temp_allocator=temp_allocator)
	if marshall_err != nil {
		update_errorf("Error saving state: %v", marshall_err)
		return
	}
	defer free_all(temp_allocator)

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

	s.current_folder = folder
	set_viewing_bookmarks(s, false)

	requesting_recomput_entries = true

	// store history regardless of whether updating the view worked

	// We moved out of a folder
	move_to_idx_if_present(s, s.current_folder)
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

bookmark_folder :: proc(s: ^State, fullpath: string) {
	idx := _bookmark_idx(s, fullpath)
	if idx == -1 {
		append(&s.bookmarked_folders, fullpath)
	}

	requesting_recomput_entries = true
}

toggle_temp_bookmarked :: proc(s: ^State, fullpath: string) {
	assert(s.viewing_bookmarks)

	for &entry in current_folder_entries {
		if entry.fullpath == fullpath {
			entry.bookmarked = !entry.bookmarked
		}
	}
}

set_viewing_bookmarks :: proc(s: ^State, viewing_bookmarks: bool) {
	folder_to_move_to := ""

	if s.viewing_bookmarks {
		s.last_bookmark_idx = selected_entry_idx
	} else {
		s.last_entry_idx = selected_entry_idx
	}

	if s.viewing_bookmarks && !viewing_bookmarks {
		if len(s.bookmarked_folders) > 0 {
			assert(len(current_folder_entries) == len(s.bookmarked_folders))

			folder_to_move_to = s.bookmarked_folders[selected_entry_idx]

			// Apply changes to bookmarks
			i := 0; 
			for i < len(s.bookmarked_folders) {
				bookmarked_folder := s.bookmarked_folders[i]
				is_bookmarked := false
				for entry in current_folder_entries {
					if entry.fullpath == bookmarked_folder {
						is_bookmarked = entry.bookmarked
						break
					}
				}

				if !is_bookmarked {
					unordered_remove(&s.bookmarked_folders, i)
				} else {
					i += 1
				}
			}
		}
	}

	s.viewing_bookmarks = viewing_bookmarks

	if viewing_bookmarks {
		selected_entry_idx = s.last_bookmark_idx
	} else {
		selected_entry_idx = s.last_entry_idx
	}

	requesting_save = true
	requesting_recomput_entries = true

	if folder_to_move_to != "" {
		move_to_folder(s, folder_to_move_to)
	}
}

is_bookmarked :: proc(s: ^State, fullpath: string) -> bool {
	idx := _bookmark_idx(s, fullpath)
	return idx != -1
}

_bookmark_idx :: proc(s: ^State, fullpath: string) -> int {
	for bookmarked_folder, i in s.bookmarked_folders {
		if bookmarked_folder == fullpath {
			return i
		}
	}

	return -1
}

recompute_current_folder_entries :: proc(s: ^State) -> bool {
	update_errorf("")

	if s.viewing_bookmarks {
		s.last_bookmark_idx = selected_entry_idx
	} else {
		s.last_entry_idx = selected_entry_idx
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

		selected_entry_idx = s.last_bookmark_idx
		selected_entry_idx = clamp(selected_entry_idx, 0, len(current_folder_entries) - 1)
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

		selected_entry_idx = s.last_entry_idx
		selected_entry_idx = clamp(selected_entry_idx, -1, len(current_folder_entries) - 1)
	}

	return true
}
