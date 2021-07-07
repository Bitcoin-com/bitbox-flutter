import 'dart:convert';
import 'utils/rest_api.dart';
import 'package:http/http.dart' as http;

/// Utilities for working raw transactions
class RawTransactions {
  /// Send raw transaction to the network
  /// Returns the resulting txid
  static Future<String> sendRawTransaction(String rawTx) async =>
      await RestApi.sendGetRequest("rawtransactions/sendRawTransaction", rawTx);

  /// Send multiple raw transactions to the network
  /// Returns the resulting array of txids
  static Future<List> sendRawTransactions(List<String> rawTxs) async =>
      await RestApi.sendPostRequest(
          "rawtransactions/sendRawTransaction", "hexes", rawTxs);

  /// Returns a JSON object representing the serialized, hex-encoded transaction
  static Future<Map> decodeRawTransaction(String hex) async =>
      await RestApi.sendGetRequest("rawtransactions/decodeRawTransaction", hex);

  /// Returns bulk hex encoded transaction
  static Future<List> decodeRawTransactions(List<String> hexes) async =>
      await RestApi.sendPostRequest(
          "rawtransactions/decodeRawTransaction", "hexes", hexes);

  /// Decodes a hex-encoded script
  static Future<Map> decodeScript(String script) async =>
      await RestApi.sendGetRequest("rawtransactions/decodeScript", script);

  /// Decodes multiple hex-encoded scripts
  static Future<List> decodeScripts(List<String> scripts) async =>
      await RestApi.sendPostRequest(
          "rawtransactions/decodeScript", "hexes", scripts);

  /// Returns the raw transaction data
  static Future getRawtransaction(String script,
      {bool verbose = true, bool testnet = false}) async {
    var _restURL = testnet ? 'trest' : 'rest';
    final response = await http.get(Uri.parse(
        "https://$_restURL.bitcoin.com/v2/rawtransactions/getRawTransaction/$script?verbose=$verbose"));
    return jsonDecode(response.body);
  }

  /// Returns raw transaction data for multiple transactions
  static Future getRawtransactions(List<String> scripts,
      {bool verbose = true, bool testnet = false}) async {
    var _restURL = testnet ? 'trest' : 'rest';
    final response = await http.post(
        Uri.parse(
            "https://$_restURL.bitcoin.com/v2/rawtransactions/getRawTransaction"),
        headers: {"content-type": "application/json"},
        body: jsonEncode({'txids': scripts, "verbose": verbose}));
    return jsonDecode(response.body);
  }
}
