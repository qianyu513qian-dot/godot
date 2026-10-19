extends CanvasLayer
class_name RtsHud3D
## Toy parchment HUD (clay RTS ref): TR resources, BL diamond-framed minimap,
## BC selection+groups, BR portrait+command card; TL menu; TC day clock.

signal train_villager_pressed
signal train_soldier_pressed
signal cancel_train_pressed
signal cancel_construct_pressed
signal build_kind_pressed(kind: int)
signal age_up_pressed
signal forestry_research_pressed
signal technology_research_pressed(tech_id: String)
signal cmd_move_pressed
signal cmd_attack_pressed
signal cmd_stop_pressed
signal cmd_guard_pressed
signal cmd_gather_pressed
signal cmd_build_toggle
signal cmd_repair_pressed
signal portrait_clicked(node: Node3D, shift: bool)
signal army_pressed
signal idle_vill_pressed
signal control_group_pressed(n: int)
signal minimap_goto(world_pos: Vector3)
signal reseed_farm_pressed
signal operational_alert_target_pressed(target: Node3D)
signal alert_location_pressed(alert_key: String, world_pos: Vector3)
signal gate_lock_pressed
signal defeat_retry_pressed
signal defeat_to_start_pressed

const Catalog := preload("res://scripts/building_catalog.gd")
const Loc := preload("res://scripts/loc.gd")
const MAP_HALF := 55.0  # match main map

var _meat_l: Label
var _wood_l: Label
var _stone_l: Label
var _gold_l: Label
var _pop_l: Label
var _workforce_l: Label
var _msg_l: Label
var _msg_t: float = 0.0

var _civ_l: Label
var _clock_l: Label
var _dn_l: Label
var _game_time: float = 0.0

var _bottom: Panel
var _minimap: Control
var _mini_draw: Control
var _army_btn: Button
var _idle_btn: Button
var _army_count_l: Label

var _group_row: HBoxContainer
var _sel_grid: GridContainer
var _info_name: Label
var _info_stock: Label
var _big_portrait: ColorRect
var _big_portrait_name: Label
var _cmd_grid: GridContainer
var _build_grid: GridContainer
var _build_open: bool = false
var _cmd_btns: Dictionary = {}
var _portrait_nodes: Array = []
var _last_kind: String = ""
var _hint_l: Label
var _info_armor: Label
var _train_row: HBoxContainer
var _train_bar: ProgressBar
var _build_prog: ProgressBar
var _construction_status_l: Label
var _wave_l: Label
var _wave_panel: Panel
var _defeat_panel: Panel
var _defeat_l: Label
var _operational_panel: PanelContainer
var _operational_rows: VBoxContainer
var _operational_row_by_key: Dictionary = {}
var _operational_label_by_key: Dictionary = {}
var _operational_button_by_key: Dictionary = {}

# Camera for minimap frustum (set by main optional)
var camera: Camera3D = null
var cam_pivot: Node3D = null
var _mini_dragging: bool = false

func _ready() -> void:
	layer = 10
	visible = true
	_build_ui()
	# Keep HUD on top of 3D; never let a bad refresh hide the layer
	show()

func _build_ui() -> void:
	_build_top_left_menu()
	_build_top_right_resources()
	_build_top_center_civ()
	_build_wave_banner()
	_build_operational_alerts()
	_build_terminal_panel()
	_build_bottom()
	_msg_l = Label.new()
	_msg_l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_l.offset_top = 48
	_msg_l.offset_left = -260
	_msg_l.offset_right = 260
	_msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_l.add_theme_font_size_override("font_size", 18)
	_msg_l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_msg_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_msg_l.add_theme_constant_override("outline_size", 4)
	add_child(_msg_l)
	show_selection_info({"kind": "none", "units": []})

func _panel_style(bg: Color = Color(0.93, 0.84, 0.68, 0.94), border: Color = Color(0.92, 0.48, 0.22, 0.95)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	return s

func _mk_circle_btn(icon_text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = icon_text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 36)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.95, 0.55, 0.28, 0.95)
	n.border_color = Color(0.85, 0.40, 0.15, 1)
	n.border_width_left = 2
	n.border_width_top = 2
	n.border_width_right = 2
	n.border_width_bottom = 2
	n.corner_radius_top_left = 18
	n.corner_radius_top_right = 18
	n.corner_radius_bottom_left = 18
	n.corner_radius_bottom_right = 18
	b.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(1.0, 0.68, 0.38, 0.98)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(0.25, 0.12, 0.05))
	return b

func _build_top_left_menu() -> void:
	var row := HBoxContainer.new()
	row.name = "TopLeftMenu"
	row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	row.offset_left = 10
	row.offset_top = 8
	row.offset_right = 100
	row.offset_bottom = 48
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(row)
	var home := _mk_circle_btn("城", "主页")
	home.pressed.connect(func(): flash_msg("玩具村落 — 主营地"))
	row.add_child(home)
	var gear := _mk_circle_btn("设", "设置")
	gear.pressed.connect(func(): flash_msg("设置：相机滚轮缩放 / 中键拖动"))
	row.add_child(gear)


func _build_top_right_resources() -> void:
	var box := Panel.new()
	box.name = "ResourceBar"
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.offset_left = -420
	box.offset_top = 6
	box.offset_right = -8
	box.offset_bottom = 40
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.94, 0.86, 0.70, 0.95), Color(0.92, 0.48, 0.22, 0.95)))
	add_child(box)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 14)
	hb.offset_left = 8
	hb.offset_right = -8
	hb.offset_top = 4
	box.add_child(hb)
	_meat_l = _mk_icon_res(hb, Color(0.85, 0.35, 0.3), "肉")
	_wood_l = _mk_icon_res(hb, Color(0.55, 0.38, 0.2), "木")
	_stone_l = _mk_icon_res(hb, Color(0.65, 0.65, 0.7), "石")
	_gold_l = _mk_icon_res(hb, Color(0.9, 0.75, 0.2), "金")
	_pop_l = _mk_icon_res(hb, Color(0.35, 0.7, 0.95), "人")
	_workforce_l = Label.new()
	_workforce_l.name = "WorkforceSummary"
	_workforce_l.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_workforce_l.offset_left = -420
	_workforce_l.offset_top = 42
	_workforce_l.offset_right = -8
	_workforce_l.offset_bottom = 64
	_workforce_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_workforce_l.add_theme_font_size_override("font_size", 12)
	_workforce_l.add_theme_color_override("font_color", Color(0.94, 0.86, 0.70, 0.96))
	_workforce_l.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04, 0.94))
	_workforce_l.add_theme_constant_override("outline_size", 3)
	_workforce_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_workforce_l.text = "工人 木0 粮0 闲0 其他0 受阻0"
	_workforce_l.tooltip_text = "返仓中的携货村民仍计入原采集工作；其他包括采石/采金、施工、移动与战斗。受阻表示保留采集意图但当前目标不可用。"
	add_child(_workforce_l)

