import 'dart:typed_data';
import 'package:bitbox/bitbox.dart';
import 'package:hex/hex.dart';
import 'package:slp_mdm/slp_mdm.dart';
import 'package:slp_parser/slp_parser.dart';
import 'dart:math' as math;

class SLP {
  static getTokenInformation(String tokenID,
      [bool decimalConversion = false]) async {
    var res;
    try {
      res = await RawTransactions.getRawtransaction(tokenID, verbose: true);
      if (res.containsKey('error')) {
        throw Exception(
            "BITBOX response error for 'RawTransactions.getRawTransaction'");
      }
    } catch (e) {
      throw Exception(e);
    }
    var slpMsg =
        parseSLP(HEX.decode(res['vout'][0]['scriptPubKey']['hex'])).toMap();
    if (decimalConversion) {
      Map slpMsgData = slpMsg['data'];

      if (slpMsg['transactionType'] == "GENESIS" ||
          slpMsg['transactionType'] == "MINT") {
        slpMsgData['qty'] =
            slpMsgData['qty'] / math.pow(10, slpMsgData['decimals']);
      } else {
        slpMsgData['amounts']
            .map((o) => o / math.pow(10, slpMsgData['decimals']));
      }
    }

    if (slpMsg['transactionType'] == "GENESIS") {
      slpMsg['tokenIdHex'] = tokenID;
    }
    return slpMsg;
  }

  static getAllSlpBalancesAndUtxos(String address) async {
    List utxos = await mapToSlpAddressUtxoResultArray(address);
    var txIds = [];
    utxos.forEach((i) {
      txIds.add(i['txid']);
    });
    if (txIds.length == 0) {
      return [];
    }
  }

  static Future<List> mapToSlpAddressUtxoResultArray(String address) async {
    var result;
    try {
      result = await Address.utxo([address]);
    } catch (e) {
      return [];
    }
    List utxo = [];
    return result['utxos'].forEach((txo) => utxo.add({
          'satoshis': txo.satoshis,
          'txid': txo.txid,
          'amount': txo.amount,
          'confirmations': txo.confirmations,
          'height': txo.height,
          'vout': txo.vout,
          'cashAddress': result.cashAddress,
          'legacyAddress': result.legacyAddress,
          'slpAddress': Address.toSLPAddress(result.legacyAddress),
          'scriptPubKey': result.scriptPubKey,
        }));
  }

  static mapToSLPUtxoArray({List utxos, String xpriv, String wif}) {
    List utxo = [];
    utxos.forEach((txo) => utxo.add({
          'satoshis': new BigInt.from(txo['satoshis']),
          'xpriv': xpriv,
          'wif': wif,
          'txid': txo['txid'],
          'vout': txo['vout'],
          'utxoType': txo['utxoType'],
          'transactionType': txo['transactionType'],
          'tokenId': txo['tokenId'],
          'tokenTicker': txo['tokenTicker'],
          'tokenName': txo['tokenName'],
          'decimals': txo['decimals'],
          'tokenType': txo['tokenType'],
          'tokenQty': txo['tokenQty'],
          'isValid': txo['isValid'],
        }));
    return utxo;
  }

  static parseSlp(String scriptPubKey) {
    var slpMsg = parseSLP(HEX.decode(scriptPubKey));
    return slpMsg.toMap(raw: true);
  }

