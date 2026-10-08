class_name CameraController
extends Node
## 相机控制：按当前地图几何界定三段视野 + 离散切换 + 松手回弹（Mini Metro 手感）。
##
## 三段锚点（setup 时按地图站点坐标计算，换图自动自适应）：
##   overview_zoom  全貌段：视野正好装下整个地图包围盒（最远）
##   mid_zoom       中景段：视野横跨约 MID_SPAN 个站距，能看到 3~5 个站点
##   fore_zoom      近景段：视野聚焦到单个站点（最近）
##
## 切换到下一段：跨过相邻两段的中点即归入下一段；否则回弹回当前段锚点。
## 两端余量：全貌段可再缩小到 OVER_OUT_FACTOR×锚点（看到比全貌更远），
##           近景段可再放大到 OVER_IN_FACTOR×锚点（比单站更近），
##           滚轮停下超过 SNAP_DELAY 秒后平滑回弹到相应锚点。
## 缩放过程始终以鼠标下方的世界点为锚（缩放不漂移）。

var camera: Camera2D
var sim: Simulation

# ---- 视野锚点 / 阈值（setup 时计算）----
var overview_zoom: float = 0.9       # 全貌段锚点（最远）
var mid_zoom: float = 3.2            # 中景段锚点
var fore_zoom: float = 9.0           # 近景段锚点（最近）
var min_allowed_zoom: float = 0.6    # 全貌段可再缩小的下限（比全貌更远）
var max_allowed_zoom: float = 13.0   # 近景段可再放大的上限（比单站更近）
var network_center: Vector2 = Vector2.ZERO

# ---- 分段 / 余量 / 平滑参数 ----
const OVERVIEW_PADDING := 0.85       # 全貌：地图占视口的比例（留边）
const MID_SPAN := 4.0                # 中景：画面横向跨越的站距数（约 4 个站）
const FORE_SPAN := 1.4               # 近景：画面横向跨越的站距数（约 1 个站）
const OVER_OUT_FACTOR := 0.7         # 全貌段可再缩小的比例
const OVER_IN_FACTOR := 1.5          # 近景段可再放大的比例
const SNAP_DELAY := 0.3              # 滚轮停下多久后回弹到锚点（秒）
const ZOOM_SMOOTH := 11.0            # 缩放趋近速度（越大越跟手）
const PAN_SMOOTH := 9.0              # 平移趋近速度
const CLICK_THRESHOLD := 6.0         # 点击 vs 拖拽判定（像素）

# ---- 目标状态 ----
var target_zoom: float = 0.9         # 期望缩放
var target_pos: Vector2 = Vector2.ZERO   # 期望相机中心

# ---- 缩放锚点 ----
var zoom_focus_world: Vector2 = Vector2.ZERO   # 缩放时保持不动的世界点
var zoom_focus_screen: Vector2 = Vector2.ZERO  # 该世界点对应的屏幕点
var zoom_focus_active: bool = false

# ---- 回弹 ----
var snapping: bool = false
var snap_target_zoom: float = 0.9
var band_settled: bool = true      # 是否已稳定停在某段锚点（供渲染层做"站点涂黑 ○→●"提示）

# ---- 拖拽 ----
var dragging: bool = false
var press_screen: Vector2 = Vector2.ZERO
var last_screen: Vector2 = Vector2.ZERO
var moved: float = 0.0

# ---- 时间 ----
var last_scroll_time: float = -100.0


func setup(p_camera: Camera2D, p_sim: Simulation) -> void:
    camera = p_camera
    sim = p_sim
    set_process(true)
    _compute_bands()
    _center_camera()


# ================= 按地图几何计算三段锚点 =================

