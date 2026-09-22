## 0.1.0

- Initial release: `.eml` parsing via `enough_mail`, and a from-scratch
  pure-Dart `.msg` (CFBF/MAPI) parser. `MailMessageViewer` widget renders
  either format with headers, HTML/plain-text body, inline `cid:` images,
  and attachments.
- `.msg` sender resolution prefers `PidTagSenderSmtpAddress` over
  `PidTagSenderEmailAddress`, which is frequently an unreadable X.500
  directory name on Exchange-generated messages.
