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
const SHAKE_PX := 9.0               # 震屏满振幅对应的屏幕像素（够"有感觉"，不至于看不清线）

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

# ================= 镜头效果 =================
# 全部效果都**只影响相机**（位置/缩放），不碰模拟层，所以不会改变任何平衡数值。

## 地图包围盒（含余量），用于拖拽到边界时的橡皮筋回弹
var map_min: Vector2 = Vector2.ZERO
var map_max: Vector2 = Vector2.ZERO
var bounds_ready: bool = false

# 震屏：踩踏等突发事件时轻微抖动。振幅按屏幕像素给，衰减很快（不晕）。
const SHAKE_DECAY := 0.9          # 每秒衰减掉的振幅比例
var _shake: float = 0.0

# 飞行（点日志 / 选中站点时平滑飞过去）
const FLY_DUR := 0.55             # 全程秒数
var _flying: bool = false
var _fly_t: float = 0.0
var _fly_from: Vector2 = Vector2.ZERO
var _fly_to: Vector2 = Vector2.ZERO
var _fly_zoom_from: float = 1.0
var _fly_zoom_to: float = 1.0

# 拖拽惯性：松手后按最后一段速度滑一小段再停
const INERTIA_DECAY := 3.4        # 越大滑得越短
var _vel: Vector2 = Vector2.ZERO
var _glide: bool = false

# 缩放"拉远-推近"过冲：每次滚轮先反向轻微过冲再回到目标，像镜头换挡
const OVERSHOOT := 0.055
var _zoom_visual: float = 1.0     # 实际渲染用的缩放倍率（= target_zoom × 过冲系数）
var _overshoot: float = 0.0
var _overshoot_vel: float = 0.0

# 跟随列车（点列车切换）。位置由 TrainLayer 提供（它每帧算过列车世界坐标）
var follow_train_id: int = -1
var train_source: Node = null


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

    # 拖拽边界的包围盒（留一点余量，让边缘的站不会被顶到屏幕正中）
    map_min = min_p - Vector2(map_w, map_h) * 0.12
    map_max = max_p + Vector2(map_w, map_h) * 0.12
    bounds_ready = true

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

    # 3) 跟车：目标点直接钉在列车上（车在动，所以每帧更新）
    if follow_train_id >= 0 and _update_follow():
        pass

    # 4) 飞行：用 easeInOutCubic 走完全程，期间接管位置与缩放
    if _flying:
        _fly_t = minf(_fly_t + delta / FLY_DUR, 1.0)
        var e := _ease_in_out(_fly_t)
        camera.position = _fly_from.lerp(_fly_to, e)
        target_pos = camera.position
        var zf := lerpf(_fly_zoom_from, _fly_zoom_to, e)
        camera.zoom = Vector2(zf, zf)
        target_zoom = _fly_zoom_to
        if _fly_t >= 1.0:
            _flying = false
            last_scroll_time = now
        _apply_shake(delta)
        return

    # 5) 惯性滑动
    if _glide and not dragging:
        if _vel.length() < 1.0:
            _glide = false
            _vel = Vector2.ZERO
        else:
            camera.position += _vel * delta
            target_pos = camera.position
            _vel = _vel.lerp(Vector2.ZERO, 1.0 - exp(-INERTIA_DECAY * delta))

    # 6) 平滑逼近（缩放的"拉远-推近"过冲叠在 target_zoom 上，不影响回弹逻辑）
    _overshoot_vel += -_overshoot * 46.0 * delta
    _overshoot_vel *= exp(-9.0 * delta)
    _overshoot += _overshoot_vel * delta
    var zoom_lerp := 1.0 - exp(-ZOOM_SMOOTH * delta)
    var pan_lerp := 1.0 - exp(-PAN_SMOOTH * delta)
    _zoom_visual = target_zoom * (1.0 + _overshoot)
    camera.zoom = camera.zoom.lerp(Vector2(_zoom_visual, _zoom_visual), zoom_lerp)
    camera.position = camera.position.lerp(target_pos, pan_lerp)

    # 7) 边界：越界时橡皮筋拉回（松手后 target_pos 已被夹住，会平滑弹回）
    if bounds_ready:
        camera.position = _rubber_band(camera.position)

    _apply_shake(delta)

    # 8) 视野是否已稳定停在某一段锚点（渲染层据此把站点画成实心 ●）
    band_settled = (
        (not dragging)
        and (not snapping)
        and (not _flying)
        and absf(target_zoom - _band_anchor(target_zoom)) < 0.002
    )


