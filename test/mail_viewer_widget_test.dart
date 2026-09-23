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
    expect(find.textContaining('Hello world', findRichText: true), findsOneWidget);
  });

  testWidgets('MailMessageViewer renders plain text when no HTML body', (tester) async {
    const plainEml = '''
From: Alice Sender <alice@example.com>\r
To: Bob Recipient <bob@example.com>\r
Subject: Plain Test\r
Date: Mon, 15 Jan 2024 10:30:00 +0000\r
Content-Type: text/plain; charset=utf-8\r
\r
Hello from plain text\r
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailMessageViewer(bytes: Uint8List.fromList(plainEml.codeUnits)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plain Test'), findsOneWidget);
    expect(find.text('Hello from plain text'), findsOneWidget);
  });

  testWidgets('MailHtmlView renders entities and dispatches link taps', (tester) async {
    String? tappedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailHtmlView(
            html: '<p>Tom &amp; Jerry &gt; Cat &lt;&nbsp;Mouse</p><a href="https://flutter.dev">Flutter</a>',
            onTapUrl: (url) {
              tappedUrl = url;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Tom & Jerry > Cat <\u00A0Mouse', findRichText: true), findsOneWidget);
    expect(find.textContaining('Flutter', findRichText: true), findsOneWidget);

    // Tap link
    await tester.tap(find.textContaining('Flutter', findRichText: true));
    await tester.pumpAndSettle();

    expect(tappedUrl, 'https://flutter.dev');
  });
}
