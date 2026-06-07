import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_protocol_codec.dart';

const String demoPeripheralName = 'MacBLE-Demo';
final Guid demoServiceUuid = Guid('0000FFF0-0000-1000-8000-00805F9B34FB');
final Guid demoCharacteristicUuid = Guid(
  '0000FFF1-0000-1000-8000-00805F9B34FB',
);

class DiscoveredBleDevice {
  const DiscoveredBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
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
  final Map<String, DiscoveredBleDevice> _devicesById = {};
  final List<String> logs = [];

  BluetoothAdapterState _adapterState = FlutterBluePlus.adapterStateNow;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? demoCharacteristic;
  bool isScanning = false;
  bool notifyEnabled = false;
  int _protocolSequence = 0;
  String? sessionToken;
  String? capabilitySummary;

  List<DiscoveredBleDevice> get devices => _devicesById.values.toList();

  String get adapterLabel => 'Bluetooth: ${_adapterState.name}';

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
    return '$name ${notifyEnabled ? "Notify ON" : "Notify OFF"} $auth$capabilities';
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

  Future<void> _sendProtocol(
    String operation,
    Map<String, Object?> body, {
    required bool includeToken,
  }) async {
    final characteristic = demoCharacteristic;
    if (characteristic == null) {
      _log('TX protocol $operation skipped: characteristic missing');
      return;
    }
    _protocolSequence += 1;
    final payload = _protocolCodec.encodeRequest(
      operation: operation,
      messageId: 'flutter-$_protocolSequence',
      body: body,
      token: includeToken ? sessionToken : null,
    );
    await characteristic.write(payload, withoutResponse: false);
    _log(
      'TX protocol $operation: ${payload.length} B token=${includeToken && sessionToken != null ? "yes" : "no"}',
    );
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

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
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
      _devicesById[id] = DiscoveredBleDevice(
        id: id,
        name: name.isEmpty ? '(unknown)' : name,
        rssi: result.rssi,
      );
      _log('SCAN found: ${name.isEmpty ? id : name} RSSI=${result.rssi}');
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
    _subscriptions.add(
      characteristic.onValueReceived.listen((value) {
        _logIncoming(value, 'RX notify/read');
      }),
    );
    await setNotify(true);
    await readValue();
    await sendPairCode(bleDefaultPairCode);
    await sendInfo();
    notifyListeners();
  }

  void _clearGattState() {
    connectedDevice = null;
    demoCharacteristic = null;
    notifyEnabled = false;
    sessionToken = null;
    capabilitySummary = null;
    notifyListeners();
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
      _captureSessionToken(decoded.token);
      final operation = envelope['op'];
      _log('$label protocol: ${_protocolCodec.summaryForProtocol(envelope)}');
      if (envelope['body'] is Map) {
        _captureCapabilities(operation, envelope['body'] as Map);
        _log(
          '${operation == "event" ? "EVT" : "RX"} body=${jsonEncode(envelope['body'])}',
        );
      }
      return;
    }
    _log('$label raw: ${decoded.bytes.length} B text="${decoded.text}"');
  }

  void _captureSessionToken(String? token) {
    if (token != null && token.isNotEmpty && token != sessionToken) {
      sessionToken = token;
      _log('AUTH token captured: $token');
      notifyListeners();
    }
  }

  void _captureCapabilities(Object? operation, Map<dynamic, dynamic> body) {
    if (operation != 'info') {
      return;
    }
    final summary = _protocolCodec.capabilitySummaryForInfoBody(body);
    capabilitySummary = summary;
    _log('CAP $summary');
    notifyListeners();
  }

  String _resultName(ScanResult result) {
    return result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
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
