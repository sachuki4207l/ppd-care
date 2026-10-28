import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/support_info.dart';
import '../models/checkin_result.dart';
import '../services/api_client.dart';

class CheckinResultScreen extends StatelessWidget {
  const CheckinResultScreen({
    super.key,
    required this.result,
    this.apiClient,
    this.emailLauncher,
  });

  final CheckinResult result;
  final ApiClient? apiClient;
  final Future<bool> Function(Uri uri)? emailLauncher;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in complete')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              result.message,
              key: const Key('checkin-result-message'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            const Text(
              'This check-in is not a diagnosis.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                key: const Key('let-someone-know'),
                onPressed: () async {
                  final recorded = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => ContactsScreen(
                        selectionMode: true,
                        checkinId: result.checkinId,
                        apiClient: apiClient,
                        emailLauncher: emailLauncher,
                      ),
                    ),
                  );
                  if (recorded == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Your email app was opened'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.email_outlined),
                label: const Text('Let someone know'),
              ),
            ),
            const SizedBox(height: 12),
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
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(padding: EdgeInsets.all(16), child: SupportInfoBanner()),
      ),
    );
  }
}

class _Contact {
  const _Contact({
    required this.id,
    required this.name,
    required this.email,
    required this.relation,
  });

  final int id;
  final String name;
  final String email;
  final String? relation;

