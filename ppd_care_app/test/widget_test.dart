import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ppd_care_app/config/support_info.dart';
import 'package:ppd_care_app/screens/home_screen.dart';
import 'package:ppd_care_app/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ApiSettings host validation', () {
    test('accepts valid IPv4 addresses and simple hostnames', () {
      expect(ApiSettings.isValidHost('192.168.1.5'), isTrue);
      expect(ApiSettings.isValidHost('192.168.1.25'), isTrue);
      expect(ApiSettings.isValidHost('10.0.0.1'), isTrue);
      expect(ApiSettings.isValidHost('laptop.local'), isTrue);
      expect(ApiSettings.isValidHost('localhost'), isTrue);
    });

    test('rejects invalid IPv4 addresses and URLs', () {
      expect(ApiSettings.isValidHost('192.l68.1.5'), isFalse);
      expect(ApiSettings.isValidHost('192.168.1.5x'), isFalse);
      expect(ApiSettings.isValidHost('192.168.l.5'), isFalse);
      expect(ApiSettings.isValidHost('256.168.1.5'), isFalse);
      expect(ApiSettings.isValidHost('http://192.168.1.5'), isFalse);
      expect(ApiSettings.isValidHost(''), isFalse);
      expect(ApiSettings.isValidHost('   '), isFalse);
      expect(ApiSettings.isValidHost('256.1.2.3'), isFalse);
      expect(ApiSettings.isValidHost('192.168.1'), isFalse);
      expect(ApiSettings.isValidHost('192.168.1.1.5'), isFalse);
      expect(ApiSettings.isValidHost('http://192.168.1.25'), isFalse);
      expect(ApiSettings.isValidHost('https://laptop.local'), isFalse);
      expect(ApiSettings.isValidHost('laptop.local:5000'), isFalse);
      expect(ApiSettings.isValidHost('laptop.local/path'), isFalse);
    });
  });

  group('ApiSettings port validation', () {
    test('accepts ports from 1 through 65535', () {
      expect(ApiSettings.isValidPort('1'), isTrue);
      expect(ApiSettings.isValidPort('5000'), isTrue);
      expect(ApiSettings.isValidPort('65535'), isTrue);
    });

    test('rejects out-of-range and non-numeric ports', () {
      expect(ApiSettings.isValidPort('0'), isFalse);
      expect(ApiSettings.isValidPort('65536'), isFalse);
      expect(ApiSettings.isValidPort('5.0'), isFalse);
      expect(ApiSettings.isValidPort('port'), isFalse);
      expect(ApiSettings.isValidPort('http://5000'), isFalse);
    });
  });

  testWidgets('home screen shows the shared support line', (tester) async {
    SharedPreferences.setMockInitialValues({
      'api_host': 'laptop.local',
      'api_port': 5000,
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text(supportInfo), findsOneWidget);
    expect(
      find.text('Need support? Tele-MANAS 14416 · Emergency 112'),
      findsOneWidget,
    );
  });

  testWidgets('opens settings first when no server is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Laptop IP address or hostname'), findsOneWidget);
  });
}
