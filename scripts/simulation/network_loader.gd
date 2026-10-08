class_name NetworkLoader
extends RefCounted
## 从 JSON 加载真实线网拓扑，构建站点/线路数据。

const NETWORK_DIR := "res://resources/networks/"


static func list_networks() -> Array:
    var result: Array = []
    var dir := DirAccess.open(NETWORK_DIR)
    if dir == null:
        return result
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if not dir.current_is_dir() and fname.ends_with(".json"):
            result.append(fname.get_basename())
        fname = dir.get_next()
    dir.list_dir_end()
    result.sort()
    return result


static func load_network(network_id: String) -> Dictionary:
    var path := NETWORK_DIR + network_id + ".json"
    if not FileAccess.file_exists(path):
        push_error("Network file not found: " + path)
        return {}
    var txt := FileAccess.get_file_as_string(path)
    var data = JSON.parse_string(txt)
    if data is Dictionary:
        return data
    push_error("Failed to parse network: " + path)
    return {}


static func get_network_name(network_id: String) -> String:
    var d := load_network(network_id)
    return str(d.get("name", network_id))


static func build_stations(network: Dictionary) -> Array[Station]:
    var stations: Array[Station] = []
    var raw_stations: Array = network.get("stations", [])
    for s in raw_stations:
        var st := Station.new()
        st.id = int(s["id"])
        st.name = str(s["name"])
        st.position = Vector2(float(s["x"]), float(s["y"]))
        st.capacity = int(s.get("capacity", 120))
        stations.append(st)
    return stations


static func build_lines(network: Dictionary, stations: Array[Station]) -> Array[Line]:
    var lines: Array[Line] = []
    var raw_lines: Array = network.get("lines", [])
    for l in raw_lines:
        var ln := Line.new()
        ln.id = int(l["id"])
        ln.name = str(l["name"])
        ln.color = Config.hex_to_color(str(l["color"]))
        ln.headway = float(l.get("headway", 12.0))
        ln.base_speed = float(l.get("speed", 120.0))
        var ids: Array[int] = []
        for sid in l["station_ids"]:
            ids.append(int(sid))
        ln.station_ids = ids
        # 回填站点所属线路
        for sid in ids:
            stations[sid].lines.append(ln.id)
        lines.append(ln)
    return lines
