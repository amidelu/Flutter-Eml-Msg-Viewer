import 'package:flutter/material.dart';
import 'package:flutter_eml_msg_viewer/src/widget/mail_html_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> renderedBlocks(WidgetTester tester, String html) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MailHtmlView(html: html))));
    return tester.widgetList<Text>(find.byType(Text)).map((t) => t.textSpan?.toPlainText() ?? t.data ?? '').toList();
  }

  testWidgets('collapses source whitespace between tags', (tester) async {
    const html = '''<!DOCTYPE html>
<html>
  <head><title>Ignored</title><meta charset="utf-8"></head>
  <body>
    <table>
      <tr>
        <td>
          Hello
          world
        </td>
      </tr>
    </table>

    <p>
      Second   paragraph<br>
    </p>
  </body>
</html>''';

    final blocks = await renderedBlocks(tester, html);
    expect(blocks, ['Hello world', 'Second paragraph']);
  });

  testWidgets('keeps whitespace inside <pre> and blank <div><br></div> lines', (tester) async {
    final blocks = await renderedBlocks(tester, '<div>A</div><div><br></div><div>B</div><pre>x\n  y</pre>');
    expect(blocks, ['A', '', 'B', 'x\n  y']);
  });
}
