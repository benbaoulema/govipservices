enum AppEnvironment {
  dev,
  prod;

  static AppEnvironment get current {
    const String raw = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    return raw.toLowerCase() == 'prod' ? AppEnvironment.prod : AppEnvironment.dev;
  }
}
