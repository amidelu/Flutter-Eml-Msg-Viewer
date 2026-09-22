import 'dart:typed_data';

/// An attachment (or inline/embedded part) belonging to a [MailMessage].
class MailAttachment {
  const MailAttachment({
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.contentId,
    required this.loadBytes,
  });

  /// Display/file name, e.g. `invoice.pdf`. Never empty.
  final String fileName;

  /// Best-effort MIME type, e.g. `application/pdf`.
  final String mimeType;

  /// Size in bytes, when known.
  final int? size;

  /// The `Content-ID` (without angle brackets), when this part is referenced
  /// from an HTML body via a `cid:` URL. `null` for ordinary attachments.
  final String? contentId;

  /// Lazily decodes and returns the attachment's raw bytes.
  final Future<Uint8List> Function() loadBytes;
}
