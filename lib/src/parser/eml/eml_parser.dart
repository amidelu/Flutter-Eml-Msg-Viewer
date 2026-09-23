import 'dart:convert';
import 'dart:typed_data';

import '../../model/mail_attachment.dart';
import '../../model/mail_message.dart';
import 'mime_parser.dart';

/// Parses RFC822/MIME `.eml` source text into a [MailMessage].
class EmlParser {
  const EmlParser._();

  static MailMessage parse(String source) {
    final bytes = Uint8List.fromList(utf8.encode(source));
    return parseBytes(bytes);
  }

  static MailMessage parseBytes(Uint8List bytes) {
    final rootPart = MimePart.parse(bytes);

    final fromList = parseAddressList(rootPart.headers['from']);
    final toList = parseAddressList(rootPart.headers['to']);
    final ccList = parseAddressList(rootPart.headers['cc']);
    final bccList = parseAddressList(rootPart.headers['bcc']);
    final subject = rootPart.headers['subject'] != null
        ? decodeMimeEncodedWords(rootPart.headers['subject']!)
        : null;
    final date = parseRfc2822Date(rootPart.headers['date']);

    final allParts = <MimePart>[];
    _collectLeafParts(rootPart, allParts);

    // Identify HTML and plain-text body parts
    String? rawHtml;
    String? textBody;

    for (final part in allParts) {
      if (part.isAttachment) continue;
      if (part.mediaType == 'text/html' && rawHtml == null) {
        rawHtml = part.decodeText();
      } else if (part.mediaType == 'text/plain' && textBody == null) {
        textBody = part.decodeText();
      }
    }

    // Collect attachments and inline media parts
    final attachmentParts = _collectAttachments(allParts);

    // Resolve cid: images in the HTML body
    final htmlBody = rawHtml == null
        ? null
        : _resolveCidImages(rawHtml, attachmentParts);

    final attachments = [
      for (final part in attachmentParts)
        MailAttachment(
          fileName: part.fileName ?? 'attachment',
          mimeType: part.mediaType,
          size: part.bodyBytes.length,
          contentId: part.contentId,
          loadBytes: () async => part.bodyBytes,
        ),
    ];

    return MailMessage(
      subject: subject,
      from: fromList.isNotEmpty ? fromList.first : null,
      to: toList,
      cc: ccList,
      bcc: bccList,
      date: date,
      htmlBody: htmlBody,
      textBody: textBody,
      attachments: attachments,
    );
  }

  static void _collectLeafParts(MimePart current, List<MimePart> leaves) {
    if (current.isMultipart) {
      for (final sub in current.subParts) {
        _collectLeafParts(sub, leaves);
      }
    } else {
      leaves.add(current);
    }
  }

  static List<MimePart> _collectAttachments(List<MimePart> leaves) {
    final attachments = <MimePart>[];
    final seen = <MimePart>{};

    for (final part in leaves) {
      final isAtt = part.isAttachment;
      final isInlineMedia = part.isInline && !part.isText;
      final hasCid = part.contentId != null && part.contentId!.isNotEmpty && !part.isText;

      if ((isAtt || isInlineMedia || hasCid) && seen.add(part)) {
        attachments.add(part);
      }
    }
    return attachments;
  }

  static String _resolveCidImages(String html, List<MimePart> attachments) {
    final byCid = <String, MimePart>{};
    for (final part in attachments) {
      final cid = part.contentId?.toLowerCase();
      if (cid != null && cid.isNotEmpty) {
        byCid[cid] = part;
      }
    }
    if (byCid.isEmpty) return html;

    return html.replaceAllMapped(
      RegExp(r'''src=(["'])cid:([^"']+)\1''', caseSensitive: false),
      (match) {
        final quote = match.group(1)!;
        final cid = match.group(2)!.replaceAll('<', '').replaceAll('>', '').toLowerCase();
        final part = byCid[cid];
        if (part == null) return match.group(0)!;

        final mimeType = part.mediaType.isNotEmpty ? part.mediaType : 'application/octet-stream';
        return 'src=$quote' 'data:$mimeType;base64,${base64Encode(part.bodyBytes)}' '$quote';
      },
    );
  }
}
