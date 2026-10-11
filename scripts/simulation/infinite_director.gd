class_name InfiniteDirector
extends RefCounted
## 无限模式导演：没有"时间到"，只有"撑不住"。
##
## 每隔 wave_seconds 就往线网里塞一个新站 + 一条新线，同时把客流、事件密度、
## 吞吐目标一起往上推。玩家不是在"撑到终点"，而是在"能撑到第几波"。
##
## 分工：这个类只管"什么时候加压、加多少"（节奏可单独调，也方便无头测试），
## 站点与线路的具体构造在 Simulation.add_infinite_station() / add_infinite_line()。

signal wave_started(wave: int, line_id: int, station_id: int)

var sim: Simulation = null

var wave: int = 0
var timer: float = 0.0        # 距离下一波的倒计时（现实秒）
var duration: float = 75.0    # 每波间隔

# 统计（结算界面用）
var stations_added: int = 0
var lines_added: int = 0


func _init(p_sim: Simulation) -> void:
    sim = p_sim
    duration = maxf(10.0, float(Config.INFINITE["wave_seconds"]))
    timer = duration


func tick(delta: float) -> void:
    if sim == null:
        return
    timer -= delta
    # 用 while 而不是 if：快进或掉帧时 delta 可能大于一整波，不能漏波
    while timer <= 0.0:
        timer += duration
        advance_wave()


## 当前这波的进度 0..1（HUD 画"下一波"倒计时条用）
func progress() -> float:
    if duration <= 0.0:
        return 1.0
    return clampf(1.0 - timer / duration, 0.0, 1.0)


func seconds_left() -> float:
    return maxf(0.0, timer)


## 加压一波：加站 -> 加线 -> 抬高客流/事件密度/吞吐目标 -> 发奖励与播报。
func advance_wave() -> void:
    wave += 1

    var new_sids: Array[int] = []
    for i in range(int(Config.INFINITE["new_stations_per_wave"])):
        var sid := sim.add_infinite_station()
        if sid >= 0:
            new_sids.append(sid)
            stations_added += 1

    var lid := sim.add_infinite_line(new_sids)
    if lid >= 0:
        lines_added += 1

    # 客流加压
    var growth := float(Config.INFINITE["spawn_growth"])
    sim.base_spawn_rate = clampf(sim.base_spawn_rate * (1.0 + growth), 1.0, float(Config.INFINITE["spawn_cap"]))

    # 事件与升级越来越密
    if sim.events != null:
        sim.events.set_interval_scale(pow(float(Config.INFINITE["event_scale_per_wave"]), float(wave)))

    # 吞吐目标同步抬高：否则吞吐比会一直卡在 1.00，这一维度就失去意义了
    if sim.score != null:
        sim.score.set_target(sim.score.target_served + float(Config.INFINITE["target_growth"]))

    # 打通一波要给点资源，否则第 3 波之后就是纯挨打，扩张没有正反馈
    sim.resources = minf(999.0, sim.resources + float(Config.INFINITE["resource_bonus"]))

    var anchor := -1
    if not new_sids.is_empty():
        anchor = new_sids[0]
    wave_started.emit(wave, lid, anchor)
    EventBus.wave_started.emit(wave, lid, anchor)

    if lid >= 0 and anchor >= 0:
        EventBus.toast.emit("第 %d 波：新线 %s，新增站点 %s" % [wave, sim.get_line(lid).name, sim.get_station(anchor).name])
    elif lid >= 0:
        EventBus.toast.emit("第 %d 波：新线开通，客流加压" % wave)
    else:
        EventBus.toast.emit("第 %d 波：客流加压（线网已达上限）" % wave)
