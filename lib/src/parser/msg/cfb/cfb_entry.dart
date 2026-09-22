/// A single 128-byte directory entry from a Compound File Binary (CFB)
/// container — either the root storage, a sub-storage ("folder"), or a
/// stream ("file"). See [MS-CFB] 2.6.1.
class CfbEntry {
  const CfbEntry({
    required this.index,
    required this.name,
    required this.objectType,
    required this.leftSiblingId,
    required this.rightSiblingId,
    required this.childId,
    required this.startingSectorLocation,
    required this.streamSize,
  });

  static const int typeUnknown = 0;
  static const int typeStorage = 1;
  static const int typeStream = 2;
  static const int typeRoot = 5;

  static const int noStream = 0xFFFFFFFF;

  /// This entry's own directory/stream ID.
  final int index;
  final String name;
  final int objectType;
  final int leftSiblingId;
  final int rightSiblingId;
  final int childId;
  final int startingSectorLocation;
  final int streamSize;

  bool get isStorage => objectType == typeStorage || objectType == typeRoot;
  bool get isStream => objectType == typeStream;
}
