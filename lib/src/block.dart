import 'dart:convert';
import 'utils/rest_api.dart';
import 'utils/rest_api.dart';

// Return details about a Block

class Block {
  // Lookup the block with a block height.
  static Future detailsByHeight(number) async {
    if (number is String) {
      // Single Block
      return await RestApi.sendGetRequest(
          "block/detailsByHeight", number.toString());
    } else if (number is List<String>) {
      // Array of Blocks
      return await RestApi.sendPostRequest(
          "block/detailsByHeight", "heights", number);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }

// Lookup the block with a block hash.
  static Future detailsByHash(hash) async {
    if (hash is String) {
      // Single Block
      return await RestApi.sendGetRequest("block/detailsByHash", hash);
    } else if (hash is List<String>) {
      // Array of Blocks
      return await RestApi.sendPostRequest(
          "block/detailsByHash", "hashes", hash);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }
}
