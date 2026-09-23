import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_eml_msg_viewer/flutter_eml_msg_viewer.dart';
import 'package:flutter_eml_msg_viewer/src/parser/eml/mime_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleEml = '''
From: Alice Sender <alice@example.com>
To: Bob Recipient <bob@example.com>
Cc: Carol Copy <carol@example.com>
Subject: Test Subject
Date: Mon, 15 Jan 2024 10:30:00 +0000
Content-Type: multipart/mixed; boundary="outer"

--outer
Content-Type: multipart/related; boundary="inner"

--inner
Content-Type: text/html; charset=utf-8

<p>Hello <img src="cid:img1"></p>

--inner
Content-Type: image/png
Content-Transfer-Encoding: base64
Content-ID: <img1>
Content-Disposition: inline; filename="photo.png"

iVBORw0KGgo=

--inner--

--outer
Content-Type: application/pdf
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="invoice.pdf"

JVBERi0xLjQK

--outer--
''';

void main() {
  group('EmlParser', () {
    test('MailMessageParser parses .eml bytes, resolving cid: images and attachments', () {
      final crlfSource = _sampleEml.replaceAll('\n', '\r\n');
      final message = MailMessageParser.parseBytes(Uint8List.fromList(crlfSource.codeUnits));

      expect(message.subject, 'Test Subject');
      expect(message.from?.email, 'alice@example.com');
      expect(message.to.single.email, 'bob@example.com');
      expect(message.cc.single.email, 'carol@example.com');

      expect(message.htmlBody, contains('data:image/png;base64,'));
      expect(message.htmlBody, isNot(contains('cid:img1')));

      expect(message.attachments.map((a) => a.fileName), containsAll(['photo.png', 'invoice.pdf']));
    });

    test('decodes RFC 2047 Base64 and Quoted-Printable encoded words in headers', () {
      final subjectB64 = base64Encode(utf8.encode('Hello World'));
      final eml = '''
From: =?UTF-8?B?$subjectB64?= <sender@example.com>
To: Recipient <recip@example.com>
Subject: =?UTF-8?Q?Special_=C3=A9t=C3=A9_test?=
Date: 15 Jan 2024 10:30:00 +0000
Content-Type: text/plain; charset=utf-8

Body content
'''
          .replaceAll('\n', '\r\n');

      final message = MailMessageParser.parseBytes(Uint8List.fromList(utf8.encode(eml)));

      expect(message.from?.name, 'Hello World');
      expect(message.subject, 'Special été test');
      expect(message.textBody, 'Body content\r\n');
    });

    test('decodes quoted-printable body content properly', () {
      const eml = '''
From: sender@example.com
To: recip@example.com
Subject: QP Test
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: quoted-printable

<p>Hello=20world=3D=
continued line</p>
''';
      final message = MailMessageParser.parseBytes(Uint8List.fromList(utf8.encode(eml.replaceAll('\n', '\r\n'))));

      expect(message.htmlBody, contains('<p>Hello world=continued line</p>'));
    });

    test('parses RFC 2822 dates with various timezone formats', () {
      final d1 = parseRfc2822Date('Mon, 15 Jan 2024 10:30:00 +0000');
      expect(d1, DateTime.utc(2024, 1, 15, 10, 30));

      final d2 = parseRfc2822Date('15 Jan 2024 05:30:00 -0500');
      expect(d2, DateTime.utc(2024, 1, 15, 10, 30));

      final d3 = parseRfc2822Date('15 Jan 2024 10:30:00 GMT');
      expect(d3, DateTime.utc(2024, 1, 15, 10, 30));
    });

    test('parses multiple recipients in To, Cc, Bcc and handles header folding', () {
      const eml = '''
From: Alice <alice@example.com>
To: Bob <bob@example.com>,
 Charlie <charlie@example.com>
Cc: Dave <dave@example.com>
Bcc: Eve <eve@example.com>
Subject: Multi-recipient
 folded header

Content
''';
      final message = MailMessageParser.parseBytes(Uint8List.fromList(utf8.encode(eml.replaceAll('\n', '\r\n'))));

      expect(message.to.map((a) => a.email), ['bob@example.com', 'charlie@example.com']);
      expect(message.cc.map((a) => a.email), ['dave@example.com']);
      expect(message.bcc.map((a) => a.email), ['eve@example.com']);
      expect(message.subject, 'Multi-recipient folded header');
    });
  });
}
