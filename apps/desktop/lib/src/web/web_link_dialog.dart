import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/strings.dart';
import 'web_companion.dart';

/// Shows the QR that links a phone browser (fresh one-time code every
/// [refresh]) and the browsers already linked, each with Remove.
class WebLinkDialog extends StatefulWidget {
  final WebCompanion web;

  /// `https://<lan ip>:<port>/web`
  final Future<String> Function() baseUrl;
  final Duration refresh;

  const WebLinkDialog(
      {super.key,
      required this.web,
      required this.baseUrl,
      this.refresh = const Duration(seconds: 100)});

  @override
  State<WebLinkDialog> createState() => _WebLinkDialogState();
}

class _WebLinkDialogState extends State<WebLinkDialog> {
  String? _url;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _next();
    _timer = Timer.periodic(widget.refresh, (_) => _next());
  }

  Future<void> _next() async {
    final base = await widget.baseUrl();
    if (mounted) setState(() => _url = '$base#c=${widget.web.newCode()}');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return AlertDialog(
      title: Text(t.linkPhoneWeb),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_url == null)
            const LinearProgressIndicator()
          else ...[
            SizedBox.square(
              dimension: 200,
              child: QrImageView(
                  key: const Key('web-qr'),
                  data: _url!,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white),
            ),
            const SizedBox(height: 8),
            SelectableText(_url!.split('#').first,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(t.linkPhoneWebHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<WebSession>>(
            valueListenable: widget.web.sessions,
            builder: (_, list, __) => Column(children: [
              if (list.isNotEmpty)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(t.linkedBrowsers,
                        style: Theme.of(context).textTheme.titleSmall)),
              for (final s in list)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.public),
                  title: Text(s.name),
                  trailing: TextButton(
                      key: Key('web-remove-${s.id}'),
                      onPressed: () => widget.web.revoke(s.id),
                      child: Text(t.remove)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel)),
      ],
    );
  }
}
