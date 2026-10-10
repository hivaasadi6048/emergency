/// Central runtime configuration. The backend URL defaults to 127.0.0.1:8000
/// which works on a real device through `adb reverse tcp:8000 tcp:8000`
/// (docs/phase-4 flow). It can be overridden in the Settings screen.
class AppConfig {
  AppConfig._();
  static const defaultBackendUrl = 'http://127.0.0.1:8001';
  static const apiPrefix = '/api/v1';
}
