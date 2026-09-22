// ignore_for_file: avoid_print
//
// Dev utility: dumps the parsed fields of an .eml/.msg file for manual
// inspection. Not published — see `dependencies` in pubspec.yaml, which
// doesn't include this file.
//
// Usage: dart run tool/inspect_msg.dart path/to/message.msg
// Deliberately imports the parser directly rather than the package's
// barrel file: the barrel also exports the Flutter widget, which pulls in
// `package:flutter/material.dart` (and transitively `dart:ui`) — unusable
// from the plain Dart VM that `dart run` uses here.
import 'dart:io';

import 'package:flutter_eml_msg_viewer/src/parser/mail_message_parser.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/inspect_msg.dart <path-to-.eml-or-.msg>');
    exitCode = 64;
    return;
  }

  final bytes = File(args[0]).readAsBytesSync();
  final message = MailMessageParser.parseBytes(bytes);

  print('subject: ${message.subject}');
  print('from: ${message.from}');
  print('to: ${message.to}');
  print('cc: ${message.cc}');
  print('date: ${message.date}');
  print('textBody length: ${message.textBody?.length}');
  print('htmlBody length: ${message.htmlBody?.length}');
  print('attachments: ${message.attachments.length}');
  for (final a in message.attachments) {
    print('  - ${a.fileName} (${a.mimeType}, ${a.size} bytes, cid=${a.contentId})');
  }
}
