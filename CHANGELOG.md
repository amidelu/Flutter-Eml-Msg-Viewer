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
