String formatBytes(int bytes) {
  final sign = bytes < 0 ? '-' : '';
  final kb = bytes.abs() / 1024;
  return '$sign${kb.toStringAsFixed(1)} KB';
}
