import '../../data/models/records.dart';
import 'arabic_normalize.dart';

class QueryTerm {
  const QueryTerm({required this.text, required this.digitGroups});

  /// Normalized letters for prefix matching. Empty for a number-only token.
  final String text;

  /// ASCII digit groups of length >= 3, or a joined decimal such as 125.
  final List<String> digitGroups;

  bool get isDigit => text.isEmpty && digitGroups.isNotEmpty;
}

class IndexedPage {
  const IndexedPage({
    required this.pageId,
    required this.documentId,
    required this.position,
    required this.raw,
    required this.normalized,
    required this.digits,
  });

  final String pageId;
  final String documentId;
  final int position;
  final String raw;
  final String normalized;

  /// Separator-stripped digit runs, separated by spaces.
  final String digits;
}

class SearchHit {
  const SearchHit({
    required this.document,
    required this.nameMatch,
    this.snippet = '',
    this.highlightStart = 0,
    this.highlightEnd = 0,
    this.pageIndex,
  });

  final DocumentRecord document;
  final bool nameMatch;
  final String snippet;
  final int highlightStart;
  final int highlightEnd;

  /// Zero-based page index when this is a content hit.
  final int? pageIndex;

  int? get pageNumber => pageIndex == null ? null : pageIndex! + 1;
}