  static simpleTokenSend({
    String tokenId,
    List<num> sendAmounts,
    List inputUtxos,
    List bchInputUtxos,
    List<String> tokenReceiverAddresses,
    String slpChangeReceiverAddress,
    String bchChangeReceiverAddress,
    List requiredNonTokenOutputs,
    int extraFee,
    int extraBCH = 0,
    int type = 0x01,
    bool buildIncomplete = false,
    int hashType = Transaction.SIGHASH_ALL,
  }) async {
    List<BigInt> amounts = [];
    BigInt totalAmount = BigInt.from(0);
    if (tokenId is! String) {
      return Exception("Token id should be a String");
    }
    tokenReceiverAddresses.forEach((tokenReceiverAddress) {
      if (tokenReceiverAddress is! String) {
        throw new Exception("Token receiving address should be a String");
      }
    });
    if (slpChangeReceiverAddress is! String) {
      throw new Exception("Slp change receiving address should be a String");
    }
    if (bchChangeReceiverAddress is! String) {
      throw new Exception("Bch change receiving address should be a String");
    }

    var tokenInfo = await getTokenInformation(tokenId);
    int decimals = tokenInfo['data']['decimals'];

    sendAmounts.forEach((sendAmount) async {
      if (sendAmount > 0) {
        totalAmount += BigInt.from(sendAmount * math.pow(10, decimals));
        amounts.add(BigInt.from(sendAmount * math.pow(10, decimals)));
      }
    });

    // 1 Set the token send amounts, send tokens to a
    // new receiver and send token change back to the sender
    BigInt totalTokenInputAmount = BigInt.from(0);
    inputUtxos.forEach((txo) =>
        totalTokenInputAmount += _preSendSlpJudgementCheck(txo, tokenId));

    // 2 Compute the token Change amount.
    BigInt tokenChangeAmount = totalTokenInputAmount - totalAmount;
    bool sendChange = tokenChangeAmount > new BigInt.from(0);

    if (tokenChangeAmount < new BigInt.from(0)) {
      return throw Exception('Token inputs less than the token outputs');
    }
    if (tokenChangeAmount > BigInt.from(0)) {
      amounts.add(tokenChangeAmount);
    }

    if (sendChange) {
      tokenReceiverAddresses.add(slpChangeReceiverAddress);
    }

    int tokenType = tokenInfo['tokenType'];

    // 3 Create the Send OP_RETURN message
    var sendOpReturn;
    if (tokenType == 1) {
      sendOpReturn = Send(HEX.decode(tokenId), amounts);
    } else if (tokenType == 129) {
      sendOpReturn = Nft1GroupSend(HEX.decode(tokenId), amounts);
    } else if (tokenType == 65) {
      sendOpReturn = Nft1ChildSend(HEX.decode(tokenId), amounts[0]);
    } else {
      return throw Exception('Invalid token type');
    }
    // 4 Create the raw Send transaction hex
    Map result = await _buildRawSendTx(
        slpSendOpReturn: sendOpReturn,
        inputTokenUtxos: inputUtxos,
        bchInputUtxos: bchInputUtxos,
        tokenReceiverAddresses: tokenReceiverAddresses,
        bchChangeReceiverAddress: bchChangeReceiverAddress,
        requiredNonTokenOutputs: requiredNonTokenOutputs,
        extraFee: extraFee,
        extraBCH: extraBCH,
        buildIncomplete: buildIncomplete,
        hashType: hashType);
    return result;
  }

