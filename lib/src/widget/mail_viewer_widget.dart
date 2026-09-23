import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../model/mail_address.dart';
import '../model/mail_attachment.dart';
import '../model/mail_message.dart';
import '../parser/mail_message_parser.dart';
import '../platform/native_bridge.dart';
import 'attachment_tile.dart';
import 'header_row.dart';
import 'mail_html_view.dart';

/// Called when an attachment is tapped, instead of the widget's default
/// behavior of writing it to a temp file and opening it with the OS's
/// registered handler.
typedef MailAttachmentTap = void Function(BuildContext context, MailAttachment attachment);

/// Called when a link inside the HTML body is tapped. Return `true` to mark
/// the tap as handled.
typedef MailLinkTap = FutureOr<bool> Function(String url);

/// An in-app preview for `.eml` (RFC822/MIME) and `.msg` (Outlook CFBF/MAPI)
/// email files: subject/from/to/cc/date headers, the HTML or plain-text
/// body (with `cid:` inline images resolved), and a tappable attachment
/// list.
///
/// Provide the message bytes directly with the default constructor, or
/// fetch them from a URL with [MailMessageViewer.url].
class MailMessageViewer extends StatefulWidget {
  const MailMessageViewer({
    super.key,
    required Uint8List this._bytes,
    this.onAttachmentTap,
    this.onLinkTap,
  })  : _url = null,
        _headers = null;

  /// Fetches the raw message bytes from [url] (e.g. a signed blob-storage
  /// URL) before parsing.
  const MailMessageViewer.url({
    super.key,
    required String this._url,
    this._headers,
    this.onAttachmentTap,
    this.onLinkTap,
  }) : _bytes = null;

  final Uint8List? _bytes;
  final String? _url;
  final Map<String, String>? _headers;

  /// Overrides the default open-attachment behavior. Called with the tapped
  /// [MailAttachment]; use [MailAttachment.loadBytes] to get its data.
  final MailAttachmentTap? onAttachmentTap;

  /// Called when a link in the HTML body is tapped. Unset by default, so
  /// tapping a link does nothing unless you provide this.
  final MailLinkTap? onLinkTap;

  @override
  State<MailMessageViewer> createState() => _MailMessageViewerState();
}

class _MailMessageViewerState extends State<MailMessageViewer> {
  MailMessage? _message;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MailMessageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._bytes != widget._bytes || oldWidget._url != widget._url) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = widget._bytes ?? await _fetch(widget._url!, widget._headers);
      final message = MailMessageParser.parseBytes(bytes);
      if (mounted) {
        setState(() {
          _loading = false;
          _message = message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  static Future<Uint8List> _fetch(String url, Map<String, String>? headers) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      headers?.forEach((key, value) => request.headers.set(key, value));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Failed to load message: HTTP ${response.statusCode}', uri: uri);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  Future<void> _openAttachment(MailAttachment attachment) async {
    final customHandler = widget.onAttachmentTap;
    if (customHandler != null) {
      customHandler(context, attachment);
      return;
    }

    try {
      final bytes = await attachment.loadBytes();
      if (bytes.isEmpty) {
        _showError('Unable to open attachment: file is empty');
        return;
      }

      // Each attachment gets its own folder so a same-named file from another
      // message (or a still-open earlier copy) never collides with this one.
      final tempDirPath = await NativeBridge.getTemporaryDirectory();
      final dir = Directory(
        '$tempDirPath${Platform.pathSeparator}flutter_eml_msg_viewer'
        '${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}',
      );
      await dir.create(recursive: true);
      final localFile = File('${dir.path}${Platform.pathSeparator}${_safeFileName(attachment.fileName)}');
      await localFile.writeAsBytes(bytes, flush: true);

      final error = await NativeBridge.openFile(localFile.path, mimeType: attachment.mimeType);
      if (error != null) {
        _showError('Unable to open attachment: $error');
      }
    } catch (e) {
      debugPrint('flutter_eml_msg_viewer: failed to open attachment: $e');
      _showError('Unable to open attachment');
    }
  }

  /// Makes an attachment name safe to use as a file name on Android/iOS:
  /// strips path separators and control/reserved characters and caps the
  /// length (keeping the extension), since a name straight from a MIME header
  /// can contain any of these.
  static String _safeFileName(String name) {
    var clean = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    while (clean.startsWith('.')) {
      clean = clean.substring(1);
    }
    if (clean.isEmpty) clean = 'attachment';

    const maxLength = 120;
    if (clean.length > maxLength) {
      final dot = clean.lastIndexOf('.');
      final ext = (dot > 0 && clean.length - dot <= 16) ? clean.substring(dot) : '';
      clean = clean.substring(0, maxLength - ext.length) + ext;
    }
    return clean;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Normalizes CRLF/CR line endings (which can render as double line
  /// breaks) and trims trailing blank lines from a plain-text body.
  static String? _normalizePlainText(String? text) {
    if (text == null) return null;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
    return normalized.isEmpty ? null : normalized;
  }

  static String _formatDate(DateTime date) {
    final d = date.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[d.month - 1];
    final hour24 = d.hour;
    final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = hour24 >= 12 ? 'PM' : 'AM';
    return '$month ${d.day}, ${d.year}, $hour12:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }

    final message = _message;
    if (_error != null || message == null) {
      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline, size: 40, color: cs.error),
              const SizedBox(height: 12),
              Text(
                'Failed to load email',
                style: tt.titleMedium?.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final subject = message.subject;
    final from = message.from?.toString();
    final to = formatAddressList(message.to);
    final cc = formatAddressList(message.cc);
    final date = message.date;
    final htmlBody = message.htmlBody;
    final textBody = message.textBody;
    final attachments = message.attachments;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject?.isNotEmpty == true ? subject! : '(No subject)',
            style: tt.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          HeaderRow(label: 'From', value: (from?.isNotEmpty ?? false) ? from! : 'Unknown sender'),
          if (to != null) HeaderRow(label: 'To', value: to),
          if (cc != null) HeaderRow(label: 'Cc', value: cc),
          if (date != null) HeaderRow(label: 'Date', value: _formatDate(date)),
          const SizedBox(height: 8),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 16),
          if (attachments.isNotEmpty) ...[
            Text(
              'Attachments (${attachments.length})',
              style: tt.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final attachment in attachments)
              AttachmentTile(attachment: attachment, onTap: () => _openAttachment(attachment)),
            const SizedBox(height: 16),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 16),
          ],
          if (htmlBody != null && htmlBody.trim().isNotEmpty)
            MailHtmlView(
              html: htmlBody,
              textStyle: tt.bodyMedium?.copyWith(color: cs.onSurface),
              onTapUrl: widget.onLinkTap,
            )
          else
            Text(
              _normalizePlainText(textBody) ?? '(No content)',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            ),
        ],
      ),
    );
  }
}