class Snippet {
  const Snippet({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final int start;
  final int end;
}

List<QueryTerm> analyzeQuery(String query) {
  final terms = <QueryTerm>[];
  for (final part in query.trim().split(RegExp(r'\s+'))) {
    if (part.isEmpty) continue;
    final normalized = normalizeForSearch(part);
    final letters = StringBuffer();
    for (final rune in normalized.runes) {
      if (isSearchLetter(rune)) letters.writeCharCode(rune);
    }
    final groups = queryDigitGroups(part);
    if (letters.isEmpty && groups.isEmpty) continue;
    terms.add(QueryTerm(text: letters.toString(), digitGroups: groups));
  }
  return terms;
}

/// Name matches first, then content matches. A document is listed once.
List<SearchHit> rankSearch(
  String query,
  List<DocumentRecord> documents,
  List<IndexedPage> pages,
) {
  final terms = analyzeQuery(query);
  if (terms.isEmpty) return const [];
  final nameHits = <SearchHit>[];
  final used = <String>{};
  for (final document in documents) {
    if (!_nameMatches(document.name, terms)) continue;
    nameHits.add(SearchHit(document: document, nameMatch: true));
    used.add(document.id);
  }
  final byDocument = <String, List<IndexedPage>>{};
  for (final page in pages) {
    byDocument.putIfAbsent(page.documentId, () => []).add(page);
  }
  final contentHits = <SearchHit>[];
  for (final document in documents) {
    if (used.contains(document.id)) continue;
    final candidates = byDocument[document.id];
    if (candidates == null) continue;
    IndexedPage? match;
    for (final page in candidates) {
      if (!_pageMatches(page, terms)) continue;
      if (match == null || page.position < match.position) match = page;
    }
    if (match == null) continue;
    final snippet = snippetFor(match.raw, terms);
    contentHits.add(
      SearchHit(
        document: document,
        nameMatch: false,
        snippet: snippet?.text ?? '',
        highlightStart: snippet?.start ?? 0,
        highlightEnd: snippet?.end ?? 0,
        pageIndex: match.position,
      ),
    );
  }
  return [...nameHits, ...contentHits];
}

bool _nameMatches(String name, List<QueryTerm> terms) {
  final normalized = normalizeForSearch(name);
  final digits = extractDigitRuns(name).map((run) => run.digits).join(' ');
  for (final term in terms) {
    if (term.text.isNotEmpty && !normalized.contains(term.text)) return false;
    if (!_digitsMatch(digits, term.digitGroups)) return false;
  }
  return true;
}

bool _pageMatches(IndexedPage page, List<QueryTerm> terms) {
  for (final term in terms) {
    if (term.text.isNotEmpty && !textHasPrefix(page.normalized, term.text)) {
      return false;
    }
    if (!_digitsMatch(page.digits, term.digitGroups)) return false;
  }
  return true;
}

bool textHasPrefix(String normalized, String term) {
  if (term.isEmpty) return true;
  var current = StringBuffer();
  bool matches(String word) => word.startsWith(term);
  for (final rune in normalized.runes) {
    if (isSearchLetter(rune) || (rune >= 0x30 && rune <= 0x39)) {
      current.writeCharCode(rune);
    } else if (current.isNotEmpty) {
      if (matches(current.toString())) return true;
      current.clear();
    }
  }
  return current.isNotEmpty && matches(current.toString());
}

bool _digitsMatch(String digitsField, List<String> groups) {
  if (groups.isEmpty) return true;
  final runs = digitsField.split(' ').where((run) => run.isNotEmpty);
  for (final group in groups) {
    var found = false;
    for (final run in runs) {
      if (run.contains(group)) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

Snippet? snippetFor(String raw, List<QueryTerm> terms) {
  int? start;
  int? end;
  for (final term in terms) {
    final span = _spanForTerm(raw, term);
    if (span == null) continue;
    if (start == null || span.$1 < start) {
      start = span.$1;
      end = span.$2;
    }
  }
  if (start == null || end == null || end <= start) return null;
  final windowStart = (start - 18).clamp(0, raw.length);
  final windowEnd = (end + 18).clamp(0, raw.length);
  final text = raw.substring(windowStart, windowEnd).replaceAll('\n', ' ');
  return Snippet(
    text: text,
    start: start - windowStart,
    end: end - windowStart,
  );
}

(int, int)? _spanForTerm(String raw, QueryTerm term) {
  if (term.text.isNotEmpty) {
    final word = _rawWordWithPrefix(raw, term.text);
    if (word != null) return word;
  }
  for (final group in term.digitGroups) {
    final span = _digitSpan(raw, group);
    if (span != null) return span;
  }
  return null;
}

(int, int)? _rawWordWithPrefix(String raw, String term) {
  final normalized = normalizeForSearch(raw);
  // Walk raw and normalized together. Normalization can drop characters.
  var normIndex = 0;
  var wordNormStart = 0;
  var wordRawStart = 0;
  var inWord = false;
  for (var i = 0; i < raw.length; i++) {
    final folded = normalizeForSearch(raw[i]);
    if (folded.isEmpty) continue;
    final rune = folded.codeUnitAt(0);
    final wordChar = isSearchLetter(rune) || (rune >= 0x30 && rune <= 0x39);
    if (wordChar) {
      if (!inWord) {
        inWord = true;
        wordNormStart = normIndex;
        wordRawStart = i;
      }
      normIndex += folded.length;
    } else {
      if (inWord) {
        final word = normalized.substring(wordNormStart, normIndex);
        if (word.startsWith(term)) return (wordRawStart, i);
        inWord = false;
      }
      normIndex += folded.length;
    }
  }
  if (inWord) {
    final word = normalized.substring(wordNormStart, normIndex);
    if (word.startsWith(term)) return (wordRawStart, raw.length);
  }
  return null;
}

(int, int)? _digitSpan(String raw, String group) {
  for (final run in extractDigitRuns(raw)) {
    final index = run.digits.indexOf(group);
    if (index < 0) continue;
    final positions = <int>[];
    for (var i = run.start; i < run.end; i++) {
      final folded = normalizeForSearch(raw[i]);
      final unit = folded.isEmpty ? raw.codeUnitAt(i) : folded.codeUnitAt(0);
      final value = _queryDigit(unit, inRun: positions.isNotEmpty);
      if (value != null) positions.add(i);
    }
    if (index + group.length > positions.length) continue;
    final from = positions[index];
    final to = positions[index + group.length - 1] + 1;
    return (from, to);
  }
  return null;
}

int? _queryDigit(int rune, {required bool inRun}) {
  if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660;
  if (rune >= 0x06F0 && rune <= 0x06F9) return rune - 0x06F0;
  if (rune >= 0x30 && rune <= 0x39) return rune - 0x30;
  if (!inRun) return null;
  if (rune == 0x4F || rune == 0x6F) return 0;
  if (rune == 0x6C || rune == 0x49 || rune == 0x7C) return 1;
  return null;
}

/// FTS5 prefix query for the letter terms. Null when the query has none.
String? ftsPrefixQuery(List<QueryTerm> terms) {
  final parts = <String>[];
  for (final term in terms) {
    if (term.text.isEmpty) continue;
    final safe = term.text.replaceAll(RegExp(r'["*]'), '');
    if (safe.isEmpty) continue;
    parts.add('$safe*');
  }
  if (parts.isEmpty) return null;
  return parts.join(' ');
}