  static BigInt _preSendSlpJudgementCheck(Map txo, tokenID) {
    // if (txo['slpUtxoJudgement'] == "undefined" ||
    //     txo['slpUtxoJudgement'] == null ||
    //     txo['slpUtxoJudgement'] == "UNKNOWN") {
    //   throw Exception(
    //       "There is at least one input UTXO that does not have a proper SLP judgement");
    // }
    // if (txo['slpUtxoJudgement'] == "UNSUPPORTED_TYPE") {
    //   throw Exception(
    //       "There is at least one input UTXO that is an Unsupported SLP type.");
    // }
    // if (txo['slpUtxoJudgement'] == "SLP_BATON") {
    //   throw Exception(
    //       "There is at least one input UTXO that is a baton. You can only spend batons in a MINT transaction.");
    // }
    //if (txo.containsKey('slpTransactionDetails')) {
    //if (txo['slpUtxoJudgement'] == "SLP_TOKEN") {
    if (txo['utxoType'] == "token") {
      //if (txo['transactionType'] != 'send') {
      // throw Exception(
      //     "There is at least one input UTXO that does not have a proper SLP judgement");
      // }
      //if (!txo.containsKey('slpUtxoJudgementAmount')) {
      if (!txo.containsKey('tokenQty')) {
        throw Exception(
            "There is at least one input token that does not have the 'slpUtxoJudgementAmount' property set.");
      }
      //if (txo['slpTransactionDetails']['tokenIdHex'] != tokenID) {
      if (txo['tokenId'] != tokenID) {
        throw Exception(
            "There is at least one input UTXO that is a different SLP token than the one specified.");
      }
      // if (txo['slpTransactionDetails']['tokenIdHex'] == tokenID) {
      if (txo['tokenId'] == tokenID) {
        //return BigInt.from(num.parse(txo['slpUtxoJudgementAmount']));
        return BigInt.from(txo['tokenQty'] * math.pow(10, txo['decimals']));
      }
    }
    // }
    return BigInt.from(0);
  }

