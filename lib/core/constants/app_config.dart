/// Application configuration constants
/// 
/// Backend URLs and other configuration values are managed here.
/// Use environment variables in your deployment to override these values.
class AppConfig {
  AppConfig._();

  /// Backend server base URL
  /// 
  /// Default: Firebase Functions or local backend
  /// Override via environment variable: BACKEND_URL
  static const String backendBaseUrl = 
      String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'http://localhost:5000', // Development default
      );

  /// Backend notification endpoints
  static const String notifyAdminsEndpoint = '$backendBaseUrl/notify-admins';
  static const String sendNotificationEndpoint = '$backendBaseUrl/send-notification';
  static const String notifyClassEndpoint = '$backendBaseUrl/notify-class';

  /// HTTP request timeouts (in seconds)
  static const int httpTimeoutSeconds = 90; // Account for Render cold start

  /// Retry configuration
  static const int maxHttpRetries = 2;
}
