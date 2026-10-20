import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'core/config_io.dart';
import 'models.dart';

/// App-side wrapper: resolves the config file inside the OS app-support
/// dir via path_provider, then delegates to the pure-Dart core IO so the
/// CLI and MCP server share the exact same format.
class ConfigStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}log_chard.yaml');
  }

  Future<List<Environment>> load() async =>
      loadConfigFile((await _file()).path);

  Future<Map<String, dynamic>> loadSettings() async =>
      loadSettingsFile((await _file()).path);

  Future<void> save(List<Environment> envs,
          {Map<String, dynamic> settings = const {}}) async =>
      saveConfigFile((await _file()).path, envs, settings: settings);
}
