import 'mail_address.dart';
import 'mail_attachment.dart';

/// A parsed email message, normalized from either `.eml` or `.msg` source
/// bytes into one shape the viewer widget renders.
class MailMessage {
  const MailMessage({
    this.subject,
    this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.date,
    this.htmlBody,
    this.textBody,
    this.attachments = const [],
  });

  final String? subject;
  final MailAddress? from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final DateTime? date;

  /// HTML body with any `cid:` image references already resolved to inline
  /// `data:` URIs. Prefer this over [textBody] when non-empty.
  final String? htmlBody;

  /// Plain-text body, used when [htmlBody] is unavailable.
  final String? textBody;

  final List<MailAttachment> attachments;
}
