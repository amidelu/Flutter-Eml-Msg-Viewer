import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_message_viewer/src/parser/msg/cfb/cfb_reader.dart';
import 'package:mail_message_viewer/src/parser/msg/msg_parser.dart';

import 'support/msg_fixture_builder.dart';

void main() {
  group('MsgParser', () {
    test('parses subject, sender, recipient, dates, body, html and attachments', () async {
      final submitTime = DateTime.utc(2024, 1, 15, 10, 30);
      final htmlSource = '<p>Hello <b>world</b></p><img src="cid:img1">';
      final attachmentBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);

      final recipientStorage = CfbNode.storage('__recip_version1.0_#00000000', [
        CfbNode.stream(
          '__properties_version1.0',
          propertiesStream(8, [
            PropRow.long(0x0C15, 1), // TO
            PropRow.unicode(0x3001, 'Bob Recipient'),
            PropRow.unicode(0x39FE, 'bob@example.com'),
          ]),
        ),
        CfbNode.stream(substgName(0x3001, 0x001F), utf16le('Bob Recipient')),
        CfbNode.stream(substgName(0x39FE, 0x001F), utf16le('bob@example.com')),
      ]);

      final attachmentStorage = CfbNode.storage('__attach_version1.0_#00000000', [
        CfbNode.stream(
          '__properties_version1.0',
          propertiesStream(8, [
            PropRow.long(0x3705, 1), // ATTACH_BY_VALUE
            PropRow.unicode(0x3707, 'photo.png'),
            PropRow.unicode(0x370E, 'image/png'),
            PropRow.unicode(0x3712, 'img1'),
            PropRow.binary(0x3701, attachmentBytes),
          ]),
        ),
        CfbNode.stream(substgName(0x3707, 0x001F), utf16le('photo.png')),
        CfbNode.stream(substgName(0x370E, 0x001F), utf16le('image/png')),
        CfbNode.stream(substgName(0x3712, 0x001F), utf16le('img1')),
        CfbNode.stream(substgName(0x3701, 0x0102), attachmentBytes),
      ]);

      final topLevelProps = propertiesStream(32, [
        PropRow.unicode(0x0037, 'Test Subject'),
        PropRow.unicode(0x0C1A, 'Alice Sender'),
        PropRow.unicode(0x0C1F, 'alice@example.com'),
        PropRow.sysTime(0x0039, toFileTime(submitTime)),
        PropRow.unicode(0x1000, 'Hello world plain text'),
        PropRow.binary(0x1013, Uint8List.fromList(utf8.encode(htmlSource))),
      ]);

      final root = CfbNode.root([
        CfbNode.stream('__properties_version1.0', topLevelProps),
        CfbNode.stream(substgName(0x0037, 0x001F), utf16le('Test Subject')),
        CfbNode.stream(substgName(0x0C1A, 0x001F), utf16le('Alice Sender')),
        CfbNode.stream(substgName(0x0C1F, 0x001F), utf16le('alice@example.com')),
        CfbNode.stream(substgName(0x1000, 0x001F), utf16le('Hello world plain text')),
        CfbNode.stream(substgName(0x1013, 0x0102), Uint8List.fromList(utf8.encode(htmlSource))),
        recipientStorage,
        attachmentStorage,
      ]);

      final bytes = CfbNode.build(root);

      expect(looksLikeCompoundFile(bytes), isTrue);

      final message = MsgParser.parse(bytes);

      expect(message.subject, 'Test Subject');
      expect(message.from?.name, 'Alice Sender');
      expect(message.from?.email, 'alice@example.com');
      expect(message.date, submitTime);
      expect(message.textBody, 'Hello world plain text');

      expect(message.to, hasLength(1));
      expect(message.to.single.name, 'Bob Recipient');
      expect(message.to.single.email, 'bob@example.com');

      expect(message.attachments, hasLength(1));
      final attachment = message.attachments.single;
      expect(attachment.fileName, 'photo.png');
      expect(attachment.mimeType, 'image/png');
      expect(await attachment.loadBytes(), attachmentBytes);

      // The HTML body's cid: reference must be rewritten to an inline
      // data: URI using the attachment's bytes.
      expect(message.htmlBody, contains('data:image/png;base64,'));
      expect(message.htmlBody, isNot(contains('cid:img1')));
    });

    test('rejects bytes without the CFB signature', () {
      expect(
        () => MsgParser.parse(Uint8List.fromList('not a compound file'.codeUnits)),
        throwsA(isA<CfbFormatException>()),
      );
    });
  });
}
