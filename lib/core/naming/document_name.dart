/// Suggested document title, stable for a given clock reading.
///
/// Uses the fields of [time] as given so tests are not timezone-dependent.
/// Callers should pass a local [DateTime].
String defaultDocumentName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}-${two(time.minute)}';
}

String formatTimestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${local.year}/${two(local.month)}/${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
}

/// File-system-safe stem derived from a document title.
String safeFileStem(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
  final collapsed = cleaned.replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return 'document';
  return collapsed.length > 80 ? collapsed.substring(0, 80).trim() : collapsed;
}
