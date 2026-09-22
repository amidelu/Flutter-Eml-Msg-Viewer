import 'dart:convert';
import 'dart:typed_data';

import '../../model/mail_address.dart';
import '../../model/mail_attachment.dart';
import '../../model/mail_message.dart';
import 'cfb/cfb_entry.dart';
import 'cfb/cfb_reader.dart';
import 'mapi_properties.dart';
import 'mapi_property_reader.dart';

/// Parses an Outlook `.msg` file (a MAPI message stored as an [MS-CFB]
/// compound file, per [MS-OXMSG]) into a [MailMessage].
///
/// Supports the common case: plain-text and/or HTML body, recipients, and
/// attachments stored "by value". Attachments stored as an embedded message
/// (`PidTagAttachMethod` = `EMBEDDED_MESSAGE`) are not expanded — Outlook
/// itself treats those as a nested `.msg`, which is out of scope here.
class MsgParser {
  const MsgParser._();

  static const String _attachPrefix = '__attach_version1.0_#';
  static const String _recipPrefix = '__recip_version1.0_#';

  static MailMessage parse(Uint8List bytes) {
    final cf = CompoundFile.parse(bytes);
    final root = cf.root;
    final props = MapiPropertyReader.read(
      cf,
      root,
      headerSize: MapiPropertyReader.topLevelHeaderSize,
    );

    final recipients = _readRecipients(cf, root);
    final to = recipients[MapiRecipientType.to] ?? const <MailAddress>[];
    final cc = recipients[MapiRecipientType.cc] ?? const <MailAddress>[];
    final bcc = recipients[MapiRecipientType.bcc] ?? const <MailAddress>[];

    final senderName = props.getString(MapiProperty.senderName) ??
        props.getString(MapiProperty.sentRepresentingName);
    final senderEmail = props.getString(MapiProperty.senderEmailAddress) ??
        props.getString(MapiProperty.sentRepresentingEmailAddress);

    final decodedAttachments = _readAttachments(cf, root);
    final rawHtml = _readHtmlBody(props);
    final htmlBody = rawHtml == null
        ? null
        : _resolveCidImages(
            rawHtml,
            [
              for (final a in decodedAttachments)
                if (a.contentId != null && a.contentId!.isNotEmpty)
                  (contentId: a.contentId!, mimeType: a.mimeType, bytes: a.bytes),
            ],
          );
    final attachments = [
      for (final a in decodedAttachments)
        MailAttachment(
          fileName: a.fileName,
          mimeType: a.mimeType,
          size: a.bytes.length,
          contentId: a.contentId,
          loadBytes: () async => a.bytes,
        ),
    ];

    return MailMessage(
      subject: props.getString(MapiProperty.subject),
      from: senderEmail == null && senderName == null
          ? null
          : MailAddress(name: senderName, email: senderEmail ?? ''),
      to: to.isNotEmpty ? to : _fallbackAddresses(props.getString(MapiProperty.displayTo)),
      cc: cc.isNotEmpty ? cc : _fallbackAddresses(props.getString(MapiProperty.displayCc)),
      bcc: bcc.isNotEmpty ? bcc : _fallbackAddresses(props.getString(MapiProperty.displayBcc)),
      date: props.getDateTime(MapiProperty.messageDeliveryTime) ??
          props.getDateTime(MapiProperty.clientSubmitTime),
      htmlBody: htmlBody,
      textBody: props.getString(MapiProperty.body),
      attachments: attachments,
    );
  }

  static String? _readHtmlBody(MapiPropertyReader props) {
    final binary = props.getBinary(MapiProperty.html);
    if (binary != null && binary.isNotEmpty) {
      try {
        return utf8.decode(binary);
      } on FormatException {
        return latin1.decode(binary);
      }
    }
    return props.getString(MapiProperty.html);
  }

