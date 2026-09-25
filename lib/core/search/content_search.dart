import 'dart:math' as math;

import '../../data/models/records.dart';
import 'arabic_normalize.dart';

class QueryTerm {
  const QueryTerm({required this.text, required this.digitGroups});

  /// Normalized letters for prefix/substring/fuzzy matching. Empty for a number-only token.
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

enum MatchQuality { none, fuzzy, exact }

class SearchHit {
  const SearchHit({
    required this.document,
    required this.nameMatch,
    this.snippet = '',
    this.highlightStart = 0,
    this.highlightEnd = 0,
    this.pageIndex,
    this.exactMatch = true,
  });

  final DocumentRecord document;
  final bool nameMatch;
  final String snippet;
  final int highlightStart;
  final int highlightEnd;

  /// Zero-based page index when this is a content hit.
  final int? pageIndex;

  /// True when all terms matched exactly (or name match); false for fuzzy OCR match.
  final bool exactMatch;

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

/// Name matches first, then exact content matches, then fuzzy content matches.
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
    nameHits.add(SearchHit(document: document, nameMatch: true, exactMatch: true));
    used.add(document.id);
  }
  final byDocument = <String, List<IndexedPage>>{};
  for (final page in pages) {
    byDocument.putIfAbsent(page.documentId, () => []).add(page);
  }

  final exactContentHits = <SearchHit>[];
  final fuzzyContentHits = <SearchHit>[];

  for (final document in documents) {
    if (used.contains(document.id)) continue;
    final candidates = byDocument[document.id];
    if (candidates == null) continue;

    IndexedPage? bestMatch;
    MatchQuality bestQuality = MatchQuality.none;

    for (final page in candidates) {
      final quality = _pageMatchQuality(page, terms);
      if (quality == MatchQuality.none) continue;

      if (bestMatch == null) {
        bestMatch = page;
        bestQuality = quality;
      } else if (quality == MatchQuality.exact && bestQuality != MatchQuality.exact) {
        bestMatch = page;
        bestQuality = quality;
      } else if (quality == bestQuality && page.position < bestMatch.position) {
        bestMatch = page;
      }
    }

    if (bestMatch == null) continue;
    final snippet = snippetFor(bestMatch.raw, terms);
    final hit = SearchHit(
      document: document,
      nameMatch: false,
      snippet: snippet?.text ?? '',
      highlightStart: snippet?.start ?? 0,
      highlightEnd: snippet?.end ?? 0,
      pageIndex: bestMatch.position,
      exactMatch: bestQuality == MatchQuality.exact,
    );

    if (bestQuality == MatchQuality.exact) {
      exactContentHits.add(hit);
    } else {
      fuzzyContentHits.add(hit);
    }
  }

  return [...nameHits, ...exactContentHits, ...fuzzyContentHits];
}

bool _nameMatches(String name, List<QueryTerm> terms) {
  final normalized = normalizeForSearch(name);
  final digits = extractDigitRuns(name).map((run) => run.digits).join(' ');
  for (final term in terms) {
    if (term.text.isNotEmpty && _termMatchQuality(normalized, term.text) == MatchQuality.none) {
      return false;
    }
    if (!_digitsMatch(digits, term.digitGroups)) return false;
  }
  return true;
}

MatchQuality _pageMatchQuality(IndexedPage page, List<QueryTerm> terms) {
  var allExact = true;
  for (final term in terms) {
    if (!_digitsMatch(page.digits, term.digitGroups)) return MatchQuality.none;
    if (term.text.isNotEmpty) {
      final quality = _termMatchQuality(page.normalized, term.text);
      if (quality == MatchQuality.none) return MatchQuality.none;
      if (quality != MatchQuality.exact) allExact = false;
    }
  }
  return allExact ? MatchQuality.exact : MatchQuality.fuzzy;
}

