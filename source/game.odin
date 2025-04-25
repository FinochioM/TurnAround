package game

import "core:math"
import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180
GRID_SIZE :: 8
MAX_MOVES :: 10

Game_Mode :: enum {
	Lobby,
	Wilderness,
}

Action_Type :: enum {
	None,
	Move,
	Attack,
	Skip,
}

Direction :: enum {
	None,
	Up,
	Down,
	Left,
	Right,
}

Entity :: struct {
	position:	[2]int,
	health:		int,
	texture:	rl.Texture,
}

Game_Memory :: struct {
	mode	: Game_Mode,
	run		: bool,

	player_pos	: rl.Vector2,
	player_grid_pos	: [2]int,
	player_texture	: rl.Texture,
	player_health	: int,

	enemies:	[dynamic]Entity,

	current_action	: Action_Type,
	moves_remaining	: int,
	selected_grid_pos	: [2]int,
	show_grid	: bool,

	move_button_rect	: rl.Rectangle,
	attack_button_rect	: rl.Rectangle,
	skip_button_rect	: rl.Rectangle,
	switch_mode_button_rect	: rl.Rectangle,
}

g_mem: ^Game_Memory

grid_to_world :: proc(grid_pos: [2]int) -> rl.Vector2 {
	return rl.Vector2{
		f32(grid_pos[0]) * GRID_SIZE,
		f32(grid_pos[1]) * GRID_SIZE,
	}
}

world_to_grid :: proc(world_pos: rl.Vector2) -> [2]int {
	return [2]int {
		int(math.floor(world_pos.x / GRID_SIZE)),
		int(math.floor(world_pos.y / GRID_SIZE)),
	}
}

is_adjacent :: proc(pos1, pos2: [2]int) -> bool {
	dx := abs(pos1[0] - pos2[0])
	dy := abs(pos1[1] - pos2[1])

	return (dx == 1 && dy == 0) || (dx == 0 && dy == 1)
}

is_within_range :: proc(pos1, pos2: [2]int, range: int) -> bool {
	return manhattan_distance(pos1, pos2) <= range
}

abs :: proc(x: int) -> int {
	if x < 0 do return -x
	return x
}

