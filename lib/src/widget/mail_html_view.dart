import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A pure Flutter, zero-dependency widget for rendering email HTML bodies.
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.html,
    this.textStyle,
    this.onTapUrl,
  });

  final String html;
  final TextStyle? textStyle;
  final FutureOr<bool> Function(String url)? onTapUrl;

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final defaultStyle = widget.textStyle ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ) ??
        const TextStyle(fontSize: 14);

    final widgets = _HtmlParser(
      html: widget.html,
      baseStyle: defaultStyle,
      colorScheme: Theme.of(context).colorScheme,
      onTapUrl: widget.onTapUrl,
      registerRecognizer: (r) => _recognizers.add(r),
    ).parse();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets.isEmpty ? [Text('', style: defaultStyle)] : widgets,
    );
  }
}

class _HtmlParser {
  _HtmlParser({
    required this.html,
    required this.baseStyle,
    required this.colorScheme,
    required this.onTapUrl,
    required this.registerRecognizer,
  });

  final String html;
  final TextStyle baseStyle;
  final ColorScheme colorScheme;
  final FutureOr<bool> Function(String url)? onTapUrl;
  final void Function(TapGestureRecognizer) registerRecognizer;

  final List<Widget> _blocks = [];
  List<_Run> _currentRuns = [];

  /// True when the next collapsed-whitespace text should drop its leading
  /// space (start of a block, or right after a space / line break), matching
  /// how browsers collapse insignificant HTML whitespace.
  bool _suppressLeadingSpace = true;

  static final _collapsibleWhitespace = RegExp(r'[ \t\r\n\f]+');