func _mk_icon_res(parent: HBoxContainer, icon_col: Color, tip: String) -> Label:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	parent.add_child(wrap)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = tip
	var key := "meat"
	if tip == "木":
		key = "wood"
	elif tip == "石":
		key = "stone"
	elif tip == "金":
		key = "gold"
	elif tip == "人":
		key = "pop"
	var ipath := "res://assets/icons/%s.png" % key
	if ResourceLoader.exists(ipath):
		icon.texture = load(ipath) as Texture2D
		wrap.add_child(icon)
	else:
		var cr := ColorRect.new()
		cr.custom_minimum_size = Vector2(22, 22)
		cr.color = icon_col
		wrap.add_child(cr)
	var l := Label.new()
	l.text = "0"
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.35, 0.22, 0.10))
	wrap.add_child(l)
	return l

func _build_top_center_civ() -> void:
	var box := Panel.new()
	box.name = "CivClock"
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -72
	box.offset_right = 72
	box.offset_top = 4
	box.offset_bottom = 76
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock_style := _panel_style(Color(0.55, 0.35, 0.78, 0.92), Color(0.95, 0.75, 0.28, 0.95))
	clock_style.corner_radius_top_left = 36
	clock_style.corner_radius_top_right = 36
	clock_style.corner_radius_bottom_left = 36
	clock_style.corner_radius_bottom_right = 36
	box.add_theme_stylebox_override("panel", clock_style)
	add_child(box)
	_civ_l = Label.new()
	_civ_l.text = Loc.t("civ_name")
	_civ_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_civ_l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_civ_l.offset_top = 2
	_civ_l.offset_bottom = 22
	_civ_l.add_theme_font_size_override("font_size", 14)
	_civ_l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	box.add_child(_civ_l)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -20
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_clock_l = Label.new()
	_clock_l.text = "00:00"
	_clock_l.add_theme_font_size_override("font_size", 13)
	_clock_l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	row.add_child(_clock_l)
	_dn_l = Label.new()
	_dn_l.text = Loc.t("day")
	_dn_l.add_theme_font_size_override("font_size", 12)
	_dn_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	row.add_child(_dn_l)

func _build_wave_banner() -> void:
	_wave_panel = Panel.new()
	_wave_panel.name = "WaveBanner"
	_wave_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wave_panel.offset_left = -160
	_wave_panel.offset_right = 160
	_wave_panel.offset_top = 48
	_wave_panel.offset_bottom = 78
	_wave_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.05, 0.05, 0.82), Color(0.75, 0.25, 0.2, 0.85)))
	_wave_panel.visible = false
	add_child(_wave_panel)
	_wave_l = Label.new()
	_wave_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wave_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_l.add_theme_font_size_override("font_size", 15)
	_wave_l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	_wave_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_wave_l.add_theme_constant_override("outline_size", 3)
	_wave_l.text = ""
	_wave_panel.add_child(_wave_l)

func _build_operational_alerts() -> void:
	_operational_panel = PanelContainer.new()
	_operational_panel.name = "OperationalAlerts"
	_operational_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_operational_panel.offset_left = -210
	_operational_panel.offset_right = 210
	_operational_panel.offset_top = 84
	_operational_panel.offset_bottom = 116
	_operational_panel.visible = false
	_operational_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.07, 0.04, 0.94), Color(0.85, 0.50, 0.18, 0.95)))
	add_child(_operational_panel)
	_operational_rows = VBoxContainer.new()
	_operational_rows.add_theme_constant_override("separation", 3)
	_operational_panel.add_child(_operational_rows)

func set_operational_alerts(alerts: Array) -> void:
	var active_keys: Dictionary = {}
	for alert in alerts:
		var key := str(alert.get("key", ""))
		if key.is_empty():
			continue
		active_keys[key] = true
		var row: HBoxContainer = _operational_row_by_key.get(key)
		var label: Label = _operational_label_by_key.get(key)
		var button: Button = _operational_button_by_key.get(key)
		if not is_instance_valid(row) or not is_instance_valid(label) or not is_instance_valid(button):
			row = HBoxContainer.new()
			row.set_meta("operational_alert_key", key)
			row.add_theme_constant_override("separation", 8)
			_operational_rows.add_child(row)
			label = Label.new()
			label.custom_minimum_size = Vector2(260, 30)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 13)
			row.add_child(label)
			button = Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.set_meta("operational_alert_key", key)
			button.pressed.connect(_on_operational_alert_button_pressed.bind(button))
			row.add_child(button)
			_operational_row_by_key[key] = row
			_operational_label_by_key[key] = label
			_operational_button_by_key[key] = button
		var next_text := str(alert.get("text", ""))
		if label.text != next_text:
			label.text = next_text
		var is_combat_alert: bool = str(alert.get("alert_kind", "")) == "combat"
		label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.38) if is_combat_alert else Color(1.0, 0.80, 0.48))
		var next_action := str(alert.get("action", "定位"))
		if button.text != next_action:
			button.text = next_action
		var next_tooltip := str(alert.get("tooltip", ""))
		if button.tooltip_text != next_tooltip:
			button.tooltip_text = next_tooltip
		button.disabled = bool(alert.get("disabled", false))
		var target: Variant = alert.get("target")
		var location: Variant = alert.get("location")
		if target is Node3D and is_instance_valid(target):
			button.set_meta("operational_alert_target", target)
		else:
			button.remove_meta("operational_alert_target")
		if location is Vector3:
			button.set_meta("alert_location", location)
			button.set_meta("alert_location_key", key)
		else:
			button.remove_meta("alert_location")
			button.remove_meta("alert_location_key")
	var retired_keys: Array = []
	for existing_key in _operational_row_by_key:
		if not active_keys.has(existing_key):
			retired_keys.append(existing_key)
	for key in retired_keys:
		var retired_button: Button = _operational_button_by_key.get(key)
		if is_instance_valid(retired_button):
			retired_button.disabled = true
			retired_button.remove_meta("operational_alert_target")
			retired_button.remove_meta("alert_location")
			retired_button.remove_meta("alert_location_key")
		var retired_row: HBoxContainer = _operational_row_by_key.get(key)
		if is_instance_valid(retired_row):
			retired_row.queue_free()
		_operational_row_by_key.erase(key)
		_operational_label_by_key.erase(key)
		_operational_button_by_key.erase(key)
	_operational_panel.visible = not active_keys.is_empty()
	_operational_panel.offset_bottom = 84 + active_keys.size() * 32

