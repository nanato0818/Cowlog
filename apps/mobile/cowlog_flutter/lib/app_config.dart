/// Build-time configuration. No connection form is exposed to farm users.
class AppConfig {
  static const demoMode = bool.fromEnvironment(
    'COWLOG_DEMO',
    defaultValue: true,
  );
  static const apiUrl = String.fromEnvironment('COWLOG_API_URL');
  // Prototype credential only. Production must use provisioned, revocable sessions.
  static const manageToken = String.fromEnvironment('COWLOG_MANAGE_TOKEN');
  static const readToken = String.fromEnvironment('COWLOG_READ_TOKEN');
}
