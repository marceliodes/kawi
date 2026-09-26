import 'dart:ffi';
import 'dart:io';

DynamicLibrary loadNativeLibrary(String name) {
  if (Platform.isLinux) {
    final localCandidates = [
      'native/prebuilt/linux/x64/lib$name.so',
      'native/prebuilt/linux/x86_64/lib$name.so',
      'lib$name.so',
    ];
    for (final path in localCandidates) {
      final file = File(path);
      if (file.existsSync()) {
        return DynamicLibrary.open(file.absolute.path);
      }
    }
    return DynamicLibrary.open('lib$name.so');
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('lib$name.so');
  }

  if (Platform.isMacOS) {
    final localCandidates = [
      'native/prebuilt/macos/universal/lib$name.dylib',
      'lib$name.dylib',
    ];
    for (final path in localCandidates) {
      final file = File(path);
      if (file.existsSync()) {
        return DynamicLibrary.open(file.absolute.path);
      }
    }
    return DynamicLibrary.open('lib$name.dylib');
  }

  if (Platform.isWindows) {
    final localCandidates = [
      'native/prebuilt/windows/x86_64/$name.dll',
      'native/prebuilt/windows/x64/$name.dll',
      '$name.dll',
    ];
    for (final path in localCandidates) {
      final file = File(path);
      if (file.existsSync()) {
        return DynamicLibrary.open(file.absolute.path);
      }
    }
    return DynamicLibrary.open('$name.dll');
  }

  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
