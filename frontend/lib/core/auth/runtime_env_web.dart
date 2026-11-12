/// Web builds never run the keystore plugin, so [TokenStore] always uses its
/// plain-storage path. `flutter test` does not run on web either.
const bool kIsTest = false;
