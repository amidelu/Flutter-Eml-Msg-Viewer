# Flutter EML MSG Viewer

Preview `.eml` (RFC822/MIME) and `.msg` (Outlook's proprietary CFBF/MAPI binary format) email files inside a Flutter app on **Android** and **iOS** with **zero external package dependencies** — headers, HTML or plain-text body with inline (`cid:`) images resolved, and a tappable attachment list.

## Why

Handing an `.eml` or `.msg` file off to whatever mail app is installed doesn't work as a "viewer" — Outlook, Mail, and friends treat an incoming message file as something to attach to a new draft, not something to display. This package parses and renders the message itself directly inside your Flutter app.

- **Zero Third-Party Dependencies**: No external pub packages required.
- **Android & iOS Focused**: Native Kotlin and Swift platform integration for opening attachments securely and managing cache storage.
- **Pure-Dart Parsers**: Full built-in parsers for RFC 822 / MIME `.eml` and Compound File Binary Format / MAPI `.msg`.
- **Pure-Flutter HTML Body Renderer**: Lightweight built-in HTML-to-Widget / TextSpan renderer (`MailHtmlView`) supporting headings, inline styles, links, and inline `data:` images.

## Supported Platforms

- **Android** (API 21+)
- **iOS** (iOS 12.0+)

## Usage

```dart
import 'package:flutter_eml_msg_viewer/flutter_eml_msg_viewer.dart';

// From bytes you already have (e.g. picked from disk, or downloaded):
MailMessageViewer(bytes: fileBytes);

// Or fetch straight from a URL:
MailMessageViewer.url(url: signedBlobUrl);
```

Both `.eml` and `.msg` are auto-detected from their content (not the file extension), so you can point either constructor at whichever format you have.

To parse a message without rendering it (e.g. to show just the subject in a list row), use the parser directly:

```dart
final message = MailMessageParser.parseBytes(bytes);
message.subject;
message.from;   // MailAddress?
message.to;     // List<MailAddress>
message.htmlBody ?? message.textBody;
message.attachments; // List<MailAttachment>
```

### Attachment taps

By default, tapping an attachment writes it to a cache file and opens it using the OS registered viewer (via native Android `FileProvider` + `Intent.ACTION_VIEW` and iOS `UIDocumentInteractionController`). Override this with `onAttachmentTap` to do something else (e.g. upload it, or show a custom preview):

```dart
MailMessageViewer(
  bytes: fileBytes,
  onAttachmentTap: (context, attachment) async {
    final bytes = await attachment.loadBytes();
    // ...
  },
)
```

### Link taps

Tapping a link in the HTML body does nothing by default. Wire up `onLinkTap` to open links with whatever your app already uses (e.g. `url_launcher`):

```dart
MailMessageViewer(
  bytes: fileBytes,
  onLinkTap: (url) async {
    // e.g. await launchUrl(Uri.parse(url));
    return true; // mark the tap as handled
  },
)
```

## Known limitations

- `.msg` attachments stored as an embedded message (`AttachMethod` = `EMBEDDED_MESSAGE`) — i.e. one `.msg` forwarded inside another — are not expanded.
- `.msg` messages authored in RTF-only format (no HTML or plain-text body property set) aren't decompressed; only the HTML/plain-text bodies Outlook keeps in sync are read.
- String properties encoded with an 8-bit codepage other than UTF-8/Latin-1 are decoded on a best-effort basis (most modern senders use `PT_UNICODE` and are unaffected).

[MS-CFB]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/
[MS-OXMSG]: https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxmsg/
