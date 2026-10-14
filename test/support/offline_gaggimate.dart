import 'package:beand/machines/gaggimate/gaggimate_service.dart';

// GaggiMate service for tests that don't need the machine at all, but do
// need the provider. Its transport never comes up: a connect() (e.g. via
// the switch in Settings → Home) thus ends up in the error state right
// away, instead of opening a real WebSocket or leaving a request with a
// timeout open — either would trip the test over a pending timer.
GaggiMateService offlineGaggiMate() => GaggiMateService(
  host: 'unreachable.local',
  autoReconnect: false,
  transportFactory: (uri) => throw StateError('offline in tests: $uri'),
);
