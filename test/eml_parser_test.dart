import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_message_viewer/mail_message_viewer.dart';

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
}
