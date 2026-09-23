import 'dart:convert';
import 'dart:typed_data';

import '../../model/mail_address.dart';

/// A self-contained, pure-Dart MIME (RFC 822 / RFC 2045-2049) parser.
class MimePart {
  MimePart({
    required this.headers,
    this.mediaType = 'text/plain',
    this.charset,
    this.boundary,
    this.fileName,
    this.contentDisposition,
    this.contentTransferEncoding,
    this.contentId,
    required this.bodyBytes,
    this.subParts = const [],
  });

  final Map<String, String> headers;
  final String mediaType;
  final String? charset;
  final String? boundary;
  final String? fileName;
  final String? contentDisposition;
  final String? contentTransferEncoding;
  final String? contentId;
  final Uint8List bodyBytes;
  final List<MimePart> subParts;

  bool get isMultipart => mediaType.startsWith('multipart/');
  bool get isText => mediaType.startsWith('text/');
  bool get isAttachment =>
      (contentDisposition != null && contentDisposition!.toLowerCase() == 'attachment') ||
      (fileName != null && fileName!.isNotEmpty);
  bool get isInline => contentDisposition != null && contentDisposition!.toLowerCase() == 'inline';

  /// Decodes this part's body as a string using its declared charset or UTF-8.
  String decodeText() {
    if (bodyBytes.isEmpty) return '';
    final cs = (charset ?? 'utf-8').toLowerCase().trim();
    try {
      if (cs.contains('latin1') || cs.contains('8859-1') || cs.contains('windows-1252')) {
        return latin1.decode(bodyBytes);
      } else if (cs.contains('ascii')) {
        return ascii.decode(bodyBytes, allowInvalid: true);
      }
      return utf8.decode(bodyBytes, allowMalformed: true);
    } catch (_) {
      return utf8.decode(bodyBytes, allowMalformed: true);
    }
  }

  /// Parses raw MIME text or bytes into a structured [MimePart].
  static MimePart parse(Uint8List rawBytes) {
    // Separate headers from body at the first blank line.
    final headerEnd = _findHeaderEnd(rawBytes);
    final headerBytes = headerEnd >= 0 ? rawBytes.sublist(0, headerEnd) : rawBytes;
    final bodyBytes = headerEnd >= 0
        ? rawBytes.sublist(headerEnd + (_isCrlf(rawBytes, headerEnd) ? 4 : 2))
        : Uint8List(0);

    final headerText = utf8.decode(headerBytes, allowMalformed: true);
    final headers = _parseHeaders(headerText);

    final contentTypeRaw = headers['content-type'] ?? 'text/plain';
    final parsedContentType = _parseHeaderWithParams(contentTypeRaw);
    final mediaType = parsedContentType.value.toLowerCase();
    final charset = parsedContentType.params['charset'];
    final boundary = parsedContentType.params['boundary'];
    var fileName = parsedContentType.params['name'];

    final contentDispRaw = headers['content-disposition'];
    String? contentDisposition;
    if (contentDispRaw != null) {
      final parsedDisp = _parseHeaderWithParams(contentDispRaw);
      contentDisposition = parsedDisp.value.toLowerCase();
      fileName ??= parsedDisp.params['filename'];
    }

    final transferEncoding = headers['content-transfer-encoding']?.trim().toLowerCase();
    final contentIdRaw = headers['content-id'];
    final contentId = contentIdRaw?.replaceAll('<', '').replaceAll('>', '').trim();

    if (mediaType.startsWith('multipart/') && boundary != null && boundary.isNotEmpty) {
      final subParts = _parseMultipart(bodyBytes, boundary);
      return MimePart(
        headers: headers,
        mediaType: mediaType,
        charset: charset,
        boundary: boundary,
        fileName: _decodeHeaderWord(fileName),
        contentDisposition: contentDisposition,
        contentTransferEncoding: transferEncoding,
        contentId: contentId,
        bodyBytes: bodyBytes,
        subParts: subParts,
      );
    }

    // Leaf part: decode content transfer encoding
    final decodedBytes = _decodeTransferEncoding(bodyBytes, transferEncoding);
    return MimePart(
      headers: headers,
      mediaType: mediaType,
      charset: charset,
      boundary: boundary,
      fileName: _decodeHeaderWord(fileName),
      contentDisposition: contentDisposition,
      contentTransferEncoding: transferEncoding,
      contentId: contentId,
      bodyBytes: decodedBytes,
    );
  }

