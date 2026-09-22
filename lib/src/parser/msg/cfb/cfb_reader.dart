import 'dart:typed_data';

import 'cfb_entry.dart';

/// Thrown when the given bytes are not a valid Compound File Binary (CFB)
/// container (i.e. not a `.msg` file).
class CfbFormatException implements Exception {
  CfbFormatException(this.message);
  final String message;

  @override
  String toString() => 'CfbFormatException: $message';
}

const List<int> _cfbSignature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

/// Returns true if [bytes] starts with the CFB magic number, i.e. this looks
/// like an OLE Compound File (`.msg`, `.doc`, `.xls`, ...) rather than plain
/// text (`.eml`).
bool looksLikeCompoundFile(Uint8List bytes) {
  if (bytes.length < _cfbSignature.length) return false;
  for (var i = 0; i < _cfbSignature.length; i++) {
    if (bytes[i] != _cfbSignature[i]) return false;
  }
  return true;
}

const int _freeSect = 0xFFFFFFFF;
const int _endOfChain = 0xFFFFFFFE;

/// A read-only reader for the Compound File Binary Format ([MS-CFB]) that
/// backs `.msg` (and legacy `.doc`/`.xls`) files: a small in-file FAT-based
/// filesystem of "storages" (folders) and "streams" (files).
class CompoundFile {
  CompoundFile._({
    required this.entries,
    required int miniStreamCutoff,
    required Uint8List Function(int startSector, int size) readChain,
    required Uint8List Function(int startMiniSector, int size) readMiniChain,
  })  : _miniStreamCutoff = miniStreamCutoff,
        _readChain = readChain,
        _readMiniChain = readMiniChain;

  final List<CfbEntry> entries;
  final int _miniStreamCutoff;
  final Uint8List Function(int startSector, int size) _readChain;
  final Uint8List Function(int startMiniSector, int size) _readMiniChain;

  CfbEntry get root => entries[0];