func _compute_bands() -> void:
    if sim == null or sim.stations.is_empty():
        overview_zoom = 0.9
        mid_zoom = 3.2
        fore_zoom = 9.0
        network_center = Vector2.ZERO
        _finalize_bounds()
        return

    var vp := get_viewport().get_visible_rect().size
    if vp.x <= 0.0 or vp.y <= 0.0:
        vp = Vector2(1280, 720)

    # 站点包围盒
    var min_p := sim.stations[0].position
    var max_p := sim.stations[0].position
    for st in sim.stations:
        min_p.x = minf(min_p.x, st.position.x)
        min_p.y = minf(min_p.y, st.position.y)
        max_p.x = maxf(max_p.x, st.position.x)
        max_p.y = maxf(max_p.y, st.position.y)
    network_center = (min_p + max_p) * 0.5

    var map_w := maxf(max_p.x - min_p.x, 1.0)
    var map_h := maxf(max_p.y - min_p.y, 1.0)

    var avg_edge := _avg_edge_len()
    if avg_edge <= 0.0:
        avg_edge = maxf(map_w, map_h) * 0.5

    # 全貌：宽高都能装下整个地图
    overview_zoom = minf(vp.x / map_w, vp.y / map_h) * OVERVIEW_PADDING
    # 中景：画面横向跨越 MID_SPAN 个站距
    mid_zoom = vp.x / (MID_SPAN * avg_edge)
    # 近景：画面横向跨越 FORE_SPAN 个站距（单站）
    fore_zoom = vp.x / (FORE_SPAN * avg_edge)
    _finalize_bounds()


func _finalize_bounds() -> void:
    overview_zoom = maxf(overview_zoom, 0.01)
    # 保证 全貌 < 中景 < 近景 的严格顺序
    mid_zoom = maxf(mid_zoom, overview_zoom * 1.3)
    fore_zoom = maxf(fore_zoom, mid_zoom * 1.3)
    # 两端余量：全貌可更远、近景可更近
    min_allowed_zoom = overview_zoom * OVER_OUT_FACTOR
    max_allowed_zoom = fore_zoom * OVER_IN_FACTOR


func _avg_edge_len() -> float:
    var total := 0.0
    var count := 0
    for ln in sim.lines:
        for i in range(ln.station_ids.size() - 1):
            var a_id := ln.station_ids[i]
            var b_id := ln.station_ids[i + 1]
            if a_id < 0 or a_id >= sim.stations.size():
                continue
            if b_id < 0 or b_id >= sim.stations.size():
                continue
            var a: Vector2 = sim.stations[a_id].position
            var b: Vector2 = sim.stations[b_id].position
            total += a.distance_to(b)
            count += 1
    if count == 0:
        return 0.0
    return total / float(count)


func _center_camera() -> void:
    if sim == null or sim.stations.is_empty():
        return
    target_zoom = overview_zoom
    target_pos = network_center
    camera.position = network_center
    camera.zoom = Vector2(overview_zoom, overview_zoom)
    zoom_focus_active = false
    snapping = false


func _now() -> float:
    return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
    if camera == null or sim == null:
        return

    var now := _now()

    # 1) 滚轮停下超过 SNAP_DELAY 且未拖拽 -> 回弹到当前段锚点
    if not dragging and (now - last_scroll_time) > SNAP_DELAY:
        if not snapping:
            var anchor := _band_anchor(target_zoom)
            if absf(target_zoom - anchor) > 0.0001:
                snapping = true
                snap_target_zoom = anchor
            else:
                zoom_focus_active = false

    if snapping:
        # 回弹：指数趋近锚点
        target_zoom = lerpf(target_zoom, snap_target_zoom, 1.0 - exp(-ZOOM_SMOOTH * delta))
        if absf(target_zoom - snap_target_zoom) < 0.0005:
            target_zoom = snap_target_zoom
            snapping = false
            zoom_focus_active = false

    # 2) 缩放过程中维持鼠标锚点：按当前已渲染的缩放计算期望相机中心
    if zoom_focus_active:
        target_pos = _position_for_zoom(zoom_focus_world, zoom_focus_screen, camera.zoom.x)

    # 3) 平滑逼近
    var zoom_lerp := 1.0 - exp(-ZOOM_SMOOTH * delta)
    var pan_lerp := 1.0 - exp(-PAN_SMOOTH * delta)
    camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), zoom_lerp)
    camera.position = camera.position.lerp(target_pos, pan_lerp)

    # 4) 视野是否已稳定停在某一段锚点（渲染层据此把站点画成实心 ●）
    band_settled = (
        (not dragging)
        and (not snapping)
        and absf(target_zoom - _band_anchor(target_zoom)) < 0.002
    )


## 是否已稳定停在某个视野段（供渲染层/UI 查询）。
func is_settled() -> bool:
    return band_settled