  static int _findHeaderEnd(Uint8List bytes) {
    for (var i = 0; i < bytes.length - 1; i++) {
      // \r\n\r\n
      if (i + 3 < bytes.length &&
          bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
      // \n\n
      if (bytes[i] == 10 && bytes[i + 1] == 10) {
        return i;
      }
    }
    return -1;
  }

  static bool _isCrlf(Uint8List bytes, int index) {
    return index + 3 < bytes.length &&
        bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10;
  }

  /// Parses headers, performing RFC 5322 line unfolding and RFC 2047 decoding.
  static Map<String, String> _parseHeaders(String headerText) {
    final rawLines = headerText.split(RegExp(r'\r?\n'));
    final unfoldedLines = <String>[];

    for (final line in rawLines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (unfoldedLines.isNotEmpty) {
          unfoldedLines[unfoldedLines.length - 1] += ' ${line.trim()}';
        }
      } else {
        if (line.trim().isNotEmpty) {
          unfoldedLines.add(line);
        }
      }
    }

    final headers = <String, String>{};
    for (final line in unfoldedLines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex <= 0) continue;
      final name = line.substring(0, colonIndex).trim().toLowerCase();
      final value = line.substring(colonIndex + 1).trim();
      headers[name] = value;
    }
    return headers;
  }

  static ({String value, Map<String, String> params}) _parseHeaderWithParams(String header) {
    final parts = _splitHeaderParameters(header);
    if (parts.isEmpty) return (value: '', params: <String, String>{});

    final mainValue = parts.first.trim();
    final params = <String, String>{};

    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      final eqIdx = p.indexOf('=');
      if (eqIdx <= 0) continue;
      var paramName = p.substring(0, eqIdx).trim().toLowerCase();
      var paramVal = p.substring(eqIdx + 1).trim();

      // Remove surrounding quotes if present
      if (paramVal.startsWith('"') && paramVal.endsWith('"') && paramVal.length >= 2) {
        paramVal = paramVal.substring(1, paramVal.length - 1).replaceAll(r'\"', '"');
      } else if (paramVal.startsWith("'") && paramVal.endsWith("'") && paramVal.length >= 2) {
        paramVal = paramVal.substring(1, paramVal.length - 1);
      }

      // Handle RFC 2231 encoding e.g. filename*=utf-8''encoded_name
      if (paramName.endsWith('*')) {
        paramName = paramName.substring(0, paramName.length - 1);
        final apostropheIdx = paramVal.indexOf("''");
        if (apostropheIdx >= 0) {
          paramVal = Uri.decodeComponent(paramVal.substring(apostropheIdx + 2));
        }
      }

      params[paramName] = paramVal;
    }

    return (value: mainValue, params: params);
  }

  static List<String> _splitHeaderParameters(String header) {
    final result = <String>[];
    var inQuotes = false;
    var current = StringBuffer();

    for (var i = 0; i < header.length; i++) {
      final char = header[i];
      if (char == '"' && (i == 0 || header[i - 1] != r'\')) {
        inQuotes = !inQuotes;
      }
      if (char == ';' && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) {
      result.add(current.toString());
    }
    return result;
  }

  static List<MimePart> _parseMultipart(Uint8List bodyBytes, String boundary) {
    final parts = <MimePart>[];
    final boundaryBytes = utf8.encode('--$boundary');

    final indices = _findSubsequenceIndices(bodyBytes, boundaryBytes);
    if (indices.isEmpty) return parts;

    for (var i = 0; i < indices.length; i++) {
      final start = indices[i] + boundaryBytes.length;
      if (start >= bodyBytes.length) break;

      // Check if this was the closing boundary (--boundary--)
      if (start + 2 <= bodyBytes.length &&
          bodyBytes[start] == 45 &&
          bodyBytes[start + 1] == 45) {
        break;
      }

      // Skip trailing CRLF or LF after the boundary delimiter
      var actualStart = start;
      if (actualStart < bodyBytes.length && bodyBytes[actualStart] == 13) actualStart++;
      if (actualStart < bodyBytes.length && bodyBytes[actualStart] == 10) actualStart++;

      final end = (i + 1 < indices.length) ? indices[i + 1] : bodyBytes.length;
      // Strip preceding CRLF before the next boundary
      var actualEnd = end;
      if (actualEnd >= actualStart + 2 &&
          bodyBytes[actualEnd - 2] == 13 &&
          bodyBytes[actualEnd - 1] == 10) {
        actualEnd -= 2;
      } else if (actualEnd >= actualStart + 1 && bodyBytes[actualEnd - 1] == 10) {
        actualEnd -= 1;
      }

      if (actualEnd > actualStart) {
        final partBytes = bodyBytes.sublist(actualStart, actualEnd);
        parts.add(MimePart.parse(partBytes));
      }
    }

    return parts;
  }

  static List<int> _findSubsequenceIndices(Uint8List source, List<int> target) {
    final indices = <int>[];
    if (target.isEmpty || source.length < target.length) return indices;

    outer:
    for (var i = 0; i <= source.length - target.length; i++) {
      for (var j = 0; j < target.length; j++) {
        if (source[i + j] != target[j]) continue outer;
      }
      indices.add(i);
      i += target.length - 1;
    }
    return indices;
  }

  static Uint8List _decodeTransferEncoding(Uint8List bytes, String? encoding) {
    if (encoding == null || encoding.isEmpty) return bytes;
    switch (encoding) {
      case 'base64':
        return _decodeBase64(bytes);
      case 'quoted-printable':
        return _decodeQuotedPrintable(bytes);
      default:
        return bytes;
    }
  }

  static Uint8List _decodeBase64(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final sanitized = text.replaceAll(RegExp(r'[\r\n\t ]+'), '');
      if (sanitized.isEmpty) return Uint8List(0);
      // Pad to length multiple of 4
      final padLength = (4 - (sanitized.length % 4)) % 4;
      final padded = sanitized + ('=' * padLength);
      return Uint8List.fromList(base64Decode(padded));
    } catch (_) {
      return bytes;
    }
  }

  static Uint8List _decodeQuotedPrintable(Uint8List bytes) {
    final result = <int>[];
    final len = bytes.length;
    var i = 0;

    while (i < len) {
      final b = bytes[i];
      if (b == 61) {
        // '='
        if (i + 1 >= len) break;
        final next1 = bytes[i + 1];
        // Soft line break: '=\r\n' or '=\n' or '=\r'
        if (next1 == 13) {
          i += 2;
          if (i < len && bytes[i] == 10) i++;
          continue;
        } else if (next1 == 10) {
          i += 2;
          continue;
        }

        if (i + 2 < len) {
          final next2 = bytes[i + 2];
          final hexStr = String.fromCharCode(next1) + String.fromCharCode(next2);
          final val = int.tryParse(hexStr, radix: 16);
          if (val != null) {
            result.add(val);
            i += 3;
            continue;
          }
        }
        // Not a valid hex sequence, emit '='
        result.add(b);
        i++;
      } else {
        result.add(b);
        i++;
      }
    }

    return Uint8List.fromList(result);
  }

  /// Decodes RFC 2047 encoded words in header strings, e.g.
  /// `=?UTF-8?B?...?=` or `=?ISO-8859-1?Q?...?=`
  static String? _decodeHeaderWord(String? input) {
    if (input == null || input.isEmpty) return input;
    return decodeMimeEncodedWords(input);
  }
}

