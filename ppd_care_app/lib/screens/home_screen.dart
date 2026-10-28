import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/support_info.dart';
import '../models/research_questions.dart';
import '../services/api_client.dart';
import 'checkin_screen.dart';
import 'checkin_result_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ApiSettings? _settings;
  bool _loading = true;
  bool _openingSettings = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndPromptIfNeeded();
  }

  Future<void> _loadSettingsAndPromptIfNeeded() async {
    final settings = await ApiSettings.loadSaved();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _loading = false;
    });
    if (settings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_openingSettings) {
          _openSettings();
        }
      });
    }
  }

  Future<void> _openSettings() async {
    if (_openingSettings) {
      return;
    }
    _openingSettings = true;
    await Navigator.of(context).push<ApiSettings>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _openingSettings = false;
    final settings = await ApiSettings.loadSaved();
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  Future<void> _openCheckin() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const CheckinScreen()));
  }

  Future<void> _openSleep() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => const SleepScreen()));
  }

  Future<void> _openContacts() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ContactsScreen()),
    );
  }

  Future<void> _openResearch() async {
    final preferences = await SharedPreferences.getInstance();
    final researchId = preferences.getString(researchIdPreferenceKey);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => researchId == null || researchId.trim().isEmpty
            ? ResearchConsentScreen(apiClient: widget.apiClient)
            : ResearchFormScreen(
                researchId: researchId,
                apiClient: widget.apiClient,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PPD Care')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your care, in one place',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_settings != null)
              Text(
                'Server: ${_settings!.host}:${_settings!.port}',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 24),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCheckin,
                icon: const Icon(Icons.favorite_border),
                label: const Text('Check-in'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openSleep,
                icon: const Icon(Icons.bedtime_outlined),
                label: const Text('Sleep'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openContacts,
                icon: const Icon(Icons.people_outline),
                label: const Text('Contacts'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openResearch,
                icon: const Icon(Icons.volunteer_activism_outlined),
                label: const Text('Research'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 60,
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Settings'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const SupportInfoBanner(),
        ),
      ),
    );
  }
}

