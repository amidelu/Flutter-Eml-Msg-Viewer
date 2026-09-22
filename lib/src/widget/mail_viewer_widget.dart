import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../model/mail_address.dart';
import '../model/mail_attachment.dart';
import '../model/mail_message.dart';
import '../parser/mail_message_parser.dart';
import 'attachment_tile.dart';
import 'header_row.dart';

/// Called when an attachment is tapped, instead of the widget's default
/// behavior of writing it to a temp file and opening it with the OS's
/// registered handler via `open_filex`.
typedef MailAttachmentTap = void Function(BuildContext context, MailAttachment attachment);

/// Called when a link inside the HTML body is tapped. The widget itself
/// never launches URLs (that would require a `url_launcher` dependency);
/// wire this up to actually open [url] if you want that behavior. Return
/// `true` to mark the tap as handled.
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
    required Uint8List bytes,
    this.onAttachmentTap,
    this.onLinkTap,
  })  : _bytes = bytes,
        _url = null,
        _headers = null;

  /// Fetches the raw message bytes from [url] (e.g. a signed blob-storage
  /// URL) before parsing.
  const MailMessageViewer.url({
    super.key,
    required String url,
    Map<String, String>? headers,
    this.onAttachmentTap,
    this.onLinkTap,
  })  : _bytes = null,
        _url = url,
        _headers = headers;

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
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Failed to load message: HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.bodyBytes;
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
        _showError('Unable to open attachment');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final cleanName = attachment.fileName.replaceAll('/', '');
      final localFile = File('${tempDir.path}/$cleanName');
      await localFile.writeAsBytes(bytes);

      final result = await OpenFilex.open(localFile.path);
      if (result.type != ResultType.done) {
        _showError('Failed to open attachment: ${result.message}');
      }
    } catch (_) {
      _showError('Unable to open attachment');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      padding: const EdgeInsets.all(16),
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
          if (date != null) HeaderRow(label: 'Date', value: DateFormat.yMMMd().add_jm().format(date.toLocal())),
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
            HtmlWidget(
              htmlBody,
              renderMode: RenderMode.column,
              textStyle: tt.bodyMedium?.copyWith(color: cs.onSurface),
              onTapUrl: widget.onLinkTap == null ? null : (url) async => await widget.onLinkTap!(url),
            )
          else
            Text(
              textBody?.isNotEmpty == true ? textBody! : '(No content)',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface),
            ),
        ],
      ),
    );
  }
}
