import 'dart:convert';
import 'dart:typed_data';

import 'cfb/cfb_entry.dart';
import 'cfb/cfb_reader.dart';
import 'mapi_properties.dart';

class _RawProperty {
  const _RawProperty(this.type, this.fixedOrSizeBytes);

  final int type;

  /// For fixed-length types: the raw 8-byte value slot.
  /// For variable-length types: 4-byte declared size + 4 bytes reserved.
  final Uint8List fixedOrSizeBytes;
}

/// Reads MAPI properties out of one CFB storage's `__properties_version1.0`
/// stream (plus the per-property value streams for variable-length types),
/// per [MS-OXMSG] 2.4.
class MapiPropertyReader {
  MapiPropertyReader._(this._cf, this._storage, this._properties);

  final CompoundFile _cf;
  final CfbEntry _storage;
  final Map<int, _RawProperty> _properties;

  static const String _propertiesStreamName = '__properties_version1.0';

  /// Header sizes per [MS-OXMSG] 2.4.2, before the first 16-byte property
  /// row: 32 bytes for the top-level Message object, 24 bytes for an
  /// embedded message, 8 bytes for Attachment/Recipient objects.
  static const int topLevelHeaderSize = 32;
  static const int embeddedMessageHeaderSize = 24;
  static const int attachmentOrRecipientHeaderSize = 8;

  factory MapiPropertyReader.read(
    CompoundFile cf,
    CfbEntry storage, {
    required int headerSize,
  }) {
    final stream = cf.findChild(storage, _propertiesStreamName);
    final properties = <int, _RawProperty>{};
    if (stream != null) {
      final bytes = cf.readStream(stream);
      var offset = headerSize;
      while (offset + 16 <= bytes.length) {
        final row = ByteData.sublistView(bytes, offset, offset + 16);
        final type = row.getUint16(0, Endian.little);
        final id = row.getUint16(2, Endian.little);
        final valueBytes = Uint8List.sublistView(bytes, offset + 8, offset + 16);
        properties[id] = _RawProperty(type, valueBytes);
        offset += 16;
      }
    }
    return MapiPropertyReader._(cf, storage, properties);
  }

  bool has(int propertyId) => _properties.containsKey(propertyId);

  int? getInt(int propertyId) {
    final prop = _properties[propertyId];
    if (prop == null) return null;
    final data = ByteData.sublistView(prop.fixedOrSizeBytes);
    return switch (prop.type) {
      MapiType.i2 => data.getInt16(0, Endian.little),
      MapiType.long => data.getInt32(0, Endian.little),
      MapiType.i8 => data.getInt64(0, Endian.little),
      _ => null,
    };
  }

  bool? getBool(int propertyId) {
    final prop = _properties[propertyId];
    if (prop == null || prop.type != MapiType.boolean) return null;
    return ByteData.sublistView(prop.fixedOrSizeBytes).getInt16(0, Endian.little) != 0;
  }

  DateTime? getDateTime(int propertyId) {
    final prop = _properties[propertyId];
    if (prop == null || prop.type != MapiType.sysTime) return null;
    final fileTime = ByteData.sublistView(prop.fixedOrSizeBytes).getUint64(0, Endian.little);
    return _fileTimeToDateTime(fileTime);
  }

  /// Decodes a string property, preferring the value however it was
  /// actually stored (`PT_UNICODE` UTF-16LE, or `PT_STRING8` 8-bit).
  String? getString(int propertyId) {
    final prop = _properties[propertyId];
    if (prop == null) return null;
    final bytes = _readValueStream(propertyId, prop.type);
    if (bytes == null) return null;
    if (prop.type == MapiType.unicode) {
      return _decodeUtf16Le(bytes);
    }
    if (prop.type == MapiType.string8) {
      // PT_STRING8 is codepage-dependent; UTF-8 covers modern senders and
      // falls back to Latin-1 (a superset of the common Windows-1252 range)
      // for anything that isn't valid UTF-8.
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    }
    return null;
  }

  Uint8List? getBinary(int propertyId) {
    final prop = _properties[propertyId];
    if (prop == null) return null;
    return _readValueStream(propertyId, prop.type);
  }

  Uint8List? _readValueStream(int propertyId, int type) {
    final streamName =
        '__substg1.0_${propertyId.toRadixString(16).padLeft(4, '0').toUpperCase()}'
        '${type.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    final entry = _cf.findChild(_storage, streamName);
    if (entry == null) return null;
    return _cf.readStream(entry);
  }

  static String _decodeUtf16Le(Uint8List bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  /// Converts a Windows FILETIME (100-ns intervals since 1601-01-01 UTC)
  /// into a UTC [DateTime].
  static DateTime _fileTimeToDateTime(int fileTime) {
    const epochDiffMicroseconds = 11644473600000000; // 1601-01-01 -> 1970-01-01
    final microseconds = (fileTime ~/ 10) - epochDiffMicroseconds;
    return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
  }
}