func set_workforce_summary(summary: Dictionary) -> void:
	if not is_instance_valid(_workforce_l):
		return
	var next_text := "工人 木%d 粮%d 闲%d 其他%d 受阻%d" % [
		int(summary.get("wood", 0)), int(summary.get("food", 0)),
		int(summary.get("idle", 0)), int(summary.get("other", 0)), int(summary.get("blocked", 0))
	]
	if _workforce_l.text != next_text:
		_workforce_l.text = next_text
	var tooltip := "返仓中的携货村民仍计入原采集工作；其他包括采石/采金、施工、移动与战斗。受阻表示保留采集意图但当前目标不可用。"
	if _workforce_l.tooltip_text != tooltip:
		_workforce_l.tooltip_text = tooltip

func _on_operational_alert_button_pressed(button: Button) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	var target: Variant = null
	var location: Variant = null
	if button.has_meta("operational_alert_target"):
		target = button.get_meta("operational_alert_target", null)
	if button.has_meta("alert_location"):
		location = button.get_meta("alert_location", null)
	if location is Vector3:
		var alert_key := str(button.get_meta("alert_location_key", "")) if button.has_meta("alert_location_key") else ""
		alert_location_pressed.emit(alert_key, location)
	elif is_instance_valid(target) and target.is_inside_tree() and target.get("alive") != false:
		operational_alert_target_pressed.emit(target)

func _build_terminal_panel() -> void:
	_defeat_panel = Panel.new()
	_defeat_panel.name = "DefeatBanner"
	_defeat_panel.set_anchors_preset(Control.PRESET_CENTER)
	_defeat_panel.offset_left = -240
	_defeat_panel.offset_right = 240
	_defeat_panel.offset_top = -110
	_defeat_panel.offset_bottom = 110
	_defeat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_defeat_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.02, 0.02, 0.94), Color(0.85, 0.15, 0.12, 0.95)))
	_defeat_panel.visible = false
	add_child(_defeat_panel)
	var dvbox := VBoxContainer.new()
	dvbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dvbox.offset_left = 16
	dvbox.offset_right = -16
	dvbox.offset_top = 12
	dvbox.offset_bottom = -12
	dvbox.add_theme_constant_override("separation", 10)
	_defeat_panel.add_child(dvbox)
	_defeat_l = Label.new()
	_defeat_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_defeat_l.add_theme_font_size_override("font_size", 24)
	_defeat_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.75))
	_defeat_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_defeat_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dvbox.add_child(_defeat_l)
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 12)
	dvbox.add_child(drow)
	var btn_retry := Button.new()
	btn_retry.name = "BtnRetry"
	btn_retry.text = Loc.t("btn_retry")
	btn_retry.custom_minimum_size = Vector2(140, 36)
	btn_retry.pressed.connect(func(): defeat_retry_pressed.emit())
	drow.add_child(btn_retry)
	var btn_start := Button.new()
	btn_start.name = "BtnToStart"
	btn_start.text = Loc.t("btn_to_start")
	btn_start.custom_minimum_size = Vector2(140, 36)
	btn_start.pressed.connect(func(): defeat_to_start_pressed.emit())
	drow.add_child(btn_start)

func show_message(msg: String, secs: float = 2.5) -> void:
	if _msg_l == null:
		return
	_msg_l.text = msg
	_msg_t = secs

func show_defeat(title: String, detail: String) -> void:
	if _defeat_panel == null or _defeat_l == null:
		return
	_defeat_l.text = "%s\n%s" % [title, detail]
	_defeat_panel.visible = true
	_defeat_panel.move_to_front()

func set_wave_status(wave_n: int, secs_left: float, warning: bool, active: bool = false, mode_label: String = "") -> void:
	## Chinese countdown / warning for They Are Billions-style hordes.
	if _wave_l == null or _wave_panel == null:
		return
	if wave_n <= 0 and secs_left > 9990.0:
		_wave_panel.visible = false
		return
	_wave_panel.visible = true
	var sec_i: int = maxi(0, int(ceil(secs_left)))
	var mode_prefix: String = "[%s] " % mode_label if not mode_label.is_empty() else ""
	if active:
		_wave_l.text = "%s%s #%d — %s" % [mode_prefix, Loc.t("wave_label"), wave_n, Loc.t("wave_incoming")]
	elif warning:
		_wave_l.text = "%s%s #%d — %d秒" % [mode_prefix, Loc.t("wave_warn"), wave_n, sec_i]
	else:
		_wave_l.text = "%s%s #%d — %d秒" % [mode_prefix, Loc.t("wave_label"), wave_n, sec_i]

