import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ppd_care_app/config/support_info.dart';
import 'package:ppd_care_app/models/research_questions.dart';
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
    tester.view.physicalSize = const Size(1200, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> answerEveryQuestion(WidgetTester tester) async {
    for (final question in researchQuestions) {
      await tester.ensureVisible(
        find.byKey(Key('research-question-${question.key}')),
      );
      await tester.tap(find.byKey(Key('research-option-${question.key}-0')));
      await tester.pump();
    }
    await tester.ensureVisible(
      find.byKey(const Key('research-question-abuse')),
    );
    await tester.tap(find.byKey(const Key('research-abuse-option-0')));
    await tester.pump();
    for (var index = 0; index < epdsQuestions.length; index++) {
      await tester.ensureVisible(
        find.byKey(Key('research-epds-question-$index')),
      );
      await tester.tap(find.byKey(Key('research-epds-option-$index-0')));
      await tester.pump();
    }
  }

  test('feature list matches the verified contract and derived flags', () {
    const expectedNames = [
      'Education Level',
      'Current monthly income',
      'Husband’s monthly income',
      'Total children',
      'Family type',
      'Relationship with the in-laws',
      'Relationship with husband',
      'Relationship with the newborn',
      'Relationship between father and newborn',
      'Feeling about motherhood',
      'Recieved Support',
      'Major changes or losses during pregnancy',
      'Trust and share feelings',
      'Fear of pregnancy',
      'Diseases during pregnancy',
      'Gender of newborn',
      'Birth compliancy',
      'Breastfeed',
      'Worry about newborn',
      'Relax/sleep when the newborn is asleep',
      'Angry after latest child birth',
      'Depression before pregnancy (PHQ2)',
      'Depression during pregnancy (PHQ2)',
      'Occupation before latest pregnancy_Housewife',
      'Occupation before latest pregnancy_Student',
      'Feeling for regular activities_Normal',
      'Need for Support_Unknown',
    ];
    const expectedMaximums = {
      'Education Level': 3,
      'Current monthly income': 5,
      'Husband’s monthly income': 4,
      'Total children': 2,
      'Family type': 1,
      'Relationship with the in-laws': 4,
      'Relationship with husband': 4,
      'Relationship with the newborn': 3,
      'Relationship between father and newborn': 3,
      'Feeling about motherhood': 2,
      'Recieved Support': 2,
      'Major changes or losses during pregnancy': 1,
      'Trust and share feelings': 1,
      'Fear of pregnancy': 1,
      'Diseases during pregnancy': 2,
      'Gender of newborn': 1,
      'Birth compliancy': 1,
      'Breastfeed': 1,
      'Worry about newborn': 1,
      'Relax/sleep when the newborn is asleep': 1,
      'Angry after latest child birth': 1,
      'Depression before pregnancy (PHQ2)': 1,
      'Depression during pregnancy (PHQ2)': 1,
      'Occupation before latest pregnancy_Housewife': 1,
      'Occupation before latest pregnancy_Student': 1,
      'Feeling for regular activities_Normal': 1,
      'Need for Support_Unknown': 1,
    };
    expect(researchFeatureNames, expectedNames);
    expect(researchFeatureMaximums, expectedMaximums);
    expect(researchFeatureNames, hasLength(27));
    expect(researchFeatureNames.toSet(), hasLength(27));
    expect(researchFeatureNames, contains('Husband’s monthly income'));
    expect(researchFeatureNames, contains('Recieved Support'));
    expect(researchFeatureNames, isNot(contains('Abuse')));
    expect(researchFeatureMaximums.keys.toList(), researchFeatureNames);

    final answers = {
      for (final question in researchQuestions) question.key: 0,
      'activities': 0,
      'support_need': 3,
    };
    final features = buildResearchFeatures(selectedQuestionOptions: answers);
    expect(features.keys.toList(), researchFeatureNames);
    expect(
      [
        features['Occupation before latest pregnancy_Housewife'],
        features['Occupation before latest pregnancy_Student'],
      ],
      [1, 0],
    );
    expect(features['Feeling for regular activities_Normal'], 1);
    expect(features['Need for Support_Unknown'], 1);

    for (final selection in [
      ('occupation', 0, [1, 0]),
      ('occupation', 1, [0, 1]),
      ('occupation', 2, [0, 0]),
      ('activities', 1, [0]),
      ('activities', 2, [0]),
      ('activities', 3, [0]),
      ('support_need', 0, [0]),
      ('support_need', 1, [0]),
      ('support_need', 2, [0]),
      ('support_need', 3, [1]),
    ]) {
      final questionAnswers = {
        for (final question in researchQuestions) question.key: 0,
        selection.$1: selection.$2,
      };
      final result = buildResearchFeatures(
        selectedQuestionOptions: questionAnswers,
      );
      final values = switch (selection.$1) {
        'occupation' => [
          result['Occupation before latest pregnancy_Housewife'],
          result['Occupation before latest pregnancy_Student'],
        ],
        'activities' => [result['Feeling for regular activities_Normal']],
        _ => [result['Need for Support_Unknown']],
      };
      expect(values, selection.$3);
    }

    for (final entry in features.entries) {
      expect(
        entry.value,
        inInclusiveRange(0, researchFeatureMaximums[entry.key]!),
      );
    }
    for (final question in researchQuestions) {
      for (final option in question.options) {
        for (final entry in option.featureValues.entries) {
          expect(
            entry.value,
            inInclusiveRange(0, researchFeatureMaximums[entry.key]!),
          );
        }
      }
    }
  });

  testWidgets(
    'research requires all answers and submits exact feature payload',
    (tester) async {
      useTallViewport(tester);
      http.Request? sentRequest;
      final responseCompleter = Completer<http.Response>();
      var submitAttempts = 0;
      final requestBodies = <String>[];
      final apiClient = ApiClient(
        settings: const ApiSettings(host: 'laptop.local', port: 5000),
        client: MockClient((request) async {
          submitAttempts++;
          sentRequest = request;
          requestBodies.add(request.body);
          if (submitAttempts == 1) {
            return http.Response('{"error":"temporary error"}', 500);
          }
          return responseCompleter.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResearchFormScreen(
            researchId: 'research-7',
            apiClient: apiClient,
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('research-submit')))
            .onPressed,
        isNull,
      );

      await answerEveryQuestion(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('research-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byKey(const Key('research-submit')));
      await tester.tap(find.byKey(const Key('research-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('research-error')), findsOneWidget);
      expect(find.byType(ResearchThankYouScreen), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const Key('research-option-education-0')),
            )
            .selected,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('research-submit')));
      await tester.tap(find.byKey(const Key('research-submit')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('research-submit')))
            .onPressed,
        isNull,
      );
      expect(submitAttempts, 2);
      responseCompleter.complete(
        http.Response(
          jsonEncode({
            'submission_id': 7,
            'crisis_flag': false,
            'message':
                'Thank you for contributing to postpartum depression research.',
          }),
          201,
        ),
      );
      await tester.pumpAndSettle();

      expect(sentRequest?.method, 'POST');
      expect(sentRequest?.url.path, '/research/submit');
      final payload = jsonDecode(sentRequest!.body) as Map<String, dynamic>;
      expect(payload.keys.toSet(), {
        'research_id',
        'features',
        'abuse_reworded',
        'epds_answers',
      });
      expect(payload['research_id'], 'research-7');
      expect(payload['abuse_reworded'], 0);
      expect(payload['epds_answers'], List<int>.filled(10, 0));
      final features = payload['features'] as Map<String, dynamic>;
      expect(features.keys.toList(), researchFeatureNames);
      expect(features.containsKey('Abuse'), isFalse);
      for (final name in researchFeatureNames) {
        expect(
          features[name],
          inInclusiveRange(0, researchFeatureMaximums[name]!),
        );
      }
      expect(
        find.text(
          'Thank you for contributing to postpartum depression research.',
        ),
        findsOneWidget,
      );
      expect(requestBodies, hasLength(2));
      expect(requestBodies[0], requestBodies[1]);
      apiClient.close();
    },
  );

  testWidgets('EPDS item 10 support banner appears and clears immediately', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ResearchFormScreen(researchId: 'id')),
    );
    await tester.ensureVisible(
      find.byKey(const Key('research-epds-option-9-0')),
    );
    await tester.tap(find.byKey(const Key('research-epds-option-9-0')));
    await tester.pump();
    expect(find.byKey(const Key('research-item10-support')), findsOneWidget);
    expect(find.text(supportInfo), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('research-epds-option-9-3')),
    );
    await tester.tap(find.byKey(const Key('research-epds-option-9-3')));
    await tester.pump();
    expect(find.byKey(const Key('research-item10-support')), findsNothing);
  });

  testWidgets('crisis thank-you response displays the shared support banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ResearchThankYouScreen(message: 'Thank you.', crisisFlag: true),
      ),
    );
    expect(find.byKey(const Key('research-crisis-support')), findsOneWidget);
    expect(find.text(supportInfo), findsOneWidget);
    expect(find.text('Thank you.'), findsOneWidget);
  });

  testWidgets('consent stores research ID and Home opens the form', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"research_id":"participant-23"}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research'));
    await tester.pumpAndSettle();
    expect(find.text(researchConsentReviewNotice), findsOneWidget);

    await tester.tap(find.byKey(const Key('research-consent-checkbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('research-consent-submit')));
    await tester.pumpAndSettle();

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/research/consent');
    expect(jsonDecode(requests.single.body), {
      'consent_given': true,
      'consent_version': 'v1',
    });
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(researchIdPreferenceKey), 'participant-23');
    expect(find.byType(ResearchFormScreen), findsOneWidget);
    apiClient.close();
  });

  testWidgets('declining consent creates no research participation', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{"research_id":"unexpected"}', 201);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('research-consent-submit')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('research-consent-decline')));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(researchIdPreferenceKey), isNull);
    expect(find.text('PPD Care'), findsOneWidget);
    apiClient.close();
  });

  testWidgets('withdraw clears research ID only after successful response', (
    tester,
  ) async {
    useTallViewport(tester);
    SharedPreferences.setMockInitialValues({
      'api_host': 'laptop.local',
      'api_port': 5000,
      researchIdPreferenceKey: 'participant-23',
    });
    var withdrawRequests = 0;
    final apiClient = ApiClient(
      settings: const ApiSettings(host: 'laptop.local', port: 5000),
      client: MockClient((request) async {
        withdrawRequests++;
        if (withdrawRequests == 1) {
          return http.Response('{"error":"temporary failure"}', 500);
        }
        return http.Response(
          '{"status":"withdrawn","research_id":"participant-23"}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(apiClient: apiClient)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research'));
    await tester.pumpAndSettle();
    expect(find.byType(ResearchFormScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('research-withdraw')));
    await tester.tap(find.byKey(const Key('research-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('research-withdraw-confirm')));
    await tester.pumpAndSettle();
    var preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(researchIdPreferenceKey), 'participant-23');
    expect(find.byKey(const Key('research-error')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('research-withdraw')));
    await tester.tap(find.byKey(const Key('research-withdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('research-withdraw-confirm')));
    await tester.pumpAndSettle();
    preferences = await SharedPreferences.getInstance();
    expect(withdrawRequests, 2);
    expect(preferences.getString(researchIdPreferenceKey), isNull);
    expect(find.text('PPD Care'), findsOneWidget);
    apiClient.close();
  });
}
