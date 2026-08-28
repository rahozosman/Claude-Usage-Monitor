/// Typed, human-readable errors. Messages never contain credentials.
enum AppErrorKind {
  cliMissing,
  unauthenticated,
  invalidCredentials,
  tokenExpired,
  network,
  rateLimited,
  malformed,
  api,
  unsupported,
  permission,
  unknown,
}

class AppError implements Exception {
  const AppError(this.kind, this.message, {this.detail, this.retryAfter});

  final AppErrorKind kind;
  final String message;
  final String? detail;
  final Duration? retryAfter;

  bool get isNetwork => kind == AppErrorKind.network;
  bool get isAuth =>
      kind == AppErrorKind.unauthenticated ||
      kind == AppErrorKind.invalidCredentials ||
      kind == AppErrorKind.tokenExpired;

  @override
  String toString() => detail == null ? message : '$message ($detail)';

  static AppError network([String? detail]) => AppError(
        AppErrorKind.network,
        'Network unavailable',
        detail: detail,
      );

  static AppError malformed([String? detail]) => AppError(
        AppErrorKind.malformed,
        'Unexpected response format',
        detail: detail,
      );

  /// Builds an error from an HTTP status without leaking the body verbatim
  /// (bodies may echo request headers in some proxies).
  static AppError fromStatus(int status, {String? apiMessage, Duration? retryAfter}) {
    final safe = _sanitize(apiMessage);
    switch (status) {
      case 401:
        return AppError(AppErrorKind.invalidCredentials, 'Authentication failed', detail: safe);
      case 403:
        return AppError(AppErrorKind.permission, 'Permission denied', detail: safe);
      case 404:
        return AppError(AppErrorKind.api, 'Endpoint not found', detail: safe);
      case 429:
        return AppError(AppErrorKind.rateLimited, 'Rate limited', detail: safe, retryAfter: retryAfter);
      case 400:
        return AppError(AppErrorKind.api, 'Request rejected', detail: safe);
      default:
        if (status >= 500) {
          return AppError(AppErrorKind.api, 'Anthropic service error ($status)', detail: safe);
        }
        return AppError(AppErrorKind.api, 'HTTP $status', detail: safe);
    }
  }

  static String? _sanitize(String? text) {
    if (text == null) return null;
    var t = text.replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_\-]+'), 'sk-ant-•••');
    t = t.replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+'), 'Bearer •••');
    return t.length > 240 ? '${t.substring(0, 240)}…' : t;
  }
}
