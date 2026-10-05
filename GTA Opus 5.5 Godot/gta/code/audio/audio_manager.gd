extends Node
## Procedural audio (autoload "Audio"): every sound is synthesised by project code at startup
## (or loaded from res://gta/generated/audio/<name>.wav if baked), then played through pooled players.

const RATE := 22050
var streams := {}
var pool3d: Array[AudioStreamPlayer3D] = []
var pool2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var rng := RandomNumberGenerator.new()
var _radio_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 1234
	_setup_buses()
	var t0 := Time.get_ticks_msec()
	if _load_cache():
		print("[Audio] loaded %d baked sounds in %d ms" % [streams.size(), Time.get_ticks_msec() - t0])
	else:
		_generate_all()
		print("[Audio] synthesised %d sounds in %d ms" % [streams.size(), Time.get_ticks_msec() - t0])
		_radio_pending = true
		WorkerThreadPool.add_task(_radio_thread)
	for i in 28:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 8.0
		p.max_distance = 220.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		pool3d.append(p)
	for i in 10:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "UI"
		add_child(p2)
		pool2d.append(p2)


func _setup_buses() -> void:
	for b in ["SFX", "Ambient", "Music", "UI"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 900.0
	AudioServer.add_bus_effect(0, lp)
	AudioServer.set_bus_effect_enabled(0, 0, false)


func _process(_delta: float) -> void:
	if _radio_done:
		_radio_done = false
		var out := _radio_out
		_radio_out = {}
		for k in out:
			_wav(k, out[k], true)
		print("[Audio] radio stations ready")


func set_underwater(v: bool) -> void:
	AudioServer.set_bus_effect_enabled(0, 0, v)


func get_stream(name: String) -> AudioStream:
	return streams.get(name)


func play_3d(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_dist := 0.0) -> AudioStreamPlayer3D:
	var s: AudioStream = streams.get(name)
	if s == null:
		return null
	var p := pool3d[_i3]
	_i3 = (_i3 + 1) % pool3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.max_distance = max_dist if max_dist > 0.0 else 220.0
	p.play()
	return p


func play_2d(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	var p := pool2d[_i2]
	_i2 = (_i2 + 1) % pool2d.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func play_ui(name: String) -> void:
	play_2d(name, -6.0, 1.0)


## Looping positional emitter attached to a node (engines, sirens, rotors).
func make_loop(parent: Node3D, name: String, vol_db := 0.0, max_dist := 160.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.get(name)
	p.bus = "SFX"
	p.volume_db = vol_db
	p.unit_size = 10.0
	p.max_distance = max_dist
	parent.add_child(p)
	return p


# ------------------------------------------------------------------ synthesis

const CACHE_DIR := "res://gta/generated/audio/"

func _load_cache() -> bool:
	var mf := CACHE_DIR + "manifest.txt"
	if not FileAccess.file_exists(mf):
		return false
	for line in FileAccess.get_file_as_string(mf).split("
", false):
		var res = load(CACHE_DIR + line.strip_edges() + ".res")
		if not (res is AudioStream):
			streams.clear()
			return false
		streams[line.strip_edges()] = res
	return streams.has("radio_0")


## Editor/headless tool entry: synthesise everything and save as binary resources.
func bake() -> void:
	streams.clear()
	_generate_all()
	_generate_radio()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var names := PackedStringArray()
	for n in streams:
		ResourceSaver.save(streams[n], CACHE_DIR + n + ".res", ResourceSaver.FLAG_COMPRESS)
		names.append(n)
	var f := FileAccess.open(CACHE_DIR + "manifest.txt", FileAccess.WRITE)
	f.store_string("
".join(names))
	f.close()
	print("[Audio] baked %d sounds" % names.size())


## Runs off the main thread; results are handed over through _radio_out and applied in _process.
static var _radio_out := {}
static var _radio_done := false

func _radio_thread() -> void:
	var out := {}
	out["radio_0"] = _song(108.0, [57, 53, 60, 55], "synth")
	out["radio_1"] = _song(78.0, [50, 55, 48, 52], "lofi")
	out["radio_2"] = _song(90.0, [45, 45, 48, 43], "dub")
	_radio_out = out
	_radio_done = true


func _wav(name: String, buf: PackedFloat32Array, loop := false) -> void:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	streams[name] = w


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _noise() -> float:
	return rng.randf() * 2.0 - 1.0


## Shot: noise crack + low body thump, filtered by "tone" (0 dark .. 1 bright).
func _shot(dur: float, decay: float, thump_hz: float, tone: float, vol := 1.0) -> PackedFloat32Array:
	var b := _buf(dur)
	var lp := 0.0
	var a := lerpf(0.08, 0.9, tone)
	for i in b.size():
		var t := float(i) / RATE
		var env := exp(-t * decay)
		lp += a * (_noise() - lp)
		var crack := lp * env
		var body := sin(TAU * thump_hz * t * (1.0 - t * 2.0)) * exp(-t * decay * 0.6) * 0.8
		b[i] = (crack * 1.1 + body) * vol * (1.0 if t > 0.002 else t / 0.002)
	return b


func _generate_all() -> void:
	_wav("shot_pistol", _shot(0.45, 18.0, 120.0, 0.7))
	_wav("shot_heavy", _shot(0.7, 11.0, 90.0, 0.55, 1.1))
	_wav("shot_smg", _shot(0.25, 26.0, 140.0, 0.75, 0.85))
	_wav("shot_rifle", _shot(0.6, 14.0, 100.0, 0.85))
	_wav("shot_shotgun", _shot(0.8, 9.0, 70.0, 0.5, 1.2))
	_wav("shot_sniper", _shot(1.2, 6.0, 60.0, 0.9, 1.2))
	_wav("shot_suppressed", _shot(0.18, 40.0, 220.0, 0.25, 0.45))
	_wav("shot_launcher", _shot(0.6, 8.0, 50.0, 0.2, 0.9))
	# reload / mechanical
	var rl := _buf(0.55)
	for i in rl.size():
		var t := float(i) / RATE
		var c1 := exp(-maxf(t - 0.05, 0.0) * 120.0) * float(t > 0.05) * _noise()
		var c2 := exp(-maxf(t - 0.38, 0.0) * 90.0) * float(t > 0.38) * (_noise() * 0.6 + sin(TAU * 1800.0 * t) * 0.4)
		rl[i] = (c1 + c2) * 0.7
	_wav("reload", rl)
	var em := _buf(0.08)
	for i in em.size():
		em[i] = sin(TAU * 2400.0 * i / RATE) * exp(-float(i) / RATE * 80.0) * 0.4
	_wav("empty", em)
	# explosion
	var ex := _buf(2.2)
	var lp := 0.0
	var lp2 := 0.0
	for i in ex.size():
		var t := float(i) / RATE
		lp += 0.06 * (_noise() - lp)
		lp2 += 0.01 * (lp - lp2)
		var env := (1.0 if t > 0.01 else t / 0.01) * exp(-t * 2.2)
		ex[i] = (lp * 1.8 + lp2 * 6.0 + sin(TAU * 38.0 * t) * exp(-t * 3.0) * 0.8) * env
	_wav("explosion", ex)
	var th := _buf(3.0)
	lp = 0.0
	lp2 = 0.0
	for i in th.size():
		var t := float(i) / RATE
		lp += 0.02 * (_noise() - lp)
		lp2 += 0.004 * (lp - lp2)
		var env := minf(t / 0.15, 1.0) * exp(-t * 1.1) * (0.7 + 0.3 * sin(t * 13.0))
		th[i] = (lp * 3.0 + lp2 * 8.0) * env
	_wav("thunder", th)
	# impacts
	var im := _buf(0.3)
	for i in im.size():
		var t := float(i) / RATE
		im[i] = (sin(TAU * 1250.0 * t) * 0.5 + sin(TAU * 2930.0 * t) * 0.3 + _noise() * 0.3) * exp(-t * 22.0) * 0.8
	_wav("impact_metal", im)
	var iw := _buf(0.22)
	lp = 0.0
	for i in iw.size():
		var t := float(i) / RATE
		lp += 0.25 * (_noise() - lp)
		iw[i] = (lp + sin(TAU * 180.0 * t) * 0.6) * exp(-t * 30.0)
	_wav("impact_wood", iw)
	var ic := _buf(0.18)
	lp = 0.0
	for i in ic.size():
		var t := float(i) / RATE
		lp += 0.5 * (_noise() - lp)
		ic[i] = lp * exp(-t * 40.0) * 0.8
	_wav("impact_concrete", ic)
	var ifl := _buf(0.2)
	for i in ifl.size():
		var t := float(i) / RATE
		ifl[i] = (sin(TAU * 90.0 * t) + _noise() * 0.2) * exp(-t * 28.0)
	_wav("impact_flesh", ifl)
	var gl := _buf(0.8)
	for i in gl.size():
		var t := float(i) / RATE
		var tinkle := 0.0
		for k in 4:
			var tk := 0.02 + k * 0.09
			if t > tk:
				tinkle += sin(TAU * (2800.0 + k * 900.0) * t) * exp(-(t - tk) * 30.0)
		gl[i] = (tinkle * 0.4 + _noise() * exp(-t * 18.0) * 0.6) * 0.8
	_wav("glass", gl)
	var ft := _buf(0.12)
	lp = 0.0
	for i in ft.size():
		var t := float(i) / RATE
		lp += 0.18 * (_noise() - lp)
		ft[i] = lp * exp(-t * 45.0) * 0.9
	_wav("footstep", ft)
	var sw := _buf(0.3)
	lp = 0.0
	for i in sw.size():
		var t := float(i) / RATE
		var a := 0.05 + 0.4 * sin(PI * t / 0.3)
		lp += a * (_noise() - lp)
		sw[i] = lp * sin(PI * t / 0.3) * 0.7
	_wav("swing", sw)
	var pu := _buf(0.25)
	for i in pu.size():
		var t := float(i) / RATE
		pu[i] = (sin(TAU * 70.0 * t) * 1.2 + _noise() * 0.35) * exp(-t * 25.0)
	_wav("punch", pu)
	var sp := _buf(0.9)
	lp = 0.0
	for i in sp.size():
		var t := float(i) / RATE
		lp += 0.3 * (_noise() - lp)
		sp[i] = lp * minf(t / 0.02, 1.0) * exp(-t * 4.5)
	_wav("splash", sp)
	var cr := _buf(0.7)
	for i in cr.size():
		var t := float(i) / RATE
		cr[i] = (_noise() * 0.8 + sin(TAU * 60.0 * t) * 0.6 + sin(TAU * 900.0 * t * (1.0 + _noise() * 0.1)) * 0.25) * exp(-t * 7.0)
	_wav("crash", cr)
	# loops
	_wav("engine_car", _engine(48.0, 0.5, 1.0), true)
	_wav("engine_bike", _engine(62.0, 0.8, 1.0), true)
	_wav("engine_truck", _engine(36.0, 0.35, 1.0), true)
	_wav("engine_boat", _engine(55.0, 0.9, 1.0), true)
	_wav("engine_plane", _engine(70.0, 0.6, 1.0), true)
	var heli := _buf(1.0)
	lp = 0.0
	for i in heli.size():
		var t := float(i) / RATE
		var ph := fmod(t * 11.0, 1.0)
		lp += 0.12 * (_noise() - lp)
		heli[i] = (lp * 1.4 + sin(TAU * 44.0 * t) * 0.4) * exp(-ph * 6.0) * 0.9 + sin(TAU * 220.0 * t) * 0.05
	_wav("heli_loop", heli, true)
	var horn := _buf(0.5)
	for i in horn.size():
		var t := float(i) / RATE
		horn[i] = (signf(sin(TAU * 392.0 * t)) * 0.25 + signf(sin(TAU * 494.0 * t)) * 0.25) * 0.8
	_wav("horn", horn, true)
	var siren := _buf(2.4)
	var ph2 := 0.0
	for i in siren.size():
		var t := float(i) / RATE
		var f := 700.0 + 550.0 * (0.5 - 0.5 * cos(TAU * t / 2.4))
		ph2 += TAU * f / RATE
		siren[i] = (sin(ph2) * 0.6 + signf(sin(ph2)) * 0.15) * 0.8
	_wav("siren", siren, true)
	var skid := _buf(1.0)
	lp = 0.0
	for i in skid.size():
		var t := float(i) / RATE
		lp += 0.55 * (_noise() - lp)
		skid[i] = (lp * 0.5 + sin(TAU * 1100.0 * t + sin(t * 40.0) * 2.0) * 0.25) * 0.7
	_wav("skid", skid, true)
	_wav("rain_loop", _noise_loop(2.0, 0.6, 0.5), true)
	_wav("wind_loop", _noise_loop(3.0, 0.02, 0.6, 0.3), true)
	_wav("ocean_loop", _noise_loop(4.0, 0.05, 0.8, 0.25), true)
	_wav("city_loop", _city_loop(), true)
	var uw := _buf(2.0)
	lp = 0.0
	for i in uw.size():
		var t := float(i) / RATE
		lp += 0.01 * (_noise() - lp)
		uw[i] = lp * 5.0 * (0.7 + 0.3 * sin(t * PI))
	_wav("underwater_loop", uw, true)
	# UI
	_wav("ui_click", _tone(1200.0, 0.05, 60.0, 0.4))
	_wav("ui_back", _tone(600.0, 0.07, 50.0, 0.4))
	_wav("buy", _chime([880.0, 1320.0], 0.25))
	_wav("deny", _tone(180.0, 0.25, 10.0, 0.5, true))
	_wav("pickup", _chime([660.0, 990.0, 1320.0], 0.3))
	_wav("notify", _chime([740.0, 980.0], 0.22))
	_wav("wanted_up", _chime([520.0, 390.0], 0.35, true))
	_wav("phone", _chime([1046.0, 1318.0, 1568.0], 0.35))
	var hb := _buf(0.8)
	for i in hb.size():
		var t := float(i) / RATE
		hb[i] = sin(TAU * 55.0 * t) * (exp(-t * 18.0) + exp(-maxf(t - 0.22, 0.0) * 18.0) * float(t > 0.22) * 0.7)
	_wav("heartbeat", hb)
	var sc := _buf(0.9)
	var ph3 := 0.0
	for i in sc.size():
		var t := float(i) / RATE
		var f := 520.0 - t * 160.0 + sin(t * 38.0) * 14.0
		ph3 += TAU * f / RATE
		var v := sin(ph3) + 0.5 * sin(ph3 * 2.0) + 0.3 * sin(ph3 * 3.0)
		sc[i] = v * 0.25 * minf(t / 0.05, 1.0) * exp(-t * 2.0)
	_wav("scream", sc)
	var ch := _buf(3.0)
	lp = 0.0
	for i in ch.size():
		var t := float(i) / RATE
		lp += 0.08 * (_noise() - lp)
		var syll := 0.5 + 0.5 * sin(t * TAU * 3.3 + sin(t * 2.1) * 3.0)
		ch[i] = lp * syll * 1.2 * (0.7 + 0.3 * sin(t * 1.3))
	_wav("chatter", ch, true)
	var wh := _buf(0.35)
	for i in wh.size():
		var t := float(i) / RATE
		wh[i] = sin(TAU * (900.0 + 400.0 * t) * t) * 0.3 * minf(t / 0.03, 1.0) * exp(-t * 5.0)
	_wav("whistle", wh)
	var bark := _buf(0.3)
	for i in bark.size():
		var t := float(i) / RATE
		bark[i] = (sin(TAU * (380.0 - t * 400.0) * t) * 0.6 + _noise() * 0.3) * exp(-t * 14.0)
	_wav("bark", bark)
	var gull := _buf(0.6)
	for i in gull.size():
		var t := float(i) / RATE
		var f := 1400.0 - 500.0 * t + 200.0 * sin(t * 30.0)
		gull[i] = sin(TAU * f * t) * 0.25 * exp(-t * 3.0) * minf(t / 0.02, 1.0)
	_wav("gull", gull)


func _engine(base: float, rough: float, vol: float) -> PackedFloat32Array:
	# exactly integer number of cycles for a seamless loop
	var cycles := int(base * 1.0)
	var dur := float(cycles) / base
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var ph := TAU * base * t
		var v := sin(ph) * 0.55 + sin(ph * 2.0) * 0.3 * rough + sin(ph * 3.0) * 0.18 + signf(sin(ph * 0.5)) * 0.12 * rough
		lp += 0.3 * (_noise() - lp)
		b[i] = (v + lp * 0.12 * rough) * 0.55 * vol
	return b


func _noise_loop(dur: float, cutoff: float, vol: float, swell := 0.0) -> PackedFloat32Array:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += cutoff * (_noise() - lp)
		var env := 1.0 - swell + swell * sin(PI * t / dur)
		b[i] = lp * vol * env * (1.0 / sqrt(cutoff) * 0.25 if cutoff < 0.3 else 1.0)
	# crossfade ends for a seamless loop
	var xf := int(RATE * 0.05)
	for i in xf:
		var k := float(i) / xf
		b[i] = b[i] * k + b[b.size() - xf + i] * (1.0 - k)
	return b


func _city_loop() -> PackedFloat32Array:
	var b := _buf(5.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += 0.015 * (_noise() - lp)
		lp2 += 0.2 * (_noise() - lp2)
		var distant := sin(TAU * 52.0 * t) * 0.06 * (0.5 + 0.5 * sin(t * 1.3))
		var honk := 0.0
		if absf(t - 3.1) < 0.18:
			honk = signf(sin(TAU * 420.0 * t)) * 0.03
		b[i] = lp * 2.5 + lp2 * 0.04 + distant + honk
	return b


func _tone(f: float, dur: float, decay: float, vol: float, square := false) -> PackedFloat32Array:
	var b := _buf(dur)
	for i in b.size():
		var t := float(i) / RATE
		var s := sin(TAU * f * t)
		b[i] = (signf(s) * 0.5 if square else s) * vol * exp(-t * decay) * minf(t / 0.005, 1.0)
	return b


func _chime(freqs: Array, dur: float, down := false) -> PackedFloat32Array:
	var b := _buf(dur)
	var n := freqs.size()
	for i in b.size():
		var t := float(i) / RATE
		var seg := mini(int(t / (dur / n)), n - 1)
		var f: float = freqs[seg]
		var lt := t - seg * dur / n
		b[i] = (sin(TAU * f * t) * 0.35 + sin(TAU * f * 2.0 * t) * 0.08) * exp(-lt * 9.0) * minf(lt / 0.004, 1.0)
	return b


# ------------------------------------------------------------------ radio (original procedural music)

const STATIONS := ["VBR 88.1 Neon Drive", "Harbor Lo-Fi 92.4", "Crown Hill Dub 101.7", "Static (off)"]

func _generate_radio() -> void:
	_wav("radio_0", _song(108.0, [57, 53, 60, 55], "synth"), true)
	_wav("radio_1", _song(78.0, [50, 55, 48, 52], "lofi"), true)
	_wav("radio_2", _song(90.0, [45, 45, 48, 43], "dub"), true)


func _midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69.0) / 12.0)


func _song(bpm: float, roots: Array, style: String) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = int(bpm * 10.0)
	var beat := 60.0 / bpm
	var bars := roots.size() * 2
	var dur := beat * 4.0 * bars
	var b := _buf(dur)
	var lp := 0.0
	var minor := [0, 3, 7, 10]
	for i in b.size():
		var t := float(i) / RATE
		var bar := int(t / (beat * 4.0)) % roots.size()
		var root: float = roots[bar]
		var bt := fmod(t, beat)
		var step16 := int(t / (beat * 0.25)) % 16
		var s := 0.0
		# pad chord
		for iv in minor:
			var f := _midi(root + 12 + iv)
			s += sin(TAU * f * t + sin(TAU * f * 0.5 * t) * (0.6 if style == "synth" else 0.2)) * 0.06
		# bass
		var bf := _midi(root - 12)
		var benv := exp(-bt * (6.0 if style != "dub" else 2.5))
		s += (sin(TAU * bf * t) + 0.3 * sin(TAU * bf * 2.0 * t)) * 0.28 * benv
		# arp / melody
		if style == "synth":
			var note: int = minor[step16 % 4] + 24 + (12 if step16 >= 8 else 0)
			var st := fmod(t, beat * 0.25)
			s += signf(sin(TAU * _midi(root + note) * t)) * 0.05 * exp(-st * 14.0)
		elif style == "lofi":
			var st2 := fmod(t, beat * 0.5)
			if step16 % 3 == 0:
				s += sin(TAU * _midi(root + 24 + minor[(step16 / 3) % 4]) * t) * 0.09 * exp(-st2 * 5.0)
		else:
			if step16 % 4 == 2:
				var st3 := fmod(t, beat)
				s += sin(TAU * _midi(root + 24 + 7) * t) * 0.08 * exp(-st3 * 3.0)
		# drums
		var kick := exp(-bt * 22.0) * sin(TAU * (55.0 + 90.0 * exp(-bt * 30.0)) * bt) * 0.5
		var half := fmod(t, beat * 2.0)
		var snare := 0.0
		if half > beat:
			snare = (r.randf() * 2.0 - 1.0) * exp(-(half - beat) * 18.0) * 0.18
		lp += 0.7 * ((r.randf() * 2.0 - 1.0) - lp)
		var hat := ((r.randf() * 2.0 - 1.0) - lp) * exp(-fmod(t, beat * 0.5) * 50.0) * 0.06
		if style == "lofi":
			hat *= 0.6
			s += (r.randf() * 2.0 - 1.0) * 0.008
		s += kick + snare + hat
		b[i] = s * 0.9
	return b
