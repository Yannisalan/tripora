/// Central place for environment/build configuration.
///
/// All values are resolved at compile time via `--dart-define`. Override
/// for a specific environment, e.g.:
///
///     flutter run \
///       --dart-define=API_BASE_URL=https://api.tripora.example.com \
///       --dart-define=GOOGLE_ANDROID_CLIENT_ID=... \
///       --dart-define=GOOGLE_IOS_CLIENT_ID=... \
///       --dart-define=APPLE_CLIENT_ID=com.tripora.app.login
///
/// If no override is provided, the defaults below are used.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://tripora-api-yom5.onrender.com',
  );

  // ------------------------------------------------------------
  // GOOGLE SIGN-IN
  // ------------------------------------------------------------
  //
  // On iOS the client ID is the iOS OAuth client id
  // (e.g. ...apps.googleusercontent.com). On Android the default
  // client id is '' (auto-resolved from the google-services config),
  // but an explicit one can be supplied as `GOOGLE_ANDROID_CLIENT_ID`.

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue: '',
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  // ------------------------------------------------------------
  // SIGN IN WITH APPLE
  // ------------------------------------------------------------

  static const String appleClientId = String.fromEnvironment(
    'APPLE_CLIENT_ID',
    defaultValue: 'com.tripora.app.login',
  );

  /// Redirect URI for Sign in with Apple's web flow (required on Android
  /// and Web). Must be a URI you registered with Apple as a callback.
  static const String appleRedirectUri = String.fromEnvironment(
    'APPLE_REDIRECT_URI',
    defaultValue: 'https://tripora.example.com/callbacks/sign_in_with_apple',
  );

  // ------------------------------------------------------------
  // PREMIUM SUBSCRIPTION (IN-APP PURCHASE)
  // ------------------------------------------------------------
  //
  // Real store product ids are created in App Store Connect and the Google
  // Play Console and passed at build time. A blank value means store IAP has
  // not been configured yet (the UI falls back to a "coming soon" state and
  // the dev `activate` path for testing).

  /// App Store / Play subscription product id (auto-renewing monthly).
  static const String premiumMonthlyProductId = String.fromEnvironment(
    'PREMIUM_MONTHLY_PRODUCT_ID',
    defaultValue: '',
  );

  /// App Store / Play subscription product id (auto-renewing yearly).
  static const String premiumYearlyProductId = String.fromEnvironment(
    'PREMIUM_YEARLY_PRODUCT_ID',
    defaultValue: '',
  );

  // ------------------------------------------------------------
  // PREMIUM / FREEMIUM FEATURE FLAG
  // ------------------------------------------------------------
  //
  // v1 ships 100% free for everyone: the premium paywall and the premium-only
  // travel-search features are hidden until this flag is enabled. The code is
  // kept in place so a future update only has to build with
  //
  //     --dart-define=PREMIUM_ENABLED=true
  //
  // to turn the freemium features on. When false (default), the `/premium`
  // and `/travel*` routes are not registered and the profile shows no premium
  // entry point at all, so there is no premium surface anywhere in the app.
  static const bool premiumEnabled = bool.fromEnvironment(
    'PREMIUM_ENABLED',
    defaultValue: false,
  );
}