func _build_bottom() -> void:
	_bottom = Panel.new()
	_bottom.name = "BottomBar"
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.offset_top = -178
	# The parchment is visual only. Interactive children keep their own hit areas,
	# while clicks through the empty space continue to reach the world.
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.93, 0.84, 0.68, 0.72)
	bs.border_color = Color(0.92, 0.48, 0.22, 0.95)
	bs.border_width_top = 3
	bs.corner_radius_top_left = 16
	bs.corner_radius_top_right = 16
	_bottom.add_theme_stylebox_override("panel", bs)
	add_child(_bottom)

	# --- BL: minimap + army/idle ---
	_minimap = Panel.new()
	_minimap.name = "Minimap"
	_minimap.position = Vector2(14, 38)
	_minimap.size = Vector2(128, 128)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	var mini_s := _panel_style(Color(0.55, 0.72, 0.42, 1), Color(0.95, 0.48, 0.18, 1))
	mini_s.border_width_left = 5
	mini_s.border_width_top = 5
	mini_s.border_width_right = 5
	mini_s.border_width_bottom = 5
	mini_s.corner_radius_top_left = 22
	mini_s.corner_radius_top_right = 22
	mini_s.corner_radius_bottom_left = 22
	mini_s.corner_radius_bottom_right = 22
	_minimap.add_theme_stylebox_override("panel", mini_s)
	# Decorative diamond ring behind minimap (visual only)
	var diamond := Panel.new()
	diamond.name = "MinimapDiamond"
	diamond.position = Vector2(26, 50)
	diamond.size = Vector2(104, 104)
	diamond.pivot_offset = Vector2(52, 52)
	diamond.rotation = PI * 0.25
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := _panel_style(Color(0.93, 0.84, 0.68, 0.0), Color(0.95, 0.48, 0.18, 0.85))
	ds.border_width_left = 4
	ds.border_width_top = 4
	ds.border_width_right = 4
	ds.border_width_bottom = 4
	diamond.add_theme_stylebox_override("panel", ds)
	_bottom.add_child(diamond)
	diamond.z_index = -1
	_bottom.add_child(_minimap)
	_mini_draw = Control.new()
	_mini_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mini_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_draw.draw.connect(_on_minimap_draw)
	_minimap.add_child(_mini_draw)
	_minimap.gui_input.connect(_on_minimap_gui)

	_army_btn = _mk_small_btn("F2\n军队", Color(0.45, 0.2, 0.18))
	_army_btn.position = Vector2(8, 2)
	_army_btn.custom_minimum_size = Vector2(52, 24)
	_army_btn.pressed.connect(func(): army_pressed.emit())
	_bottom.add_child(_army_btn)
	_army_count_l = Label.new()
	_army_count_l.position = Vector2(62, 4)
	_army_count_l.add_theme_font_size_override("font_size", 12)
	_army_count_l.add_theme_color_override("font_color", Color(0.75, 0.28, 0.18))
	_army_count_l.text = "0"
	_army_count_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_army_count_l)
	_idle_btn = _mk_small_btn("F3\n空闲", Color(0.2, 0.35, 0.55))
	_idle_btn.position = Vector2(120, 2)
	_idle_btn.custom_minimum_size = Vector2(52, 24)
	_idle_btn.pressed.connect(func(): idle_vill_pressed.emit())
	_bottom.add_child(_idle_btn)

	# --- BC: control groups + selection strip ---
	_info_name = Label.new()
	_info_name.position = Vector2(190, 2)
	_info_name.add_theme_font_size_override("font_size", 15)
	_info_name.add_theme_color_override("font_color", Color(0.45, 0.25, 0.08))
	_info_name.text = Loc.t("sel_none")
	_info_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_info_name)
	_info_stock = Label.new()
	_info_stock.position = Vector2(320, 2)
	_info_stock.add_theme_font_size_override("font_size", 14)
	_info_stock.add_theme_color_override("font_color", Color(0.20, 0.55, 0.28))
	_info_stock.text = ""
	_info_stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_info_stock)
	_info_armor = Label.new()
	_info_armor.position = Vector2(430, 2)
	_info_armor.add_theme_font_size_override("font_size", 13)
	_info_armor.add_theme_color_override("font_color", Color(0.30, 0.40, 0.55))
	_info_armor.text = ""
	_info_armor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_info_armor)
	_train_row = HBoxContainer.new()
	_train_row.position = Vector2(190, 118)
	_train_row.add_theme_constant_override("separation", 4)
	_train_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_train_row)
	_train_bar = ProgressBar.new()
	_train_bar.position = Vector2(190, 108)
	_train_bar.custom_minimum_size = Vector2(220, 8)
	_train_bar.size = Vector2(220, 8)
	_train_bar.max_value = 1.0
	_train_bar.value = 0.0
	_train_bar.show_percentage = false
	_train_bar.visible = false
	_train_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tf := StyleBoxFlat.new()
	tf.bg_color = Color(0.25, 0.7, 1.0)
	_train_bar.add_theme_stylebox_override("fill", tf)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.12, 0.14, 0.16)
	_train_bar.add_theme_stylebox_override("background", tb)
	_bottom.add_child(_train_bar)
	_build_prog = ProgressBar.new()
	_build_prog.position = Vector2(190, 100)
	_build_prog.custom_minimum_size = Vector2(220, 8)
	_build_prog.size = Vector2(220, 8)
	_build_prog.max_value = 1.0
	_build_prog.value = 0.0
	_build_prog.show_percentage = false
	_build_prog.visible = false
	_build_prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bf := StyleBoxFlat.new()
	bf.bg_color = Color(0.95, 0.75, 0.25)
	_build_prog.add_theme_stylebox_override("fill", bf)
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(0.12, 0.14, 0.16)
	_build_prog.add_theme_stylebox_override("background", bb)
	_bottom.add_child(_build_prog)
	_construction_status_l = Label.new()
	_construction_status_l.name = "ConstructionStatus"
	_construction_status_l.position = Vector2(190, 112)
	_construction_status_l.size = Vector2(430, 20)
	_construction_status_l.visible = false
	_construction_status_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_construction_status_l.add_theme_font_size_override("font_size", 12)
	_construction_status_l.add_theme_color_override("font_color", Color(0.72, 0.28, 0.16))
	_bottom.add_child(_construction_status_l)

	_group_row = HBoxContainer.new()
	_group_row.position = Vector2(190, 26)
	_group_row.add_theme_constant_override("separation", 3)
	_group_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_group_row)
	for i in range(1, 10):
		var gb := _mk_small_btn(str(i), Color(0.18, 0.2, 0.24))
		gb.custom_minimum_size = Vector2(28, 22)
		gb.name = "Grp%d" % i
		gb.pressed.connect(_on_group_btn.bind(i))
		_group_row.add_child(gb)

	_sel_grid = GridContainer.new()
	_sel_grid.name = "SelectionGrid"
	_sel_grid.columns = 8
	_sel_grid.position = Vector2(190, 54)
	_sel_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel_grid.add_theme_constant_override("h_separation", 3)
	_sel_grid.add_theme_constant_override("v_separation", 3)
	_bottom.add_child(_sel_grid)

	_hint_l = Label.new()
	_hint_l.position = Vector2(190, 158)
	_hint_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_l.add_theme_font_size_override("font_size", 10)
	_hint_l.add_theme_color_override("font_color", Color(0.45, 0.35, 0.22, 0.85))
	_hint_l.text = Loc.t("hint_cam")
	_bottom.add_child(_hint_l)

	# --- BR: big portrait + 3-col command card ---
	_big_portrait = ColorRect.new()
	_big_portrait.name = "UnitPortrait"
	_big_portrait.size = Vector2(92, 110)
	_big_portrait.color = Color(0.88, 0.72, 0.48)
	_big_portrait.visible = false
	_big_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_big_portrait)
	_big_portrait_name = Label.new()
	_big_portrait_name.add_theme_font_size_override("font_size", 11)
	_big_portrait_name.add_theme_color_override("font_color", Color(0.35, 0.20, 0.08))
	_big_portrait_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_portrait_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_big_portrait_name)

	_cmd_grid = GridContainer.new()
	_cmd_grid.name = "CommandCard"
	_cmd_grid.columns = 3
	_cmd_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cmd_grid.add_theme_constant_override("h_separation", 4)
	_cmd_grid.add_theme_constant_override("v_separation", 4)
	_bottom.add_child(_cmd_grid)

	_build_grid = GridContainer.new()
	_build_grid.name = "BuildCard"
	_build_grid.columns = 3
	_build_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_grid.add_theme_constant_override("h_separation", 3)
	_build_grid.add_theme_constant_override("v_separation", 3)
	_build_grid.visible = false
	_bottom.add_child(_build_grid)
	_populate_build_grid()
	_layout_br()

