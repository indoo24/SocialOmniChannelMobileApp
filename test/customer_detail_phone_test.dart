/// `CustomerDetail.displayPhone`: the customer's WhatsApp number, which the
/// backend already sends in `identities[].external_id`, fills in a `phone` the
/// backend left empty — and never replaces a phone that is already stored.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:scenario_mobile/core/models/customer_detail.dart';

Map<String, Object?> _identity({
  required int id,
  required String provider,
  String externalId = '',
  String username = '',
  String? lastInteractionAt,
}) => {
  'id': id,
  'provider': provider,
  'external_id': externalId,
  'username': username,
  'display_name': '',
  'last_interaction_at': ?lastInteractionAt,
};

CustomerDetail _customer({
  String phone = '',
  List<Map<String, Object?>> identities = const [],
}) => CustomerDetail.fromJson({
  'id': 7,
  'display_name': 'Mona',
  'phone': phone,
  'identities': identities,
});

void main() {
  group('CustomerDetail.displayPhone', () {
    test('uses the WhatsApp identity number when phone is empty', () {
      final customer = _customer(
        identities: [
          _identity(
            id: 1,
            provider: 'WHATSAPP',
            externalId: '201094680929',
            username: '@+201094680929',
          ),
        ],
      );

      expect(customer.phone, '');
      expect(customer.displayPhone, '+201094680929');
      expect(customer.subtitle, '+201094680929');
    });

    test('keeps an already stored phone over the identity number', () {
      final customer = _customer(
        phone: '+201112223344',
        identities: [
          _identity(id: 1, provider: 'WHATSAPP', externalId: '201094680929'),
        ],
      );

      expect(customer.displayPhone, '+201112223344');
    });

    test('a blank stored phone counts as empty', () {
      final customer = _customer(
        phone: '   ',
        identities: [
          _identity(id: 1, provider: 'WHATSAPP', externalId: '201094680929'),
        ],
      );

      expect(customer.displayPhone, '+201094680929');
    });

    test('does not double an existing leading plus', () {
      final customer = _customer(
        identities: [
          _identity(id: 1, provider: 'WHATSAPP', externalId: '+201094680929'),
        ],
      );

      expect(customer.displayPhone, '+201094680929');
    });

    test('is empty without a WhatsApp identity', () {
      expect(_customer().displayPhone, '');
      expect(
        _customer(
          identities: [
            _identity(id: 1, provider: 'INSTAGRAM', externalId: '17841400000'),
            _identity(id: 2, provider: 'FACEBOOK', externalId: '5551234567'),
          ],
        ).displayPhone,
        '',
      );
    });

    test('ignores a WhatsApp identity id that is not a phone number', () {
      final customer = _customer(
        identities: [
          _identity(id: 1, provider: 'WHATSAPP', externalId: 'abc-123'),
          _identity(id: 2, provider: 'WHATSAPP', externalId: ''),
        ],
      );

      expect(customer.displayPhone, '');
    });

    test('prefers the most recently active WhatsApp identity', () {
      final customer = _customer(
        identities: [
          _identity(
            id: 1,
            provider: 'WHATSAPP',
            externalId: '201000000001',
            lastInteractionAt: '2026-09-01T10:00:00Z',
          ),
          _identity(
            id: 2,
            provider: 'WHATSAPP',
            externalId: '201000000002',
            lastInteractionAt: '2026-09-30T10:00:00Z',
          ),
        ],
      );

      expect(customer.displayPhone, '+201000000002');
    });
  });
}
