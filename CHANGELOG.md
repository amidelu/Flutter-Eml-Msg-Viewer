## 1.1.0

- **Zero External Dependencies**: Completely removed all 6 external packages (`enough_mail`, `flutter_widget_from_html_core`, `http`, `path_provider`, `open_filex`, and `intl`). The package now depends strictly on `flutter: sdk: flutter`.
- **Android & iOS Support**: Added native Android (Kotlin + `FileProvider`) and iOS (Swift + `UIDocumentInteractionController`) plugin implementation for opening attachments and cache management.
- **iOS Swift Package Manager Support**: The iOS plugin now ships a `Package.swift` alongside the existing podspec, so host apps using Swift Package Manager (as well as CocoaPods) can consume it.
- **Built-in Pure-Dart RFC 822 / MIME Parser**: Replaced `enough_mail` with a self-contained MIME parser supporting headers, RFC 2047 encoded words, quoted-printable and base64 transfer encodings, RFC 2822 dates, address lists, and multipart nesting.
- **Built-in Pure-Flutter HTML Body Renderer**: Replaced `flutter_widget_from_html_core` with `MailHtmlView`, rendering headings, paragraphs, bold/italic/underline styles, links, inline `data:` images, and HTML entities directly with Flutter widgets and text spans.
- **Dart SDK HTTP & Date Handling**: Replaced `http` with `dart:io`'s `HttpClient` and `intl` with a built-in lightweight date formatter.
- **Built-in Kotlin**: The Android plugin now uses AGP's built-in Kotlin support instead of applying the Kotlin Gradle Plugin, and targets Java/JVM 17 with `compileSdk 36`. Requires Flutter 3.44+ / Dart 3.12+.
- **Fixed**: Extra blank space in HTML email bodies. Source whitespace between tags is now collapsed like a browser, and `<head>`/`<title>`/doctype content is no longer rendered.
- **Fixed**: Attachments failing to open. The plugin now ships its own `FileProvider` subclass to avoid manifest-merge clashes, derives the MIME type from the file extension when the part's type is generic, sanitizes file names, and finds the presenting view controller in scene-based iOS apps.

## 1.0.0

- Initial release: `.eml` parsing via `enough_mail`, and a from-scratch
  pure-Dart `.msg` (CFBF/MAPI) parser. `MailMessageViewer` widget renders
  either format with headers, HTML/plain-text body, inline `cid:` images,
  and attachments.
- `.msg` sender resolution prefers `PidTagSenderSmtpAddress` over
  `PidTagSenderEmailAddress`, which is frequently an unreadable X.500
  directory name on Exchange-generated messages.
- Swapped `flutter_widget_from_html` (the "batteries included" wrapper,
  which pulls in `video_player`, `webview_flutter`, `chewie`,
  `cached_network_image` and `url_launcher` for embed features this widget
  never uses) for `flutter_widget_from_html_core` — the same rendering
  engine without the extras. Cuts the resolved dependency tree from 133
  packages to 74. Adds `MailMessageViewer.onLinkTap` so consumers can wire
  up link taps themselves without this package needing a `url_launcher`
  dependency.
