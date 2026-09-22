import 'dart:convert';
import 'dart:typed_data';

/// Builds a minimal-but-valid [MS-CFB] compound file from a tree description,
/// so `MsgParser` can be exercised against a real binary layout without
/// needing to check a proprietary Outlook `.msg` fixture into the repo.
///
/// Simplifications versus a real Outlook file (all still spec-legal):
/// - The mini-stream is disabled (`miniStreamCutoffSize = 0`), so every
///   stream — however small — is stored via the regular FAT, not MiniFAT.
///   This keeps the builder from also having to reimplement MiniFAT.
/// - Sibling "trees" are built as simple right-leaning chains rather than
///   balanced red-black trees. [CompoundFile.childrenOf] does a plain
///   left/self/right walk, so any binary tree shape containing the same
///   nodes reproduces the same children list.
class CfbNode {
  CfbNode.stream(this.name, this.bytes)
      : objectType = _typeStream,
        children = const [];

  CfbNode.storage(this.name, this.children)
      : objectType = _typeStorage,
        bytes = null;

  CfbNode.root(this.children)
      : name = 'Root Entry',
        objectType = _typeRoot,
        bytes = null;

  static const int _typeStorage = 1;
  static const int _typeStream = 2;
  static const int _typeRoot = 5;
  static const int _noStream = 0xFFFFFFFF;
  static const int _endOfChain = 0xFFFFFFFE;
  static const int _fatSect = 0xFFFFFFFD;

  final String name;
  final int objectType;
  final Uint8List? bytes;
  final List<CfbNode> children;

  int id = -1;
  int leftSiblingId = _noStream;
  int rightSiblingId = _noStream;
  int childId = _noStream;
  int startingSectorLocation = _endOfChain;
  int streamSize = 0;

  static Uint8List build(CfbNode root) {
    final all = <CfbNode>[];
    void flatten(CfbNode n) {
      n.id = all.length;
      all.add(n);
      for (final c in n.children) {
        flatten(c);
      }
    }

    flatten(root);

    for (final n in all) {
      if (n.children.isEmpty) continue;
      n.childId = n.children.first.id;
      for (var i = 0; i < n.children.length; i++) {
        n.children[i].rightSiblingId = i + 1 < n.children.length ? n.children[i + 1].id : _noStream;
      }
    }

    const sectorSize = 512;
    final dirSectorCount = (all.length / 4).ceil();
    final dataStart = 1 + dirSectorCount; // sector 0 = FAT sector

    var nextDataSector = dataStart;
    final dataSectorRanges = <CfbNode, int>{};
    for (final n in all) {
      final bytes = n.bytes;
      if (bytes == null || bytes.isEmpty) {
        n.streamSize = 0;
        n.startingSectorLocation = _endOfChain;
        continue;
      }
      final sectorsNeeded = (bytes.length / sectorSize).ceil();
      dataSectorRanges[n] = nextDataSector;
      n.startingSectorLocation = nextDataSector;
      n.streamSize = bytes.length;
      nextDataSector += sectorsNeeded;
    }
    final totalSectors = nextDataSector;

    final fat = List<int>.filled(totalSectors, _noStream);
    fat[0] = _fatSect;
    for (var i = 0; i < dirSectorCount; i++) {
      final sector = 1 + i;
      fat[sector] = i == dirSectorCount - 1 ? _endOfChain : sector + 1;
    }
    for (final entry in dataSectorRanges.entries) {
      final node = entry.key;
      final first = entry.value;
      final sectorsNeeded = (node.bytes!.length / sectorSize).ceil();
      for (var j = 0; j < sectorsNeeded; j++) {
        final sector = first + j;
        fat[sector] = j == sectorsNeeded - 1 ? _endOfChain : sector + 1;
      }
    }

    final totalFileSize = 512 + totalSectors * sectorSize;
    final file = Uint8List(totalFileSize);
    final header = ByteData.sublistView(file, 0, 512);

    const signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    for (var i = 0; i < signature.length; i++) {
      file[i] = signature[i];
    }
    header.setUint16(26, 3, Endian.little); // major version
    header.setUint16(28, 0xFFFE, Endian.little); // byte order
    header.setUint16(30, 9, Endian.little); // sector shift -> 512
    header.setUint16(32, 6, Endian.little); // mini sector shift -> 64
    header.setUint32(44, 1, Endian.little); // num FAT sectors
    header.setUint32(48, 1, Endian.little); // first directory sector
    header.setUint32(56, 0, Endian.little); // mini stream cutoff (disabled)
    header.setUint32(60, _endOfChain, Endian.little); // first mini FAT sector
    header.setUint32(64, 0, Endian.little); // num mini FAT sectors
    header.setUint32(68, _endOfChain, Endian.little); // first DIFAT sector
    header.setUint32(72, 0, Endian.little); // num DIFAT sectors
    header.setUint32(76, 0, Endian.little); // DIFAT[0] -> FAT sector 0
    for (var i = 1; i < 109; i++) {
      header.setUint32(76 + i * 4, _noStream, Endian.little);
    }

    void writeSector(int sectorId, Uint8List data, [int offset = 0]) {
      final base = 512 + sectorId * sectorSize;
      file.setRange(base + offset, base + offset + data.length, data);
    }

    // FAT sector.
    final fatSectorBytes = Uint8List(sectorSize);
    final fatData = ByteData.sublistView(fatSectorBytes);
    for (var i = 0; i < sectorSize ~/ 4; i++) {
      fatData.setUint32(i * 4, i < fat.length ? fat[i] : _noStream, Endian.little);
    }
    writeSector(0, fatSectorBytes);

    // Directory sectors: 4 entries (128 bytes each) per 512-byte sector.
    for (var s = 0; s < dirSectorCount; s++) {
      final sectorBytes = Uint8List(sectorSize);
      for (var k = 0; k < 4; k++) {
        final globalIndex = s * 4 + k;
        if (globalIndex >= all.length) continue;
        final record = _encodeDirEntry(all[globalIndex]);
        sectorBytes.setRange(k * 128, k * 128 + 128, record);
      }
      writeSector(1 + s, sectorBytes);
    }

    // Data sectors.
    for (final entry in dataSectorRanges.entries) {
      final node = entry.key;
      final first = entry.value;
      final bytes = node.bytes!;
      var remaining = bytes.length;
      var offset = 0;
      var sector = first;
      while (remaining > 0) {
        final chunkLen = remaining > sectorSize ? sectorSize : remaining;
        writeSector(sector, Uint8List.sublistView(bytes, offset, offset + chunkLen));
        remaining -= chunkLen;
        offset += chunkLen;
        sector++;
      }
    }

    return file;
  }

