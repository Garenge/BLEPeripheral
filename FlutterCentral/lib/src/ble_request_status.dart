const List<BleRequestDefinition> bleTrackedRequestDefinitions = [
  BleRequestDefinition(operation: 'pair', label: 'Pair'),
  BleRequestDefinition(operation: 'getInfo', label: 'Info'),
  BleRequestDefinition(operation: 'ping', label: 'Ping'),
  BleRequestDefinition(operation: 'echo', label: 'Echo'),
  BleRequestDefinition(operation: 'telemetry', label: 'Telemetry'),
  BleRequestDefinition(operation: 'command', label: 'Command'),
];

class BleRequestDefinition {
  const BleRequestDefinition({required this.operation, required this.label});

  final String operation;
  final String label;
}

enum BleRequestPhase { idle, sending, succeeded, failed }

class BleRequestStatus {
  const BleRequestStatus({
    required this.operation,
    required this.label,
    required this.phase,
    required this.detail,
    this.messageId,
    this.updatedAt,
  });

  const BleRequestStatus.idle({required this.operation, required this.label})
    : phase = BleRequestPhase.idle,
      detail = 'Ready',
      messageId = null,
      updatedAt = null;

  final String operation;
  final String label;
  final BleRequestPhase phase;
  final String detail;
  final String? messageId;
  final DateTime? updatedAt;

  String get phaseLabel {
    return switch (phase) {
      BleRequestPhase.idle => 'Idle',
      BleRequestPhase.sending => 'Sending',
      BleRequestPhase.succeeded => 'OK',
      BleRequestPhase.failed => 'Error',
    };
  }

  BleRequestStatus copyWith({
    BleRequestPhase? phase,
    String? detail,
    String? messageId,
    DateTime? updatedAt,
  }) {
    return BleRequestStatus(
      operation: operation,
      label: label,
      phase: phase ?? this.phase,
      detail: detail ?? this.detail,
      messageId: messageId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
