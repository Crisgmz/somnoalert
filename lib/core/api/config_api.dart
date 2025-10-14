import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/config_model.dart';

class ConfigApi {
  ConfigApi(String baseUrl) : _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  final String _base;

  Uri get _configUri => Uri.parse('$_base/config');

  Future<ConfigModel> getConfig() async {
    final response = await http.get(_configUri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load config: ${response.statusCode}');
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ConfigModel.fromJson(jsonBody);
  }

  Future<ConfigModel> updateConfig(ConfigModel config) async {
    final response = await http.post(
      _configUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config.toJson()),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update config: ${response.statusCode}');
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return ConfigModel.fromJson(jsonBody);
  }
}