func _layout_br() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var card_w := 3 * 64.0 + 2 * 4.0
	var right_x := vp.x - card_w - 16.0
	_cmd_grid.position = Vector2(right_x, 36)
	_build_grid.position = Vector2(right_x, 20)
	_big_portrait.position = Vector2(right_x - 100, 24)
	_big_portrait_name.position = Vector2(right_x - 100, 136)
	_big_portrait_name.size = Vector2(92, 18)

func _mk_small_btn(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxFlat.new()
	n.bg_color = col
	n.corner_radius_top_left = 3
	n.corner_radius_top_right = 3
	n.corner_radius_bottom_left = 3
	n.corner_radius_bottom_right = 3
	n.border_width_left = 1
	n.border_width_top = 1
	n.border_width_right = 1
	n.border_width_bottom = 1
	n.border_color = Color(0.92, 0.48, 0.22, 0.75)
	n.corner_radius_top_left = 10
	n.corner_radius_top_right = 10
	n.corner_radius_bottom_left = 10
	n.corner_radius_bottom_right = 10
	b.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = col.lightened(0.15)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", Color(0.25, 0.12, 0.05))
	return b

func _mk_cmd_btn(label: String, hotkey: String, col: Color) -> Button:
	var b := Button.new()
	if hotkey != "":
		b.text = "%s\n[%s]" % [label, hotkey]
	else:
		b.text = label
	b.custom_minimum_size = Vector2(64, 48)
	b.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.45, 0.62, 0.92, 0.95).lerp(col, 0.35)
	n.corner_radius_top_left = 12
	n.corner_radius_top_right = 12
	n.corner_radius_bottom_left = 12
	n.corner_radius_bottom_right = 12
	n.border_width_left = 2
	n.border_width_top = 2
	n.border_width_right = 2
	n.border_width_bottom = 2
	n.border_color = Color(0.92, 0.48, 0.22, 0.85)
	b.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = n.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("hover", h)
	var p: StyleBoxFlat = n.duplicate()
	p.bg_color = n.bg_color.darkened(0.12)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08))
	return b

func _on_group_btn(n: int) -> void:
	control_group_pressed.emit(n)

func _clear_cmd_grid() -> void:
	for c in _cmd_grid.get_children():
		c.queue_free()
	_cmd_btns.clear()

func _clear_sel_grid() -> void:
	for c in _sel_grid.get_children():
		c.queue_free()
	_portrait_nodes.clear()

func _populate_build_grid() -> void:
	for c in _build_grid.get_children():
		c.queue_free()
	var defs := [
		[Catalog.HOUSE, Loc.t("btn_house"), Color(0.35, 0.4, 0.32)],
		[Catalog.FARM, Loc.t("btn_farm"), Color(0.35, 0.42, 0.28)],
		[Catalog.RELAY, Loc.t("btn_relay"), Color(0.32, 0.4, 0.45)],
		[Catalog.WALL, Loc.t("btn_wall"), Color(0.42, 0.42, 0.45)],
		[Catalog.GATE, Loc.t("btn_gate"), Color(0.48, 0.42, 0.36)],
		[Catalog.ARROW_TOWER, Loc.t("btn_tower"), Color(0.45, 0.4, 0.35)],
		[Catalog.ATTACK_BARRACKS, Loc.t("btn_barracks"), Color(0.55, 0.35, 0.28)],
	]
	for bd in defs:
		var kind: int = int(bd[0])
		var label: String = str(bd[1])
		var cdef: Dictionary = Catalog.get_def(kind)
		var cost_s: String = Catalog.cost_text_cn(cdef)
		if cost_s != "":
			label = label + "\n" + cost_s
		var btn := _mk_cmd_btn(label, "", bd[2])
		btn.custom_minimum_size = Vector2(72, 42)
		if bool(cdef.get("is_tower", false)):
			btn.tooltip_text = "真实 XZ 攻击半径 %.1fm · 伤害 %.0f · 攻击间隔 %.2fs" % [float(cdef.get("attack_range", 0.0)), float(cdef.get("attack_damage", 0.0)), float(cdef.get("attack_interval", 0.0))]
		btn.pressed.connect(_on_build.bind(kind))
		_build_grid.add_child(btn)
	var back := _mk_cmd_btn("返回", "Esc", Color(0.25, 0.25, 0.28))
	back.custom_minimum_size = Vector2(72, 42)
	back.pressed.connect(_on_build_back)
	_build_grid.add_child(back)

func _on_build(kind: int) -> void:
	_build_open = false
	_build_grid.visible = false
	_cmd_grid.visible = true
	build_kind_pressed.emit(kind)

func _on_build_back() -> void:
	_build_open = false
	_build_grid.visible = false
	_cmd_grid.visible = true

func _on_build_toggle() -> void:
	_build_open = not _build_open
	_build_grid.visible = _build_open
	_cmd_grid.visible = not _build_open
	cmd_build_toggle.emit()

func update_resources(wood: int, meat: int, stone: int, gold: int, pop: int, pop_cap: int, age_name: String) -> void:
	_meat_l.text = str(meat)
	_wood_l.text = str(wood)
	_stone_l.text = str(stone)
	_gold_l.text = str(gold)
	_pop_l.text = "%d/%d" % [pop, pop_cap]
	# age shown subtly in civ frame tooltip via civ label suffix
	if _civ_l:
		_civ_l.text = "%s · %s" % [Loc.t("civ_name"), age_name]

func set_army_count(count: int) -> void:
	if _army_count_l:
		_army_count_l.text = str(maxi(count, 0))

func set_game_time(t: float) -> void:
	_game_time = t

func update_control_groups(groups: Array) -> void:
	## groups: index 1..9 -> Array of nodes
	for i in range(1, 10):
		var btn: Button = _group_row.get_node_or_null("Grp%d" % i) as Button
		if btn == null:
			continue
		var arr: Array = groups[i] if i < groups.size() else []
		var alive: int = 0
		for n in arr:
			if is_instance_valid(n):
				alive += 1
		if alive > 0:
			btn.text = "%d\n×%d" % [i, alive]
			btn.modulate = Color(1, 1, 1, 1)
		else:
			btn.text = str(i)
			btn.modulate = Color(1, 1, 1, 0.45)

