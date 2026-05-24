import 'package:flutter/material.dart';

import 'src/ble_central_controller.dart';

void main() {
  runApp(const FlutterCentralApp());
}

class FlutterCentralApp extends StatelessWidget {
  const FlutterCentralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter BLE Central',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const BleCentralPage(),
    );
  }
}

class BleCentralPage extends StatefulWidget {
  const BleCentralPage({super.key});

  @override
  State<BleCentralPage> createState() => _BleCentralPageState();
}

class _BleCentralPageState extends State<BleCentralPage> {
  late final BleCentralController _controller;
  final TextEditingController _payloadController = TextEditingController(
    text: 'hello from Flutter macOS',
  );

  @override
  void initState() {
    super.initState();
    _controller = BleCentralController()..addListener(_refresh);
  }

  @override
  void dispose() {
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
            Expanded(child: _buildGattPanel()),
          ];
          return Padding(
            padding: const EdgeInsets.all(16),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: panels,
                  )
                : Column(children: panels),
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
            Expanded(child: _buildDeviceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildGattPanel() {
    return Card(
      margin: const EdgeInsets.only(left: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader('GATT', _controller.connectionLabel),
            const SizedBox(height: 12),
            TextField(
              controller: _payloadController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Write payload',
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
                      : () => _sendPayload(_payloadController.text),
                  icon: const Icon(Icons.send),
                  label: const Text('Write'),
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
                      : () => _controller.setNotify(!_controller.notifyEnabled),
                  icon: Icon(
                    _controller.notifyEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                  ),
                  label: Text(
                    _controller.notifyEnabled ? 'Notify Off' : 'Notify On',
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Expanded(child: _buildLogList()),
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
          subtitle: Text('${device.id}  RSSI ${device.rssi}'),
          trailing: FilledButton(
            onPressed: () => _controller.connect(device.id),
            child: const Text('Connect'),
          ),
        );
      },
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
}
