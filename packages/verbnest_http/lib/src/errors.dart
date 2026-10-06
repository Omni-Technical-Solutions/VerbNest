/// Failures from the HTTP engine, each with a user-facing message.
sealed class HttpEngineError implements Exception {
  const HttpEngineError(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkError extends HttpEngineError {
  const NetworkError(super.message);
}

class TlsError extends HttpEngineError {
  const TlsError(super.message);
}

class TimeoutError extends HttpEngineError {
  const TimeoutError(super.message);
}

class CancelledError extends HttpEngineError {
  const CancelledError() : super('Request cancelled');
}

class ProtocolError extends HttpEngineError {
  const ProtocolError(super.message);
}

class TooManyRedirectsError extends HttpEngineError {
  const TooManyRedirectsError(int max) : super('Exceeded $max redirects');
}
