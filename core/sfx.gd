extends Node
## Autoload "Sfx": efectos de sonido sintetizados al arrancar (sin archivos
## de audio). Uso: Sfx.play(&"dice").
##
## Para sustituir un efecto por una grabación, basta con poner un archivo en
## res://assets/sfx/<nombre>.wav (u .ogg): se usará en lugar del sintetizado.

const RATE := 22050
const POOL_SIZE := 8
const OVERRIDE_DIR := "res://assets/sfx/"

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams = {
		&"dice": _dice(),
		&"build": _build(),
		&"resource": _tone([1046.5, 1568.0], 0.16, 0.25),
		&"card": _noise_swish(0.14),
		&"robber": _sweep(320.0, 110.0, 0.45, 0.35),
		&"turn": _bell(),
		&"trade": _tone([784.0, 1046.5, 1318.5], 0.11, 0.25),
		&"win": _tone([523.25, 659.25, 783.99, 1046.5], 0.16, 0.3, 0.5),
		&"error": _buzz(),
		&"click": _tone([1800.0], 0.025, 0.12),
		# La Conjura.
		&"approve": _tone([659.25, 987.77], 0.1, 0.22),
		&"reject": _tone([392.0, 293.66], 0.13, 0.22),
		&"seal": _seal(),
		&"gong": _gong(),
		&"whisper": _whisper(),
		&"crisis": _drum_roll(),
		&"win_sombra": _tone([440.0, 523.25, 659.25, 622.25, 440.0], 0.17, 0.26, 0.6),
	}
	for sound in _streams.keys():
		for ext in ["wav", "ogg"]:
			var path: String = OVERRIDE_DIR + String(sound) + "." + ext
			if ResourceLoader.exists(path):
				_streams[sound] = load(path)
	# Sin depender del autoload App por nombre (así el script carga en tests).
	var app := get_node_or_null("/root/App")
	set_volume(app.get_setting("volume", 0.8) if app != null else 0.8)


func play(sound: StringName, pitch: float = 1.0) -> void:
	if not _streams.has(sound) or AudioServer.is_bus_mute(0):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()


func has_sound(sound: StringName) -> bool:
	return _streams.has(sound)


## Volumen general de 0 a 1 (0 = silencio).
func set_volume(volume: float) -> void:
	AudioServer.set_bus_mute(0, volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))


# --- Síntesis ----------------------------------------------------------------------

func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	return s


## Notas seguidas (arpegio) con envolvente de campana.
func _tone(freqs: Array, note_len: float, volume: float, tail: float = 0.1) -> AudioStreamWAV:
	var s := _buffer(note_len * freqs.size() + tail)
	for n in freqs.size():
		var start := int(n * note_len * RATE)
		var length := int((note_len + tail) * RATE)
		for i in length:
			if start + i >= s.size():
				break
			var t := float(i) / RATE
			var env := exp(-t * 9.0) * minf(1.0, t * 400.0)
			var f: float = freqs[n]
			s[start + i] += volume * env * (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t))
	return _to_stream(s)