class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  final _hoursController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _date;
  String? _quality;
  String? _errorMessage;
  bool _saving = false;
  ApiClient? _client;
  bool _ownsClient = false;

  @override
  void initState() {
    super.initState();
    _date = _today();
    _client = widget.apiClient;
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _noteController.dispose();
    if (_ownsClient) {
      _client?.close();
    }
    super.dispose();
  }

  Future<ApiClient> _getClient() async {
    if (_client != null) {
      return _client!;
    }
    _client = await ApiClient.fromSavedSettings();
    _ownsClient = true;
    return _client!;
  }

  String get _formattedDate =>
      '${_date.year.toString().padLeft(4, '0')}-'
      '${_date.month.toString().padLeft(2, '0')}-'
      '${_date.day.toString().padLeft(2, '0')}';

  Future<void> _chooseDate() async {
    final today = _today();
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 29)),
      lastDate: today,
    );
    if (selected != null) {
      setState(() {
        _date = DateTime(selected.year, selected.month, selected.day);
        _errorMessage = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final hours = double.tryParse(_hoursController.text.trim());
    if (hours == null || !hours.isFinite || hours < 0 || hours > 24) {
      setState(() => _errorMessage = 'Enter hours from 0 to 24.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      final client = await _getClient();
      await client.postJson('/sleep', {
        'date': _formattedDate,
        'hours': hours,
        'quality': _quality,
        'note': _noteController.text.isEmpty ? null : _noteController.text,
      });
      if (!mounted) {
        return;
      }
      _hoursController.clear();
      _noteController.clear();
      setState(() {
        _date = _today();
        _quality = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } on ApiConflictException {
      _showError('You already logged sleep for this date');
    } on ApiBadRequestException catch (error) {
      _showError(
        _responseMessage(error.message, 'The sleep entry is invalid.'),
      );
    } on ApiTimeoutException {
      _showError('The request timed out. Please retry.');
    } on ApiNetworkException {
      _showError(
        'Could not reach the server. Check your connection and retry.',
      );
    } on ApiServerException {
      _showError('The service is unavailable, please try again.');
    } on ApiException catch (error) {
      _showError(
        _responseMessage(error.message, 'The sleep entry could not be saved.'),
      );
    } on Exception {
      _showError('The sleep entry could not be saved. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
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
      appBar: AppBar(title: const Text('Sleep log')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            OutlinedButton.icon(
              key: const Key('sleep-date'),
              onPressed: _saving ? null : _chooseDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(_formattedDate),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sleep-hours'),
              controller: _hoursController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Hours slept',
                hintText: '0 to 24',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sleep quality (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final quality in ['Poor', 'Fair', 'Good'])
                  ChoiceChip(
                    label: Text(quality),
                    selected: _quality == quality,
                    onSelected: _saving
                        ? null
                        : (selected) => setState(
                            () => _quality = selected ? quality : null,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sleep-note'),
              controller: _noteController,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                key: const Key('sleep-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('sleep-save'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SleepHistoryScreen(apiClient: _client),
                ),
              ),
              child: const Text('View sleep history'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(padding: EdgeInsets.all(16), child: SupportInfoBanner()),
      ),
    );
  }
}

class SleepHistoryScreen extends StatefulWidget {
  const SleepHistoryScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<SleepHistoryScreen> createState() => _SleepHistoryScreenState();
}

class _SleepHistoryScreenState extends State<SleepHistoryScreen> {
  ApiClient? _client;
  bool _ownsClient = false;
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient;
    _loadEntries();
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
    super.dispose();
  }

  Future<ApiClient> _getClient() async {
    if (_client != null) {
      return _client!;
    }
    _client = await ApiClient.fromSavedSettings();
    _ownsClient = true;
    return _client!;
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await (await _getClient()).get('/sleep');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['entries'] is! List) {
        throw const FormatException('Unexpected sleep history response.');
      }
      final rawEntries = decoded['entries'] as List<dynamic>;
      if (rawEntries.any((entry) => entry is! Map<String, dynamic>)) {
        throw const FormatException('Unexpected sleep history entry.');
      }
      if (mounted) {
        setState(() => _entries = rawEntries.cast<Map<String, dynamic>>());
      }
    } on ApiTimeoutException {
      _setError('The request timed out. Please retry.');
    } on ApiNetworkException {
      _setError('Could not reach the server. Check your connection and retry.');
    } on ApiServerException {
      _setError('The service is unavailable, please try again.');
    } on ApiException catch (error) {
      _setError(
        _responseMessage(error.message, 'Could not load sleep history.'),
      );
    } on FormatException {
      _setError('The server returned an unexpected response.');
    } on Exception {
      _setError('Could not load sleep history. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep history')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!, key: const Key('sleep-history-error')),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('sleep-history-retry'),
                      onPressed: _loadEntries,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _entries.isEmpty
            ? const Center(child: Text('No sleep entries yet.'))
            : ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final details = <String>[
                    '${entry['hours']} hours',
                    if (entry['quality'] is String) entry['quality'] as String,
                    if (entry['note'] is String &&
                        (entry['note'] as String).isNotEmpty)
                      entry['note'] as String,
                  ];
                  return ListTile(
                    title: Text(entry['date']?.toString() ?? ''),
                    subtitle: Text(details.join(' · ')),
                  );
                },
              ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(padding: EdgeInsets.all(16), child: SupportInfoBanner()),
      ),
    );
  }
}

String _responseMessage(String body, String fallback) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded['error'] is String) {
      return decoded['error'] as String;
    }
  } on FormatException {
    if (body.isNotEmpty) {
      return body;
    }
  }
  return fallback;
}

class ResearchConsentScreen extends StatefulWidget {
  const ResearchConsentScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<ResearchConsentScreen> createState() => _ResearchConsentScreenState();
}

class _ResearchConsentScreenState extends State<ResearchConsentScreen> {
  ApiClient? _client;
  bool _ownsClient = false;
  bool _consentGiven = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
    super.dispose();
  }

  Future<ApiClient> _getClient() async {
    if (_client != null) {
      return _client!;
    }
    _client = await ApiClient.fromSavedSettings();
    _ownsClient = true;
    return _client!;
  }

  Future<void> _giveConsent() async {
    if (!_consentGiven || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final response = await (await _getClient()).postJson(
        '/research/consent',
        const {'consent_given': true, 'consent_version': 'v1'},
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 1 ||
          decoded['research_id'] is! String ||
          (decoded['research_id'] as String).trim().isEmpty) {
        throw const FormatException('Unexpected consent response.');
      }
      final researchId = decoded['research_id'] as String;
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        researchIdPreferenceKey,
        researchId,
      );
      if (!saved) {
        throw const FormatException('Could not save research consent.');
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ResearchFormScreen(
            researchId: researchId,
            apiClient: widget.apiClient,
          ),
        ),
      );
    } on ApiException catch (error) {
      _showError(
        _responseMessage(
          error.message,
          'Could not record consent. Please retry.',
        ),
      );
    } on FormatException {
      _showError('The service returned an unexpected consent response.');
    } on Exception {
      _showError('Could not record consent. Please retry.');
    } finally {
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
      appBar: AppBar(title: const Text(researchConsentHeading)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(researchConsentDraft),
            const SizedBox(height: 16),
            Text(
              researchConsentReviewNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const Key('research-consent-checkbox'),
              value: _consentGiven,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _consentGiven = value ?? false),
              title: const Text(
                'I have read this information and agree to take part.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                key: const Key('research-consent-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('research-consent-submit'),
                onPressed: _consentGiven && !_submitting ? _giveConsent : null,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Agree and continue'),
              ),
            ),
            TextButton(
              key: const Key('research-consent-decline'),
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(padding: EdgeInsets.all(16), child: SupportInfoBanner()),
      ),
    );
  }
}

