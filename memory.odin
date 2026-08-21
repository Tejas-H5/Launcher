package main

import "core:mem"

Arena :: struct {
	alloc: mem.Allocator,
	arena: mem.Arena,
}

make_arena :: proc(arena: ^Arena, bytes: int) {
	memory := make([]byte, bytes)
	mem.arena_init(&arena.arena, memory)
	// mem.arena_allocator Requires `arena` to already have a fixed position in memory,
	// so we can't return -> Arena here
	arena.alloc = mem.arena_allocator(&arena.arena)
}