  factory _Contact.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final email = json['email'];
    final relation = json['relation'];
    if (id is! int ||
        id <= 0 ||
        name is! String ||
        email is! String ||
        (relation != null && relation is! String)) {
      throw const FormatException('Invalid contact response.');
    }
    final relationValue = relation is String ? relation : null;
    return _Contact(id: id, name: name, email: email, relation: relationValue);
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.selectionMode = false,
    this.checkinId,
    this.apiClient,
    this.emailLauncher,
  });

  final bool selectionMode;
  final int? checkinId;
  final ApiClient? apiClient;
  final Future<bool> Function(Uri uri)? emailLauncher;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  ApiClient? _client;
  bool _ownsClient = false;
  bool _loading = true;
  String? _errorMessage;
  List<_Contact> _contacts = [];
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient;
    _loadContacts();
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

  Future<void> _loadContacts({int? selectContactId}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await (await _getClient()).get('/contacts');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['contacts'] is! List) {
        throw const FormatException('Unexpected contacts response.');
      }
      final rawContacts = decoded['contacts'] as List<dynamic>;
      final contacts = rawContacts
          .map((entry) {
            if (entry is! Map<String, dynamic>) {
              throw const FormatException('Unexpected contact entry.');
            }
            return _Contact.fromJson(entry);
          })
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _contacts = contacts;
          if (selectContactId != null) {
            _selectedIds.add(selectContactId);
          }
        });
      }
    } on ApiTimeoutException {
      _setError('The request timed out. Please retry.');
    } on ApiNetworkException {
      _setError('Could not reach the server. Check your connection and retry.');
    } on ApiServerException {
      _setError('The service is unavailable, please try again.');
    } on ApiException catch (error) {
      _setError(
        _contactResponseMessage(error.message, 'Could not load contacts.'),
      );
    } on FormatException {
      _setError('The server returned an unexpected contacts response.');
    } on Exception {
      _setError('Could not load contacts. Please retry.');
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

  Future<void> _addContact() async {
    if (_contacts.length >= 5) {
      return;
    }
    final formKey = GlobalKey<FormState>();
    var submitting = false;
    String? dialogError;
    var name = '';
    var email = '';
    var relation = '';

    final contactId = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add a contact'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    key: const Key('contact-name'),
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: 'Name'),
                    onSaved: (value) => name = value ?? '',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter a name.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    key: const Key('contact-email'),
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    onSaved: (value) => email = value ?? '',
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!_isValidEmail(email)) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: 'Relation (optional)',
                    ),
                    onSaved: (value) => relation = value ?? '',
                  ),
                  if (dialogError != null)
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      formKey.currentState!.save();
                      setDialogState(() {
                        submitting = true;
                        dialogError = null;
                      });
                      try {
                        final response = await (await _getClient()).postJson(
                          '/contacts',
                          {
                            'name': name.trim(),
                            'email': email.trim(),
                            'relation': relation.trim().isEmpty
                                ? null
                                : relation.trim(),
                          },
                        );
                        final decoded = jsonDecode(response.body);
                        if (decoded is! Map<String, dynamic> ||
                            decoded['contact_id'] is! int) {
                          throw const FormatException(
                            'Unexpected contact creation response.',
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext)
                              .pop(decoded['contact_id'] as int);
                        }
                      } on ApiConflictException catch (error) {
                        setDialogState(() {
                          submitting = false;
                          dialogError = _contactResponseMessage(
                            error.message,
                            'The contact could not be added.',
                          );
                        });
                      } on ApiBadRequestException catch (error) {
                        setDialogState(() {
                          submitting = false;
                          dialogError = _contactResponseMessage(
                            error.message,
                            'Check the contact details and retry.',
                          );
                        });
                      } on ApiTimeoutException {
                        setDialogState(() {
                          submitting = false;
                          dialogError = 'The request timed out. Please retry.';
                        });
                      } on ApiNetworkException {
                        setDialogState(() {
                          submitting = false;
                          dialogError = 'Could not reach the server. Check the connection and retry.';
                        });
                      } on ApiServerException {
                        setDialogState(() {
                          submitting = false;
                          dialogError =
                              'The service is unavailable, please try again.';
                        });
                      } on Exception {
                        setDialogState(() {
                          submitting = false;
                          dialogError =
                              'The contact could not be added. Please retry.';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (contactId != null) {
      await _loadContacts(selectContactId: contactId);
    }
  }

  static bool _isValidEmail(String email) {
    return email.length <= 254 &&
        !RegExp(r'[\s\r\n\t]').hasMatch(email) &&
        RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email);
  }

  Future<void> _deleteContact(_Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Remove ${contact.name} from saved contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await (await _getClient()).delete('/contacts/${contact.id}');
      if (mounted) {
        setState(() {
          _contacts.removeWhere((entry) => entry.id == contact.id);
          _selectedIds.remove(contact.id);
        });
      }
    } on ApiException catch (error) {
      _showSnack(
        _contactResponseMessage(error.message, 'Could not delete contact.'),
      );
    } on Exception {
      _showSnack('Could not delete contact. Please retry.');
    }
  }

  Future<void> _continueWithSelected() async {
    if (!widget.selectionMode ||
        widget.checkinId == null ||
        _selectedIds.isEmpty) {
      return;
    }
    final recipients = _contacts
        .where((contact) => _selectedIds.contains(contact.id))
        .toList(growable: false);
    final client = await _getClient();
    if (!mounted) {
      return;
    }
    final recorded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _AlertConfirmationScreen(
          checkinId: widget.checkinId!,
          recipients: recipients,
          apiClient: client,
          emailLauncher: widget.emailLauncher,
        ),
      ),
    );
    if (recorded != null && mounted) {
      Navigator.of(context).pop(recorded);
    }
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _contacts.length < 5;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode ? 'Choose contacts' : 'Contacts'),
        actions: [
          IconButton(
            key: const Key('add-contact'),
            tooltip: 'Add contact',
            onPressed: canAdd ? _addContact : null,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorMessage!, key: const Key('contacts-error')),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadContacts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (!canAdd)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Maximum of 5 contacts reached.'),
                    ),
                  Expanded(
                    child: _contacts.isEmpty
                        ? const Center(child: Text('No saved contacts yet.'))
                        : ListView.builder(
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: ListTile(
                                  onTap: widget.selectionMode
                                      ? () => setState(() {
                                          if (!_selectedIds.add(contact.id)) {
                                            _selectedIds.remove(contact.id);
                                          }
                                        })
                                      : null,
                                  leading: widget.selectionMode
                                      ? Checkbox(
                                          value: _selectedIds.contains(
                                            contact.id,
                                          ),
                                          onChanged: (_) => setState(() {
                                            if (!_selectedIds.add(contact.id)) {
                                              _selectedIds.remove(contact.id);
                                            }
                                          }),
                                        )
                                      : null,
                                  title: Text(contact.name),
                                  subtitle: Text(
                                    '${contact.email}'
                                    '${contact.relation == null || contact.relation!.isEmpty ? '' : ' · ${contact.relation}'}',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Delete ${contact.name}',
                                    onPressed: () => _deleteContact(contact),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (widget.selectionMode)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          key: const Key('contacts-continue'),
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _continueWithSelected,
                          child: const Text('Continue'),
                        ),
                      ),
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

class _AlertConfirmationScreen extends StatefulWidget {
  const _AlertConfirmationScreen({
    required this.checkinId,
    required this.recipients,
    required this.apiClient,
    this.emailLauncher,
  });

  final int checkinId;
  final List<_Contact> recipients;
  final ApiClient apiClient;
  final Future<bool> Function(Uri uri)? emailLauncher;

  @override
  State<_AlertConfirmationScreen> createState() =>
      _AlertConfirmationScreenState();
}

class _AlertConfirmationScreenState extends State<_AlertConfirmationScreen> {
  static const _subject = 'A message for you';
  final _messageController = TextEditingController(
    text: 'I wanted to reach out and talk when you have a moment.',
  );
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _composeEmail() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: widget.recipients.map((contact) => contact.email).join(','),
        queryParameters: {'subject': _subject, 'body': _messageController.text},
      );
      final opened = await (widget.emailLauncher ?? launchUrl)(uri);
      if (!opened) {
        _setError('Could not open an email app. No alert was recorded.');
        return;
      }
      await widget.apiClient.postJson('/alerts', {
        'checkin_id': widget.checkinId,
        'decision': 'compose_opened',
        'recipient_contact_ids': [
          for (final contact in widget.recipients) contact.id,
        ],
      });
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException {
      _setError(
        'Your email app was opened, but the decision could not be recorded. Please retry.',
      );
    } on Exception {
      _setError('Could not open an email app. No alert was recorded.');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _decline() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.postJson('/alerts', {
        'checkin_id': widget.checkinId,
        'decision': 'declined',
        'recipient_contact_ids': null,
      });
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    } on ApiException catch (error) {
      _setError(
        _contactResponseMessage(error.message, 'Could not save your choice.'),
      );
    } on Exception {
      _setError('Could not save your choice. Please retry.');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
      appBar: AppBar(title: const Text('Review your message')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'To: ${widget.recipients.map((contact) => contact.name).join(', ')}',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('alert-message'),
              controller: _messageController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('alert-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                key: const Key('alert-compose'),
                onPressed: _submitting ? null : _composeEmail,
                child: _submitting
                    ? const CircularProgressIndicator()
                    : const Text('Open email app'),
              ),
            ),
            TextButton(
              onPressed: _submitting ? null : _decline,
              child: const Text('Cancel'),
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

String _contactResponseMessage(String body, String fallback) {
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