## 震屏：把抖动作为**额外**偏移叠在相机位置上，不写回 target_pos，所以不会漂移
func _apply_shake(delta: float) -> void:
    if _shake <= 0.0001:
        _shake = 0.0
        return
    var amp := _shake * SHAKE_PX / maxf(camera.zoom.x, 0.01)
    camera.position += Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
    _shake = maxf(0.0, _shake - delta * SHAKE_DECAY * (0.6 + _shake))


static func _ease_in_out(t: float) -> float:
    if t < 0.5:
        return 4.0 * t * t * t
    return 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5


## 橡皮筋：在允许范围外施加阻力，越拉越难，但松手会弹回
func _rubber_band(p: Vector2) -> Vector2:
    var vp := get_viewport().get_visible_rect().size / maxf(camera.zoom.x, 0.01)
    var lo := map_min - vp * 0.5
    var hi := map_max + vp * 0.5
    var out := p
    for axis in 2:
        if p[axis] < lo[axis]:
            out[axis] = lo[axis] - (lo[axis] - p[axis]) * 0.30
        elif p[axis] > hi[axis]:
            out[axis] = hi[axis] + (p[axis] - hi[axis]) * 0.30
    return out


## 越界（含橡皮筋余量）时把目标夹回允许范围
func _clamp_target(p: Vector2) -> Vector2:
    if not bounds_ready:
        return p
    var vp := get_viewport().get_visible_rect().size / maxf(camera.zoom.x, 0.01)
    var lo := map_min - vp * 0.5
    var hi := map_max + vp * 0.5
    return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))


# ================= 对外接口（给事件 / UI 调用）=================

## 震屏：amount 1.0 = 明显但不晕。踩踏用 1.0，单站恐慌用 0.35
func shake(amount: float) -> void:
    _shake = minf(1.4, _shake + amount)


## 平滑飞到某个世界坐标；zoom > 0 时同时改变缩放（会按既有规则回弹到最近的段锚点）
func fly_to(world: Vector2, zoom: float = 0.0) -> void:
    _flying = true
    _fly_t = 0.0
    _fly_from = camera.position
    _fly_to = _clamp_target(world)
    _fly_zoom_from = camera.zoom.x
    _fly_zoom_to = clampf(zoom, min_allowed_zoom, max_allowed_zoom) if zoom > 0.0 else camera.zoom.x
    _glide = false
    _vel = Vector2.ZERO
    _snapshot_bands_for_fly()


## 飞行的目标缩放如果不在段锚点上，落地后会被回弹逻辑拉到最近锚点——这是**故意**的：
## 和滚轮缩放一致，停下来永远是 H/M/L 三段之一。
func _snapshot_bands_for_fly() -> void:
    zoom_focus_active = false
    snapping = false


## 开始 / 停止跟随某列车
func set_follow(train_id: int) -> void:
    follow_train_id = train_id
    if train_id < 0:
        return
    _flying = false
    _glide = false
    _vel = Vector2.ZERO


## 每帧把目标点钉到跟随列车上。返回 false 表示车没了（已解锁）
func _update_follow() -> bool:
    if train_source == null or not train_source.has_method("train_world_pos"):
        follow_train_id = -1
        return false
    var wp = train_source.call("train_world_pos", follow_train_id)
    if wp == null:
        follow_train_id = -1
        return false
    target_pos = wp
    zoom_focus_active = false
    return true



## 是否已稳定停在某个视野段（供渲染层/UI 查询）。
func is_settled() -> bool:
    return band_settled