  static Uint8List _encodeDirEntry(CfbNode node) {
    final record = Uint8List(128);
    final data = ByteData.sublistView(record);
    final nameUnits = node.name.codeUnits;
    for (var i = 0; i < nameUnits.length && i < 32; i++) {
      data.setUint16(i * 2, nameUnits[i], Endian.little);
    }
    final nameLenField = nameUnits.isEmpty ? 0 : (nameUnits.length + 1) * 2;
    data.setUint16(64, nameLenField, Endian.little);
    record[66] = node.objectType;
    record[67] = 1; // color flag, unused by the reader
    data.setUint32(68, node.leftSiblingId, Endian.little);
    data.setUint32(72, node.rightSiblingId, Endian.little);
    data.setUint32(76, node.childId, Endian.little);
    data.setUint32(116, node.startingSectorLocation, Endian.little);
    data.setUint64(120, node.streamSize, Endian.little);
    return record;
  }
}

Uint8List utf16le(String s) {
  final out = Uint8List(s.length * 2);
  final data = ByteData.sublistView(out);
  for (var i = 0; i < s.length; i++) {
    data.setUint16(i * 2, s.codeUnitAt(i), Endian.little);
  }
  return out;
}

Uint8List u32le(int value) {
  final out = Uint8List(4);
  ByteData.sublistView(out).setUint32(0, value, Endian.little);
  return out;
}

Uint8List u64le(int value) {
  final out = Uint8List(8);
  ByteData.sublistView(out).setUint64(0, value, Endian.little);
  return out;
}

/// Builds a `__properties_version1.0` stream: [headerSize] reserved bytes
/// followed by one 16-byte row per entry in [rows].
Uint8List propertiesStream(int headerSize, List<PropRow> rows) {
  final out = BytesBuilder();
  out.add(Uint8List(headerSize));
  for (final row in rows) {
    out.add(row.encode());
  }
  return out.toBytes();
}

/// One row of a MAPI properties stream.
class PropRow {
  PropRow.string8(this.id, String value)
      : type = 0x001E,
        _valueLength = utf8.encode(value).length;

  PropRow.unicode(this.id, String value)
      : type = 0x001F,
        _valueLength = value.length * 2;

  PropRow.binary(this.id, Uint8List value)
      : type = 0x0102,
        _valueLength = value.length;

  PropRow.long(this.id, int value)
      : type = 0x0003,
        _fixedValue = value;

  PropRow.sysTime(this.id, int fileTimeValue)
      : type = 0x0040,
        _fixedValue = fileTimeValue,
        _isSysTime = true;

  final int id;
  final int type;
  int? _fixedValue;
  int? _valueLength;
  bool _isSysTime = false;

  Uint8List encode() {
    final row = Uint8List(16);
    final data = ByteData.sublistView(row);
    data.setUint16(0, type, Endian.little);
    data.setUint16(2, id, Endian.little);
    data.setUint32(4, 0, Endian.little); // flags
    if (_valueLength != null) {
      data.setUint32(8, _valueLength!, Endian.little);
      data.setUint32(12, 0, Endian.little);
    } else if (_isSysTime) {
      data.setUint64(8, _fixedValue!, Endian.little);
    } else {
      data.setInt32(8, _fixedValue!, Endian.little);
      data.setUint32(12, 0, Endian.little);
    }
    return row;
  }
}

/// The `__substg1.0_XXXXTTTT` stream name for property [id] of MAPI type
/// [type], per [MS-OXMSG] 2.4.3.
String substgName(int id, int type) =>
    '__substg1.0_${id.toRadixString(16).padLeft(4, '0').toUpperCase()}${type.toRadixString(16).padLeft(4, '0').toUpperCase()}';

/// Windows FILETIME (100ns ticks since 1601-01-01 UTC) for [dateTime].
int toFileTime(DateTime dateTime) {
  const epochDiffMicroseconds = 11644473600000000;
  return (dateTime.toUtc().microsecondsSinceEpoch + epochDiffMicroseconds) * 10;
}
