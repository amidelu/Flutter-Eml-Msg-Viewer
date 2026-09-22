/// MAPI property IDs used to extract message content from a `.msg` file.
/// See [MS-OXPROPS] for the full canonical property set.
class MapiProperty {
  const MapiProperty._();

  static const int subject = 0x0037;
  static const int messageClass = 0x001A;
  static const int clientSubmitTime = 0x0039;
  static const int messageDeliveryTime = 0x0E06;

  static const int senderName = 0x0C1A;
  static const int senderEmailAddress = 0x0C1F;
  static const int sentRepresentingName = 0x0042;
  static const int sentRepresentingEmailAddress = 0x0065;

  static const int displayTo = 0x0E04;
  static const int displayCc = 0x0E03;
  static const int displayBcc = 0x0E02;

  static const int body = 0x1000;
  static const int html = 0x1013;
  static const int internetCodepage = 0x3FDE;

  static const int recipientType = 0x0C15;
  static const int displayName = 0x3001;
  static const int emailAddress = 0x3003;
  static const int smtpAddress = 0x39FE;

  static const int attachLongFilename = 0x3707;
  static const int attachFilename = 0x3704;
  static const int attachMimeTag = 0x370E;
  static const int attachDataBinary = 0x3701;
  static const int attachMethod = 0x3705;
  static const int attachContentId = 0x3712;
}

/// MAPI property type codes ([MS-OXCDATA] 2.11.1) — the low 16 bits of a
/// property tag, identifying how a property's value is encoded.
class MapiType {
  const MapiType._();

  static const int i2 = 0x0002;
  static const int long = 0x0003;
  static const int r4 = 0x0004;
  static const int double_ = 0x0005;
  static const int boolean = 0x000B;
  static const int i8 = 0x0014;
  static const int string8 = 0x001E;
  static const int unicode = 0x001F;
  static const int sysTime = 0x0040;
  static const int binary = 0x0102;
}

/// Recipient type values for [MapiProperty.recipientType].
class MapiRecipientType {
  const MapiRecipientType._();

  static const int to = 1;
  static const int cc = 2;
  static const int bcc = 3;
}

/// Attachment method values for [MapiProperty.attachMethod].
class MapiAttachMethod {
  const MapiAttachMethod._();

  static const int none = 0;
  static const int byValue = 1;
  static const int byReference = 4;
  static const int embeddedMessage = 5;
  static const int storage = 6;
}