MatchQuality _termMatchQuality(String normalizedText, String term) {
  if (term.isEmpty) return MatchQuality.exact;

  // 1. Exact normalized substring match
  if (normalizedText.contains(term)) return MatchQuality.exact;

  // 2. Exact word prefix match
  final words = _extractWords(normalizedText);
  for (final word in words) {
    if (word.startsWith(term)) return MatchQuality.exact;
  }

  // 3. Fuzzy matching for OCR errors (for terms length >= 4)
  if (term.length >= 4) {
    final maxDist = term.length <= 5 ? 1 : 2;
    for (final word in words) {
      if ((word.length - term.length).abs() <= maxDist) {
        if (editDistance(word, term, maxDistance: maxDist) <= maxDist) {
          return MatchQuality.fuzzy;
        }
      }
      if (word.length > term.length) {
        final prefix = word.substring(0, term.length);
        if (editDistance(prefix, term, maxDistance: maxDist) <= maxDist) {
          return MatchQuality.fuzzy;
        }
      }
      if (word.length >= 3 && trigramSimilarity(word, term) >= 0.65) {
        return MatchQuality.fuzzy;
      }
    }
  }

  return MatchQuality.none;
}

List<String> _extractWords(String normalized) {
  final words = <String>[];
  var current = StringBuffer();
  for (final rune in normalized.runes) {
    if (isSearchLetter(rune) || (rune >= 0x30 && rune <= 0x39)) {
      current.writeCharCode(rune);
    } else if (current.isNotEmpty) {
      words.add(current.toString());
      current.clear();
    }
  }
  if (current.isNotEmpty) words.add(current.toString());
  return words;
}

bool textHasPrefix(String normalized, String term) {
  return _termMatchQuality(normalized, term) != MatchQuality.none;
}

/// Bounded Levenshtein distance for fuzzy matching OCR errors.
int editDistance(String s1, String s2, {int maxDistance = 2}) {
  if (s1 == s2) return 0;
  final len1 = s1.length;
  final len2 = s2.length;
  if ((len1 - len2).abs() > maxDistance) return maxDistance + 1;
  if (len1 == 0) return len2;
  if (len2 == 0) return len1;

  var previousRow = List<int>.generate(len2 + 1, (i) => i);
  var currentRow = List<int>.filled(len2 + 1, 0);

  for (var i = 0; i < len1; i++) {
    currentRow[0] = i + 1;
    var minInRow = currentRow[0];
    for (var j = 0; j < len2; j++) {
      final insertCost = previousRow[j + 1] + 1;
      final deleteCost = currentRow[j] + 1;
      final substituteCost = previousRow[j] + (s1.codeUnitAt(i) == s2.codeUnitAt(j) ? 0 : 1);
      final cost = math.min(insertCost, math.min(deleteCost, substituteCost));
      currentRow[j + 1] = cost;
      if (cost < minInRow) minInRow = cost;
    }
    if (minInRow > maxDistance) return maxDistance + 1;
    final temp = previousRow;
    previousRow = currentRow;
    currentRow = temp;
  }
  return previousRow[len2];
}

/// Character trigram similarity between 0.0 and 1.0.
double trigramSimilarity(String s1, String s2) {
  if (s1 == s2) return 1.0;
  if (s1.length < 3 || s2.length < 3) return 0.0;
  final t1 = <String>{};
  for (var i = 0; i <= s1.length - 3; i++) {
    t1.add(s1.substring(i, i + 3));
  }
  final t2 = <String>{};
  for (var i = 0; i <= s2.length - 3; i++) {
    t2.add(s2.substring(i, i + 3));
  }
  var intersection = 0;
  for (final tri in t1) {
    if (t2.contains(tri)) intersection++;
  }
  final total = t1.length + t2.length;
  if (total == 0) return 0.0;
  return (2.0 * intersection) / total;
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

  (int, int)? bestFuzzySpan;
  var bestFuzzyDist = 999;

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
        if (word.startsWith(term) || word.contains(term)) {
          return (wordRawStart, i);
        }
        if (term.length >= 4) {
          final maxDist = term.length <= 5 ? 1 : 2;
          final d = editDistance(word, term, maxDistance: maxDist);
          if (d <= maxDist && d < bestFuzzyDist) {
            bestFuzzyDist = d;
            bestFuzzySpan = (wordRawStart, i);
          }
        }
        inWord = false;
      }
      normIndex += folded.length;
    }
  }
  if (inWord) {
    final word = normalized.substring(wordNormStart, normIndex);
    if (word.startsWith(term) || word.contains(term)) {
      return (wordRawStart, raw.length);
    }
    if (term.length >= 4) {
      final maxDist = term.length <= 5 ? 1 : 2;
      final d = editDistance(word, term, maxDistance: maxDist);
      if (d <= maxDist && d < bestFuzzyDist) {
        bestFuzzySpan = (wordRawStart, raw.length);
      }
    }
  }
  return bestFuzzySpan;
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