func show_selection_info(info: Dictionary) -> void:
	_layout_br()
	_build_open = false
	_build_grid.visible = false
	_cmd_grid.visible = true
	var kind: String = str(info.get("kind", "none"))
	var units: Array = info.get("units", [])
	_rebuild_portraits(units)
	var count: int = units.size() if not units.is_empty() else int(info.get("count", 0))
	var name_s: String = str(info.get("name", Loc.t("sel_none")))
	var stock_s: String = str(info.get("stock_text", ""))
	var construction_status: String = str(info.get("construction_status", ""))
	if _construction_status_l != null:
		_construction_status_l.visible = kind == "constructing" and not construction_status.is_empty()
		_construction_status_l.text = construction_status
	var tower_selected: bool = bool(info.get("is_tower", false)) and count == 1
	if _hint_l != null:
		_hint_l.text = str(info.get("tower_status", "")) if tower_selected else "继续施工：选农民，按 R 后左键该地基（或选中农民后右键地基）" if kind == "constructing" else Loc.t("hint_cam")
	if _info_stock:
		_info_stock.text = stock_s
	if count <= 0:
		_info_name.text = Loc.t("sel_none")
		_big_portrait.visible = false
		_big_portrait_name.text = ""
		if _info_stock:
			_info_stock.text = ""
	elif count == 1:
		_info_name.text = name_s
		_big_portrait.visible = true
		_big_portrait_name.text = name_s if stock_s == "" else "%s\n%s" % [name_s, stock_s]
		_big_portrait.color = _color_for(str(units[0].get("color_kind", "unit")) if units.size() > 0 else "unit")
	else:
		_info_name.text = "%s ×%d" % [name_s, count]
		_big_portrait.visible = true
		_big_portrait_name.text = name_s
		_big_portrait.color = _color_for(str(units[0].get("color_kind", "unit")) if units.size() > 0 else "unit")
	# HP + armor line
	var hp_v: float = float(info.get("hp", -1.0))
	var max_hp_v: float = float(info.get("max_hp", 0.0))
	var am: int = int(info.get("armor_melee", 0))
	var ap: int = int(info.get("armor_pierce", 0))
	var atk_v: float = float(info.get("attack", -1.0))
	var attack_range: float = float(info.get("attack_range", -1.0))
	var attack_interval: float = float(info.get("attack_interval", -1.0))
	if _info_armor:
		if tower_selected and hp_v >= 0.0 and atk_v >= 0.0:
			_info_armor.text = "HP %.0f/%.0f  伤害%.0f  射程%.1fm  间隔%.2fs  近%d远%d" % [hp_v, max_hp_v, atk_v, attack_range, attack_interval, am, ap]
		elif count == 1 and hp_v >= 0.0 and atk_v >= 0.0:
			_info_armor.text = "HP %.0f/%.0f  攻%.0f  近%d 远%d" % [hp_v, max_hp_v, atk_v, am, ap]
		elif count == 1 and hp_v >= 0.0:
			_info_armor.text = "HP %.0f/%.0f  近%d 远%d" % [hp_v, max_hp_v, am, ap]
		elif count == 1 and atk_v >= 0.0:
			_info_armor.text = "攻%.0f  近%d 远%d" % [atk_v, am, ap]
		elif count == 1:
			_info_armor.text = "近%d 远%d" % [am, ap]
		else:
			_info_armor.text = ""
	# Train queue strip
	_refresh_train_ui(info)
	# Build progress
	var bp: float = float(info.get("build_progress", -1.0))
	if _build_prog:
		if bp >= 0.0 and bp < 1.0:
			_build_prog.visible = true
			_build_prog.value = bp
		else:
			_build_prog.visible = false
	# Fingerprint includes queue so SC2 queue updates
	var q: Array = info.get("train_queue", [])
	var glock: int = 1 if info.get("gate_locked") == true else 0
	var tech_fp: String = "%d%d%d|%d" % [
		1 if info.get("forestry_researched") == true else 0,
		1 if info.get("wheelbarrow_researched") == true else 0,
		1 if info.get("bronze_weapons_researched") == true else 0,
		int(info.get("research_age", 1)),
	]
	var qfp: String = "%s|%d|%.2f|%.2f|L%d|%s" % [kind, q.size(), float(info.get("train_progress", 0.0)), bp, glock, tech_fp]
	if qfp != _last_kind:
		_last_kind = qfp
		_clear_cmd_grid()
		match kind:
			"villager":
				_add_cmd("move", Loc.t("cmd_move"), "M", Color(0.28, 0.45, 0.32), func(): cmd_move_pressed.emit())
				_add_cmd("attack", Loc.t("cmd_attack"), "A", Color(0.65, 0.25, 0.2), func(): cmd_attack_pressed.emit())
				_add_cmd("stop", Loc.t("cmd_stop"), "S", Color(0.5, 0.28, 0.25), func(): cmd_stop_pressed.emit())
				_add_cmd("gather", Loc.t("cmd_gather"), "G", Color(0.4, 0.42, 0.28), func(): cmd_gather_pressed.emit())
				_add_cmd("build", Loc.t("cmd_build"), "B", Color(0.35, 0.4, 0.48), _on_build_toggle)
				_add_cmd("repair", Loc.t("cmd_repair"), "R", Color(0.55, 0.42, 0.28), func(): cmd_repair_pressed.emit())
			"soldier", "military", "mixed_army":
				_add_cmd("move", Loc.t("cmd_move"), "M", Color(0.28, 0.45, 0.32), func(): cmd_move_pressed.emit())
				_add_cmd("attack", Loc.t("cmd_attack"), "A", Color(0.65, 0.25, 0.2), func(): cmd_attack_pressed.emit())
				_add_cmd("guard", "守点", "F", Color(0.28, 0.48, 0.58), func(): cmd_guard_pressed.emit())
				_add_cmd("stop", Loc.t("cmd_stop"), "S", Color(0.5, 0.28, 0.25), func(): cmd_stop_pressed.emit())
				var guard_button := _cmd_btns.get("guard") as Button
				if guard_button != null:
					guard_button.tooltip_text = "F：点击地图设置守点锚点；守点仅在锚点 8 米内接敌。Shift 点击可排队；守点会一直占用队列，直到 Stop 或新指令。"
			"tc":
				_add_cmd_cost("train", Loc.t("train_villager"), "V", Color(0.3, 0.48, 0.7), Catalog.train_cost("villager"), func(): train_villager_pressed.emit())
				_add_cmd("cancel", Loc.t("cancel_train"), "X", Color(0.72, 0.2, 0.16), func(): cancel_train_pressed.emit())
				_add_cmd("age", Loc.t("age_up"), "U", Color(0.65, 0.5, 0.2), func(): age_up_pressed.emit())
				_add_cmd_cost("forestry", "改良斧具", "T", Color(0.42, 0.5, 0.3), {"meat": 25, "wood": 10}, func(): forestry_research_pressed.emit())
				_add_cmd_cost("wheelbarrow", "手推车", "W", Color(0.42, 0.5, 0.3), {"meat": 75, "wood": 50}, func(): technology_research_pressed.emit("wheelbarrow"))
			"barracks":
				_add_cmd_cost("soldier", Loc.t("train_soldier"), "A", Color(0.55, 0.35, 0.28), Catalog.train_cost("soldier"), func(): train_soldier_pressed.emit())
				_add_cmd("cancel", Loc.t("cancel_train"), "X", Color(0.72, 0.2, 0.16), func(): cancel_train_pressed.emit())
				_add_cmd_cost("bronze_weapons", "青铜武器", "B", Color(0.58, 0.39, 0.27), {"meat": 75, "wood": 25, "gold": 25}, func(): technology_research_pressed.emit("bronze_weapons"))
			"arid_farm":
				_add_cmd("reseed", Loc.t("reseed_farm"), "R", Color(0.4, 0.55, 0.25), func(): reseed_farm_pressed.emit())
			"gate":
				var locked: bool = (info.get("gate_locked", false) == true)
				if locked:
					_add_cmd("gate_unlock", Loc.t("gate_unlock"), "L", Color(0.35, 0.55, 0.35), func(): gate_lock_pressed.emit())
				else:
					_add_cmd("gate_lock", Loc.t("gate_lock"), "L", Color(0.55, 0.35, 0.28), func(): gate_lock_pressed.emit())
			"constructing":
				_add_cmd("cancel_build", Loc.t("cancel_construct"), "Del", Color(0.75, 0.18, 0.15), func(): cancel_construct_pressed.emit())
			"enemy_info":
				pass
			"resource", "farm":
				pass
			"building":
				pass
			_:
				pass
	var forestry_button := _cmd_btns.get("forestry") as Button
	if forestry_button != null:
		if info.get("forestry_researched") == true:
			forestry_button.disabled = true
			forestry_button.text = "斧具已改良"
			forestry_button.tooltip_text = "木材采集更快，携带量增加（已研发）"
		else:
			forestry_button.disabled = false
			forestry_button.text = "改良斧具\n粮25 木10"
			forestry_button.tooltip_text = "改良斧具：木材采集量 +25%，携带量 +5"
	var wheelbarrow_button := _cmd_btns.get("wheelbarrow") as Button
	if wheelbarrow_button != null:
		var wheelbarrow_done: bool = info.get("wheelbarrow_researched") == true
		var wheelbarrow_age_ok: bool = int(info.get("research_age", 1)) >= 2
		wheelbarrow_button.disabled = wheelbarrow_done or not wheelbarrow_age_ok
		wheelbarrow_button.text = "手推车已研发" if wheelbarrow_done else ("手推车\n需封建时代" if not wheelbarrow_age_ok else "手推车\n粮75 木50")
		wheelbarrow_button.tooltip_text = "所有资源携带量 +5" if wheelbarrow_age_ok else "需要先升级到封建时代"
	var bronze_button := _cmd_btns.get("bronze_weapons") as Button
	if bronze_button != null:
		var bronze_done: bool = info.get("bronze_weapons_researched") == true
		var bronze_age_ok: bool = int(info.get("research_age", 1)) >= 2
		bronze_button.disabled = bronze_done or not bronze_age_ok
		bronze_button.text = "青铜武器已研发" if bronze_done else ("青铜武器\n需封建时代" if not bronze_age_ok else "青铜武器\n粮75 木25 金25")
		bronze_button.tooltip_text = "士兵攻击力 +20%" if bronze_age_ok else "需要先升级到封建时代"

