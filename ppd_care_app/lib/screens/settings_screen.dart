import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/support_info.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '5000');

  bool _loading = true;
  bool _testingConnection = false;
  String? _testingUrl;
  String? _connectionMessage;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final settings = await ApiSettings.loadSaved();
    if (!mounted) {
      return;
    }
    if (settings != null) {
      _hostController.text = settings.host;
      _portController.text = settings.port.toString();
    }
    setState(() => _loading = false);
  }

  ApiSettings? _settingsFromForm() {
    if (!_formKey.currentState!.validate()) {
      return null;
    }
    return ApiSettings(
      host: _hostController.text,
      port: int.parse(_portController.text),
    );
  }

  Future<void> _saveSettings() async {
    final settings = _settingsFromForm();
    if (settings == null) {
      return;
    }
    await settings.save();
    if (!mounted) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(settings);
    } else {
      setState(() => _connectionMessage = 'Settings saved.');
    }
  }

  Future<void> _testConnection() async {
    final settings = _settingsFromForm();
    if (settings == null) {
      setState(() => _connectionMessage = 'Invalid address or port.');
      return;
    }

    final client = ApiClient(
      settings: settings,
      timeout: const Duration(seconds: 5),
    );
    setState(() {
      _testingConnection = true;
      _testingUrl = '${client.baseUri}/health';
      _connectionMessage = 'Testing connection...';
    });
    try {
      final response = await client.get('/health');
      final decoded = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          decoded is Map<String, dynamic> &&
          decoded.length == 1 &&
          decoded['status'] == 'ok') {
        _showConnectionMessage('Connected');
      } else if (response.statusCode >= 500) {
        _showConnectionMessage('Server error (HTTP ${response.statusCode}).');
      } else {
        _showConnectionMessage(
          'Unexpected health response (HTTP ${response.statusCode}).',
        );
      }
    } on ApiTimeoutException catch (error) {
      _showConnectionMessage('Connection timed out: ${error.message}');
    } on ApiNetworkException catch (error) {
      _showConnectionMessage(
        'Connection refused or unreachable: ${error.message}',
      );
    } on ApiServerException catch (error) {
      _showConnectionMessage('Server error (HTTP ${error.statusCode}).');
    } on ApiException catch (error) {
      _showConnectionMessage('Server returned an error: ${error.message}');
    } on FormatException {
      _showConnectionMessage('Server returned an invalid health response.');
    } finally {
      client.close();
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  void _showConnectionMessage(String message) {
    if (mounted) {
      setState(() => _connectionMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Laptop server',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Laptop IP address or hostname',
                        hintText: '192.168.1.10 or laptop.local',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || !ApiSettings.isValidHost(value)) {
                          return 'Enter a valid IPv4 address or hostname.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || !ApiSettings.isValidPort(value)) {
                          return 'Enter a port from 1 to 65535.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _testingConnection ? null : _testConnection,
                        child: _testingConnection
                            ? const CircularProgressIndicator()
                            : const Text('Test connection'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _testingConnection ? null : _saveSettings,
                        child: const Text('Save settings'),
                      ),
                    ),
                    if (_testingUrl != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          'Testing $_testingUrl',
                          key: const Key('testing-url'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_connectionMessage != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _connectionMessage!,
                          key: const Key('connection-message'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(supportInfo, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
