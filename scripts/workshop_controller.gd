
extends Control

var root
var is_working = false
var is_suspended = true

var selector = preload('res://gui/selector.xscn').instance()
var selector_position = Vector2(0,0)
var game_scale
var map_pos

var hud_message
var hud_message_box
var hud_message_box_button
var hud_message_box_title
var hud_message_box_message

var toolset_active_page = 0
var tool_type = "terrain"
var brush_type = 0


var restore_file_name = "restore_map"

var map
var terrain
var units
var painting = false
var painting_allowed = true
var history = []
var paint_count = 0
var autosave_after = 10
var painting_motion = false
var movement_mode = true
var tileset

var settings = {
	fill = [8,12,16,20,24,32],
	fill_selected = [0,0],
}

const MAP_MAX_X = 64
const MAP_MAX_Y = 64

func init_gui():
	map = get_node("blueprint/scale/map")
	terrain = map.get_node("terrain")
	units = map.get_node("terrain/units")

	game_scale = get_node("blueprint/scale")

	# message
	hud_message = self.get_node("message")
	hud_message_box = hud_message.get_node("center/message")
	hud_message_box_button = hud_message_box.get_node("button")
	hud_message_box_button.connect("pressed", self, "close_message")
	self.load_map(restore_file_name)

func add_action(params):
	var last_brush

	if params.tool_type == "terrain":
		last_brush = terrain.get_cell(params.position.x,params.position.y)

	if params.tool_type == "units":
		last_brush = units.get_cell(params.position.x,params.position.y)

	history.append({
		position = params.position,
		tool_type = params.tool_type,
		brush_type = last_brush
		})
	paint_count += 1
	if not painting_motion and paint_count >= autosave_after:
		self.save_map(restore_file_name)
		paint_count = 0

func undo_last_action():
	var last_action
	if self.history.size() > 0:
		last_action = history[history.size()-1]
		self.paint(last_action.position,last_action.tool_type,last_action.brush_type, true)
		history.remove(history.size()-1)

func toolbox_fill():
	map.fill(settings.fill[settings.fill_selected[0]],settings.fill[settings.fill_selected[1]])
	self.center_camera()

func toolbox_clear(layer):
	if layer == 0:
		self.map.clear_layer(0)
	if layer == 1:
		self.map.clear_layer(1)

func play_map():
	self.save_map(self.restore_file_name)
	self.is_working = false
	self.is_suspended = true
	self.root.load_map("workshop", self.restore_file_name)
	self.root.menu.hide_workshop()
	self.root.toggle_menu()
	self.root.dependency_container.match_state.set_workshop_map()

func save_map(name, input = false):
	if input:
		name = name.get_text()
	if not map.save_map(name):
		self.show_message("File error", ["Failure!","File name: "+str(name)])

func load_map(name, input = false):
	if input:
		name = name.get_text()
	if not map.load_map(name):
		self.show_message("File not found", ["Failure!","File name: "+str(name)])

func paint(position, tool_type = null, brush_type = null, undo_action = false):
	if hud_message.is_visible():
		return false

	if tool_type == null:
		tool_type = self.tool_type
	if brush_type == null:
		brush_type = self.brush_type


	if position.x < 0 or position.y < 0 or position.x >= MAP_MAX_X or position.y >= MAP_MAX_Y:
		return false
	else:
		if tool_type == "terrain":
			if brush_type == -1 and units.get_cell(position.x,position.y) > -1:
				if not undo_action:
					add_action({position=Vector2(position.x,position.y),tool_type="units"})
				units.set_cell(position.x,position.y,brush_type)
			else:
				if terrain.get_cell(position.x,position.y) != brush_type:
					if not undo_action:
						add_action({position=Vector2(position.x,position.y),tool_type="terrain"})
					terrain.set_cell(position.x,position.y,brush_type)

		if tool_type == "units":
			if units.get_cell(position.x,position.y) != brush_type:
				if terrain.get_cell(position.x, position.y) in [self.tileset.TERRAIN_PLAIN, self.tileset.TERRAIN_DIRT, self.tileset.TERRAIN_ROAD, self.tileset.TERRAIN_DIRT_ROAD, self.tileset.TERRAIN_BRIDGE, self.tileset.TERRAIN_SPAWN]:
					if not undo_action:
						add_action({position=Vector2(position.x,position.y),tool_type="units"})
					units.set_cell(position.x,position.y,brush_type)
				else:
					return false
	units.raise()
	selector.raise()
	return true

func init(root):
	self.root = root
	self.tileset = self.root.dependency_container.map_tiles
	terrain.add_child(selector)
	map.set_default_zoom()
	game_scale.set_scale(map.scale)
	set_process_input(true)

func _input(event):
	if self.is_working && not self.is_suspended && self.painting_allowed:
		if event.type == InputEvent.MOUSE_BUTTON:
			if event.button_index == BUTTON_LEFT && not self.movement_mode:
				if event.pressed:
					painting = true
				else:
					painting = false
					painting_motion = false

		if event.type == InputEvent.MOUSE_MOTION || event.type == InputEvent.MOUSE_BUTTON:
			map_pos = terrain.get_global_pos() / Vector2(map.scale.x, map.scale.y)
			selector_position = terrain.world_to_map(Vector2((event.x / map.scale.x) - map_pos.x, (event.y / map.scale.y) - map_pos.y))
			var position = terrain.map_to_world(selector_position)
			selector.set_pos(position)

		if (event.type == InputEvent.MOUSE_MOTION):
			painting_motion = true

		if (event.type == InputEvent.MOUSE_MOTION or event.type == InputEvent.MOUSE_BUTTON) and painting and not self.root.dependency_container.workshop_dead_zone.is_dead_zone(event.x, event.y):
			self.paint(selector_position)

		if event.type == InputEvent.KEY:
			if event.scancode == KEY_Z && event.pressed:
				self.undo_last_action()

	if Input.is_action_pressed('ui_cancel') && not self.root.is_map_loaded:
		self.toggle_menu()

func toggle_menu():
	if not self.is_working:
		#print('skip')
		return

	if self.is_hidden():
		self.is_suspended = false
		root.menu.show_workshop()
	else:
		self.is_suspended = true
		root.menu.hide_workshop()

func show_message(title, msg):
	self.hud_message_box.show_message(title, msg)
	self.hud_message.show()

func close_message():
	self.hud_message.hide()

func center_camera():
	self.map.move_to_map(Vector2(self.map.MAP_MAX_X / 2, self.map.MAP_MAX_Y / 2))

func show():
	self.center_camera()
	.show()

func _ready():
	init_gui()