  factory CompoundFile.parse(Uint8List bytes) {
    if (!looksLikeCompoundFile(bytes)) {
      throw CfbFormatException('Missing CFB signature — not an OLE compound file');
    }
    final header = ByteData.sublistView(bytes, 0, 512);

    final sectorShift = header.getUint16(30, Endian.little);
    final numFatSectors = header.getUint32(44, Endian.little);
    final firstDirectorySector = header.getUint32(48, Endian.little);
    final miniStreamCutoff = header.getUint32(56, Endian.little);
    final firstMiniFatSector = header.getUint32(60, Endian.little);
    final numMiniFatSectors = header.getUint32(64, Endian.little);
    final firstDifatSector = header.getUint32(68, Endian.little);
    final numDifatSectors = header.getUint32(72, Endian.little);
    final miniSectorShift = header.getUint16(32, Endian.little);

    final sectorSize = 1 << sectorShift;
    final miniSectorSize = 1 << miniSectorShift;

    int sectorOffset(int sectorId) => (sectorId + 1) * sectorSize;
    Uint8List readSector(int sectorId) {
      final start = sectorOffset(sectorId);
      if (start >= bytes.length || sectorId < 0) return Uint8List(0);
      final end = (start + sectorSize).clamp(0, bytes.length);
      return Uint8List.sublistView(bytes, start, end);
    }

    // 1. Full DIFAT: the 109 entries embedded in the header, plus any
    // additional DIFAT sectors chained off `firstDifatSector`.
    final difat = <int>[];
    for (var i = 0; i < 109; i++) {
      final entry = header.getUint32(76 + i * 4, Endian.little);
      if (entry != _freeSect) difat.add(entry);
    }
    var difatSector = firstDifatSector;
    final entriesPerDifatSector = sectorSize ~/ 4;
    var difatSectorsRead = 0;
    while (difatSector != _endOfChain &&
        difatSector != _freeSect &&
        difatSectorsRead < numDifatSectors) {
      final sectorBytes = readSector(difatSector);
      if (sectorBytes.isEmpty) break;
      final data = ByteData.sublistView(sectorBytes);
      for (var i = 0; i < entriesPerDifatSector - 1; i++) {
        final entry = data.getUint32(i * 4, Endian.little);
        if (entry != _freeSect) difat.add(entry);
      }
      difatSector = data.getUint32((entriesPerDifatSector - 1) * 4, Endian.little);
      difatSectorsRead++;
    }

    // 2. FAT: concatenation of every FAT sector's 32-bit entries.
    final entriesPerSector = sectorSize ~/ 4;
    final fat = List<int>.filled(numFatSectors * entriesPerSector, _freeSect);
    for (var s = 0; s < numFatSectors && s < difat.length; s++) {
      final sectorBytes = readSector(difat[s]);
      if (sectorBytes.isEmpty) continue;
      final data = ByteData.sublistView(sectorBytes);
      for (var i = 0; i < entriesPerSector; i++) {
        fat[s * entriesPerSector + i] = data.getUint32(i * 4, Endian.little);
      }
    }

    Uint8List readChain(int startSector, int size) {
      if (size <= 0 || startSector == _endOfChain || startSector == _freeSect) {
        return Uint8List(0);
      }
      final out = BytesBuilder();
      var sector = startSector;
      var guard = 0;
      final maxSectors = fat.length + 1;
      while (sector != _endOfChain && sector != _freeSect && guard < maxSectors) {
        out.add(readSector(sector));
        if (sector < 0 || sector >= fat.length) break;
        sector = fat[sector];
        guard++;
      }
      final collected = out.toBytes();
      return size <= collected.length ? Uint8List.sublistView(collected, 0, size) : collected;
    }

    // 3. Directory entries. The directory stream's size isn't stored
    // anywhere but its own chain length, so read the whole chain and slice
    // it into 128-byte records.
    final dirBytes = () {
      final out = BytesBuilder();
      var sector = firstDirectorySector;
      var guard = 0;
      final maxSectors = fat.length + 1;
      while (sector != _endOfChain && sector != _freeSect && guard < maxSectors) {
        out.add(readSector(sector));
        if (sector < 0 || sector >= fat.length) break;
        sector = fat[sector];
        guard++;
      }
      return out.toBytes();
    }();

    final entryCount = dirBytes.length ~/ 128;
    final entries = <CfbEntry>[];
    for (var i = 0; i < entryCount; i++) {
      final base = i * 128;
      final nameLenBytes =
          ByteData.sublistView(dirBytes, base + 64, base + 66).getUint16(0, Endian.little);
      final nameChars = (nameLenBytes ~/ 2) - (nameLenBytes >= 2 ? 1 : 0);
      final name = nameChars > 0
          ? String.fromCharCodes(
              List<int>.generate(
                nameChars,
                (c) => ByteData.sublistView(dirBytes, base + c * 2, base + c * 2 + 2)
                    .getUint16(0, Endian.little),
              ),
            )
          : '';
      final objectType = dirBytes[base + 66];
      final data = ByteData.sublistView(dirBytes, base, base + 128);
      entries.add(
        CfbEntry(
          index: i,
          name: name,
          objectType: objectType,
          leftSiblingId: data.getUint32(68, Endian.little),
          rightSiblingId: data.getUint32(72, Endian.little),
          childId: data.getUint32(76, Endian.little),
          startingSectorLocation: data.getUint32(116, Endian.little),
          streamSize: data.getUint64(120, Endian.little),
        ),
      );
    }

    // 4. MiniFAT (chained via the regular FAT, same as any other stream).
    final miniFatBytes = readChain(firstMiniFatSector, numMiniFatSectors * sectorSize);
    final miniFat = List<int>.filled(miniFatBytes.length ~/ 4, _freeSect);
    final miniFatData = ByteData.sublistView(miniFatBytes);
    for (var i = 0; i < miniFat.length; i++) {
      miniFat[i] = miniFatData.getUint32(i * 4, Endian.little);
    }

    // 5. Mini stream (the root entry's own stream, holding every small
    // stream's bytes packed into `miniSectorSize`-byte chunks).
    final rootEntry = entries.isNotEmpty ? entries[0] : null;
    final miniStream = rootEntry == null
        ? Uint8List(0)
        : readChain(rootEntry.startingSectorLocation, rootEntry.streamSize);

    Uint8List readMiniChain(int startMiniSector, int size) {
      if (size <= 0 || startMiniSector == _endOfChain || startMiniSector == _freeSect) {
        return Uint8List(0);
      }
      final out = BytesBuilder();
      var sector = startMiniSector;
      var guard = 0;
      final maxSectors = miniFat.length + 1;
      while (sector != _endOfChain && sector != _freeSect && guard < maxSectors) {
        final start = sector * miniSectorSize;
        if (start < miniStream.length) {
          final end = (start + miniSectorSize).clamp(0, miniStream.length);
          out.add(Uint8List.sublistView(miniStream, start, end));
        }
        if (sector < 0 || sector >= miniFat.length) break;
        sector = miniFat[sector];
        guard++;
      }
      final collected = out.toBytes();
      return size <= collected.length ? Uint8List.sublistView(collected, 0, size) : collected;
    }

    return CompoundFile._(
      entries: entries,
      miniStreamCutoff: miniStreamCutoff,
      readChain: readChain,
      readMiniChain: readMiniChain,
    );
  }

  /// Reads a stream entry's full contents.
  Uint8List readStream(CfbEntry entry) {
    if (entry.streamSize <= 0) return Uint8List(0);
    if (entry.streamSize < _miniStreamCutoff) {
      return _readMiniChain(entry.startingSectorLocation, entry.streamSize);
    }
    return _readChain(entry.startingSectorLocation, entry.streamSize);
  }

  /// All entries directly contained in [storage] (its immediate children),
  /// resolved by walking the red-black tree rooted at [CfbEntry.childId].
  List<CfbEntry> childrenOf(CfbEntry storage) {
    final result = <CfbEntry>[];
    void visit(int id) {
      if (id == CfbEntry.noStream || id < 0 || id >= entries.length) return;
      final e = entries[id];
      visit(e.leftSiblingId);
      result.add(e);
      visit(e.rightSiblingId);
    }

    visit(storage.childId);
    return result;
  }

  /// The immediate child of [storage] named [name] (case-insensitive), or
  /// `null` if there is none.
  CfbEntry? findChild(CfbEntry storage, String name) {
    final target = name.toLowerCase();
    for (final child in childrenOf(storage)) {
      if (child.name.toLowerCase() == target) return child;
    }
    return null;
  }
}
