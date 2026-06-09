import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_chunk_reassembler.dart';
import 'ble_protocol_codec.dart';
import 'ble_request_status.dart';

const String demoPeripheralName = 'MacBLE-Demo';
const Duration _demoFlowStepDelay = Duration(milliseconds: 350);
const Duration _requestStatusTimeout = Duration(seconds: 12);
const String _demoFlowLongEchoText =
    'demo-flow long echo payload: pair info ping telemetry rule burst sample '
    'identify raw read; this string is intentionally long enough to exercise '
    'notify queue and chunk reassembly across clients. Flutter keeps the same '
    'flow as the Objective-C clients so the peripheral can compare sessions.';
final Guid demoServiceUuid = Guid('0000FFF0-0000-1000-8000-00805F9B34FB');
final Guid demoCharacteristicUuid = Guid(
  '0000FFF1-0000-1000-8000-00805F9B34FB',
);

class DiscoveredBleDevice {
  const DiscoveredBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.matchReason,
    required this.lastSeen,
    required this.serviceCount,
    required this.manufacturerDataCount,
    required this.serviceDataCount,
  });

  final String id;
  final String name;
  final int rssi;
  final String matchReason;
  final DateTime lastSeen;
  final int serviceCount;
  final int manufacturerDataCount;
  final int serviceDataCount;

  String get detailLabel {
    return 'RSSI $rssi | $matchReason | seen $_lastSeenLabel | adv services=$serviceCount msd=$manufacturerDataCount svcData=$serviceDataCount';
  }

  String get _lastSeenLabel {
    return '${lastSeen.hour.toString().padLeft(2, '0')}:'
        '${lastSeen.minute.toString().padLeft(2, '0')}:'
        '${lastSeen.second.toString().padLeft(2, '0')}';
  }
}