func _refresh_train_ui(info: Dictionary) -> void:
	if _train_row == null:
		return
	for c in _train_row.get_children():
		c.queue_free()
	var q: Array = info.get("train_queue", [])
	var prog: float = float(info.get("train_progress", 0.0))
	if _train_bar:
		_train_bar.visible = not q.is_empty()
		_train_bar.value = prog
	for i in range(mini(q.size(), 7)):
		var ut: String = str(q[i])
		var cost: Dictionary = Catalog.train_cost(ut)
		var lab := Label.new()
		lab.text = str(cost.get("name", ut))
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", Color(0.9, 0.85, 0.55) if i == 0 else Color(0.7, 0.7, 0.65))
		lab.custom_minimum_size = Vector2(48, 18)
		_train_row.add_child(lab)
	if info.get("train_paused") == true and not q.is_empty():
		var pl := Label.new()
		pl.text = str(info.get("train_shortage_text", "暂停·资源不足"))
		pl.add_theme_font_size_override("font_size", 12)
		pl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
		_train_row.add_child(pl)


func _rebuild_portraits(units: Array) -> void:
	_clear_sel_grid()
	var i: int = 0
	for u in units:
		if i >= 24:
			break
		var node: Node3D = u.get("node") if typeof(u) == TYPE_DICTIONARY else null
		if node == null or not is_instance_valid(node):
			continue
		var hp: float = float(u.get("hp", 1.0))
		var max_hp: float = maxf(float(u.get("max_hp", 1.0)), 1.0)
		var ck: String = str(u.get("color_kind", "unit"))
		var cell := _mk_portrait_cell(node, hp, max_hp, ck, str(u.get("name", "")))
		_sel_grid.add_child(cell)
		_portrait_nodes.append(node)
		i += 1

func _mk_portrait_cell(node: Node3D, hp: float, max_hp: float, color_kind: String, tip: String) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(48, 58)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.gui_input.connect(_on_portrait_gui.bind(node))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.14, 1)
	sb.border_color = Color(0.35, 0.85, 0.45, 0.9)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_color = Color(0.92, 0.48, 0.22, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	wrap.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	wrap.add_child(vb)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(42, 6)
	bar.max_value = max_hp
	bar.value = hp
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.25, 0.85, 0.35) if hp / max_hp > 0.35 else Color(0.9, 0.3, 0.2)
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.12)
	bar.add_theme_stylebox_override("background", bg)
	vb.add_child(bar)
	var face := ColorRect.new()
	face.custom_minimum_size = Vector2(42, 36)
	face.color = _color_for(color_kind)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(face)
	wrap.tooltip_text = tip
	return wrap

