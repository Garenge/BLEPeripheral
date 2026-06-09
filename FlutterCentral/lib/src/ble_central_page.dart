import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble_central_controller.dart';
import 'ble_protocol_codec.dart';
import 'ble_request_status.dart';

typedef BleCentralControllerFactory = BleCentralController Function();

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
    text: 'hello from Flutter BLE client',
  );
  int _selectedIndex = 0;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Flutter BLE Central'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text(_controller.adapterLabel)),
              ),
            ],
          ),
          body: isWide ? _buildWideBody() : _buildMobileBody(),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.bluetooth_searching),
                      selectedIcon: Icon(Icons.bluetooth_connected),
                      label: 'Connect',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune),
                      selectedIcon: Icon(Icons.settings_input_component),
                      label: 'Operate',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: 'Logs',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildWideBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildConnectPanel()),
          const SizedBox(width: 12),
          Expanded(child: _buildOperatePanel()),
          const SizedBox(width: 12),
          Expanded(child: _buildLogPanel()),
        ],
      ),
    );
  }

  Widget _buildMobileBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildConnectPanel(),
          _buildOperatePanel(),
          _buildLogPanel(),
        ],
      ),
    );
  }

  Widget _buildConnectPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusHeader(),
              const SizedBox(height: 12),
              _buildScanActions(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _SectionSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(
                  'Scan',
                  'Target service FFF0, name MacBLE-Demo',
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildDeviceList()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperatePanel() {
    return _SectionSurface(
      child: ListView(
        children: [
          _buildSectionHeader('Session', _controller.connectionLabel),
          const SizedBox(height: 12),
          _buildRequestStatusPanel(),
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
              labelText: 'Payload or command name',
            ),
            onSubmitted: _sendPayload,
          ),
          const SizedBox(height: 12),
          _buildPrimaryFlowActions(),
          const SizedBox(height: 16),
          _buildProtocolActions(),
          const SizedBox(height: 16),
          _buildRuleModeControl(),
          const SizedBox(height: 8),
          _buildAdvancedActions(),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return _SectionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader(
                  'Logs',
                  '${_controller.logs.length} event(s)',
                ),
              ),
              IconButton(
                tooltip: 'Copy logs',
                onPressed: _controller.logs.isEmpty ? null : _copyLogs,
                icon: const Icon(Icons.copy_all),
              ),
              IconButton(
                tooltip: 'Clear logs',
                onPressed: _controller.logs.isEmpty
                    ? null
                    : _controller.clearLogs,
                icon: const Icon(Icons.delete_sweep),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Device', _controller.connectionLabel),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(icon: Icons.bluetooth, label: _controller.adapterLabel),
            _StatusChip(
              icon: _controller.connectedDevice == null
                  ? Icons.link_off
                  : Icons.link,
              label: _controller.connectedDevice == null
                  ? 'Disconnected'
                  : 'Connected',
            ),
            _StatusChip(
              icon: _controller.sessionToken == null
                  ? Icons.lock_outline
                  : Icons.verified_user_outlined,
              label: _controller.sessionToken == null ? 'Unpaired' : 'Paired',
            ),
            _StatusChip(
              icon: _controller.notifyEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              label: _controller.notifyEnabled ? 'Notify ON' : 'Notify OFF',
            ),
            _StatusChip(
              icon: Icons.rule,
              label: 'Rule ${_controller.eventRuleMode}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScanActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _controller.isScanning ? null : _controller.startScan,
          icon: const Icon(Icons.radar),
          label: const Text('Scan'),
        ),
        OutlinedButton.icon(
          onPressed: _controller.isScanning ? _controller.stopScan : null,
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
    );
  }

  Widget _buildPrimaryFlowActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            _controller.isDemoFlowRunning ? 'Running Demo' : 'Run Demo',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _controller.demoCharacteristic == null
              ? null
              : () => _sendPair(_pairCodeController.text),
          icon: const Icon(Icons.lock_open),
          label: const Text('Pair'),
        ),
      ],
    );
  }

  Widget _buildProtocolActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _controller.demoCharacteristic == null
              ? null
              : _controller.sendInfo,
          icon: const Icon(Icons.info_outline),
          label: const Text('Info'),
        ),
        OutlinedButton.icon(
          onPressed: _controller.demoCharacteristic == null
              ? null
              : _controller.sendPing,
          icon: const Icon(Icons.bolt),
          label: const Text('Ping'),
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
      ],
    );
  }

  Widget _buildRequestStatusPanel() {
    final statuses = _controller.requestStatuses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Request Status', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (var index = 0; index < statuses.length; index += 1) ...[
          _RequestStatusRow(status: statuses[index]),
          if (index < statuses.length - 1) const Divider(height: 12),
        ],
      ],
    );
  }

  Widget _buildAdvancedActions() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 4),
      title: const Text('Advanced'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _controller.demoCharacteristic == null
                    ? null
                    : () => _controller.sendRawText(_payloadController.text),
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
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
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
      showSelectedIcon: false,
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
    if (_controller.logs.isEmpty) {
      return const Center(child: Text('No logs yet.'));
    }
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

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _controller.logs.join('\n')));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logs copied')));
  }
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: colorScheme.onSecondaryContainer),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusRow extends StatelessWidget {
  const _RequestStatusRow({required this.status});

  final BleRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _phaseColor(colorScheme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_phaseIcon(), size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${status.label} request',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                status.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          status.phaseLabel,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }

  IconData _phaseIcon() {
    return switch (status.phase) {
      BleRequestPhase.idle => Icons.radio_button_unchecked,
      BleRequestPhase.sending => Icons.sync,
      BleRequestPhase.succeeded => Icons.check_circle_outline,
      BleRequestPhase.failed => Icons.error_outline,
    };
  }

  Color _phaseColor(ColorScheme colorScheme) {
    return switch (status.phase) {
      BleRequestPhase.idle => colorScheme.outline,
      BleRequestPhase.sending => colorScheme.primary,
      BleRequestPhase.succeeded => colorScheme.tertiary,
      BleRequestPhase.failed => colorScheme.error,
    };
  }
}