## Traqueteo de dados: golpes cortos de ruido filtrado.
func _dice() -> AudioStreamWAV:
	var s := _buffer(0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits := [0.0, 0.07, 0.15, 0.22, 0.31, 0.38, 0.46]
	for h in hits:
		var start: int = int(h * RATE)
		var amp: float = 0.5 * (1.0 - h)
		var last := 0.0
		for i in int(0.03 * RATE):
			if start + i >= s.size():
				break
			var t := float(i) / RATE
			last = last * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4  # paso bajo
			s[start + i] += amp * exp(-t * 120.0) * (last + 0.5 * sin(TAU * 900.0 * t))
	return _to_stream(s)


## Golpe de pieza sobre la mesa.
func _build() -> AudioStreamWAV:
	var s := _buffer(0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in s.size():
		var t := float(i) / RATE
		var thump := sin(TAU * (140.0 - 60.0 * t) * t) * exp(-t * 22.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 300.0)
		s[i] = 0.6 * thump + 0.25 * click
	return _to_stream(s)


func _noise_swish(seconds: float) -> AudioStreamWAV:
	var s := _buffer(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var last := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := sin(PI * t / seconds)
		last = last * 0.75 + rng.randf_range(-1.0, 1.0) * 0.25
		s[i] = 0.5 * env * last
	return _to_stream(s)


func _sweep(f0: float, f1: float, seconds: float, volume: float) -> AudioStreamWAV:
	var s := _buffer(seconds)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / seconds)
		phase += TAU * f / RATE
		var env := minf(1.0, t * 50.0) * (1.0 - t / seconds)
		s[i] = volume * env * (sin(phase) + 0.4 * sin(phase * 0.5))
	return _to_stream(s)


func _bell() -> AudioStreamWAV:
	var s := _buffer(0.9)
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 4.5) * minf(1.0, t * 300.0)
		s[i] = 0.22 * env * (sin(TAU * 659.25 * t) + 0.5 * sin(TAU * 987.77 * t) + 0.25 * sin(TAU * 1318.5 * t))
	return _to_stream(s)


func _buzz() -> AudioStreamWAV:
	var s := _buffer(0.16)
	for i in s.size():
		var t := float(i) / RATE
		var square := 1.0 if fmod(t * 140.0, 1.0) < 0.5 else -1.0
		s[i] = 0.18 * square * (1.0 - t / 0.16)
	return _to_stream(s)


## Sello de lacre: golpe sordo con un tono grave.
func _seal() -> AudioStreamWAV:
	var s := _buffer(0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var last := 0.0
	for i in s.size():
		var t := float(i) / RATE
		last = last * 0.85 + rng.randf_range(-1.0, 1.0) * 0.15
		var thump := sin(TAU * (95.0 - 40.0 * t) * t) * exp(-t * 14.0)
		s[i] = 0.55 * thump + 0.5 * last * exp(-t * 60.0) + 0.12 * sin(TAU * 196.0 * t) * exp(-t * 6.0)
	return _to_stream(s)


## Gong grave (destierro).
func _gong() -> AudioStreamWAV:
	var s := _buffer(1.8)
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 2.2) * minf(1.0, t * 200.0)
		var wobble := 1.0 + 0.004 * sin(TAU * 5.0 * t)
		s[i] = 0.3 * env * (sin(TAU * 98.0 * wobble * t) + 0.6 * sin(TAU * 147.0 * t) + 0.35 * sin(TAU * 233.0 * t) + 0.2 * sin(TAU * 311.0 * t))
	return _to_stream(s)


## Susurro: ruido suave que sube y baja (secretos y poderes).
func _whisper() -> AudioStreamWAV:
	var s := _buffer(0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var a := 0.0
	var b := 0.0
	for i in s.size():
		var t := float(i) / RATE
		a = a * 0.5 + rng.randf_range(-1.0, 1.0) * 0.5
		b = b * 0.9 + a * 0.1
		var env := sin(PI * t / 0.6) * (0.6 + 0.4 * sin(TAU * 7.0 * t))
		s[i] = 0.35 * env * (a - b)
	return _to_stream(s)


## Redoble de tambor (crisis).
func _drum_roll() -> AudioStreamWAV:
	var s := _buffer(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var hit := 0.0
	while hit < 0.85:
		var start := int(hit * RATE)
		var amp := 0.2 + 0.35 * hit
		for i in int(0.05 * RATE):
			if start + i >= s.size():
				break
			var t := float(i) / RATE
			s[start + i] += amp * exp(-t * 70.0) * (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 160.0 * t))
		hit += 0.045
	var boom := int(0.85 * RATE)
	for i in s.size() - boom:
		var t := float(i) / RATE
		s[boom + i] += 0.6 * sin(TAU * (80.0 - 30.0 * t) * t) * exp(-t * 12.0)
	return _to_stream(s)
