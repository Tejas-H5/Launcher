package im
//
// import "rect"
// import "core:mem"
//
// Document :: struct {
// 	root: Node,
//
// 	node_idx: int,
//
// 	nodes: [dynamic]Node,
// 	stack: [dynamic]^Node,
// }
//
// Node :: struct {
// 	parent : ^Node,
//
// 	width, height: f32,
// }
//
//
// new_document :: proc(capacity := 16384) -> (result: Document) {
// 	result.nodes = make([dynamic]Node, 0, capacity)
// 	result.stack = make([dynamic]^Node, 0, 256)
// 	return
// }
//
// new_node :: proc(document: ^Document) -> ^Node {
// 	parent: ^Node
// 	if len(document.stack) > 0 {
// 		parent = document.stack[len(document.stack) - 1]
// 	}
//
// 	node := &document.nodes[document.node_idx]
// 	node^ = {
// 		parent = parent,
// 	}
// 	if parent != nil {
// 		node.rect = parent.rect
// 	}
//
// 	document.node_idx += 1
// 	return node
// }
//
// begin_document :: proc(document: ^Document, width, height: f32) {
// 	document.node_idx = 0
// 	begin(document)
// }
//
// begin :: proc(document: ^Document) -> ^Node {
// 	node := new_node(document)
// 	append(&document.stack, node)
// 	return node
// }
//
// end :: proc(document: ^Document) {
// 	pop(&document.stack)
// }
