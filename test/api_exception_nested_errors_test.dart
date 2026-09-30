/// Validation errors from a nested serializer arrive as a list of field maps —
/// `{"responsibilities": [{"provider": ["…"]}]}` — and the message the user
/// sees must be the sentence, not the stringified map.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/api/api_exception.dart';

Map<String, Object?> _envelope(Object details, {String message = ''}) => {
  'error': {'code': 'invalid', 'message': message, 'details': details},
};

void main() {
  group('ApiException message from nested validation details', () {
    test('a list of field maps yields the sentence, not the map', () {
      final error = ApiException.fromResponse(
        400,
        _envelope({
          'responsibilities': [
            {
              'provider': ['"" is not a valid choice.'],
            },
          ],
        }, message: 'The submitted data was invalid.'),
      );

      expect(error.message, '"" is not a valid choice.');
      expect(error.message, isNot(contains('{')));
      expect(error.statusCode, 400);
    });

    test('several failing items are all listed, one per line', () {
      final error = ApiException.fromResponse(
        400,
        _envelope({
          'responsibilities': [
            {
              'provider': ['"" is not a valid choice.'],
            },
            {
              'channel_connection_ids': ['Unknown account.'],
            },
          ],
        }),
      );

      expect(error.message, '"" is not a valid choice.\nUnknown account.');
    });

    test('an empty item in the list is skipped', () {
      final error = ApiException.fromResponse(
        400,
        _envelope({
          'responsibilities': [
            <String, Object?>{},
            {
              'scope': ['Required.'],
            },
          ],
        }),
      );

      expect(error.message, 'Required.');
    });

    test('flat and list-of-string details are unchanged', () {
      expect(
        ApiException.fromResponse(400, {
          'name': ['This field may not be blank.'],
        }).message,
        'This field may not be blank.',
      );
      expect(
        ApiException.fromResponse(
          400,
          _envelope({
            'name': ['Too short.', 'Not unique.'],
          }),
        ).message,
        'Too short.\nNot unique.',
      );
    });

    test('a specific server headline still wins over the details', () {
      final error = ApiException.fromResponse(
        400,
        _envelope({
          'responsibilities': [
            {
              'provider': ['x'],
            },
          ],
        }, message: 'Pick at least one account.'),
      );

      expect(error.message, 'Pick at least one account.');
    });
  });
}