## 视野滑钮用：直接指定目标缩放。
## 把 `last_scroll_time` 顶成"刚刚操作过"，0.3 秒内回弹逻辑就不会来抢；
## 松手后仍按既有规则平滑回弹到最近的段锚点（与滚轮行为一致）。
func set_zoom_target(z: float) -> void:
    target_zoom = clampf(z, min_allowed_zoom, max_allowed_zoom)
    last_scroll_time = _now()
    zoom_focus_active = false


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
                _glide = false
                _vel = Vector2.ZERO
                _flying = false
                last_scroll_time = _now()
            else:
                dragging = false
                if moved < CLICK_THRESHOLD:
                    _handle_click(mb.position)
                else:
                    # 松手进入惯性滑动；target_pos 先夹回边界，越界的话会平滑弹回
                    _vel = _vel * 0.55
                    _glide = _vel.length() > 40.0
                    target_pos = _clamp_target(camera.position)

    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if dragging:
            var delta_screen := mm.position - last_screen
            last_screen = mm.position
            moved += delta_screen.length()
            # 拖拽平移：直接移动相机（1:1 跟手），并同步目标。
            # 越界部分被橡皮筋衰减（越拉越难），松手后弹回。
            var raw := -delta_screen / camera.zoom.x
            var before := camera.position
            camera.position = _rubber_band(camera.position + raw)
            var actual := camera.position - before
            target_pos = camera.position
            # 惯性速度取实际位移（所以撞边界时惯性自然变小）
            var inst := actual / maxf(mm.relative.length() / 600.0 + 0.0001, 0.0001)
            _vel = _vel.lerp(actual * 60.0, 0.35)
            zoom_focus_active = false
            _flying = false
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
    _flying = false
    _glide = false
    _vel = Vector2.ZERO
    target_zoom = new_zoom
    last_scroll_time = _now()
    # "拉远-推近"：换挡瞬间先往反方向轻轻冲一下，再弹回目标（弹簧）
    _overshoot_vel += (-1.0 if factor > 1.0 else 1.0) * OVERSHOOT * 16.0


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
        set_follow(-1)
        sim.select_station(best_st.id)
        EventBus.selection_changed.emit({"type": "station", "id": best_st.id})
        # 点站点 -> **快速聚焦到该站（近景 L 视野）**，需求原文："点击站点则快速聚焦该站点（L视野）"
        fly_to(best_st.position, fore_zoom)
        EventBus.camera_focus.emit(best_st.position, best_st.id)
        return

    # 再找列车：点中就开始**跟车**（相机会一直跟着它走，再点空白处解除）
    if train_source != null and train_source.has_method("train_world_pos"):
        var best_tr: Train = null
        var best_td := 20.0 / camera.zoom.x
        for t in sim.trains:
            var wp = train_source.call("train_world_pos", t.id)
            if wp == null:
                continue
            var dt: float = (wp as Vector2).distance_to(world)
            if dt < best_td:
                best_td = dt
                best_tr = t
        if best_tr != null:
            sim.select_line(best_tr.line_id)
            set_follow(best_tr.id)
            EventBus.selection_changed.emit({"type": "train", "id": best_tr.id})
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
        set_follow(-1)
        sim.select_line(best_ln.id)
        EventBus.selection_changed.emit({"type": "line", "id": best_ln.id})
        # 点线路 -> **聚焦到这条线的范围，视野为 H（全貌）**。
        # H 本来就是看全图，所以这里做的是"把这条线的包围盒中心摆到画面中心"。
        var lo: Vector2 = sim.stations[best_ln.station_ids[0]].position
        var hi: Vector2 = lo
        for sid2 in best_ln.station_ids:
            var p2: Vector2 = sim.stations[sid2].position
            lo.x = minf(lo.x, p2.x)
            lo.y = minf(lo.y, p2.y)
            hi.x = maxf(hi.x, p2.x)
            hi.y = maxf(hi.y, p2.y)
        fly_to((lo + hi) * 0.5, overview_zoom)
        return

    set_follow(-1)
    sim.clear_selection()
    EventBus.selection_changed.emit({"type": "none", "id": -1})


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var len_sq := ab.length_squared()
    if len_sq < 0.0001:
        return p.distance_to(a)
    var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
    return p.distance_to(a + ab * t)
