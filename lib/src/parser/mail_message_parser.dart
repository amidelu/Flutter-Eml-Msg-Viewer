import 'dart:convert';
import 'dart:typed_data';

import '../model/mail_message.dart';
import 'eml/eml_parser.dart';
import 'msg/cfb/cfb_reader.dart';
import 'msg/msg_parser.dart';

/// Parses either `.eml` (RFC822/MIME text) or `.msg` (Outlook CFBF/MAPI
/// binary) bytes into a unified [MailMessage], auto-detecting the format
/// from its content rather than trusting a file extension.
class MailMessageParser {
  const MailMessageParser._();

  static MailMessage parseBytes(Uint8List bytes) {
    if (looksLikeCompoundFile(bytes)) {
      return MsgParser.parse(bytes);
    }
    return EmlParser.parse(utf8.decode(bytes, allowMalformed: true));
  }
}
