import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ppd_care_app/config/support_info.dart';
import 'package:ppd_care_app/models/checkin_questions.dart';
import 'package:ppd_care_app/models/checkin_result.dart';
import 'package:ppd_care_app/screens/checkin_result_screen.dart';
import 'package:ppd_care_app/screens/checkin_screen.dart';
import 'package:ppd_care_app/screens/home_screen.dart';
import 'package:ppd_care_app/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'api_host': 'laptop.local',
      'api_port': 5000,
    });
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> chooseAllAnswers(WidgetTester tester) async {
    for (var index = 0; index < checkinQuestions.length; index++) {
      final question = checkinQuestions[index];
      final questionText = find.text('${index + 1}. ${question.question}');
      final card = find.ancestor(of: questionText, matching: find.byType(Card));
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.widgetWithText(ChoiceChip, question.choices.first),
        ),
      );
      await tester.pump();
    }
  }

  Future<void> expectAllAnswersSelected(WidgetTester tester) async {
    for (var index = 0; index < checkinQuestions.length; index++) {
      final question = checkinQuestions[index];
      final questionText = find.text('${index + 1}. ${question.question}');
      final card = find.ancestor(of: questionText, matching: find.byType(Card));
      final chip = tester.widget<ChoiceChip>(
        find.descendant(
          of: card,
          matching: find.widgetWithText(ChoiceChip, question.choices.first),
        ),
      );
      expect(chip.selected, isTrue);
    }
  }

  Widget appWithCheckin(ApiClient apiClient) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CheckinScreen(apiClient: apiClient),
                ),
              );
            },
            child: const Text('Open check-in'),
          ),
        ),
      ),
    );
  }

  Future<void> openCheckin(WidgetTester tester, ApiClient apiClient) async {
    useTallViewport(tester);
    await tester.pumpWidget(appWithCheckin(apiClient));
    await tester.tap(find.text('Open check-in'));
    await tester.pumpAndSettle();
  }

  testWidgets('submit is disabled until all seven answers are selected', (
    tester,
  ) async {
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await openCheckin(tester, apiClient);

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('checkin-submit')))
          .onPressed,
      isNull,
    );
    await chooseAllAnswers(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('checkin-submit')))
          .onPressed,
      isNotNull,
    );
    for (final question in checkinQuestions) {
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(
              '${checkinQuestions.indexOf(question) + 1}. ${question.question}',
            ),
            matching: find.byType(Card),
          ),
          matching: find.widgetWithText(ChoiceChip, question.choices.first),
        ),
        findsOneWidget,
      );
    }
    apiClient.close();
  });

  testWidgets('submits exactly seven selected strings and shows typed result', (
    tester,
  ) async {
    http.Request? sentRequest;
    final client = MockClient((request) async {
      sentRequest = request;
      return http.Response(
        jsonEncode({
          'checkin_id': 42,
          'message': 'Your check-in has been recorded.',
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: client,
    );
    await openCheckin(tester, apiClient);
    await chooseAllAnswers(tester);
    await tester.tap(find.byKey(const Key('checkin-submit')));
    await tester.pumpAndSettle();

    expect(sentRequest?.method, 'POST');
    expect(sentRequest?.url.path, '/checkin');
    final requestBody = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
    expect(
      requestBody.keys.toSet(),
      checkinQuestions.map((q) => q.key).toSet(),
    );
    for (final question in checkinQuestions) {
      expect(question.choices, contains(requestBody[question.key]));
    }
    expect(find.byType(CheckinResultScreen), findsOneWidget);
    expect(find.text('Your check-in has been recorded.'), findsOneWidget);
    expect(find.text('This check-in is not a diagnosis.'), findsOneWidget);
    expect(find.text(supportInfo), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    for (final prohibited in [
      'probability',
      'risk score',
      'prediction',
      'risk label',
    ]) {
      expect(find.textContaining(prohibited), findsNothing);
    }
    apiClient.close();
  });

  test('rejects malformed or incomplete successful response payloads', () {
    expect(
      () => CheckinResult.fromJson({'checkin_id': 42}),
      throwsFormatException,
    );
    expect(
      () => CheckinResult.fromJson({
        'checkin_id': 42,
        'message': 'Saved',
        'probability': 0.4,
      }),
      throwsFormatException,
    );
    expect(
      () => CheckinResult.fromJson({'checkin_id': '42', 'message': 'Saved'}),
      throwsFormatException,
    );
  });

  for (final scenario in [
    (
      name: 'HTTP 400',
      failure: '400',
      expected: 'Something went wrong with the answers, please retry',
    ),
    (
      name: 'HTTP 500',
      failure: '500',
      expected: 'The service is unavailable, please try again',
    ),
    (name: 'timeout', failure: 'timeout', expected: 'timed out'),
    (
      name: 'network failure',
      failure: 'network',
      expected: 'Could not reach the server',
    ),
  ]) {
    testWidgets('${scenario.name} keeps answers and allows retry', (
      tester,
    ) async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          switch (scenario.failure) {
            case '400':
              return http.Response('private server detail', 400);
            case '500':
              return http.Response('private server detail', 500);
            case 'timeout':
              throw TimeoutException('test timeout detail');
            default:
              throw SocketException(
                'test network detail',
                address: InternetAddress('127.0.0.1'),
                port: 5000,
              );
          }
        }
        return http.Response(
          jsonEncode({'checkin_id': 8, 'message': 'Retry succeeded.'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        settings: const ApiSettings(host: 'laptop.local', port: 5000),
        client: client,
      );
      await openCheckin(tester, apiClient);
      await chooseAllAnswers(tester);
      await tester.tap(find.byKey(const Key('checkin-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining(scenario.expected), findsOneWidget);
      expect(find.byType(CheckinResultScreen), findsNothing);
      await expectAllAnswersSelected(tester);

      await tester.tap(find.byKey(const Key('checkin-submit')));
      await tester.pumpAndSettle();
      expect(requestCount, 2);
      expect(find.byType(CheckinResultScreen), findsOneWidget);
      apiClient.close();
    });
  }

  testWidgets('submit is disabled while request is in flight', (tester) async {
    final responseCompleter = Completer<http.Response>();
    var requestCount = 0;
    final client = MockClient((_) {
      requestCount++;
      return responseCompleter.future;
    });
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: client,
    );
    await openCheckin(tester, apiClient);
    await chooseAllAnswers(tester);
    await tester.tap(find.byKey(const Key('checkin-submit')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('checkin-submit')),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(requestCount, 1);

    responseCompleter.complete(
      http.Response(
        jsonEncode({'checkin_id': 9, 'message': 'Saved.'}),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckinResultScreen), findsOneWidget);
    apiClient.close();
  });

  testWidgets('sleep sends the exact payload and clears after a 201', (
    tester,
  ) async {
    http.Request? sentRequest;
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        sentRequest = request;
        return http.Response('{"sleep_id":1}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: SleepScreen(apiClient: apiClient)),
    );
    await tester.enterText(find.byKey(const Key('sleep-hours')), '7.5');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Good'));
    await tester.enterText(find.byKey(const Key('sleep-note')), 'Rested');
    await tester.tap(find.byKey(const Key('sleep-save')));
    await tester.pumpAndSettle();

    expect(sentRequest?.method, 'POST');
    expect(sentRequest?.url.path, '/sleep');
    final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'date', 'hours', 'quality', 'note'});
    expect(body['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(body['hours'], 7.5);
    expect(body['quality'], 'Good');
    expect(body['note'], 'Rested');
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sleep-hours')))
          .controller!
          .text,
      isEmpty,
    );
    apiClient.close();
  });

  testWidgets('sleep conflict keeps entered values', (tester) async {
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient(
        (_) async => http.Response(
          '{"error":"A sleep log for this date already exists."}',
          409,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: SleepScreen(apiClient: apiClient)),
    );
    await tester.enterText(find.byKey(const Key('sleep-hours')), '6.25');
    await tester.tap(find.byKey(const Key('sleep-save')));
    await tester.pumpAndSettle();

    expect(find.text('You already logged sleep for this date'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sleep-hours')))
          .controller!
          .text,
      '6.25',
    );
    apiClient.close();
  });

  testWidgets('sleep history retry loads entries after a server error', (
    tester,
  ) async {
    var requestCount = 0;
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((_) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('unavailable', 500);
        }
        return http.Response(
          '{"entries":[{"date":"2026-10-25","hours":8.0,"quality":"Good","note":null}]}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: SleepHistoryScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sleep-history-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-history-retry')));
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('2026-10-25'), findsOneWidget);
    expect(find.text('8.0 hours · Good'), findsOneWidget);
    apiClient.close();
  });

  testWidgets('contacts send the exact payload with empty relation as null', (
    tester,
  ) async {
    http.Request? sentRequest;
    var saved = false;
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        if (request.method == 'POST') {
          sentRequest = request;
          saved = true;
          return http.Response('{"contact_id":12}', 201);
        }
        return http.Response(
          saved
              ? '{"contacts":[{"id":12,"name":"Sam","email":"sam@example.test","relation":null}]}'
              : '{"contacts":[]}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: ContactsScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('contact-name')), 'Sam');
    await tester.enterText(
      find.byKey(const Key('contact-email')),
      'sam@example.test',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(sentRequest?.url.path, '/contacts');
    final body = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'name', 'email', 'relation'});
    expect(body, {
      'name': 'Sam',
      'email': 'sam@example.test',
      'relation': null,
    });
    expect(find.text('Sam'), findsOneWidget);
    apiClient.close();
  });

  testWidgets('contact limit disables adding after five contacts', (
    tester,
  ) async {
    final contacts = List.generate(
      5,
      (index) => {
        'id': index + 1,
        'name': 'Contact $index',
        'email': 'contact$index@example.test',
        'relation': null,
      },
    );
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient(
        (_) async => http.Response(jsonEncode({'contacts': contacts}), 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ContactsScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maximum of 5 contacts reached.'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('add-contact'))).onPressed,
      isNull,
    );
    apiClient.close();
  });

  testWidgets('alert compose records exact recipient payload after launch', (
    tester,
  ) async {
    final requests = <http.Request>[];
    Uri? launchedUri;
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            '{"contacts":[{"id":12,"name":"Trusted person","email":"trusted@example.test","relation":"Friend"}]}',
            200,
          );
        }
        return http.Response('{"alert_id":4}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinResultScreen(
          result: const CheckinResult(
            checkinId: 42,
            message: 'Your check-in has been recorded.',
          ),
          apiClient: apiClient,
          emailLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('let-someone-know')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trusted person'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contacts-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Review your message'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('alert-message')))
          .controller!
          .text,
      'I wanted to reach out and talk when you have a moment.',
    );
    await tester.tap(find.byKey(const Key('alert-compose')));
    await tester.pumpAndSettle();

    expect(launchedUri?.scheme, 'mailto');
    expect(launchedUri?.path, 'trusted@example.test');
    expect(launchedUri?.queryParameters['subject'], 'A message for you');
    expect(
      launchedUri?.queryParameters['body'],
      'I wanted to reach out and talk when you have a moment.',
    );
    final alertRequest = requests.singleWhere(
      (request) => request.url.path == '/alerts',
    );
    expect(jsonDecode(alertRequest.body), {
      'checkin_id': 42,
      'decision': 'compose_opened',
      'recipient_contact_ids': [12],
    });
    expect(find.text('Your email app was opened'), findsOneWidget);
    apiClient.close();
  });

  testWidgets('declining an alert records null recipients', (tester) async {
    final alertPayloads = <Map<String, dynamic>>[];
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '{"contacts":[{"id":12,"name":"Trusted person","email":"trusted@example.test","relation":null}]}',
            200,
          );
        }
        alertPayloads.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"alert_id":5}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinResultScreen(
          result: const CheckinResult(checkinId: 43, message: 'Recorded.'),
          apiClient: apiClient,
          emailLauncher: (_) async => true,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('let-someone-know')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trusted person'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contacts-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(alertPayloads, [
      {'checkin_id': 43, 'decision': 'declined', 'recipient_contact_ids': null},
    ]);
    apiClient.close();
  });

  testWidgets('email launch failure does not record an alert', (tester) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"contacts":[{"id":12,"name":"Trusted person","email":"trusted@example.test","relation":null}]}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CheckinResultScreen(
          result: const CheckinResult(checkinId: 44, message: 'Recorded.'),
          apiClient: apiClient,
          emailLauncher: (_) async => false,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('let-someone-know')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trusted person'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contacts-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('alert-compose')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not open an email app. No alert was recorded.'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.url.path == '/alerts'), isEmpty);
    apiClient.close();
  });

  testWidgets('Home keeps settings and placeholders and enables Check-in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'api_host': 'laptop.local',
      'api_port': 5000,
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    for (final enabledAction in ['Sleep', 'Contacts']) {
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(enabledAction),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    }
    final researchButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Research'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(researchButton.onPressed, isNotNull);
    final checkinButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Check-in'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(checkinButton.onPressed, isNotNull);
    await tester.tap(find.text('Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Personal check-in'), findsOneWidget);
  });
}
