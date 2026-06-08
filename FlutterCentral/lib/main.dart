import 'package:flutter/material.dart';

import 'src/ble_central_controller.dart';
import 'src/ble_protocol_codec.dart';

void main() {
  runApp(const FlutterCentralApp());
}

typedef BleCentralControllerFactory = BleCentralController Function();

class FlutterCentralApp extends StatelessWidget {
  const FlutterCentralApp({super.key, this.controllerFactory});

  final BleCentralControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter BLE Central',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: BleCentralPage(controllerFactory: controllerFactory),
    );
  }
}

class BleCentralPage extends StatefulWidget {
  const BleCentralPage({super.key, this.controllerFactory});

  final BleCentralControllerFactory? controllerFactory;

  @override
  State<BleCentralPage> createState() => _BleCentralPageState();
}

class _BleCentralPageState extends State<BleCentralPage> {
  late final BleCentralController _controller;
  final TextEditingController _pairCodeController = TextEditingController(
    text: bleDefaultPairCode,
  );
  final TextEditingController _payloadController = TextEditingController(
    text: 'hello from Flutter macOS',
  );

  @override
  void initState() {
    super.initState();
    _controller = (widget.controllerFactory ?? BleCentralController.new)()
      ..addListener(_refresh);
  }

  @override
  void dispose() {
    _pairCodeController.dispose();
    _payloadController.dispose();
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter macOS BLE Central'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(_controller.adapterLabel)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;
          final panels = [
            Expanded(child: _buildScannerPanel()),
            Expanded(child: _buildGattPanel(isWide: isWide)),
          ];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: panels,
                  )
                : ListView(
                    children: [
                      SizedBox(height: 320, child: _buildScannerPanel()),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: constraints.maxHeight < 520
                            ? 420
                            : constraints.maxHeight - 36,
                        child: _buildGattPanel(isWide: false),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildScannerPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader('Scan', 'Target service FFF0, name MacBLE-Demo'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _controller.isScanning
                            ? null
                            : _controller.startScan,
                        icon: const Icon(Icons.radar),
                        label: const Text('Scan'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _controller.isScanning
                            ? _controller.stopScan
                            : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _controller.connectedDevice == null
                            ? null
                            : _controller.disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                ],
              ),
            ),
            Expanded(child: _buildDeviceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildGattPanel({required bool isWide}) {
    return Card(
      margin: EdgeInsets.only(left: isWide ? 12 : 0, top: isWide ? 0 : 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader('GATT', _controller.connectionLabel),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pairCodeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Pair code',
                      ),
                      onSubmitted: _sendPair,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _payloadController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Echo payload or command name',
                      ),
                      onSubmitted: _sendPayload,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : () => _sendPair(_pairCodeController.text),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Pair'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : _controller.sendPing,
                          icon: const Icon(Icons.bolt),
                          label: const Text('Ping'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : _controller.sendInfo,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Info'),
                        ),
                        FilledButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : () => _sendPayload(_payloadController.text),
                          icon: const Icon(Icons.send),
                          label: const Text('Echo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : _controller.sendTelemetry,
                          icon: const Icon(Icons.monitor_heart_outlined),
                          label: const Text('Telemetry'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : () => _sendCommand(_payloadController.text),
                          icon: const Icon(Icons.terminal),
                          label: const Text('Command'),
                        ),
                        _buildRuleModeControl(),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : () => _controller.sendRawText(
                                  _payloadController.text,
                                ),
                          icon: const Icon(Icons.data_object),
                          label: const Text('Raw'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : _controller.readValue,
                          icon: const Icon(Icons.download),
                          label: const Text('Read'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.demoCharacteristic == null
                              ? null
                              : () => _controller.setNotify(
                                  !_controller.notifyEnabled,
                                ),
                          icon: Icon(
                            _controller.notifyEnabled
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                          ),
                          label: Text(
                            _controller.notifyEnabled
                                ? 'Notify Off'
                                : 'Notify On',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _controller.canRunDemoFlow
                              ? _controller.runDemoFlow
                              : null,
                          icon: Icon(
                            _controller.isDemoFlowRunning
                                ? Icons.hourglass_top
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            _controller.isDemoFlowRunning
                                ? 'Running Demo'
                                : 'Run Demo',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                  ],
                ),
              ),
            ),
            Expanded(flex: 1, child: _buildLogList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildDeviceList() {
    if (_controller.devices.isEmpty) {
      return const Center(child: Text('No peripherals discovered yet.'));
    }
    return ListView.separated(
      itemCount: _controller.devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = _controller.devices[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(device.name),
          subtitle: Text('${device.id}\n${device.detailLabel}'),
          isThreeLine: true,
          trailing: FilledButton(
            onPressed: () => _controller.connect(device.id),
            child: const Text('Connect'),
          ),
        );
      },
    );
  }

  Widget _buildRuleModeControl() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'normal',
          icon: Icon(Icons.rule),
          label: Text('Normal'),
        ),
        ButtonSegment(
          value: 'quiet',
          icon: Icon(Icons.volume_down),
          label: Text('Quiet'),
        ),
        ButtonSegment(
          value: 'burst',
          icon: Icon(Icons.bolt),
          label: Text('Burst'),
        ),
      ],
      selected: {_controller.eventRuleMode},
      onSelectionChanged: _controller.demoCharacteristic == null
          ? null
          : (selection) => _controller.sendEventRuleMode(selection.first),
    );
  }

  Widget _buildLogList() {
    return ListView.builder(
      reverse: true,
      itemCount: _controller.logs.length,
      itemBuilder: (context, index) {
        final message = _controller.logs[_controller.logs.length - 1 - index];
        return SelectableText(
          message,
          style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
        );
      },
    );
  }

  void _sendPayload(String text) {
    _controller.writeText(text);
  }

  void _sendPair(String code) {
    _controller.sendPairCode(code);
  }

  void _sendCommand(String text) {
    _controller.sendCommand(text.isEmpty ? 'identify' : text);
  }
}
