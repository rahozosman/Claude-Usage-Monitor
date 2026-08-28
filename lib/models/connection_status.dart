/// Overall connection / freshness state shown in the status indicator.
enum ConnectionStatus {
  /// Fresh data from at least one source.
  live,

  /// Data exists but is older than the staleness window.
  stale,

  /// A network call failed (no route / DNS / timeout).
  offline,

  /// A source rejected our credentials (expired token, bad key).
  unauthenticated,

  /// Nothing is configured that could produce data.
  notConfigured,

  /// A non-network error occurred on the last refresh.
  error,

  /// No refresh has completed yet.
  idle,
}

extension ConnectionStatusLabel on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.live:
        return 'Live';
      case ConnectionStatus.stale:
        return 'Stale';
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.unauthenticated:
        return 'Sign-in needed';
      case ConnectionStatus.notConfigured:
        return 'Not configured';
      case ConnectionStatus.error:
        return 'Error';
      case ConnectionStatus.idle:
        return 'Waiting';
    }
  }

  bool get isConnected => this == ConnectionStatus.live;
}
