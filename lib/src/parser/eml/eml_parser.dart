import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mime;

import '../../model/mail_address.dart';
import '../../model/mail_attachment.dart';
import '../../model/mail_message.dart';

/// Parses RFC822/MIME `.eml` source text into a [MailMessage].
class EmlParser {
  const EmlParser._();

  static MailMessage parse(String source) {
    final message = mime.MimeMessage.parseFromText(source);
    final attachmentInfos = _collectAttachmentInfos(message);
    final rawHtml = message.decodeTextHtmlPart();
    final htmlBody = rawHtml == null
        ? null
        : _resolveCidImages(message, rawHtml, attachmentInfos);

    final fromList = message.from;
    return MailMessage(
      subject: message.decodeSubject(),
      from: fromList != null && fromList.isNotEmpty ? _toAddress(fromList.first) : null,
      to: _toAddresses(message.to),
      cc: _toAddresses(message.cc),
      bcc: _toAddresses(message.bcc),
      date: message.decodeDate(),
      htmlBody: htmlBody,
      textBody: message.decodeTextPlainPart(),
      attachments: [
        for (final info in attachmentInfos) _toAttachment(message, info),
      ],
    );
  }

  static MailAddress _toAddress(mime.MailAddress address) =>
      MailAddress(name: address.personalName, email: address.email);

  static List<MailAddress> _toAddresses(List<mime.MailAddress>? addresses) => [
        for (final a in addresses ?? const <mime.MailAddress>[]) _toAddress(a),
      ];

  /// Attachment-disposed parts plus non-text inline parts (e.g. images
  /// embedded in an HTML body via `cid:` references, such as a signature
  /// logo) — mail clients typically list both as "attachments" even though
  /// the inline ones also render inside the body itself.
  static List<mime.ContentInfo> _collectAttachmentInfos(mime.MimeMessage message) {
    final seen = <String>{};
    final result = <mime.ContentInfo>[];
    for (final info in [
      ...message.findContentInfo(),
      ...message
          .findContentInfo(disposition: mime.ContentDisposition.inline)
          .where((i) => !i.isText),
    ]) {
      if (seen.add(info.fetchId)) result.add(info);
    }
    return result;
  }

  /// Rewrites `<img src="cid:...">` references to inline `data:` URIs using
  /// the matching embedded part, so images referenced from within the HTML
  /// body actually render instead of failing to load (there's no host to
  /// fetch a bare `cid:` URL from).
  static String _resolveCidImages(
    mime.MimeMessage message,
    String html,
    List<mime.ContentInfo> infos,
  ) {
    final byCid = <String, mime.ContentInfo>{};
    for (final info in infos) {
      final cid = info.cid?.replaceAll('<', '').replaceAll('>', '').toLowerCase();
      if (cid != null && cid.isNotEmpty) byCid[cid] = info;
    }
    if (byCid.isEmpty) return html;

    return html.replaceAllMapped(
      RegExp('src=(["\'])cid:([^"\']+)\\1', caseSensitive: false),
      (match) {
        final quote = match.group(1)!;
        final cid = match.group(2)!.replaceAll('<', '').replaceAll('>', '').toLowerCase();
        final info = byCid[cid];
        if (info == null) return match.group(0)!;

        final bytes = message.getPart(info.fetchId)?.decodeContentBinary();
        if (bytes == null) return match.group(0)!;

        final mimeType = info.mediaType?.text ?? 'application/octet-stream';
        return 'src=$quote' 'data:$mimeType;base64,${base64Encode(bytes)}' '$quote';
      },
    );
  }

  static MailAttachment _toAttachment(mime.MimeMessage message, mime.ContentInfo info) {
    return MailAttachment(
      fileName: info.fileName ?? 'attachment',
      mimeType: info.mediaType?.text ?? 'application/octet-stream',
      size: info.size,
      contentId: info.cid?.replaceAll('<', '').replaceAll('>', ''),
      loadBytes: () async {
        final bytes = message.getPart(info.fetchId)?.decodeContentBinary();
        return bytes == null ? Uint8List(0) : Uint8List.fromList(bytes);
      },
    );
  }
}