func _color_for(color_kind: String) -> Color:
	match color_kind:
		"villager":
			return Color(0.25, 0.5, 0.85)
		"soldier":
			return Color(0.75, 0.25, 0.2)
		"tc":
			return Color(0.7, 0.45, 0.2)
		"farm":
			return Color(0.4, 0.65, 0.25)
		"gold":
			return Color(0.92, 0.75, 0.2)
		"wood":
			return Color(0.35, 0.55, 0.25)
		"stone":
			return Color(0.6, 0.6, 0.62)
		"building":
			return Color(0.45, 0.45, 0.48)
		_:
			return Color(0.35, 0.4, 0.5)

func _on_portrait_gui(event: InputEvent, node: Node3D) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			portrait_clicked.emit(node, mb.shift_pressed)
			get_viewport().set_input_as_handled()

func _add_cmd_cost(id: String, label: String, hotkey: String, col: Color, cost: Dictionary, cb) -> void:
	var tip: String = label
	var cost_s: String = Catalog.cost_text_cn(cost)
	if cost_s != "":
		tip = label + "
" + cost_s
	var btn := _mk_cmd_btn(tip, hotkey, col)
	btn.pressed.connect(cb)
	_cmd_btns[id] = btn
	_cmd_grid.add_child(btn)

func _add_cmd(id: String, label: String, hotkey: String, col: Color, cb) -> void:
	var btn := _mk_cmd_btn(label, hotkey, col)
	btn.pressed.connect(cb)
	_cmd_grid.add_child(btn)
	_cmd_btns[id] = btn

func show_selection(kind: String) -> void:
	match kind:
		"tc":
			show_selection_info({"kind": "tc", "name": Loc.t("select_tc"), "count": 1, "units": []})
		"villager":
			show_selection_info({"kind": "villager", "name": Loc.t("select_villager"), "count": 1, "units": []})
		_:
			show_selection_info({"kind": "none", "units": []})

func flash_msg(text: String) -> void:
	_msg_l.text = text
	_msg_t = 2.5

func _mini_to_world(local: Vector2, sz: Vector2 = Vector2.ZERO) -> Vector3:
	if sz.x < 1.0 or sz.y < 1.0:
		sz = _minimap.size if _minimap else Vector2(168, 168)
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(168, 168)
	var nx: float = clampf(local.x / sz.x, 0.0, 1.0)
	var nz: float = clampf(local.y / sz.y, 0.0, 1.0)
	return Vector3(nx * MAP_HALF * 2.0 - MAP_HALF, 0.0, nz * MAP_HALF * 2.0 - MAP_HALF)

func _on_minimap_gui(event: InputEvent) -> void:
	## Click / drag on minimap moves the camera (emit world pos to main).
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mini_dragging = true
				minimap_goto.emit(_mini_to_world(mb.position))
				get_viewport().set_input_as_handled()
			else:
				_mini_dragging = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mini_dragging:
		var mm: InputEventMouseMotion = event
		minimap_goto.emit(_mini_to_world(mm.position))
		get_viewport().set_input_as_handled()

func _world_to_mini(p: Vector3, sz: Vector2) -> Vector2:
	var nx: float = (p.x + MAP_HALF) / (MAP_HALF * 2.0)
	var nz: float = (p.z + MAP_HALF) / (MAP_HALF * 2.0)
	return Vector2(nx * sz.x, nz * sz.y)

func _on_minimap_draw() -> void:
	var sz: Vector2 = _mini_draw.size
	_mini_draw.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.22, 0.14, 1), true)
	var tree := get_tree()
	if tree == null:
		return
	for b in tree.get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var c: Color = Color(0.55, 0.55, 0.5)
		if int(b.get("kind")) == Catalog.TOWN_CENTER:
			c = Color(0.9, 0.7, 0.25)
		elif b.is_in_group("farms"):
			c = Color(0.35, 0.7, 0.3)
		var pt: Vector2 = _world_to_mini(b.global_position, sz)
		_mini_draw.draw_rect(Rect2(pt - Vector2(2, 2), Vector2(4, 4)), c, true)
	for v in tree.get_nodes_in_group("villagers"):
		if not is_instance_valid(v):
			continue
		var pt2: Vector2 = _world_to_mini(v.global_position, sz)
		_mini_draw.draw_circle(pt2, 2.0, Color(0.3, 0.55, 1.0))
	for s in tree.get_nodes_in_group("military"):
		if not is_instance_valid(s):
			continue
		var pt3: Vector2 = _world_to_mini(s.global_position, sz)
		_mini_draw.draw_circle(pt3, 2.2, Color(0.95, 0.35, 0.25))
	if cam_pivot:
		var cpt: Vector2 = _world_to_mini(cam_pivot.global_position, sz)
		_mini_draw.draw_rect(Rect2(cpt - Vector2(10, 7), Vector2(20, 14)), Color(1, 1, 1, 0.85), false, 1.0)

func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			_msg_l.text = ""
	# Clock: _game_time = game minutes (real 1s = 10 game min). 24h HH:MM.
	var total_min: int = int(floor(_game_time)) % (24 * 60)
	if total_min < 0:
		total_min += 24 * 60
	var hh: int = total_min / 60
	var mm: int = total_min % 60
	_clock_l.text = "%02d:%02d" % [hh, mm]
	var is_night: bool = (hh >= 22 or hh < 6)
	_dn_l.text = Loc.t("night") if is_night else Loc.t("day")
	_dn_l.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0) if is_night else Color(1.0, 0.85, 0.35))
	if _mini_draw:
		_mini_draw.queue_redraw()
	_layout_br()

func is_mouse_over_ui(pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	const EDGE_FREE := 24.0
	# Top-right resources
	if pos.y < 44.0 and pos.x > vp.x - 430.0 and pos.y > EDGE_FREE:
		return true
	# Top-center civ
	if pos.y < 48.0 and absf(pos.x - vp.x * 0.5) < 120.0 and pos.y > 2.0:
		return true
	# Bottom controls handle their own hit areas. Let unused parchment space
	# pass through to world selection and order input.
	return false

func has_command_card() -> bool:
	return _cmd_grid != null and is_instance_valid(_cmd_grid)

func has_minimap() -> bool:
	return _minimap != null and is_instance_valid(_minimap)

func is_night_clock() -> bool:
	## Night 22:00–06:00 on the 24h game clock.
	var total_min: int = int(floor(_game_time)) % (24 * 60)
	if total_min < 0:
		total_min += 24 * 60
	var hh: int = total_min / 60
	return hh >= 22 or hh < 6

func has_clock() -> bool:
	return _clock_l != null and is_instance_valid(_clock_l)

func portrait_count() -> int:
	return _portrait_nodes.size()
