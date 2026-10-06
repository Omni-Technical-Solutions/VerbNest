/// One test outcome from a script (`pm.test`) or a no-code assertion.
class TestResult {
  const TestResult({required this.name, required this.status, this.message});

  final String name;

  /// `pass`, `fail` or `skip`.
  final String status;
  final String? message;

  bool get passed => status == 'pass';
  bool get failed => status == 'fail';
  bool get skipped => status == 'skip';

  factory TestResult.fromJson(Map<String, Object?> j) => TestResult(
    name: j['name'] as String? ?? '',
    status: j['status'] as String? ?? 'fail',
    message: j['message'] as String?,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    if (message != null) 'message': message,
  };
}
