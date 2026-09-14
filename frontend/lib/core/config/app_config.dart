/// Central place for environment/build configuration.
///
/// All values are resolved at compile time via `--dart-define`. Override
/// for a specific environment, e.g.:
///
///     flutter run \
///       --dart-define=API_BASE_URL=https://api.tripora.example.com \
///       --dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com \
///       --dart-define=GOOGLE_IOS_CLIENT_ID=...apps.googleusercontent.com \
///       --dart-define=APPLE_CLIENT_ID=com.tripora.app.login
///
/// If no override is provided, the defaults below are used.
class AppConfig {
  AppConfig._();

  // ------------------------------------------------------------
  // THIRD-PARTY SIGN-IN VISIBILITY
  // ------------------------------------------------------------
  //
  // Master switch for the Google / Apple sign-in buttons on the login and
  // register screens (mobile and web). Set to true to re-enable the buttons;
  // all auth code, packages, backend routes and DB fields remain in place
  // either way.
  static const bool showThirdPartyAuth = false;

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://tripora-4mt3.onrender.com',
  );

  // ------------------------------------------------------------
  // GOOGLE SIGN-IN
  // ------------------------------------------------------------
  //
  // google_sign_in >= 7 behaviour differs per platform:
  //  * Android  uses the Credential Manager flow, which ignores `clientId`
  //    altogether and only mints an ID token for an audience it knows about.
  //    Pass the Cloud *Web* OAuth client ID as `serverClientId`
  //    (see social_auth_service.dart), or provide google-services.json whose
  //    `default_web_client_id` is that same Web client ID.
  //  * iOS     uses the iOS OAuth client ID (`GOOGLE_IOS_CLIENT_ID`).
  //  * Web     uses the Web OAuth client ID (`GOOGLE_WEB_CLIENT_ID`).
  //
  // The backend `aud` validation accepts all three client IDs, and a Google ID
  // token minted for the Web audience (as Android does with `serverClientId`)
  // or for the iOS audience verifies successfully.

  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// The Google Cloud Web OAuth client ID.
  ///
  /// Required on Android (passed as `serverClientId`) and used as `clientId`
  /// on Web. A Google Web client also activates OAuth consent and gives the
  /// API keys the `tripora-api-audience` verification audience.
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

  // ------------------------------------------------------------
  // HOTELS FEATURE FLAG
  // ------------------------------------------------------------
  //
  // Hotels shipping is currently hidden (the deck tile was removed) while
  // it is being validated. The backend routes are kept, and enabling this
  // flag at build time is what restores the hotels entry points in the app:
  //
  //     --dart-define=HOTEL_FEATURE_ENABLED=true
  //
  // Defaults to false so hotels never surface unless explicitly enabled.
  static const bool hotelFeatureEnabled = bool.fromEnvironment(
    'HOTEL_FEATURE_ENABLED',
    defaultValue: false,
  );
}