manhattan_distance :: proc(pos1, pos2: [2]int) -> int {
	return abs(pos1[0] - pos2[0]) + abs(pos1[1] - pos2[1])
}

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	target := g_mem.mode == .Lobby ? g_mem.player_pos : grid_to_world(g_mem.player_grid_pos)

	return {
		zoom = h / PIXEL_WINDOW_HEIGHT,
		target = target,
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

init_ui_elements :: proc() {
	bottom_margin := 10
	button_width := 50
	button_height := 20
	spacing := 5

	screen_height := f32(PIXEL_WINDOW_HEIGHT)

	g_mem.move_button_rect = {
		5,
		screen_height - f32(bottom_margin + button_height),
		f32(button_width),
		f32(button_height),
	}

    g_mem.attack_button_rect = {
        g_mem.move_button_rect.x + g_mem.move_button_rect.width + f32(spacing),
        screen_height - f32(bottom_margin + button_height),
        f32(button_width),
        f32(button_height),
    }

    g_mem.skip_button_rect = {
        g_mem.attack_button_rect.x + g_mem.attack_button_rect.width + f32(spacing),
        screen_height - f32(bottom_margin + button_height),
        f32(button_width),
        f32(button_height),
    }

    g_mem.switch_mode_button_rect = {
        PIXEL_WINDOW_HEIGHT - f32(button_width + 5),
        5,
        f32(button_width),
        f32(button_height),
    }
}

create_enemy := proc(pos: [2]int) -> Entity {
	return Entity {
		position = pos,
		health = 30,
		texture = rl.LoadTexture("assets/enemy.png"),
	}
}

update_lobby :: proc () {
	input: rl.Vector2

	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		input.y -= 1
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		input.y += 1
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	g_mem.player_pos += input * rl.GetFrameTime() * 100
}

handle_wilderness_input :: proc() {
    mouse_pos := rl.GetMousePosition()
    world_mouse_pos := rl.GetScreenToWorld2D(mouse_pos, game_camera())
    grid_mouse_pos := world_to_grid(world_mouse_pos)

    ui_mouse_pos := rl.GetScreenToWorld2D(mouse_pos, ui_camera())

    if rl.IsMouseButtonPressed(.LEFT) {
        if rl.CheckCollisionPointRec(ui_mouse_pos, g_mem.move_button_rect) {
            g_mem.current_action = .Move
            g_mem.selected_grid_pos = g_mem.player_grid_pos
            return
        }

        if rl.CheckCollisionPointRec(ui_mouse_pos, g_mem.attack_button_rect) {
            g_mem.current_action = .Attack
            g_mem.selected_grid_pos = g_mem.player_grid_pos
            return
        }

        if rl.CheckCollisionPointRec(ui_mouse_pos, g_mem.skip_button_rect) {
            g_mem.current_action = .None
            g_mem.moves_remaining -= 1
            return
        }

        if rl.CheckCollisionPointRec(ui_mouse_pos, g_mem.switch_mode_button_rect) {
            switch_game_mode()
            return
        }

        if g_mem.current_action == .Move {
            if is_within_range(g_mem.player_grid_pos, grid_mouse_pos, 3) {
                enemy_at_pos := false
                for enemy in g_mem.enemies {
                    if enemy.position[0] == grid_mouse_pos[0] && enemy.position[1] == grid_mouse_pos[1] {
                        enemy_at_pos = true
                        break
                    }
                }

                if !enemy_at_pos {
                    g_mem.player_grid_pos = grid_mouse_pos
                    g_mem.current_action = .None
                    g_mem.moves_remaining -= 1
                }
            }
        } else if g_mem.current_action == .Attack {
            if manhattan_distance(g_mem.player_grid_pos, grid_mouse_pos) <= 1 {
                for enemy_idx := 0; enemy_idx < len(g_mem.enemies); enemy_idx += 1 {
                    enemy := &g_mem.enemies[enemy_idx]
                    if enemy.position[0] == grid_mouse_pos[0] && enemy.position[1] == grid_mouse_pos[1] {
                        enemy.health -= 10
                        g_mem.current_action = .None
                        g_mem.moves_remaining -= 1
                        break
                    }
                }
            }
        }
    }

    if g_mem.moves_remaining <= 0 {
        g_mem.moves_remaining = MAX_MOVES
        g_mem.mode = .Lobby
    }
}

update_wilderness :: proc() {
	handle_wilderness_input()

	i := 0

	for i < len(g_mem.enemies) {
		if g_mem.enemies[i].health <= 0 {
			unordered_remove(&g_mem.enemies, i)
		}else {
			i += 1
		}
	}
}

switch_game_mode :: proc() {
	if g_mem.mode == .Lobby {
		g_mem.mode = .Wilderness
		g_mem.moves_remaining = MAX_MOVES
		g_mem.current_action = .None

		g_mem.player_grid_pos = world_to_grid(g_mem.player_pos)
	}else {
		g_mem.mode = .Lobby

		g_mem.player_pos = grid_to_world(g_mem.player_grid_pos)
	}
}

update :: proc() {
	if rl.IsKeyPressed(.ESCAPE) {
		g_mem.run = false
	}

	if rl.IsKeyPressed(.TAB) {
		switch_game_mode()
	}

	if g_mem.mode == .Lobby {
		update_lobby()
	}else {
		update_wilderness()
	}
}

draw_grid :: proc() {
    camera := game_camera()
    screen_width := f32(rl.GetScreenWidth())
    screen_height := f32(rl.GetScreenHeight())

    half_width := screen_width / (2 * camera.zoom)
    half_height := screen_height / (2 * camera.zoom)

    min_x := int(math.floor((camera.target.x - half_width) / GRID_SIZE)) - 1
    min_y := int(math.floor((camera.target.y - half_height) / GRID_SIZE)) - 1
    max_x := int(math.ceil((camera.target.x + half_width) / GRID_SIZE)) + 1
    max_y := int(math.ceil((camera.target.y + half_height) / GRID_SIZE)) + 1

    for x := min_x; x <= max_x; x += 1 {
        start := rl.Vector2{f32(x * GRID_SIZE), f32(min_y * GRID_SIZE)}
        end := rl.Vector2{f32(x * GRID_SIZE), f32(max_y * GRID_SIZE)}
        rl.DrawLineV(start, end, {50, 50, 50, 100})
    }

    for y := min_y; y <= max_y; y += 1 {
        start := rl.Vector2{f32(min_x * GRID_SIZE), f32(y * GRID_SIZE)}
        end := rl.Vector2{f32(max_x * GRID_SIZE), f32(y * GRID_SIZE)}
        rl.DrawLineV(start, end, {50, 50, 50, 100})
    }

    if g_mem.current_action == .Move {
        for y := g_mem.player_grid_pos[1] - 3; y <= g_mem.player_grid_pos[1] + 3; y += 1 {
            for x := g_mem.player_grid_pos[0] - 3; x <= g_mem.player_grid_pos[0] + 3; x += 1 {
                if (x == g_mem.player_grid_pos[0] && y == g_mem.player_grid_pos[1]) ||
                   !is_within_range(g_mem.player_grid_pos, {x, y}, 3) {
                    continue
                }

                cell_occupied := false
                for enemy in g_mem.enemies {
                    if enemy.position[0] == x && enemy.position[1] == y {
                        cell_occupied = true
                        break
                    }
                }

                if !cell_occupied {
                    pos := grid_to_world({x, y})
                    rl.DrawRectangleV(pos, {GRID_SIZE, GRID_SIZE}, {0, 200, 100, 50})
                }
            }
        }
    } else if g_mem.current_action == .Attack {
        for y := g_mem.player_grid_pos[1] - 1; y <= g_mem.player_grid_pos[1] + 1; y += 1 {
            for x := g_mem.player_grid_pos[0] - 1; x <= g_mem.player_grid_pos[0] + 1; x += 1 {
                if (x == g_mem.player_grid_pos[0] && y == g_mem.player_grid_pos[1]) ||
                   (x != g_mem.player_grid_pos[0] && y != g_mem.player_grid_pos[1]) {
                    continue
                }

                for enemy in g_mem.enemies {
                    if enemy.position[0] == x && enemy.position[1] == y {
                        pos := grid_to_world({x, y})
                        rl.DrawRectangleV(pos, {GRID_SIZE, GRID_SIZE}, {200, 0, 50, 80})
                        break
                    }
                }
            }
        }
    }
}

draw_wilderness_ui :: proc() {
    rl.DrawRectangleRec(g_mem.move_button_rect, g_mem.current_action == .Move ? rl.GREEN : rl.DARKGREEN)
    rl.DrawRectangleRec(g_mem.attack_button_rect, g_mem.current_action == .Attack ? rl.RED : rl.MAROON)
    rl.DrawRectangleRec(g_mem.skip_button_rect, rl.GRAY)

    rl.DrawText("Move", i32(g_mem.move_button_rect.x + 5), i32(g_mem.move_button_rect.y + 5), 10, rl.WHITE)
    rl.DrawText("Attack", i32(g_mem.attack_button_rect.x + 5), i32(g_mem.attack_button_rect.y + 5), 10, rl.WHITE)
    rl.DrawText("Skip", i32(g_mem.skip_button_rect.x + 5), i32(g_mem.skip_button_rect.y + 5), 10, rl.WHITE)

    rl.DrawRectangleRec(g_mem.switch_mode_button_rect, rl.DARKBLUE)
    rl.DrawText("Switch", i32(g_mem.switch_mode_button_rect.x + 5), i32(g_mem.switch_mode_button_rect.y + 5), 10, rl.WHITE)

    move_text := fmt.ctprintf("Moves: %d/%d", g_mem.moves_remaining, MAX_MOVES)
    rl.DrawText(move_text, 5, 25, 10, rl.WHITE)
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginMode2D(game_camera())

	if g_mem.mode == .Wilderness {
		draw_grid()
	}

	if g_mem.mode == .Lobby {
		rl.DrawTextureEx(g_mem.player_texture, g_mem.player_pos, 0, 1, rl.WHITE)
	}else {
		player_world_pos := grid_to_world(g_mem.player_grid_pos)
		rl.DrawTextureEx(g_mem.player_texture, player_world_pos, 0, 1, rl.WHITE)
	}

	if g_mem.mode == .Wilderness {
		for enemy in g_mem.enemies {
			enemy_pos := grid_to_world(enemy.position)
			rl.DrawTextureEx(enemy.texture, enemy_pos, 0, 1, rl.WHITE)

			health_width := f32(enemy.health) / 30.0 * GRID_SIZE
			rl.DrawRectangle(i32(enemy_pos.x), i32(enemy_pos.y - 5), i32(health_width), 3, rl.RED)
		}
	}

	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	fps := rl.GetFPS()
    if g_mem.mode == .Lobby {
        rl.DrawText(fmt.ctprintf("FPS: %v\nMode: Lobby\nPosition: %v", fps, g_mem.player_pos), 5, 5, 8, rl.WHITE)
    } else {
        rl.DrawText(fmt.ctprintf("FPS: %v\nMode: Wilderness\nGrid Pos: %v", fps, g_mem.player_grid_pos), 5, 5, 8, rl.WHITE)
        draw_wilderness_ui()
    }

	rl.EndMode2D()

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1024, 768, "Turn Around")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(144)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	g_mem^ = Game_Memory {
		mode = .Lobby,
		run = true,
		player_pos = {0, 0},
		player_grid_pos = {0, 0},
		player_texture = rl.LoadTexture("assets/player.png"),
		player_health = 100,
		moves_remaining = MAX_MOVES,
		current_action = .None,
		enemies = make([dynamic]Entity),
	}

	init_ui_elements()

	append(&g_mem.enemies, create_enemy({3, 2}))
	append(&g_mem.enemies, create_enemy({-2, 3}))

	game_hot_reloaded(g_mem)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g_mem.run
}

@(export)
game_shutdown :: proc() {
	delete(g_mem.enemies)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g_mem`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