  static _buildRawSendTx(
      {List<int> slpSendOpReturn,
      List inputTokenUtxos,
      List bchInputUtxos,
      List tokenReceiverAddresses,
      String bchChangeReceiverAddress,
      List requiredNonTokenOutputs,
      int extraBCH,
      int extraFee,
      bool buildIncomplete,
      int hashType}) async {
    // Check proper address formats are given
    tokenReceiverAddresses.forEach((addr) {
      if (!addr.startsWith('simpleledger:')) {
        throw new Exception("Token receiver address not in SlpAddr format.");
      }
    });

    if (bchChangeReceiverAddress != null) {
      if (!bchChangeReceiverAddress.startsWith('bitcoincash:')) {
        throw new Exception(
            "BCH change receiver address is not in CashAddr format.");
      }
    }

    // Parse the SLP SEND OP_RETURN message
    var sendMsg = parseSLP(slpSendOpReturn).toMap();
    Map sendMsgData = sendMsg['data'];

    // Make sure we're not spending inputs from any other token or baton
    var tokenInputQty = new BigInt.from(0);
    inputTokenUtxos.forEach((txo) {
      //if (txo['slpUtxoJudgement'] == "NOT_SLP") {
      if (txo['isValid'] == null) {
        return;
      }
      if (!txo['isValid']) {
        return;
      }
      //if (txo['slpUtxoJudgement'] == "SLP_TOKEN") {
      if (txo['utxoType'] == "token") {
        // if (txo['slpTransactionDetails']['tokenIdHex'] !=
        //     sendMsgData['tokenId']) {
        if (txo['tokenId'] != sendMsgData['tokenId']) {
          throw Exception("Input UTXOs included a token for another tokenId.");
        }
        // tokenInputQty +=
        //     BigInt.from(double.parse(txo['slpUtxoJudgementAmount']));
        tokenInputQty +=
            BigInt.from(txo['tokenQty'] * math.pow(10, txo['decimals']));
        return;
      }
      // if (txo['slpUtxoJudgement'] == "SLP_BATON") {
      //   throw Exception("Cannot spend a minting baton.");
      // }
      // if (txo['slpUtxoJudgement'] == ['INVALID_TOKEN_DAG'] ||
      //     txo['slpUtxoJudgement'] == "INVALID_BATON_DAG") {
      //   throw Exception("Cannot currently spend UTXOs with invalid DAGs.");
      // }
      throw Exception("Cannot spend utxo with no SLP judgement.");
    });

    // Make sure the number of output receivers
    // matches the outputs in the OP_RETURN message.
    if (tokenReceiverAddresses.length != sendMsgData['amounts'].length) {
      throw Exception(
          "Number of token receivers in config does not match the OP_RETURN outputs");
    }

    // Make sure token inputs == token outputs
    var outputTokenQty = BigInt.from(0);
    sendMsgData['amounts'].forEach((a) => outputTokenQty += a);
    if (tokenInputQty != outputTokenQty) {
      throw Exception("Token input quantity does not match token outputs.");
    }

    // Create a transaction builder
    var transactionBuilder = Bitbox.transactionBuilder();
    //  let sequence = 0xffffffff - 1;

    // Calculate the total input amount & add all inputs to the transaction
    var inputSatoshis = BigInt.from(0);
    inputTokenUtxos.forEach((i) {
      inputSatoshis += i['satoshis'];
      transactionBuilder.addInput(i['txid'], i['vout']);
    });

    // Calculate the total BCH input amount & add all inputs to the transaction
    bchInputUtxos.forEach((i) {
      inputSatoshis += BigInt.from(i['satoshis']);
      transactionBuilder.addInput(i['txid'], i['vout']);
    });

    // Start adding outputs to transaction
    // Add SLP SEND OP_RETURN message
    transactionBuilder.addOutput(compile(slpSendOpReturn), 0);

    // Add dust outputs associated with tokens
    tokenReceiverAddresses.forEach((outputAddress) {
      outputAddress = Address.toLegacyAddress(outputAddress);
      outputAddress = Address.toCashAddress(outputAddress);
      transactionBuilder.addOutput(outputAddress, 546);
    });

    // Calculate the amount of outputs set aside for special BCH-only outputs for fee calculation
    var bchOnlyCount =
        requiredNonTokenOutputs != null ? requiredNonTokenOutputs.length : 0;
    BigInt bchOnlyOutputSatoshis = BigInt.from(0);
    requiredNonTokenOutputs != null
        ? requiredNonTokenOutputs
            .forEach((o) => bchOnlyOutputSatoshis += BigInt.from(o['satoshis']))
        : bchOnlyOutputSatoshis = bchOnlyOutputSatoshis;

    // Add BCH-only outputs
    if (requiredNonTokenOutputs != null) {
      if (requiredNonTokenOutputs.length > 0) {
        requiredNonTokenOutputs.forEach((output) {
          transactionBuilder.addOutput(
              output['bchaddress'], output['satoshis']);
        });
      }
    }

    // Calculate mining fee cost
    int sendCost = _calculateSendCost(
        slpSendOpReturn.length,
        inputTokenUtxos.length + bchInputUtxos.length,
        tokenReceiverAddresses.length + bchOnlyCount,
        bchChangeAddress: bchChangeReceiverAddress,
        feeRate: extraFee ?? 1);

    // Compute BCH change amount
    BigInt bchChangeAfterFeeSatoshis =
        inputSatoshis - BigInt.from(sendCost) - bchOnlyOutputSatoshis;
    if (bchChangeAfterFeeSatoshis < BigInt.from(0)) {
      return {'hex': null, 'fee': "Insufficient fees"};
    }

    // Add change, if any
    if (bchChangeAfterFeeSatoshis + new BigInt.from(extraBCH) > new BigInt.from(546)) {
      transactionBuilder.addOutput(
          bchChangeReceiverAddress, bchChangeAfterFeeSatoshis.toInt() + extraBCH);
    }

    if (hashType == null) hashType = Transaction.SIGHASH_ALL;
    // Sign txn and add sig to p2pkh input with xpriv,
    int slpIndex = 0;
    inputTokenUtxos.forEach((i) {
      ECPair paymentKeyPair;
      String xpriv = i['xpriv'];
      String wif = i['wif'];
      if (xpriv != null) {
        paymentKeyPair = HDNode.fromXPriv(xpriv).keyPair;
      } else {
        paymentKeyPair = ECPair.fromWIF(wif);
      }

      transactionBuilder.sign(
          slpIndex, paymentKeyPair, i['satoshis'].toInt(), hashType);
      slpIndex++;
    });

    int bchIndex = inputTokenUtxos.length;
    bchInputUtxos.forEach((i) {
      ECPair paymentKeyPair;
      String xpriv = i['xpriv'];
      String wif = i['wif'];
      if (xpriv != null) {
        paymentKeyPair = HDNode.fromXPriv(xpriv).keyPair;
      } else {
        paymentKeyPair = ECPair.fromWIF(wif);
      }
      transactionBuilder.sign(
          bchIndex, paymentKeyPair, i['satoshis'].toInt(), hashType);
      bchIndex++;
    });

     int _extraFee = (tokenReceiverAddresses.length + bchOnlyCount) * 546;

    // Build the transaction to hex and return
    // warn user if the transaction was not fully signed
    String hex;
    if (buildIncomplete) {
      hex = transactionBuilder.buildIncomplete().toHex();
      return {'hex': hex, 'fee': sendCost - _extraFee};
    } else {
      hex = transactionBuilder.build().toHex();
    }

    // Check For Low Fee
    int outValue = 0;
    transactionBuilder.tx.outputs.forEach((o) => outValue += o.value);
    int inValue = 0;
    inputTokenUtxos.forEach((i) => inValue += i['satoshis'].toInt());
    bchInputUtxos.forEach((i) => inValue += i['satoshis']);
    if (inValue - outValue < hex.length / 2) {
      return {'hex': null, 'fee': "Insufficient fee"};
    }

    return {'hex': hex, 'fee': sendCost - _extraFee};
  }

