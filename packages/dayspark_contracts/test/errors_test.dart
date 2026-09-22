import 'package:dayspark_contracts/dayspark_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('error code constants', () {
    test('expose stable wire values', () {
      expect(errUnauthorized, 'unauthorized');
      expect(errValidation, 'validation');
      expect(errConflict, 'conflict');
      expect(errRateLimited, 'rate_limited');
    });

    test('are distinct', () {
      final codes = {errUnauthorized, errValidation, errConflict, errRateLimited};
      expect(codes, hasLength(4));
    });
  });
}
