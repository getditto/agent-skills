// Test-only: a throwaway persistence directory per run. The published program
// uses Ditto's default directory.
export 'temp_dir_web.dart' if (dart.library.io) 'temp_dir_io.dart';