class BleCentralController extends ChangeNotifier {
  BleCentralController({bool enableBluetooth = true}) {
    if (!enableBluetooth) {
      _log('SYS init: Bluetooth disabled for widget test');
      return;
    }
    _subscriptions.add(
      FlutterBluePlus.adapterState.listen(_handleAdapterState),
    );
    _subscriptions.add(
      FlutterBluePlus.onScanResults.listen(_handleScanResults),
    );
    _log('SYS init: target service=FFF0 characteristic=FFF1');
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final BleProtocolCodec _protocolCodec = const BleProtocolCodec();
  final BleChunkReassembler _chunkReassembler = BleChunkReassembler();
  final Map<String, DiscoveredBleDevice> _devicesById = {};
  final Map<String, BleRequestStatus> _requestStatuses = {
    for (final definition in bleTrackedRequestDefinitions)
      definition.operation: BleRequestStatus.idle(
        operation: definition.operation,
        label: definition.label,
      ),
  };
  final Map<String, String> _pendingOperationByMessageId = {};
  final Map<String, Timer> _requestTimeouts = {};
  final List<String> logs = [];
  StreamSubscription<List<int>>? _valueSubscription;

  BluetoothAdapterState _adapterState = FlutterBluePlus.adapterStateNow;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? demoCharacteristic;
  bool isScanning = false;
  bool notifyEnabled = false;
  bool isDemoFlowRunning = false;
  int _protocolSequence = 0;
  int _demoFlowGeneration = 0;
  String? sessionToken;
  String? capabilitySummary;
  String eventRuleMode = 'normal';

  List<DiscoveredBleDevice> get devices {
    final devices = _devicesById.values.toList();
    devices.sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  List<BleRequestStatus> get requestStatuses {
    return [
      for (final definition in bleTrackedRequestDefinitions)
        _requestStatuses[definition.operation] ??
            BleRequestStatus.idle(
              operation: definition.operation,
              label: definition.label,
            ),
    ];
  }

  String get adapterLabel => 'Bluetooth: ${_adapterState.name}';

  bool get canRunDemoFlow {
    return demoCharacteristic != null &&
        connectedDevice != null &&
        !isDemoFlowRunning;
  }

  String get connectionLabel {
    final device = connectedDevice;
    if (device == null) {
      return 'Disconnected';
    }
    final name = _deviceName(device);
    final auth = sessionToken == null ? 'unpaired' : 'paired';
    final capabilities = capabilitySummary == null
        ? ''
        : ' | $capabilitySummary';
    return '$name ${notifyEnabled ? "Notify ON" : "Notify OFF"} $auth rule=$eventRuleMode$capabilities';
  }

  Future<void> startScan() async {
    if (_adapterState != BluetoothAdapterState.on) {
      _log('SYS startScan: Bluetooth is ${_adapterState.name}, cannot scan');
      return;
    }
    _devicesById.clear();
    isScanning = true;
    notifyListeners();
    await FlutterBluePlus.startScan(
      withServices: [demoServiceUuid],
      timeout: const Duration(seconds: 12),
    );
    _log('SCAN started: filtering service FFF0');
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    isScanning = false;
    _log('SCAN stopped');
    notifyListeners();
  }

  Future<void> connect(String remoteId) async {
    await stopScan();
    await disconnect();
    final device = BluetoothDevice.fromId(remoteId);
    _log('LINK connecting: ${_deviceName(device)} ($remoteId)');
    await device.connect(
      license: License.free,
      timeout: const Duration(seconds: 20),
      mtu: null,
    );
    connectedDevice = device;
    _watchConnection(device);
    _log('LINK connected: ${_deviceName(device)}');
    await _discoverDemoCharacteristic(device);
  }

  Future<void> disconnect() async {
    final device = connectedDevice;
    if (device == null) {
      return;
    }
    _log('LINK disconnect requested: ${_deviceName(device)}');
    await device.disconnect();
    _clearGattState();
  }

  Future<void> readValue() async {
    final characteristic = demoCharacteristic;
    if (characteristic == null) {
      _log('RX read skipped: characteristic missing');
      return;
    }
    final value = await characteristic.read();
    _logIncoming(value, 'RX read');
  }

  Future<void> writeText(String text) async {
    await sendEcho(text);
  }

  Future<void> sendPairCode(String code) async {
    await _sendProtocol('pair', {'code': code}, includeToken: false);
  }

  Future<void> sendPing() async {
    await _sendProtocol('ping', const {}, includeToken: false);
  }

  Future<void> sendInfo() async {
    await _sendProtocol('getInfo', const {}, includeToken: false);
  }

  Future<void> sendEcho(String text) async {
    await _sendProtocol('echo', {'text': text}, includeToken: true);
  }

  Future<void> sendTelemetry() async {
    await _sendProtocol('telemetry', const {}, includeToken: true);
  }

  Future<void> sendCommand(String name) async {
    await _sendProtocol('command', {'name': name}, includeToken: true);
  }

  Future<void> sendEventRuleMode(String mode) async {
    await _sendProtocol('command', {
      'name': 'setEventRule',
      'mode': mode,
    }, includeToken: true);
  }

  Future<void> sendRawText(String text) async {
    final characteristic = demoCharacteristic;
    if (characteristic == null) {
      _log('TX write skipped: characteristic missing');
      return;
    }
    final payload = utf8.encode(text);
    await characteristic.write(payload, withoutResponse: false);
    _log('TX raw write: ${payload.length} B text="$text"');
  }

  void clearLogs() {
    logs.clear();
    _log('SYS logs cleared');
  }

  Future<void> runDemoFlow() async {
    if (demoCharacteristic == null || connectedDevice == null) {
      _log('FLOW demo flow skipped: characteristic missing');
      return;
    }
    if (isDemoFlowRunning) {
      _log('FLOW demo flow skipped: already running');
      return;
    }
    isDemoFlowRunning = true;
    final generation = ++_demoFlowGeneration;
    _log(
      'FLOW demo flow started: pair/info/ping/echo/telemetry/rules/commands/raw/read',
    );
    try {
      await _runDemoFlowSteps(generation);
      if (_isCurrentDemoFlow(generation)) {
        _log('FLOW demo flow queued');
      }
    } catch (error) {
      if (_isCurrentDemoFlow(generation)) {
        _log('FLOW demo flow failed: $error');
      }
    } finally {
      if (_isCurrentDemoFlow(generation)) {
        isDemoFlowRunning = false;
        notifyListeners();
      }
    }
  }

  Future<void> _sendProtocol(
    String operation,
    Map<String, Object?> body, {
    required bool includeToken,
  }) async {
    final characteristic = demoCharacteristic;
    if (characteristic == null) {
      _setRequestFailed(operation, 'Characteristic missing');
      _log('TX protocol $operation skipped: characteristic missing');
      return;
    }
    _protocolSequence += 1;
    final messageId = 'flutter-$_protocolSequence';
    final payload = _protocolCodec.encodeRequest(
      operation: operation,
      messageId: messageId,
      body: body,
      token: includeToken ? sessionToken : null,
    );
    _setRequestSending(operation, messageId);
    try {
      await characteristic.write(payload, withoutResponse: false);
      _log(
        'TX protocol $operation: ${payload.length} B token=${includeToken && sessionToken != null ? "yes" : "no"}',
      );
    } catch (error) {
      _setRequestFailed(operation, 'Write failed: $error', messageId);
      _log('TX protocol $operation failed: $error');
    }
  }

  Future<void> setNotify(bool enabled) async {
    final characteristic = demoCharacteristic;
    if (characteristic == null) {
      _log('SYS notify skipped: characteristic missing');
      return;
    }
    await characteristic.setNotifyValue(enabled);
    notifyEnabled = enabled;
    _log(enabled ? 'LINK notify ON' : 'LINK notify OFF');
    notifyListeners();
  }

  Future<void> _demoDelay() {
    return Future<void>.delayed(_demoFlowStepDelay);
  }

  Future<void> _runDemoFlowSteps(int generation) async {
    final steps = <Future<void> Function()>[
      () => setNotify(true),
      () => sendPairCode(bleDefaultPairCode),
      sendInfo,
      sendPing,
      () => sendEcho(_demoFlowLongEchoText),
      sendTelemetry,
      () => sendEventRuleMode('burst'),
      () => sendCommand('sample'),
      () => sendEventRuleMode('normal'),
      () => sendCommand('identify'),
      () => sendRawText('demo raw legacy payload'),
      readValue,
    ];
    for (var index = 0; index < steps.length; index += 1) {
      if (!_isCurrentDemoFlow(generation)) {
        return;
      }
      await steps[index]();
      if (index < steps.length - 1) {
        await _demoDelay();
      }
    }
  }

  bool _isCurrentDemoFlow(int generation) {
    return isDemoFlowRunning &&
        _demoFlowGeneration == generation &&
        demoCharacteristic != null &&
        connectedDevice != null;
  }

  void _cancelDemoFlow(String reason) {
    _demoFlowGeneration += 1;
    if (!isDemoFlowRunning) {
      return;
    }
    isDemoFlowRunning = false;
    _log('FLOW demo flow cancelled: $reason');
  }

  @override
  void dispose() {
    _cancelDemoFlow('controller disposed');
    _cancelValueSubscription();
    _cancelAllRequestTimers();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @visibleForTesting
  void debugHandleIncoming(List<int> value) {
    _logIncoming(value, 'RX test');
  }

  @visibleForTesting
  void debugMarkRequestSending(String operation, String messageId) {
    _setRequestSending(operation, messageId);
  }

  void _handleAdapterState(BluetoothAdapterState state) {
    _adapterState = state;
    _log('SYS adapter state: ${state.name}');
    notifyListeners();
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final name = _resultName(result);
      if (name.isNotEmpty && name != demoPeripheralName) {
        continue;
      }
      final id = result.device.remoteId.str;
      final previous = _devicesById[id];
      final matchReason = _scanMatchReason(result, name);
      _devicesById[id] = DiscoveredBleDevice(
        id: id,
        name: name.isEmpty ? '(unknown)' : name,
        rssi: result.rssi,
        matchReason: matchReason,
        lastSeen: DateTime.now(),
        serviceCount: result.advertisementData.serviceUuids.length,
        manufacturerDataCount: result.advertisementData.manufacturerData.length,
        serviceDataCount: result.advertisementData.serviceData.length,
      );
      if (previous == null || (previous.rssi - result.rssi).abs() >= 8) {
        final action = previous == null ? 'found' : 'updated';
        _log(
          'SCAN $action: ${name.isEmpty ? id : name} RSSI=${result.rssi} match=$matchReason',
        );
      }
    }
    notifyListeners();
  }

  void _watchConnection(BluetoothDevice device) {
    final subscription = device.connectionState.listen((state) {
      _log('LINK state: ${state.name}');
      if (state == BluetoothConnectionState.disconnected) {
        _clearGattState();
      }
    });
    device.cancelWhenDisconnected(subscription, delayed: true);
  }

  Future<void> _discoverDemoCharacteristic(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final service = services
        .where((item) => item.uuid == demoServiceUuid)
        .firstOrNull;
    if (service == null) {
      _log('GATT service FFF0 not found');
      return;
    }
    _log('GATT service discovered: ${service.uuid.str}');

    final characteristic = service.characteristics
        .where((item) => item.uuid == demoCharacteristicUuid)
        .firstOrNull;
    if (characteristic == null) {
      _log('GATT characteristic FFF1 not found');
      return;
    }
    demoCharacteristic = characteristic;
    _log('GATT characteristic ready: ${characteristic.uuid.str}');
    _cancelValueSubscription();
    _valueSubscription = characteristic.onValueReceived.listen((value) {
      _logIncoming(value, 'RX notify/read');
    });
    await setNotify(true);
    await readValue();
    await sendPairCode(bleDefaultPairCode);
    await sendInfo();
    notifyListeners();
  }

  void _clearGattState() {
    _cancelDemoFlow('connection cleared');
    connectedDevice = null;
    demoCharacteristic = null;
    notifyEnabled = false;
    sessionToken = null;
    capabilitySummary = null;
    eventRuleMode = 'normal';
    _resetRequestStatuses();
    _cancelValueSubscription();
    _chunkReassembler.clear();
    notifyListeners();
  }

  void _cancelValueSubscription() {
    final subscription = _valueSubscription;
    _valueSubscription = null;
    unawaited(subscription?.cancel());
  }

  void _logIncoming(List<int> value, String label) {
    final decoded = _protocolCodec.decode(value);
    if (decoded.kind == BleDecodedMessageKind.legacyEcho) {
      _log(
        '$label echo: prefix=00AA body=${decoded.body.length} B text="${decoded.text}"',
      );
      return;
    }
    if (decoded.kind == BleDecodedMessageKind.protocol) {
      final envelope = decoded.envelope!;
      if (_handleChunkEnvelope(envelope, label)) {
        return;
      }
      _captureSessionToken(decoded.token);
      final operation = envelope['op'];
      _log('$label protocol: ${_protocolCodec.summaryForProtocol(envelope)}');
      if (envelope['body'] is Map) {
        _captureBodyState(operation, envelope['body'] as Map);
        _log(
          '${operation == "event" ? "EVT" : "RX"} body=${jsonEncode(envelope['body'])}',
        );
      }
      _captureRequestStatus(envelope);
      return;
    }
    _log('$label raw: ${decoded.bytes.length} B text="${decoded.text}"');
  }

  bool _handleChunkEnvelope(Map<String, dynamic> envelope, String label) {
    final chunk = _protocolCodec.chunkFragmentFromEnvelope(envelope);
    if (envelope['op'] != bleProtocolOpChunk) {
      return false;
    }
    if (chunk == null) {
      _log('$label chunk invalid');
      return true;
    }
    final complete = _captureChunk(chunk, label);
    if (complete != null) {
      _logIncoming(complete, '$label chunk');
    }
    return true;
  }

  List<int>? _captureChunk(BleChunkFragment chunk, String label) {
    final result = _chunkReassembler.capture(chunk);
    if (result.trimmedStream != null) {
      _log(
        '$label chunk cache trimmed: stream=${result.trimmedStream} reason=${result.trimReason}',
      );
    }
    if (!result.accepted) {
      _log(
        '$label chunk dropped: stream=${chunk.stream} reason=${result.rejectReason}',
      );
      return null;
    }
    _log(
      '$label chunk: stream=${chunk.stream} part=${chunk.index + 1}/${chunk.count} bytes=${chunk.bytes.length}',
    );
    if (result.complete != null) {
      _log(
        'RX chunk complete: stream=${chunk.stream} bytes=${result.complete!.length}',
      );
    }
    return result.complete;
  }

  void _captureSessionToken(String? token) {
    if (token != null && token.isNotEmpty && token != sessionToken) {
      sessionToken = token;
      _log('AUTH token captured: $token');
      notifyListeners();
    }
  }

  void _setRequestSending(String operation, String messageId) {
    final status = _requestStatuses[operation];
    if (status == null) {
      return;
    }
    _cancelRequestTimer(operation);
    _dropPendingRequestsForOperation(operation);
    _pendingOperationByMessageId[messageId] = operation;
    _requestStatuses[operation] = status.copyWith(
      phase: BleRequestPhase.sending,
      detail: 'Waiting for response',
      messageId: messageId,
      updatedAt: DateTime.now(),
    );
    _requestTimeouts[operation] = Timer(_requestStatusTimeout, () {
      final current = _requestStatuses[operation];
      if (current?.phase == BleRequestPhase.sending &&
          current?.messageId == messageId) {
        _setRequestFailed(
          operation,
          'Timed out waiting for response',
          messageId,
        );
      }
    });
    notifyListeners();
  }

  void _setRequestSucceeded(
    String operation,
    String detail, [
    String? messageId,
  ]) {
    final status = _requestStatuses[operation];
    if (status == null) {
      return;
    }
    _clearPendingRequest(operation, messageId);
    _requestStatuses[operation] = status.copyWith(
      phase: BleRequestPhase.succeeded,
      detail: detail,
      messageId: messageId,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void _setRequestFailed(String operation, String detail, [String? messageId]) {
    final status = _requestStatuses[operation];
    if (status == null) {
      return;
    }
    _clearPendingRequest(operation, messageId);
    _requestStatuses[operation] = status.copyWith(
      phase: BleRequestPhase.failed,
      detail: detail,
      messageId: messageId,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void _captureRequestStatus(Map<String, dynamic> envelope) {
    final operation = _operationForResponse(envelope);
    if (operation == null) {
      return;
    }
    final messageId = _stringValue(envelope['id']);
    final error = envelope['err'];
    if (envelope['ok'] == false || error is Map) {
      _setRequestFailed(operation, _errorDetail(error), messageId);
      return;
    }
    final body = envelope['body'];
    if (operation == 'command' && body is Map && body['accepted'] == false) {
      _setRequestFailed(operation, _commandRejectedDetail(body), messageId);
      return;
    }
    _setRequestSucceeded(
      operation,
      _successDetail(operation, envelope),
      messageId,
    );
  }

  String? _operationForResponse(Map<String, dynamic> envelope) {
    final messageId = _stringValue(envelope['id']);
    if (messageId != null) {
      return _pendingOperationByMessageId[messageId];
    }
    return switch (envelope['op']) {
      'paired' => 'pair',
      'info' => 'getInfo',
      'pong' => 'ping',
      'echo' => 'echo',
      'telemetry' => 'telemetry',
      'commandResult' => 'command',
      _ => null,
    };
  }

  String _successDetail(String operation, Map<String, dynamic> envelope) {
    final body = envelope['body'];
    return switch (operation) {
      'pair' =>
        _protocolCodec.tokenFromEnvelope(envelope) == null
            ? 'Paired'
            : 'Paired, token captured',
      'getInfo' => 'Capabilities loaded',
      'ping' => 'Pong received',
      'echo' =>
        body is Map && body['text'] is String
            ? 'Echo "${_shortText(body['text'] as String)}"'
            : 'Echo received',
      'telemetry' =>
        body is Map
            ? 'reads=${body['reads'] ?? '-'} writes=${body['writes'] ?? '-'} notifies=${body['notifies'] ?? '-'} events=${body['events'] ?? '-'}'
            : 'Telemetry received',
      'command' =>
        body is Map && body['name'] is String
            ? '${body['name']} accepted'
            : 'Command accepted',
      _ => 'Response received',
    };
  }

  String _errorDetail(Object? error) {
    if (error is Map) {
      final code = error['code'] ?? 'error';
      final message = error['message'] ?? 'Request failed';
      return '$code: $message';
    }
    return 'Request failed';
  }

  String _commandRejectedDetail(Map<dynamic, dynamic> body) {
    final name = body['name'] ?? 'command';
    final message = body['message'] ?? 'Command rejected';
    return '$name rejected: $message';
  }

  String? _stringValue(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  String _shortText(String text) {
    if (text.length <= 40) {
      return text;
    }
    return '${text.substring(0, 37)}...';
  }

  void _clearPendingRequest(String operation, String? messageId) {
    _cancelRequestTimer(operation);
    if (messageId != null) {
      _pendingOperationByMessageId.remove(messageId);
    }
  }

  void _dropPendingRequestsForOperation(String operation) {
    _pendingOperationByMessageId.removeWhere((_, value) => value == operation);
  }

  void _cancelRequestTimer(String operation) {
    final timer = _requestTimeouts.remove(operation);
    timer?.cancel();
  }

  void _cancelAllRequestTimers() {
    for (final timer in _requestTimeouts.values) {
      timer.cancel();
    }
    _requestTimeouts.clear();
    _pendingOperationByMessageId.clear();
  }

  void _resetRequestStatuses() {
    _cancelAllRequestTimers();
    for (final definition in bleTrackedRequestDefinitions) {
      _requestStatuses[definition.operation] = BleRequestStatus.idle(
        operation: definition.operation,
        label: definition.label,
      );
    }
  }

  void _captureBodyState(Object? operation, Map<dynamic, dynamic> body) {
    bool changed = false;
    final mode = _protocolCodec.eventRuleModeFromBody(body);
    if (mode != null && mode != eventRuleMode) {
      eventRuleMode = mode;
      _log('RULE mode=$eventRuleMode');
      changed = true;
    }
    if (operation == 'info') {
      final summary = _protocolCodec.capabilitySummaryForInfoBody(body);
      capabilitySummary = summary;
      _log('CAP $summary');
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  String _resultName(ScanResult result) {
    return result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
  }

  String _scanMatchReason(ScanResult result, String name) {
    final reasons = <String>[];
    if (result.advertisementData.serviceUuids.contains(demoServiceUuid)) {
      reasons.add('service FFF0');
    }
    if (name == demoPeripheralName) {
      reasons.add('name');
    }
    if (reasons.isEmpty) {
      reasons.add('service filter');
    }
    return reasons.join('+');
  }

  String _deviceName(BluetoothDevice device) {
    if (device.advName.isNotEmpty) {
      return device.advName;
    }
    if (device.platformName.isNotEmpty) {
      return device.platformName;
    }
    return device.remoteId.str;
  }

  void _log(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    logs.add('[$timestamp] $message');
    if (logs.length > 300) {
      logs.removeAt(0);
    }
    notifyListeners();
  }
}