class ResearchFormScreen extends StatefulWidget {
  const ResearchFormScreen({
    super.key,
    required this.researchId,
    this.apiClient,
  });

  final String researchId;
  final ApiClient? apiClient;

  @override
  State<ResearchFormScreen> createState() => _ResearchFormScreenState();
}

class _ResearchFormScreenState extends State<ResearchFormScreen> {
  static final _expectedResponses =
      researchQuestions.length + 1 + epdsQuestions.length;

  ApiClient? _client;
  bool _ownsClient = false;
  bool _submitting = false;
  bool _withdrawing = false;
  String? _errorMessage;
  final Map<String, int> _selectedOptions = {};
  int? _abuseAnswer;
  final List<int?> _epdsAnswers = List<int?>.filled(epdsQuestions.length, null);

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient;
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client?.close();
    }
    super.dispose();
  }

  Future<ApiClient> _getClient() async {
    if (_client != null) {
      return _client!;
    }
    _client = await ApiClient.fromSavedSettings();
    _ownsClient = true;
    return _client!;
  }

  int get _answeredCount =>
      _selectedOptions.length +
      (_abuseAnswer == null ? 0 : 1) +
      _epdsAnswers.where((answer) => answer != null).length;

  bool get _isComplete =>
      _selectedOptions.length == researchQuestions.length &&
      _abuseAnswer != null &&
      _epdsAnswers.every((answer) => answer != null);

  bool get _showItem10Support =>
      _epdsAnswers[9] != null && _epdsAnswers[9] != 3;

  Future<void> _submit() async {
    if (!_isComplete || _submitting) {
      return;
    }
    final features = buildResearchFeatures(
      selectedQuestionOptions: _selectedOptions,
    );
    if (features.length != researchFeatureNames.length ||
        !features.keys.toSet().containsAll(researchFeatureNames) ||
        features.containsKey('Abuse')) {
      setState(
        () => _errorMessage = 'Please review your answers and try again.',
      );
      return;
    }
    for (final name in researchFeatureNames) {
      final value = features[name];
      final maximum = researchFeatureMaximums[name];
      if (value == null || maximum == null || value < 0 || value > maximum) {
        setState(
          () => _errorMessage = 'Please review your answers and try again.',
        );
        return;
      }
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final response = await (await _getClient()).postJson('/research/submit', {
        'research_id': widget.researchId,
        'features': features,
        'abuse_reworded': _abuseAnswer,
        'epds_answers': _epdsAnswers.cast<int>(),
      });
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 3 ||
          decoded['submission_id'] is! int ||
          decoded['crisis_flag'] is! bool ||
          decoded['message'] is! String ||
          (decoded['message'] as String).trim().isEmpty) {
        throw const FormatException('Unexpected research submission response.');
      }
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ResearchThankYouScreen(
            message: decoded['message'] as String,
            crisisFlag: decoded['crisis_flag'] as bool,
          ),
        ),
      );
    } on ApiException catch (error) {
      _showError(
        _responseMessage(
          error.message,
          'Could not submit your answers. Please retry.',
        ),
      );
    } on FormatException {
      _showError('The service returned an unexpected response. Please retry.');
    } on Exception {
      _showError('Could not submit your answers. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _withdraw() async {
    if (_withdrawing || _submitting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw from research?'),
        content: const Text(
          'Your research participation will be marked as withdrawn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep participating'),
          ),
          FilledButton(
            key: const Key('research-withdraw-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _withdrawing = true;
      _errorMessage = null;
    });
    try {
      final response = await (await _getClient()).postJson(
        '/research/withdraw',
        {'research_id': widget.researchId},
      );
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 2 ||
          decoded['status'] != 'withdrawn' ||
          decoded['research_id'] != widget.researchId) {
        throw const FormatException('Unexpected withdrawal response.');
      }
      final preferences = await SharedPreferences.getInstance();
      final removed = await preferences.remove(researchIdPreferenceKey);
      if (!removed) {
        throw const FormatException('Could not clear the saved research ID.');
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (error) {
      _showError(
        _responseMessage(error.message, 'Could not withdraw. Please retry.'),
      );
    } on FormatException {
      _showError('Could not confirm withdrawal. Please retry.');
    } on Exception {
      _showError('Could not withdraw. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _withdrawing = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  Widget _questionCard(ResearchQuestion question) {
    final selectedIndex = _selectedOptions[question.key];
    return Card(
      key: Key('research-question-${question.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question.prompt,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var index = 0; index < question.options.length; index++)
                  ChoiceChip(
                    key: Key('research-option-${question.key}-$index'),
                    label: Text(question.options[index].label),
                    selected: selectedIndex == index,
                    onSelected: _submitting || _withdrawing
                        ? null
                        : (_) => setState(() {
                            _selectedOptions[question.key] = index;
                            _errorMessage = null;
                          }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _abuseCard() {
    return Card(
      key: const Key('research-question-abuse'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(abusePrompt, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(abusePrivacyNote),
            Wrap(
              spacing: 8,
              children: [
                for (var index = 0; index < abuseOptions.length; index++)
                  ChoiceChip(
                    key: Key('research-abuse-option-$index'),
                    label: Text(abuseOptions[index].label),
                    selected:
                        _abuseAnswer ==
                        abuseOptions[index].featureValues['abuse_reworded'],
                    onSelected: _submitting || _withdrawing
                        ? null
                        : (_) => setState(() {
                            _abuseAnswer = abuseOptions[index]
                                .featureValues['abuse_reworded'];
                            _errorMessage = null;
                          }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _epdsCard(int index) {
    final question = epdsQuestions[index];
    final answer = _epdsAnswers[index];
    return Card(
      key: Key('research-epds-question-$index'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${index + 1}. ${question.prompt}'),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: answer,
              onChanged: (value) {
                if (_submitting || _withdrawing) {
                  return;
                }
                setState(() {
                  _epdsAnswers[index] = value;
                  _errorMessage = null;
                });
              },
              child: Column(
                children: [
                  for (
                    var position = 0;
                    position < question.options.length;
                    position++
                  )
                    RadioListTile<int>(
                      key: Key('research-epds-option-$index-$position'),
                      value: position,
                      enabled: !_submitting && !_withdrawing,
                      title: Text(question.options[position]),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            if (index == 9 && _showItem10Support) ...[
              const SizedBox(height: 8),
              const SupportInfoBanner(
                key: Key('research-item10-support'),
                textAlign: TextAlign.left,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Research questionnaire')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'In the past 7 days',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              key: const Key('research-progress'),
              value: _answeredCount / _expectedResponses,
            ),
            Text('$_answeredCount of $_expectedResponses answers'),
            for (final section in ResearchSection.values) ...[
              const SizedBox(height: 16),
              Text(
                researchSectionTitles[section.index],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              for (final question in researchQuestions.where(
                (question) => question.section == section,
              ))
                _questionCard(question),
              if (section == ResearchSection.pregnancy) _abuseCard(),
              if (section == ResearchSection.feelings) ...[
                const SizedBox(height: 8),
                Text(
                  'In the past 7 days',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var index = 0; index < epdsQuestions.length; index++)
                  _epdsCard(index),
              ],
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                key: const Key('research-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('research-submit'),
                onPressed: _isComplete && !_submitting && !_withdrawing
                    ? _submit
                    : null,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Submit'),
              ),
            ),
            TextButton(
              key: const Key('research-withdraw'),
              onPressed: _withdrawing || _submitting ? null : _withdraw,
              child: _withdrawing
                  ? const CircularProgressIndicator()
                  : const Text('Withdraw from research'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _showItem10Support
          ? null
          : const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SupportInfoBanner(),
              ),
            ),
    );
  }
}

class ResearchThankYouScreen extends StatelessWidget {
  const ResearchThankYouScreen({
    super.key,
    required this.message,
    required this.crisisFlag,
  });

  final String message;
  final bool crisisFlag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thank you')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              message,
              key: const Key('research-thank-you-message'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'This questionnaire is for research and is not a diagnosis.',
              textAlign: TextAlign.center,
            ),
            if (crisisFlag) ...[
              const SizedBox(height: 20),
              const SupportInfoBanner(
                key: Key('research-crisis-support'),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Back to home'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: crisisFlag
          ? null
          : const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SupportInfoBanner(),
              ),
            ),
    );
  }
}
