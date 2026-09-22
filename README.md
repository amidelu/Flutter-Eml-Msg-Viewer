# mail_message_viewer

Preview `.eml` (RFC822/MIME) and `.msg` (Outlook's proprietary CFBF/MAPI
binary format) email files inside a Flutter app — headers, HTML or
plain-text body with inline (`cid:`) images resolved, and a tappable
attachment list. Pure Dart: no platform channels, no native code.

## Why

Handing an `.eml` or `.msg` file off to whatever mail app is installed
doesn't work as a "viewer" — Outlook, Mail, and friends treat an incoming
message file as something to attach to a new draft, not something to
display. This package parses and renders the message itself instead.

`.msg` support is implemented as a from-scratch, pure-Dart reader for the
Compound File Binary Format ([MS-CFB]) and the MAPI property layout Outlook
stores on top of it ([MS-OXMSG]) — there is no bundled native library.

## Usage

```dart
import 'package:mail_message_viewer/mail_message_viewer.dart';

// From bytes you already have (e.g. picked from disk, or downloaded):
MailMessageViewer(bytes: fileBytes);

// Or fetch straight from a URL:
MailMessageViewer.url(url: signedBlobUrl);
```

Both `.eml` and `.msg` are auto-detected from their content (not the file
extension), so you can point either constructor at whichever format you
have.

To parse a message without rendering it (e.g. to show just the subject in
a list row), use the parser directly:

```dart
final message = MailMessageParser.parseBytes(bytes);
message.subject;
message.from;   // MailAddress?
message.to;     // List<MailAddress>
message.htmlBody ?? message.textBody;
message.attachments; // List<MailAttachment>
```

### Attachment taps

By default, tapping an attachment writes it to a temp file and opens it
with the OS's registered handler (via `open_filex`). Override this with
`onAttachmentTap` to do something else (e.g. upload it, or show a custom
preview):

```dart
MailMessageViewer(
  bytes: fileBytes,
  onAttachmentTap: (context, attachment) async {
    final bytes = await attachment.loadBytes();
    // ...
  },
)
```

## Known limitations

- `.msg` attachments stored as an embedded message (`AttachMethod` =
  `EMBEDDED_MESSAGE`) — i.e. one `.msg` forwarded inside another — are not
  expanded.
- `.msg` messages authored in RTF-only format (no HTML or plain-text body
  property set) aren't decompressed; only the HTML/plain-text bodies Outlook
  keeps in sync are read.
- String properties encoded with an 8-bit codepage other than UTF-8/Latin-1
  are decoded on a best-effort basis (most modern senders use `PT_UNICODE`
  and are unaffected).

[MS-CFB]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/
[MS-OXMSG]: https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxmsg/
