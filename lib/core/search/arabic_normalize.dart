/// Search text after Arabic folding, digit folding, and Latin case-fold.
///
/// Tashkeel and tatweel are removed. Alef variants become ا, ة becomes ه,
/// ى becomes ي, ؤ becomes و, and ئ becomes ي. Arabic-Indic and Persian
/// digits become ASCII. Latin letters are lowercased.
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final rune = input.codeUnitAt(i);
    if (_isSurrogate(rune)) continue;
    if (_isTashkeel(rune) || rune == 0x0640) continue;
    final folded = _foldLetter(rune);
    if (folded != null) {
      buffer.write(folded);
      continue;
    }
    final digit = _arabicDigit(rune);
    if (digit != null) {
      buffer.writeCharCode(0x30 + digit);
      continue;
    }
    buffer.writeCharCode(_lowerLatin(rune));
  }
  return buffer.toString();
}

class DigitRun {
  const DigitRun({
    required this.digits,
    required this.start,
    required this.end,
  });

  /// ASCII digits with separators removed.
  final String digits;

  /// Inclusive UTF-16 start in the original string.
  final int start;

  /// Exclusive UTF-16 end in the original string.
  final int end;
}

/// Digit runs with separators (spaces, dashes, slashes, dots, commas,
/// parentheses) removed. O/0 and l/1 are folded only inside a digit run.
List<DigitRun> extractDigitRuns(String input) {
  final runs = <DigitRun>[];
  final digits = StringBuffer();
  var start = -1;
  var lastDigitIndex = -1;

  void close() {
    if (digits.length >= 1 && start >= 0 && lastDigitIndex >= start) {
      runs.add(
        DigitRun(
          digits: digits.toString(),
          start: start,
          end: lastDigitIndex + 1,
        ),
      );
    }
    digits.clear();
    start = -1;
    lastDigitIndex = -1;
  }

  for (var i = 0; i < input.length; i++) {
    final rune = input.codeUnitAt(i);
    if (_isSurrogate(rune)) continue;
    final normalized = normalizeForSearch(input[i]);
    final inRun = start >= 0;
    final value = _digitValue(normalized.isEmpty ? rune : normalized.codeUnitAt(0), inRun: inRun);
    if (value != null && (_arabicDigit(rune) != null || _isAsciiDigit(rune) || inRun || _aheadIsDigit(input, i))) {
      // Confusion characters (O, l) only count when a real digit is adjacent.
      final real = _arabicDigit(rune) != null || _isAsciiDigit(rune);
      if (!real && !inRun && !_aheadIsDigit(input, i)) continue;
      if (!real && inRun && !_aheadIsDigit(input, i) && !_behindIsDigit(input, i)) {
        continue;
      }
      start = start < 0 ? i : start;
      digits.writeCharCode(0x30 + value);
      lastDigitIndex = i;
      continue;
    }
    if (inRun && _isSeparator(rune) && _aheadIsDigit(input, i)) {
      continue;
    }
    if (inRun) close();
  }
  close();
  return runs;
}

/// Groups used by a query. Separator-joined numbers keep each chunk of
/// length >= 3, and a short decimal such as 12.5 still matches as 125.
List<String> queryDigitGroups(String token) {
  final flatRuns = extractDigitRuns(token);
  if (flatRuns.isEmpty) return const [];
  if (!_hasInternalSeparator(token)) {
    return [
      for (final run in flatRuns)
        if (run.digits.length >= 3) run.digits,
    ];
  }
  final chunks = _consecutiveChunks(token);
  final long = [for (final chunk in chunks) if (chunk.length >= 3) chunk];
  if (long.isNotEmpty) return long;
  final flat = flatRuns.map((run) => run.digits).join();
  if (flat.length >= 3) return [flat];
  return const [];
}

bool _hasInternalSeparator(String token) {
  var seenDigit = false;
  for (var i = 0; i < token.length; i++) {
    final rune = token.codeUnitAt(i);
    if (_isRealDigit(rune) || (_isConfusion(rune) && _aheadIsDigit(token, i))) {
      seenDigit = true;
      continue;
    }
    if (seenDigit && _isSeparator(rune) && _aheadIsDigit(token, i)) return true;
  }
  return false;
}

