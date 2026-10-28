import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/checkin_questions.dart';
import '../models/checkin_result.dart';
import '../services/api_client.dart';
import 'checkin_result_screen.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final Map<String, String> _answers = {};
  bool _submitting = false;
  String? _errorMessage;

  bool get _isComplete =>
      checkinQuestions.every((question) => _answers.containsKey(question.key));

  Future<void> _submit() async {
    if (!_isComplete || _submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    ApiClient? client = widget.apiClient;
    try {
      client ??= await ApiClient.fromSavedSettings(
        timeout: const Duration(seconds: 15),
      );
      final response = await client.postJson('/checkin', {
        for (final question in checkinQuestions)
          question.key: _answers[question.key],
      }, requestTimeout: const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected check-in response.');
      }
      final result = CheckinResult.fromJson(decoded);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckinResultScreen(result: result),
        ),
      );
    } on ApiBadRequestException {
      _showError('Something went wrong with the answers, please retry');
    } on ApiServerException {
      _showError('The service is unavailable, please try again');
    } on ApiTimeoutException {
      _showError(
        'The request timed out. Please check your connection and retry.',
      );
    } on ApiNetworkException {
      _showError('Could not reach the server. Check the address and retry.');
    } on ApiException {
      _showError('The request could not be completed. Please retry.');
    } on FormatException {
      _showError('The server returned an unexpected response. Please retry.');
    } on Exception {
      _showError('The request could not be completed. Please retry.');
    } finally {
      if (widget.apiClient == null) {
        client?.close();
      }
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal check-in')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var index = 0; index < checkinQuestions.length; index++)
              _QuestionCard(
                question: checkinQuestions[index],
                questionNumber: index + 1,
                selectedAnswer: _answers[checkinQuestions[index].key],
                enabled: !_submitting,
                onSelected: (answer) {
                  setState(() {
                    _answers[checkinQuestions[index].key] = answer;
                    _errorMessage = null;
                  });
                },
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _errorMessage!,
                  key: const Key('checkin-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('checkin-submit'),
                onPressed: _isComplete && !_submitting ? _submit : null,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.questionNumber,
    required this.selectedAnswer,
    required this.enabled,
    required this.onSelected,
  });

  final CheckinQuestion question;
  final int questionNumber;
  final String? selectedAnswer;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$questionNumber. ${question.question}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final choice in question.choices)
                  ChoiceChip(
                    label: Text(choice),
                    selected: selectedAnswer == choice,
                    onSelected: enabled ? (_) => onSelected(choice) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