  /// A display string like `Jane Doe; John Smith` has no reliable email
  /// addresses in it, but is the only thing available when a `.msg` was
  /// saved without a full recipient table — show it as a single named,
  /// email-less entry per name so it's still visible in the header.
  static List<MailAddress> _fallbackAddresses(String? displayList) {
    if (displayList == null || displayList.trim().isEmpty) return const [];
    return displayList
        .split(RegExp('[;,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((name) => MailAddress(name: name, email: ''))
        .toList();
  }

  static Map<int, List<MailAddress>> _readRecipients(CompoundFile cf, CfbEntry root) {
    final byType = <int, List<MailAddress>>{};
    for (final storage in cf.childrenOf(root)) {
      if (!storage.isStorage || !storage.name.startsWith(_recipPrefix)) continue;
      final props = MapiPropertyReader.read(
        cf,
        storage,
        headerSize: MapiPropertyReader.attachmentOrRecipientHeaderSize,
      );
      final type = props.getInt(MapiProperty.recipientType) ?? MapiRecipientType.to;
      final name = props.getString(MapiProperty.displayName);
      final email = props.getString(MapiProperty.smtpAddress) ??
          props.getString(MapiProperty.emailAddress) ??
          '';
      if (name == null && email.isEmpty) continue;
      (byType[type] ??= []).add(MailAddress(name: name, email: email));
    }
    return byType;
  }

  static List<
      ({String fileName, String mimeType, String? contentId, Uint8List bytes})> _readAttachments(
    CompoundFile cf,
    CfbEntry root,
  ) {
    final result = <({String fileName, String mimeType, String? contentId, Uint8List bytes})>[];
    for (final storage in cf.childrenOf(root)) {
      if (!storage.isStorage || !storage.name.startsWith(_attachPrefix)) continue;
      final props = MapiPropertyReader.read(
        cf,
        storage,
        headerSize: MapiPropertyReader.attachmentOrRecipientHeaderSize,
      );

      final method = props.getInt(MapiProperty.attachMethod) ?? MapiAttachMethod.byValue;
      if (method != MapiAttachMethod.byValue) {
        // Embedded-message / by-reference / storage attachments aren't
        // expanded — see class docs.
        continue;
      }

      final fileName = props.getString(MapiProperty.attachLongFilename) ??
          props.getString(MapiProperty.attachFilename) ??
          'attachment';
      final mimeType = props.getString(MapiProperty.attachMimeTag) ?? 'application/octet-stream';
      final contentId = props.getString(MapiProperty.attachContentId);
      final bytes = props.getBinary(MapiProperty.attachDataBinary) ?? Uint8List(0);

      result.add((fileName: fileName, mimeType: mimeType, contentId: contentId, bytes: bytes));
    }
    return result;
  }

  /// Rewrites `<img src="cid:...">` references to inline `data:` URIs,
  /// mirroring the `.eml` behavior so embedded images (e.g. signature
  /// logos) render without needing a host to fetch a bare `cid:` URL from.
  ///
  /// Takes the raw decoded attachment bytes directly (rather than going
  /// through [MailAttachment.loadBytes], which is async) since by-value
  /// `.msg` attachments are already fully decoded in memory at this point.
  static String _resolveCidImages(
    String html,
    List<({String contentId, String mimeType, Uint8List bytes})> inlineImages,
  ) {
    final byCid = <String, ({String mimeType, Uint8List bytes})>{
      for (final image in inlineImages) image.contentId.toLowerCase(): (mimeType: image.mimeType, bytes: image.bytes),
    };
    if (byCid.isEmpty) return html;

    final matches = RegExp('src=(["\'])cid:([^"\']+)\\1', caseSensitive: false).allMatches(html);
    if (matches.isEmpty) return html;

    final buffer = StringBuffer();
    var lastEnd = 0;
    for (final match in matches) {
      final quote = match.group(1)!;
      final cid = match.group(2)!.toLowerCase();
      final image = byCid[cid];
      buffer.write(html.substring(lastEnd, match.start));
      if (image == null) {
        buffer.write(match.group(0));
      } else {
        buffer.write(
          'src=$quote' 'data:${image.mimeType};base64,${base64Encode(image.bytes)}' '$quote',
        );
      }
      lastEnd = match.end;
    }
    buffer.write(html.substring(lastEnd));
    return buffer.toString();
  }
}
