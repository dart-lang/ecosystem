import 'package:package2/anotherLib.dart' as anotherLib;
import 'package:package2/package2.dart' as p2;
import 'package:test/test.dart';

void main() {
  test('calculate', () {
    expect(p2.calculate(), 42);
  });
  test('calculate', () {
    expect(anotherLib.calculateUnused(), 42);
  });
}