  static int _calculateSendCost(
      int sendOpReturnLength, int inputUtxoSize, int outputs,
      {String bchChangeAddress, int feeRate = 1, bool forTokens = true}) {
    int nonfeeoutputs = 0;
    if (forTokens) {
      nonfeeoutputs = outputs * 546;
    }
    if (bchChangeAddress != null && bchChangeAddress != 'undefined') {
      outputs += 1;
    }

    int fee = BitcoinCash.getByteCount(inputUtxoSize, outputs);
    fee += sendOpReturnLength;
    fee += 10; // added to account for OP_RETURN ammount of 0000000000000000
    fee *= feeRate;
    //print("SEND cost before outputs: " + fee.toString());
    fee += nonfeeoutputs;
    //print("SEND cost after outputs are added: " + fee.toString());
    return fee;
  }

  /*
    Todo
   */

  _createSimpleToken(
      {String tokenName,
      String tokenTicker,
      int tokenAmount,
      String documentUri,
      Uint8List documentHash,
      int decimals,
      String tokenReceiverAddress,
      String batonReceiverAddress,
      String bchChangeReceiverAddress,
      List inputUtxos,
      int type = 0x01}) async {
    int batonVout = batonReceiverAddress.isNotEmpty ? 2 : null;
    if (decimals == null) {
      throw Exception("Decimals property must be in range 0 to 9");
    }
    if (tokenTicker != null && tokenTicker is! String) {
      throw Exception("ticker must be a string");
    }
    if (tokenName != null && tokenName is! String) {
      throw Exception("name must be a string");
    }

    var genesisOpReturn = Genesis(tokenTicker, tokenName, documentUri,
        documentHash, decimals, BigInt.from(batonVout), tokenAmount);
    if (genesisOpReturn.length > 223) {
      throw Exception(
          "Script too long, must be less than or equal to 223 bytes.");
    }
    return genesisOpReturn;

    // var genesisTxHex = buildRawGenesisTx({
    //   slpGenesisOpReturn: genesisOpReturn,
    //   mintReceiverAddress: tokenReceiverAddress,
    //   batonReceiverAddress: batonReceiverAddress,
    //   bchChangeReceiverAddress: bchChangeReceiverAddress,
    //   input_utxos: Utils.mapToUtxoArray(inputUtxos)
    // });

    // return await RawTransactions.sendRawTransaction(genesisTxHex);
  }

  //simpleTokenMint() {}

  //simpleTokenBurn() {}
}
