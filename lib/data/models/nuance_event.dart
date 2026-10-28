enum NuanceSeverity { info, warning, critical }

class NuanceEvent {
  final String id;
  DateTime timestamp;
  NuanceSeverity severity;
  String title;
  String description;
  Map<String, String> snapshot;
  int hzCount;

  NuanceEvent({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.title,
    required this.description,
    required this.snapshot,
    this.hzCount = 1,
  });

  String get timeStr =>
      "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': timestamp.toIso8601String(),
        'sev': severity.name,
        'title': title,
        'desc': description,
        'snap': snapshot,
        'hz': hzCount,
      };

  factory NuanceEvent.fromJson(Map<String, dynamic> j) {
    final sevName = (j['sev'] ?? 'info').toString();
    final sev = NuanceSeverity.values.firstWhere(
      (e) => e.name == sevName,
      orElse: () => NuanceSeverity.info,
    );
    final rawSnap = j['snap'] as Map<String, dynamic>? ?? {};
    return NuanceEvent(
      id: (j['id'] ?? '').toString(),
      timestamp: DateTime.tryParse((j['ts'] ?? '').toString()) ?? DateTime.now(),
      severity: sev,
      title: (j['title'] ?? '').toString(),
      description: (j['desc'] ?? '').toString(),
      snapshot: rawSnap.map((k, v) => MapEntry(k, v.toString())),
      hzCount: (j['hz'] as num?)?.toInt() ?? 1,
    );
  }
}

class TrimBin {
  final String label;
  final List<double> _samples = [];
  TrimBin(this.label);

  int get count => _samples.length;
  bool get isNotEmpty => _samples.isNotEmpty;
  List<double> get rawSamples => List.unmodifiable(_samples);

  void loadSamples(List<double> saved) {
    _samples..clear()..addAll(saved.take(90));
  }

  void addSample(double stft, double ltft) {
    if (stft.abs() > 30.0 || ltft.abs() > 30.0) return;
    _samples.add(stft + ltft);
    if (_samples.length > 90) _samples.removeAt(0);
  }

  double get median {
    if (_samples.isEmpty) return 0.0;
    final sorted = List<double>.from(_samples)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  void clear() => _samples.clear();
}
