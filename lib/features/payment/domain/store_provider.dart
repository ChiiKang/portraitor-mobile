enum StoreProvider {
  apple,
  google;

  static StoreProvider parse(String value) => switch (value) {
    'apple' => StoreProvider.apple,
    'google' => StoreProvider.google,
    _ => throw FormatException('Unsupported store provider: $value'),
  };
}
