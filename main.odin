package main

import "im"
import "core:os"
import "core:path/filepath"

current_folder := "."
current_entries: []os.File_Info

update_current_folder :: proc(folder: string) {
	current_folder = folder

	entries, err := os.read_all_directory_by_path(folder, context.allocator);
	assert(err == nil);

	if len(current_entries) != 0 { os.file_info_slice_delete(current_entries, context.allocator) }
	current_entries = entries
}

main :: proc() {
	r := im.init_renderer("Terminal", "./font/IBMPlexMono-Regular.ttf");
	defer im.destroy_renderer(r);

	path, err := os.get_executable_path(context.allocator)
	assert(err == nil)
	defer delete(path)

	folder := filepath.dir(path)

	update_current_folder(folder)

	for im.next_frame(r) {
		im.options(r).color = {255, 255, 255, 255}
		im.clear_rect(r)

		im.options(r).color = {0, 0, 0, 255}
		im.options(r).font_size = 30

		dims: im.Measurer; 
		for im.measure_draw_phases(r, &dims) {
			im.push_aligned_rect(r, dims.rect, 0.5, 0.5); {
				dark_theme(r);

				if len(current_entries) > 0 {
					max_width : f32 = 0
					im.push(r); {
						for entry in current_entries {
							x, y := im.rect_draw_textf(r, "%v", entry.name)
							im.rect_pad_top(r, 1, .TextLineHeight)
							max_width = max(x, max_width)
						}
					}; im.pop(r);

					im.rect_pad_left(r, max_width + 40, .Pixel);

					im.push(r); {
						for entry in current_entries {
							im.rect_draw_textf(r, "%v", "what")
							im.rect_pad_top(r, 1, .TextLineHeight)
						}
					}; im.pop(r)
				} else {
					im.rect_draw_text(r, "This directory's got nothing xd");
				}
			}; im.pop(r);
		}
	}
}

light_theme :: proc(r: ^im.Renderer) {
	im.push(r); {
		im.options(r).color = {255, 255, 255, 255}
		im.clear_rect(r)
	}; im.pop(r);
	im.options(r).color = {0, 0, 0, 255}
}

dark_theme :: proc(r: ^im.Renderer) {
	im.push(r); {
		im.options(r).color = {0, 0, 0, 255}
		im.clear_rect(r)
	}; im.pop(r);
	im.options(r).color = {255, 255, 255, 255}
}
