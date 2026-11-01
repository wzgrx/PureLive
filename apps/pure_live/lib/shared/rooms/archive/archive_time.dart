/// Human-readable clock shared by catalogs, resume positions and controls.
String vodTime(Duration position) {
  final seconds = position.inSeconds.clamp(0, 31536000);
  final minutes = (seconds ~/ 60) % 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600 ? '${seconds ~/ 3600}:${minutes.toString().padLeft(2, '0')}:$rest' : '${seconds ~/ 60}:$rest';
}
