import 'utils/rest_api.dart';

class Blockchain {
  // Hash of the best block in the longest blockchain.
  static Future getBestBlockHash() async {
    // Returns the hash of the best (tip) block in the longest blockchain.
    return await RestApi.sendGetRequest("blockchain/getBestBlockHash");
  }

  // Info regarding blockchain processing
  static Future getBlockchainInfo() async {
    // Returns an object containing various state info regarding blockchain processing.
    return await RestApi.sendGetRequest("blockchain/getBlockchainInfo");
  }

  // Number of blocks in the longest blockchain.
  static Future getBlockCount() async {
    // Returns the number of blocks in the longest blockchain.
    return await RestApi.sendGetRequest("blockchain/getBlockCount");
  }

  // Information about blockheader hash
  static Future getBlockHeader(hash) async {
    if (hash is String) {
      // If verbose is false, returns a string that is serialized, hex-encoded data for blockheader 'hash'. If verbose is true, returns an Object with information about blockheader hash.
      return await RestApi.sendGetRequest(
          "blockchain/getBlockHeader", '$hash?verbose=true');
    } else if (hash is List<String>) {
      // Bulk information about blockheader hash
      return await RestApi.sendPostRequest(
          "blockchain/getBlockHeader", "hashes", hash);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }

// Information about all known tips in the block tree
  static Future getChainTips() async {
    // Return information about all known tips in the block tree, including the main chain as well as orphaned branches.
    return await RestApi.sendGetRequest("blockchain/getChainTips");
  }

  // Proof-of-work difficulty
  static Future getDifficulty() async {
    // Returns the proof-of-work difficulty as a multiple of the minimum difficulty.
    return await RestApi.sendGetRequest("blockchain/getDifficulty");
  }

  // Mempool data for transaction
  static Future getMempoolEntry(txid) async {
    if (txid is String) {
      // Returns mempool data for given transaction
      return await RestApi.sendGetRequest("blockchain/getMempoolEntry", txid);
    } else if (txid is List<String>) {
      // Returns mempool data for given transaction
      return await RestApi.sendPostRequest(
          "block/getMempoolEntry", "txids", txid);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }

  // All transaction ids in memory pool.
  static Future getRawMempool() async {
    // Returns all transaction ids in memory pool as a json array of string transaction ids.
    return await RestApi.sendGetRequest("blockchain/getRawMempool");
  }

  // Details about unspent transaction output.
  static Future getTxOut(txid, n) async {
    // Returns mempool data for given transaction
    return await RestApi.sendGetRequest("blockchain/getTxOut", '$txid/$n');
  }

  // Hex-encoded proof that single txid was included.
  static Future getTxOutProof(txid) async {
    if (txid is String) {
      // Returns a hex-encoded proof that 'txid' was included in a block.
      return await RestApi.sendGetRequest("blockchain/getTxOutProof", txid);
    } else if (txid is List<String>) {
      // Returns a hex-encoded proof that multiple txids were included in a block.
      return await RestApi.sendPostRequest(
          "block/getTxOutProof", "txids", txid);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }

  // Verify that a single proof points to a transaction in a block
  static Future verifyTxOutProof(proof) async {
    if (proof is String) {
      // Returns a hex-encoded proof that 'txid' was included in a block.
      return await RestApi.sendGetRequest("blockchain/verifyTxOutProof", proof);
    } else if (proof is List<String>) {
      // Returns a hex-encoded proof that multiple txids were included in a block.
      return await RestApi.sendPostRequest(
          "blockchain/verifyTxOutProof", "proofs", proof);
    } else
      return throw ("Function parameter must be String for single block and List<String> for multiple blocks");
  }
}