  static const _voidTags = {
    'area', 'base', 'col', 'embed', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr',
  };

  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'pre', 'li', 'blockquote', 'ul', 'ol',
    'table', 'tr', 'center', 'section', 'article', 'header', 'footer', 'body', 'html', 'form',
  };

  final List<_StyleFrame> _styleStack = [];

  List<Widget> parse() {
    _styleStack.add(_StyleFrame(style: baseStyle));

    // Strip comments, doctype/CDATA markers, and non-rendered elements
    final sanitized = html
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'<![^>]*>'), '')
        .replaceAll(RegExp(r'<\?[^>]*>'), '')
        .replaceAll(RegExp(r'<head[\s>][\s\S]*?<\/head>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<title[\s\S]*?<\/title>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false), '');

    final tagPattern = RegExp(r'<(/?)(\w+)([^>]*)>', caseSensitive: false);
    var lastIndex = 0;

    for (final match in tagPattern.allMatches(sanitized)) {
      if (match.start > lastIndex) {
        final textChunk = sanitized.substring(lastIndex, match.start);
        _handleText(textChunk);
      }

      final isClosing = match.group(1) == '/';
      final tagName = match.group(2)!.toLowerCase();
      final attrString = match.group(3) ?? '';
      final isSelfClosing = attrString.trim().endsWith('/');

      _handleTag(tagName, isClosing, isSelfClosing, attrString);
      lastIndex = match.end;
    }

    if (lastIndex < sanitized.length) {
      _handleText(sanitized.substring(lastIndex));
    }

    _flushSpans();
    return _blocks;
  }

  void _handleText(String rawText) {
    if (rawText.isEmpty) return;
    final currentFrame = _styleStack.last;

    String text;
    if (currentFrame.preformatted) {
      text = _unescapeHtml(rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
    } else {
      // Collapse runs of source whitespace (newlines, indentation) to a single
      // space before unescaping, so `&nbsp;` survives as a real space.
      text = _unescapeHtml(rawText.replaceAll(_collapsibleWhitespace, ' '));
      if (_suppressLeadingSpace && text.startsWith(' ')) {
        text = text.substring(1);
      }
    }
    if (text.isEmpty) return;
    _suppressLeadingSpace = text.endsWith(' ') || text.endsWith('\n');

    TapGestureRecognizer? recognizer;
    if (currentFrame.linkUrl != null) {
      final url = currentFrame.linkUrl!;
      recognizer = TapGestureRecognizer()
        ..onTap = () {
          onTapUrl?.call(url);
        };
      registerRecognizer(recognizer);
    }

    _currentRuns.add(_Run(text, style: currentFrame.style, recognizer: recognizer));
  }

  void _handleTag(String tag, bool isClosing, bool isSelfClosing, String attrString) {
    final attrs = _parseAttributes(attrString);

    if (tag == 'br') {
      _trimTrailingSpaces();
      _currentRuns.add(_Run('\n'));
      _suppressLeadingSpace = true;
      return;
    }

    if (_voidTags.contains(tag)) return;

    if (tag == 'hr') {
      _flushSpans();
      _blocks.add(Divider(color: colorScheme.outlineVariant));
      return;
    }

    if (tag == 'img') {
      final src = attrs['src'] ?? '';
      final widget = _buildImage(src, attrs);
      if (widget != null) {
        _flushSpans();
        _blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: widget,
          ),
        );
      }
      return;
    }

    if (isClosing) {
      _closeTag(tag);
      return;
    }

    // Opening tags
    switch (tag) {
      case 'p':
      case 'div':
      case 'ul':
      case 'ol':
      case 'table':
      case 'tr':
      case 'center':
      case 'section':
      case 'article':
      case 'header':
      case 'footer':
      case 'body':
      case 'html':
      case 'form':
        _flushSpans();
        _pushStyle();
        break;
      case 'td':
      case 'th':
        // Separate adjacent cells on the same row with a single space.
        if (_currentRuns.isNotEmpty && !_suppressLeadingSpace) {
          _currentRuns.add(_Run(' ', style: _styleStack.last.style));
          _suppressLeadingSpace = true;
        }
        _pushStyle(fontWeight: tag == 'th' ? FontWeight.bold : null);
        break;
      case 'h1':
        _flushSpans();
        _pushStyle(
          fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 1.8 : 24,
          fontWeight: FontWeight.bold,
        );
        break;
      case 'h2':
        _flushSpans();
        _pushStyle(
          fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 1.5 : 20,
          fontWeight: FontWeight.bold,
        );
        break;
      case 'h3':
        _flushSpans();
        _pushStyle(
          fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! * 1.25 : 18,
          fontWeight: FontWeight.bold,
        );
        break;
      case 'h4':
      case 'h5':
      case 'h6':
        _flushSpans();
        _pushStyle(fontWeight: FontWeight.bold);
        break;
      case 'b':
      case 'strong':
        _pushStyle(fontWeight: FontWeight.bold);
        break;
      case 'i':
      case 'em':
        _pushStyle(fontStyle: FontStyle.italic);
        break;
      case 'u':
        _pushStyle(decoration: TextDecoration.underline);
        break;
      case 's':
      case 'strike':
      case 'del':
        _pushStyle(decoration: TextDecoration.lineThrough);
        break;
      case 'code':
        _pushStyle(
          fontFamily: 'monospace',
          backgroundColor: colorScheme.surfaceContainerHighest,
        );
        break;
      case 'pre':
        _flushSpans();
        _pushStyle(fontFamily: 'monospace', preformatted: true);
        break;
      case 'a':
        final href = attrs['href'];
        _pushStyle(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
          linkUrl: href,
        );
        break;
      case 'blockquote':
        _flushSpans();
        _pushStyle(fontStyle: FontStyle.italic);
        break;
      case 'li':
        _flushSpans();
        _currentRuns.add(_Run('• '));
        _suppressLeadingSpace = true;
        _pushStyle();
        break;
      default:
        // Other tags: preserve styling
        _pushStyle();
        break;
    }

    if (isSelfClosing) {
      _closeTag(tag);
    }
  }

  void _pushStyle({
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    double? fontSize,
    Color? color,
    Color? backgroundColor,
    String? fontFamily,
    String? linkUrl,
    bool? preformatted,
  }) {
    final parent = _styleStack.last;
    final parentStyle = parent.style;

    final newStyle = parentStyle.copyWith(
      fontWeight: fontWeight ?? parentStyle.fontWeight,
      fontStyle: fontStyle ?? parentStyle.fontStyle,
      decoration: decoration ?? parentStyle.decoration,
      fontSize: fontSize ?? parentStyle.fontSize,
      color: color ?? parentStyle.color,
      backgroundColor: backgroundColor ?? parentStyle.backgroundColor,
      fontFamily: fontFamily ?? parentStyle.fontFamily,
    );

    _styleStack.add(_StyleFrame(
      style: newStyle,
      linkUrl: linkUrl ?? parent.linkUrl,
      preformatted: preformatted ?? parent.preformatted,
    ));
  }

  void _closeTag(String tag) {
    if (_styleStack.length > 1) {
      _styleStack.removeLast();
    }
    if (_blockTags.contains(tag)) {
      _flushSpans();
    }
  }

  /// Removes collapsible trailing spaces from the current line.
  void _trimTrailingSpaces() {
    while (_currentRuns.isNotEmpty) {
      final last = _currentRuns.last;
      if (last.text.endsWith('\n')) return;
      final trimmed = last.text.replaceFirst(RegExp(r' +$'), '');
      if (trimmed.isNotEmpty) {
        last.text = trimmed;
        return;
      }
      _currentRuns.removeLast();
    }
  }

  void _flushSpans() {
    _suppressLeadingSpace = true;
    if (_currentRuns.isEmpty) return;
    _trimTrailingSpaces();

    final hasContent = _currentRuns.any((r) => r.text.replaceAll('\n', '').isNotEmpty);
    if (!hasContent) {
      // A block holding only line breaks (e.g. `<div><br></div>`) is an
      // intentional blank line; render exactly one line for it.
      if (_currentRuns.isNotEmpty) {
        _blocks.add(Text('', style: baseStyle));
      }
      _currentRuns = [];
      return;
    }

    // Like browsers, a single trailing <br> in a block adds no extra line.
    final last = _currentRuns.last;
    if (last.text.endsWith('\n')) {
      last.text = last.text.substring(0, last.text.length - 1);
      if (last.text.isEmpty) _currentRuns.removeLast();
    }

    _blocks.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(children: [for (final r in _currentRuns) r.toSpan()]),
          style: baseStyle,
        ),
      ),
    );
    _currentRuns = [];
  }

  Widget? _buildImage(String src, Map<String, String> attrs) {
    if (src.isEmpty) return null;

    final width = double.tryParse(attrs['width'] ?? '');
    final height = double.tryParse(attrs['height'] ?? '');

    if (src.startsWith('data:')) {
      final commaIndex = src.indexOf(',');
      if (commaIndex > 0) {
        final base64Data = src.substring(commaIndex + 1);
        try {
          final bytes = base64Decode(base64Data.replaceAll(RegExp(r'\s+'), ''));
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        } catch (_) {
          return null;
        }
      }
    } else if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return null;
  }

  static Map<String, String> _parseAttributes(String raw) {
    final attrs = <String, String>{};
    final regex = RegExp(r'''(\w+)(?:=(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?''');
    for (final match in regex.allMatches(raw)) {
      final name = match.group(1)!.toLowerCase();
      final val = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attrs[name] = val;
    }
    return attrs;
  }

  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&nbsp;', '\u00A0')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }
}

class _StyleFrame {
  _StyleFrame({required this.style, this.linkUrl, this.preformatted = false});
  final TextStyle style;
  final String? linkUrl;
  final bool preformatted;
}

/// A mutable run of inline text; kept mutable so trailing whitespace can be
/// trimmed when its block is flushed.
class _Run {
  _Run(this.text, {this.style, this.recognizer});
  String text;
  final TextStyle? style;
  final TapGestureRecognizer? recognizer;

  InlineSpan toSpan() => TextSpan(text: text, style: style, recognizer: recognizer);
}
