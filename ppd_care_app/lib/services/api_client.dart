import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiSettings {
  const ApiSettings({required this.host, required this.port});

  static const _hostKey = 'api_host';
  static const _portKey = 'api_port';

  final String host;
  final int port;

  static bool isValidHost(String value) {
    if (value.isEmpty || value != value.trim() || value.length > 253) {
      return false;
    }

    final labels = value.split('.');
    if (labels.length == 4 &&
        labels.every((label) => RegExp(r'^\d+$').hasMatch(label))) {
      return labels.every((label) {
        final octet = int.tryParse(label);
        return octet != null && octet >= 0 && octet <= 255;
      });
    }

    if (RegExp(r'^[\d.]+$').hasMatch(value)) {
      return false;
    }

    if (labels.length == 4 &&
        labels.where((label) => RegExp(r'^\d+$').hasMatch(label)).length >= 3) {
      return false;
    }

    return labels.every((label) {
          if (label.isEmpty || label.length > 63) {
            return false;
          }
          return RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$')
              .hasMatch(label);
        }) &&
        RegExp(r'[A-Za-z]').hasMatch(labels.last);
  }

  static bool isValidPort(String value) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      return false;
    }
    final port = int.tryParse(value);
    return port != null && port >= 1 && port <= 65535;
  }

  static Future<ApiSettings?> loadSaved() async {
    final preferences = await SharedPreferences.getInstance();
    final host = preferences.getString(_hostKey);
    final port = preferences.getInt(_portKey);
    if (host == null ||
        !isValidHost(host) ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return ApiSettings(host: host, port: port);
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_hostKey, host);
    await preferences.setInt(_portKey, port);
  }
}

sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiConfigurationException extends ApiException {
  const ApiConfigurationException(super.message);
}

class ApiNetworkException extends ApiException {
  const ApiNetworkException(super.message);
}

class ApiTimeoutException extends ApiException {
  const ApiTimeoutException(super.message);
}

class ApiBadRequestException extends ApiException {
  const ApiBadRequestException(super.message);
}

class ApiNotFoundException extends ApiException {
  const ApiNotFoundException(super.message);
}

class ApiConflictException extends ApiException {
  const ApiConflictException(super.message);
}

class ApiServerException extends ApiException {
  const ApiServerException(super.message, this.statusCode);

  final int statusCode;
}

class ApiHttpException extends ApiException {
  const ApiHttpException(super.message, this.statusCode);

  final int statusCode;
}

class ApiClient {
  ApiClient({
    required this.settings,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ApiSettings settings;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  Uri get baseUri =>
      Uri(scheme: 'http', host: settings.host, port: settings.port);

  static Future<ApiClient> fromSavedSettings({
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final settings = await ApiSettings.loadSaved();
    if (settings == null) {
      throw const ApiConfigurationException(
        'No valid server address has been saved.',
      );
    }
    return ApiClient(settings: settings, client: client, timeout: timeout);
  }

  Future<http.Response> get(String path) {
    return _send(() => _client.get(_uriFor(path)).timeout(timeout));
  }

  Future<http.Response> post(String path, Object? body) {
    return postJson(path, body);
  }

  Future<http.Response> postJson(
    String path,
    Object? body, {
    Duration? requestTimeout,
  }) {
    return _send(
      () => _client
          .post(
            _uriFor(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(requestTimeout ?? timeout),
    );
  }

  Future<http.Response> delete(String path) {
    return _send(() => _client.delete(_uriFor(path)).timeout(timeout));
  }

  Uri _uriFor(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(path: normalizedPath);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() sendRequest,
  ) async {
    late final http.Response response;
    try {
      response = await sendRequest();
    } on TimeoutException catch (error) {
      throw ApiTimeoutException(error.toString());
    } on SocketException catch (error) {
      throw ApiNetworkException(error.toString());
    } on http.ClientException catch (error) {
      throw ApiNetworkException(error.toString());
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    final message = response.body.isEmpty
        ? 'HTTP ${response.statusCode}'
        : response.body;
    switch (response.statusCode) {
      case 400:
        throw ApiBadRequestException(message);
      case 404:
        throw ApiNotFoundException(message);
      case 409:
        throw ApiConflictException(message);
      case 500:
        throw ApiServerException(message, response.statusCode);
      default:
        if (response.statusCode >= 500) {
          throw ApiServerException(message, response.statusCode);
        }
        throw ApiHttpException(message, response.statusCode);
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
