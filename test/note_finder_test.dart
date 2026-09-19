import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/note_finder.dart';

/// The contract for Ctrl+F: where the hits are, and which one is next.
void main() {
  group('finding', () {
    test('reports every hit, left to right', () {
      expect(findMatchOffsets('abcabc', 'abc'), <int>[0, 3]);
    });

    test('ignores case', () {
      expect(findMatchOffsets('Syncthing syncthing SYNCTHING', 'syncthing'),
          <int>[0, 10, 20]);
    });

    test('finds Chinese', () {
      expect(findMatchOffsets('牛奶、鸡蛋、面包、牛奶', '牛奶'), <int>[0, 9]);
    });

    test('offsets are positions in the original text', () {
      const String text = 'İstanbul 和 istanbul';
      // The dotted capital İ lower-cases to two code units; lower-casing the haystack would
      // shift every offset after it. Matching case-insensitively against the original avoids
      // that entirely, and the offsets below are the ones the field needs.
      final List<int> hits = findMatchOffsets(text, 'stanbul');
      expect(hits, <int>[1, 12]);
      for (final int at in hits) {
        expect(text.substring(at, at + 7).toLowerCase(), 'stanbul');
      }
    });

    test('matches do not overlap', () {
      expect(findMatchOffsets('aaaa', 'aa'), <int>[0, 2],
          reason: 'overlapping hits make "next" look stuck');
    });

    test('characters that mean something to a regex are literal', () {
      expect(findMatchOffsets(r'D:\Notes\a.md', r'\N'), <int>[2]);
      expect(findMatchOffsets('a.b', '.'), <int>[1]);
      expect(findMatchOffsets('x(y)z', '(y)'), <int>[1]);
      expect(findMatchOffsets('a+b', '+'), <int>[1]);
    });

    test('nothing to look for, or nowhere to look', () {
      expect(findMatchOffsets('abc', ''), isEmpty);
      expect(findMatchOffsets('', 'abc'), isEmpty);
    });

    test('a term longer than the text finds nothing', () {
      expect(findMatchOffsets('ab', 'abc'), isEmpty);
    });
  });

  group('stepping', () {
    test('next moves down and wraps', () {
      expect(nextMatch(0, 3), 1);
      expect(nextMatch(2, 3), 0, reason: 'going past the last one comes back to the first');
    });

    test('previous moves up and wraps', () {
      expect(previousMatch(2, 3), 1);
      expect(previousMatch(0, 3), 2);
    });

    test('no hits means no position', () {
      expect(nextMatch(-1, 0), -1);
      expect(previousMatch(-1, 0), -1);
    });

    test('a single hit is both next and previous', () {
      expect(nextMatch(0, 1), 0);
      expect(previousMatch(0, 1), 0);
    });
  });

  group('where to start', () {
    test('the first hit at or after the caret', () {
      expect(firstMatchFrom(<int>[0, 10, 20], 10), 1,
          reason: 'Ctrl+F in the middle of a note looks downwards, not back to the top');
      expect(firstMatchFrom(<int>[0, 10, 20], 11), 2);
      expect(firstMatchFrom(<int>[0, 10, 20], 0), 0);
    });

    test('and back to the first when there is nothing below', () {
      expect(firstMatchFrom(<int>[0, 10, 20], 99), 0);
    });

    test('no hits means no position', () {
      expect(firstMatchFrom(<int>[], 5), -1);
    });
  });
}
