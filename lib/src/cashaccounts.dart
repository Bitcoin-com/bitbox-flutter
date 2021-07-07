import 'dart:convert';
import 'utils/rest_api.dart';
import 'package:http/http.dart' as http;

class CashAccounts {
  static Future<Map> lookup(String account, int number, {int collision}) async {
    String col = "";
    if (collision != null) {
      col = collision.toString();
    }
    final response = await http.get(Uri.parse(
        "https://rest.bitcoin.com/v2/cashAccounts/lookup/$account/$number/$col"));
    return json.decode(response.body);
  }

  static Future<Map> check(String account, int number) async {
    final response = await http.get(Uri.parse(
        "https://rest.bitcoin.com/v2/cashAccounts/check/$account/$number"));
    return json.decode(response.body);
  }

  static Future<Map> reverseLookup(String cashAddress) async {
    final response = await http.get(Uri.parse(
        "https://rest.bitcoin.com/v2/cashAccounts/reverseLookup/$cashAddress"));
    return json.decode(response.body);
  }

  static Future<Map> register(String name, String address) async {
    Map register = {
      'name': name,
      'payments': [address]
    };
    final response = await http.post(
        Uri.parse('https://api.cashaccount.info/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(register));
    Map data = jsonDecode(response.body);
    return data;
  }
}
