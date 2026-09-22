/// A single email address with an optional display name.
class MailAddress {
  const MailAddress({this.name, required this.email});

  final String? name;
  final String email;

  @override
  String toString() {
    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) return email;
    return '$trimmedName <$email>';
  }
}

/// Joins a list of addresses the way a mail client's header line would,
/// returning `null` when there is nothing to show.
String? formatAddressList(List<MailAddress>? addresses) {
  if (addresses == null || addresses.isEmpty) return null;
  return addresses.map((a) => a.toString()).join(', ');
}
