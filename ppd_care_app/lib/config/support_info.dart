import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String supportInfo = 'Need support? Tele-MANAS 14416 · Emergency 112';

class SupportInfoBanner extends StatefulWidget {
  const SupportInfoBanner({super.key, this.textAlign = TextAlign.center});

  final TextAlign textAlign;

  @override
  State<SupportInfoBanner> createState() => _SupportInfoBannerState();
}

class _SupportInfoBannerState extends State<SupportInfoBanner> {
  static const _telemanas = 'Tele-MANAS 14416';
  static const _emergency = 'Emergency 112';

  late final TapGestureRecognizer _telemanasRecognizer = TapGestureRecognizer()
    ..onTap = () => _openPhone('14416');
  late final TapGestureRecognizer _emergencyRecognizer = TapGestureRecognizer()
    ..onTap = () => _openPhone('112');

  @override
  void dispose() {
    _telemanasRecognizer.dispose();
    _emergencyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openPhone(String number) async {
    try {
      final opened = await launchUrl(Uri(scheme: 'tel', path: number));
      if (!opened) {
        _showFallback();
      }
    } on Exception {
      _showFallback();
    }
  }

  void _showFallback() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Unable to open the phone app. Call Tele-MANAS 14416 or Emergency 112.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teleIndex = supportInfo.indexOf(_telemanas);
    final emergencyIndex = supportInfo.indexOf(_emergency);
    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: supportInfo.substring(0, teleIndex)),
          TextSpan(
            text: _telemanas,
            style: linkStyle,
            recognizer: _telemanasRecognizer,
          ),
          TextSpan(
            text: supportInfo.substring(
              teleIndex + _telemanas.length,
              emergencyIndex,
            ),
          ),
          TextSpan(
            text: _emergency,
            style: linkStyle,
            recognizer: _emergencyRecognizer,
          ),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