/// Decodes RFC 2047 encoded words in a string.
String decodeMimeEncodedWords(String input) {
  if (!input.contains('=?')) return input;

  // RFC 2047: when two encoded words are separated ONLY by whitespace, the whitespace must be ignored.
  final normalized = input.replaceAll(RegExp(r'(\?=\s+=\?)'), '?==?');

  final pattern = RegExp(r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?=', caseSensitive: false);
  return normalized.replaceAllMapped(pattern, (match) {
    final charset = match.group(1)!.toLowerCase();
    final encoding = match.group(2)!.toUpperCase();
    final encodedText = match.group(3)!;

    Uint8List bytes;
    if (encoding == 'B') {
      try {
        final pad = (4 - (encodedText.length % 4)) % 4;
        bytes = Uint8List.fromList(base64Decode(encodedText + ('=' * pad)));
      } catch (_) {
        return match.group(0)!;
      }
    } else if (encoding == 'Q') {
      // In RFC 2047 Q-encoding, '_' represents space (0x20).
      final byteList = <int>[];
      var i = 0;
      while (i < encodedText.length) {
        final c = encodedText[i];
        if (c == '_') {
          byteList.add(32);
          i++;
        } else if (c == '=' && i + 2 < encodedText.length) {
          final hex = encodedText.substring(i + 1, i + 3);
          final val = int.tryParse(hex, radix: 16);
          if (val != null) {
            byteList.add(val);
            i += 3;
            continue;
          }
          byteList.add(c.codeUnitAt(0));
          i++;
        } else {
          byteList.add(c.codeUnitAt(0));
          i++;
        }
      }
      bytes = Uint8List.fromList(byteList);
    } else {
      return match.group(0)!;
    }

    try {
      if (charset.contains('latin1') || charset.contains('8859-1') || charset.contains('windows-1252')) {
        return latin1.decode(bytes);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return utf8.decode(bytes, allowMalformed: true);
    }
  });
}

/// Parses an RFC 2822 / 5322 date string into a UTC [DateTime].
DateTime? parseRfc2822Date(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.trim();

  // Pattern: [DayOfWeek,] Day Month Year Hour:Min[:Sec] [Timezone]
  final regex = RegExp(
    r'(?:[A-Za-z]{3},\s+)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s+([+-]\d{4}|[A-Za-z]+))?',
  );

  final match = regex.firstMatch(cleaned);
  if (match == null) {
    try {
      return DateTime.parse(cleaned);
    } catch (_) {
      return null;
    }
  }

  final day = int.parse(match.group(1)!);
  final monthStr = match.group(2)!.toLowerCase();
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final month = months[monthStr] ?? 1;

  var year = int.parse(match.group(3)!);
  if (year < 100) {
    year += (year < 50 ? 2000 : 1900);
  }

  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;

  var offsetMinutes = 0;
  final tz = match.group(7)?.toUpperCase();
  if (tz != null) {
    if (RegExp(r'^[+-]\d{4}$').hasMatch(tz)) {
      final sign = tz.startsWith('-') ? -1 : 1;
      final hours = int.parse(tz.substring(1, 3));
      final mins = int.parse(tz.substring(3, 5));
      offsetMinutes = sign * (hours * 60 + mins);
    } else {
      const namedTz = {
        'UT': 0, 'UTC': 0, 'GMT': 0,
        'EDT': -240, 'EST': -300,
        'CDT': -300, 'CST': -360,
        'MDT': -360, 'MST': -420,
        'PDT': -420, 'PST': -480,
      };
      offsetMinutes = namedTz[tz] ?? 0;
    }
  }

  final utcTime = DateTime.utc(year, month, day, hour, minute, second);
  return utcTime.subtract(Duration(minutes: offsetMinutes));
}

/// Parses a comma-separated list of mail addresses, e.g.:
/// `"Alice Sender" <alice@example.com>, bob@example.com`
List<MailAddress> parseAddressList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final decoded = decodeMimeEncodedWords(raw);
  final addresses = <MailAddress>[];

  // Split by comma outside of quotes
  final tokens = <String>[];
  var inQuotes = false;
  var current = StringBuffer();

  for (var i = 0; i < decoded.length; i++) {
    final char = decoded[i];
    if (char == '"' && (i == 0 || decoded[i - 1] != r'\')) {
      inQuotes = !inQuotes;
    }
    if (char == ',' && !inQuotes) {
      if (current.toString().trim().isNotEmpty) {
        tokens.add(current.toString().trim());
      }
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  if (current.toString().trim().isNotEmpty) {
    tokens.add(current.toString().trim());
  }

  final addrRegex = RegExp(r'''^(?:["']?([^"'<>]*)["']?\s*)?<([^>]+)>$|^([^\s@]+@[^\s@]+)$''');

  for (final token in tokens) {
    final match = addrRegex.firstMatch(token);
    if (match != null) {
      if (match.group(2) != null) {
        // Name <email>
        final name = match.group(1)?.trim();
        final email = match.group(2)!.trim();
        addresses.add(MailAddress(name: (name != null && name.isNotEmpty) ? name : null, email: email));
      } else if (match.group(3) != null) {
        // bare email
        addresses.add(MailAddress(email: match.group(3)!.trim()));
      }
    } else {
      // Fallback: search for <...> or use whole string
      final angleMatch = RegExp(r'<([^>]+)>').firstMatch(token);
      if (angleMatch != null) {
        final email = angleMatch.group(1)!.trim();
        final name = token.substring(0, angleMatch.start).trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
        addresses.add(MailAddress(name: name.isNotEmpty ? name : null, email: email));
      } else if (token.contains('@')) {
        addresses.add(MailAddress(email: token.trim()));
      }
    }
  }

  return addresses;
}
