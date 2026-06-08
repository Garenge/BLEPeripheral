import 'ble_protocol_codec.dart';

class BleChunkReassembler {
  BleChunkReassembler({
    this.maxStreams = defaultBleMaxChunkStreams,
    this.maxPartsPerStream = defaultBleMaxChunkPartsPerStream,
    this.maxBufferedBytes = defaultBleMaxChunkBufferedBytes,
  }) : assert(maxStreams > 0),
       assert(maxPartsPerStream > 0),
       assert(maxBufferedBytes > 0);

  final int maxStreams;
  final int maxPartsPerStream;
  final int maxBufferedBytes;
  final Map<String, Map<int, List<int>>> _buffers = {};
  final Map<String, int> _counts = {};
  int _bufferedBytes = 0;

  int get activeStreams => _buffers.length;
  int get bufferedBytes => _bufferedBytes;

  BleChunkCaptureResult capture(BleChunkFragment chunk) {
    if (chunk.count > maxPartsPerStream) {
      return BleChunkCaptureResult.rejected('part-count-limit');
    }

    final trim = _trimForCountChange(chunk);
    final streamTrim = trim ?? _trimForStreamLimit(chunk.stream);
    final parts = _buffers.putIfAbsent(chunk.stream, () => {});
    _counts[chunk.stream] = chunk.count;

    final oldPart = parts[chunk.index];
    final nextBytes =
        _bufferedBytes -
        (oldPart == null ? 0 : oldPart.length) +
        chunk.bytes.length;
    if (nextBytes > maxBufferedBytes) {
      _dropStream(chunk.stream);
      return BleChunkCaptureResult.rejected('byte-limit');
    }

    parts[chunk.index] = chunk.bytes;
    _bufferedBytes = nextBytes;
    if (parts.length < chunk.count) {
      return BleChunkCaptureResult.partial(
        trimmedStream: streamTrim?.stream,
        trimReason: streamTrim?.reason,
      );
    }
    return BleChunkCaptureResult.complete(
      _reassembledChunkData(chunk.stream, chunk.count),
      trimmedStream: streamTrim?.stream,
      trimReason: streamTrim?.reason,
    );
  }

  void clear() {
    _buffers.clear();
    _counts.clear();
    _bufferedBytes = 0;
  }

  BleChunkTrim? _trimForCountChange(BleChunkFragment chunk) {
    final expectedCount = _counts[chunk.stream];
    if (expectedCount == null || expectedCount == chunk.count) {
      return null;
    }
    _dropStream(chunk.stream);
    return BleChunkTrim(chunk.stream, 'count-changed');
  }

  BleChunkTrim? _trimForStreamLimit(String stream) {
    if (_buffers.containsKey(stream) || _buffers.length < maxStreams) {
      return null;
    }
    final droppedStream = _buffers.keys.first;
    _dropStream(droppedStream);
    return BleChunkTrim(droppedStream, 'stream-limit');
  }

  List<int> _reassembledChunkData(String stream, int count) {
    final parts = _buffers[stream]!;
    final complete = <int>[];
    for (var index = 0; index < count; index += 1) {
      complete.addAll(parts[index]!);
    }
    _dropStream(stream);
    return complete;
  }

  void _dropStream(String stream) {
    final parts = _buffers.remove(stream);
    _counts.remove(stream);
    if (parts == null) {
      return;
    }
    final droppedBytes = parts.values.fold<int>(
      0,
      (total, part) => total + part.length,
    );
    _bufferedBytes = droppedBytes > _bufferedBytes
        ? 0
        : _bufferedBytes - droppedBytes;
  }
}

class BleChunkTrim {
  const BleChunkTrim(this.stream, this.reason);

  final String stream;
  final String reason;
}

class BleChunkCaptureResult {
  const BleChunkCaptureResult._({
    this.complete,
    this.trimmedStream,
    this.trimReason,
    this.rejectReason,
  });

  factory BleChunkCaptureResult.partial({
    String? trimmedStream,
    String? trimReason,
  }) {
    return BleChunkCaptureResult._(
      trimmedStream: trimmedStream,
      trimReason: trimReason,
    );
  }

  factory BleChunkCaptureResult.complete(
    List<int> complete, {
    String? trimmedStream,
    String? trimReason,
  }) {
    return BleChunkCaptureResult._(
      complete: complete,
      trimmedStream: trimmedStream,
      trimReason: trimReason,
    );
  }

  factory BleChunkCaptureResult.rejected(String reason) {
    return BleChunkCaptureResult._(rejectReason: reason);
  }

  final List<int>? complete;
  final String? trimmedStream;
  final String? trimReason;
  final String? rejectReason;

  bool get accepted => rejectReason == null;
}
