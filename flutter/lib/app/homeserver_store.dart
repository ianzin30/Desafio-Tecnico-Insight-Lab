import 'dart:io';

/// Remembers the last homeserver used to log in, so the next startup can
/// restore that session. Stores only the URL: never credentials or tokens.
abstract interface class HomeserverStore {
  Future<String?> read();
  Future<void> write(String homeserverUrl);
}

/// [HomeserverStore] backed by a small text file.
final class FileHomeserverStore implements HomeserverStore {
  FileHomeserverStore(this._directory);

  static const fileName = 'last_homeserver';

  final Future<Directory> _directory;

  Future<File> get _file async => File('${(await _directory).path}/$fileName');

  @override
  Future<String?> read() async {
    final file = await _file;
    if (!await file.exists()) return null;
    final value = (await file.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String homeserverUrl) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    await file.writeAsString(homeserverUrl, flush: true);
  }
}