## 当前视野段名称 H/M/L（供 HUD 显示，对应效果图右侧那一栏）。
func band_name() -> String:
    var anchor := _band_anchor(target_zoom)
    if absf(anchor - overview_zoom) < 0.0001:
        return "视野 H · 全貌"
    if absf(anchor - mid_zoom) < 0.0001:
        return "视野 M · 中景"
    return "视野 L · 近景"


## 当前缩放所属的视野段锚点。
## 越出两端余量时也归到最近的端锚点（所以到全貌/近景后继续缩放，停下会弹回该端锚点）。
func _band_anchor(z: float) -> float:
    var t_low := (overview_zoom + mid_zoom) * 0.5
    var t_high := (mid_zoom + fore_zoom) * 0.5
    if z < t_low:
        return overview_zoom
    elif z < t_high:
        return mid_zoom
    return fore_zoom


## 计算让 focus_world 显示在 focus_screen 处所需的相机中心（uniform zoom）
func _position_for_zoom(focus_world: Vector2, focus_screen: Vector2, z: float) -> Vector2:
    var t := camera.get_canvas_transform()
    var v_half := t.origin + camera.position * camera.zoom.x
    return focus_world - (focus_screen - v_half) / z


func _unhandled_input(event: InputEvent) -> void:
    if camera == null or sim == null:
        return

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _zoom_gesture(1.2)
        elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _zoom_gesture(1.0 / 1.2)
        elif mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                dragging = true
                press_screen = mb.position
                last_screen = mb.position
                moved = 0.0
                zoom_focus_active = false
                snapping = false
                last_scroll_time = _now()
            else:
                dragging = false
                if moved < CLICK_THRESHOLD:
                    _handle_click(mb.position)

    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if dragging:
            var delta_screen := mm.position - last_screen
            last_screen = mm.position
            moved += delta_screen.length()
            # 拖拽平移：直接移动相机（1:1 跟手），并同步目标
            camera.position -= delta_screen / camera.zoom.x
            target_pos = camera.position
            zoom_focus_active = false
            last_scroll_time = _now()


## 滚轮缩放手势：锚定鼠标处的世界点，连续调整 target_zoom。
## 两端允许越出锚点（min_allowed_zoom / max_allowed_zoom），停下后再回弹。
func _zoom_gesture(factor: float) -> void:
    var screen := get_viewport().get_mouse_position()
    var before_world := _world_mouse_from(screen)
    var new_zoom := clampf(target_zoom * factor, min_allowed_zoom, max_allowed_zoom)
    if new_zoom == target_zoom:
        return

    zoom_focus_world = before_world
    zoom_focus_screen = screen
    zoom_focus_active = true
    snapping = false
    target_zoom = new_zoom
    last_scroll_time = _now()


func _world_mouse() -> Vector2:
    return _world_mouse_from(get_viewport().get_mouse_position())


func _world_mouse_from(screen: Vector2) -> Vector2:
    return camera.get_canvas_transform().affine_inverse() * screen


func _handle_click(screen: Vector2) -> void:
    var world: Vector2 = camera.get_canvas_transform().affine_inverse() * screen
    # 先找站点
    var station_radius := 20.0 / camera.zoom.x
    var best_st: Station = null
    var best_d := station_radius
    for st in sim.stations:
        var d := st.position.distance_to(world)
        if d < best_d:
            best_d = d
            best_st = st
    if best_st != null:
        sim.select_station(best_st.id)
        EventBus.selection_changed.emit({"type": "station", "id": best_st.id})
        return

    # 再找线路
    var line_radius := 12.0 / camera.zoom.x
    var best_ln: Line = null
    var best_ld := line_radius
    for ln in sim.lines:
        for i in range(ln.station_ids.size() - 1):
            var a: Vector2 = sim.stations[ln.station_ids[i]].position
            var b: Vector2 = sim.stations[ln.station_ids[i + 1]].position
            var d := _dist_to_segment(world, a, b)
            if d < best_ld:
                best_ld = d
                best_ln = ln
    if best_ln != null:
        sim.select_line(best_ln.id)
        EventBus.selection_changed.emit({"type": "line", "id": best_ln.id})
        return

    sim.clear_selection()
    EventBus.selection_changed.emit({"type": "none", "id": -1})


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var len_sq := ab.length_squared()
    if len_sq < 0.0001:
        return p.distance_to(a)
    var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
    return p.distance_to(a + ab * t)