List<String> _consecutiveChunks(String token) {
  final chunks = <String>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    buffer.clear();
  }

  for (var i = 0; i < token.length; i++) {
    final rune = token.codeUnitAt(i);
    final normalized = normalizeForSearch(token[i]);
    final unit = normalized.isEmpty ? rune : normalized.codeUnitAt(0);
    final inChunk = buffer.isNotEmpty;
    final value = _digitValue(unit, inRun: inChunk);
    final real = _isRealDigit(rune);
    if (value != null && (real || (inChunk && _aheadIsDigit(token, i)) || _aheadIsDigit(token, i))) {
      if (!real && !inChunk && !_aheadIsDigit(token, i)) {
        flush();
        continue;
      }
      buffer.writeCharCode(0x30 + value);
      continue;
    }
    flush();
  }
  flush();
  return chunks;
}

bool _aheadIsDigit(String input, int index) {
  for (var i = index + 1; i < input.length; i++) {
    final rune = input.codeUnitAt(i);
    if (_isSurrogate(rune)) continue;
    if (_isSeparator(rune)) continue;
    return _isRealDigit(rune);
  }
  return false;
}

bool _behindIsDigit(String input, int index) {
  for (var i = index - 1; i >= 0; i--) {
    final rune = input.codeUnitAt(i);
    if (_isSurrogate(rune)) continue;
    if (_isSeparator(rune)) continue;
    return _isRealDigit(rune);
  }
  return false;
}

bool _isRealDigit(int rune) => _isAsciiDigit(rune) || _arabicDigit(rune) != null;

bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

bool _isConfusion(int rune) =>
    rune == 0x4F || rune == 0x6F || rune == 0x6C || rune == 0x49 || rune == 0x7C;

int? _digitValue(int rune, {required bool inRun}) {
  final arabic = _arabicDigit(rune);
  if (arabic != null) return arabic;
  if (_isAsciiDigit(rune)) return rune - 0x30;
  if (!inRun && !_isConfusion(rune)) return null;
  if (rune == 0x4F || rune == 0x6F) return 0;
  if (rune == 0x6C || rune == 0x49 || rune == 0x7C) return 1;
  return null;
}

int? _arabicDigit(int rune) {
  if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660;
  if (rune >= 0x06F0 && rune <= 0x06F9) return rune - 0x06F0;
  return null;
}

bool _isTashkeel(int rune) =>
    (rune >= 0x064B && rune <= 0x065F) || rune == 0x0670;

String? _foldLetter(int rune) {
  switch (rune) {
    case 0x0623: // أ
    case 0x0625: // إ
    case 0x0622: // آ
    case 0x0671: // ٱ
      return 'ا';
    case 0x0629: // ة
      return 'ه';
    case 0x0649: // ى
      return 'ي';
    case 0x0624: // ؤ
      return 'و';
    case 0x0626: // ئ
      return 'ي';
  }
  return null;
}

int _lowerLatin(int rune) {
  if (rune >= 0x41 && rune <= 0x5A) return rune + 0x20;
  return rune;
}

bool _isSurrogate(int rune) => rune >= 0xD800 && rune <= 0xDFFF;

bool _isSeparator(int rune) {
  switch (rune) {
    case 0x20:
    case 0x09:
    case 0x0A:
    case 0x0D:
    case 0x2D: // -
    case 0x2F: // /
    case 0x2E: // .
    case 0x2C: // ,
    case 0x28: // (
    case 0x29: // )
    case 0x2B: // +
    case 0x3A: // :
    case 0x060C: // ،
    case 0x066B: // ٫
    case 0x066C: // ٬
    case 0x2013: // –
    case 0x2014: // —
      return true;
  }
  return false;
}

bool isSearchLetter(int rune) {
  if (rune >= 0x61 && rune <= 0x7A) return true;
  if (rune >= 0x41 && rune <= 0x5A) return true;
  if (rune >= 0x0621 && rune <= 0x063A) return true;
  if (rune >= 0x0641 && rune <= 0x064A) return true;
  if (rune == 0x0671) return true;
  return false;
}
