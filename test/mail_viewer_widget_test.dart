import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_eml_msg_viewer/flutter_eml_msg_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleEml = '''
From: Alice Sender <alice@example.com>\r
To: Bob Recipient <bob@example.com>\r
Subject: Test Subject\r
Date: Mon, 15 Jan 2024 10:30:00 +0000\r
Content-Type: text/html; charset=utf-8\r
\r
<p>Hello <b>world</b></p>\r
''';

void main() {
  testWidgets('MailMessageViewer renders subject, headers and HTML body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailMessageViewer(bytes: Uint8List.fromList(_sampleEml.codeUnits)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Subject'), findsOneWidget);
    expect(find.textContaining('alice@example.com'), findsOneWidget);
    // The HTML body renders as a RichText (bold "world" needs multiple
    // TextSpans), which find.text/textContaining ignore unless asked to
    // look inside RichText too.
    expect(find.textContaining('Hello world', findRichText: true), findsOneWidget);
  });
}
