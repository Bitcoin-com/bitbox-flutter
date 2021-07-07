import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bitbox/bitbox.dart' as Bitbox;

// These tests generate a bunch of keys, addresses and compare them to the testing data generated by the original bitbox
// If there are balances on the addresses, the tests retrieve utxos, compile testing spending transactions,
// and optionally broadcast the transactions
//
// Make sure to run create_test_data.js first to generate the test data.
void main() {
  // path to the file generated by create_test_data.js
  const TEST_DATA_PATH = "/tmp/test_data.json";

  // If these are false, the transactions will be only built and compared to the output generated by bitbox js
  // You can turn these on separately
  const BROADCAST_TESTNET_TRANSACTION = true;
  const BROADCAST_MAINNET_TRANSACTION = true;

  // Data generated by the original bitbox library
  Map testData;

  // Placeholder for data about master, account and childnodes for both networks
  Map nodeData = {"mainnet" : {}, "testnet" : {}};

  // The whole code would be a bit more elegant if this was a map with true/false as keys and forEach would be used
  // in each of the testing methods. However the whole asynchronisity is messed up when it's done that way,
  // so a simple list and for() loop is used
  final networks = ["mainnet", "testnet"];

  // Generate master node master private key and public key and compare with the testing data
  test('Generating master node from mnemonic', () {
    // retrieve and parse the testing data
    final testFile = File.fromUri(Uri(path: TEST_DATA_PATH));
    final testDataJson = testFile.readAsStringSync();
    testData = jsonDecode(testDataJson);

    // create a seed from the mnemonic
    final seed = Bitbox.Mnemonic.toSeed(testData["mnemonic"]);

    // create master nodes for both networks and store their master keys
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      nodeData[network]["master_node"] = Bitbox.HDNode.fromSeed(seed, network == "testnet");
      final masterXPriv = nodeData[network]["master_node"].toXPriv();
      final masterXpub = nodeData[network]["master_node"].toXPub();

      // compare the result with the js test data
      expect(masterXPriv, testData[network]["master_xpriv"]);
      expect(masterXpub, testData[network]["master_xpub"]);
    }
  });

  // generate account node and compare its master keys with the original testing data
  test('Generating account node', () {
    // generate the nodes for both networks
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      nodeData[network]["account_node"] = nodeData[network]["master_node"].derivePath(testData["account_path"]);
      final accountXPriv = nodeData[network]["account_node"].toXPriv();
      final accountXPub = nodeData[network]["account_node"].toXPub();

      // compare the master private and public key with the original testing data
      expect(accountXPriv, testData[network]["account_xpriv"]);
      expect(accountXPub, testData[network]["account_xpub"]);
    }
  });

  // The following few methods work with child nodes of the account node created above.
  // Tests to generate various outputs from each child nodes are separated
  // It is not determined here how many child nodes are created.
  // The test simply follows the index and thus number of child nodes stored in the original test file.
  // That being said, it takes only the index number and derives all other data itself.

  // First generate private keys for each of the child nodes
  test('Generating child nodes and private keys', () {
    // Generate child nodes for each network
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];

      testData[network]["child_nodes"].forEach((childTestData) {
        // generate the child node and extract its private key
        final childNode = nodeData[network]["account_node"].derive(childTestData["index"]);
        final childPrivateKey = childNode.privateKey;

        // compare the private key with the original test file
        expect(childPrivateKey, childTestData["private_key"]);
      });
    };
  });

  test('Generating child nodes and legacy addresses', () {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      testData[network]["child_nodes"].forEach((childTestData) {
        final childNode = nodeData[network]["account_node"].derive(childTestData["index"]);
        final childLegacy = childNode.toLegacyAddress();

        expect(childLegacy, childTestData["legacy"]);
      });
    }
  });

  test('Generating child nodes and cash addresses', () {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      testData[network]["child_nodes"].forEach((childTestData) {
        final childNode = nodeData[network]["account_node"].derive(childTestData["index"]);
        final childCashAddr = childNode.toCashAddress();

        expect(childCashAddr, childTestData["cashAddress"]);
      });
    }
  });

  // For these conversion tests the script uses the addresses from the original script
  test('Converting cashAddr to legacy', () {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      testData[network]["child_nodes"].forEach((childTestData) {
        final cashAddr = childTestData["cashAddress"];

        expect(Bitbox.Address.toLegacyAddress(cashAddr), childTestData["toLegacy"]);
      });
    };
  });

  test('Converting legacy to cashAddr', () {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      testData[network]["child_nodes"].forEach((childTestData) {
        final legacy = childTestData["legacy"];

        expect(Bitbox.Address.toCashAddress(legacy), childTestData["toCashAddr"]);
      });
    }
  });

  // Placeholder to store addresses with balance for which to fetch utxos later
  final utxosToFetch = <String, List<String>>{};

  test('Fetching address details', () async {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];
      utxosToFetch[network] = <String>[];

      // set rest url based on which network is being tested
      Bitbox.Bitbox.setRestUrl(restUrl: network == "mainnet" ? Bitbox.Bitbox.restUrl : Bitbox.Bitbox.trestUrl);

      // Placeholder for test addresses to fetch the details off
      List<String> testAddresses = <String>[];

      // Accumulate the list of all addresses from the test file
      testData[network]["child_nodes"].forEach((childTestData) {
        testAddresses.add(childTestData["cashAddress"]);
      });

      // test retreiving both single address details and list of all addresses
      final detailsSingle = await Bitbox.Address.details(testAddresses.first);
      final detailsAll = await Bitbox.Address.details(testAddresses) as List;

      // check if the return data is of the expected type
      expect(true, detailsSingle is Map);
      expect(true, detailsAll is List);

      // store all addresses with non-zero confirmed balance
      detailsAll.forEach((addressDetails) {
        if (addressDetails["balance"] > 0) {
          utxosToFetch[network].add(addressDetails["cashAddress"]);
        }
      });
    }
  });

  // Placeholder for utxo details for later use
  Map<String, List> utxos = {};

  test('Fetching utxos', () async {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];

      // placeholder for utxos for the particular network
      utxos[network] = [];

      // If there were addresses with non-zero balance for this network, fetch their utxos
      if (utxosToFetch[network].length > 0) {
        // set the appropriate rest api url
        Bitbox.Bitbox.setRestUrl(restUrl: network == "mainnet" ? Bitbox.Bitbox.restUrl : Bitbox.Bitbox.trestUrl);

        // fetch the required utxo details
        utxos[network] = await Bitbox.Address.utxo(utxosToFetch[network]) as List;

        // go through the list of the returned utxos
        utxos[network].forEach((addressUtxo) {
          // go through each address in the testing data to test if the utxos match
          testData[network]["child_nodes"].forEach((childNode) {
            if (childNode["cashAddress"] == addressUtxo["cashAddress"]) {
              for (int i = 0; i < addressUtxo["utxos"].length; i++) {
                Bitbox.Utxo utxo = addressUtxo["utxos"][i];

                expect(utxo.txid, childNode["utxos"][i]["txid"]);
              };
            }
          });
        });
      }
    }
  });

  // Placeholder for both mainnet and testnet raw transaction data
  Map<String, String> rawTx = {};

  // If there are unspent outputs for any of the addresses in any of the network, built spending transactions and
  // compare them with the testing data
  test('Building spending transaction', () async {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];

      // Placeholder for total unspent balance
      int totalBalance = 0;

      // placeholder for input signatures
      final signatures = <Map>[];

      // create a transaction builder for the appropriate network
      final builder = Bitbox.Bitbox.transactionBuilder(testnet: network == "testnet");

      // go through the list of utxos accumulated in the previous test
      utxos[network].forEach((addressUtxos) {
        testData[network]["child_nodes"].forEach((childNode) {
          if (childNode["cashAddress"] == addressUtxos["cashAddress"]) {
            addressUtxos["utxos"].forEach((Bitbox.Utxo utxo) {
              // add the utxo as an input for the transaction
              builder.addInput(utxo.txid, utxo.vout);

              // add a signature to the list to be used later
              signatures.add({
                "vin": signatures.length,
                "key_pair": nodeData[network]["account_node"].derive(childNode["index"]).keyPair,
                "original_amount": utxo.satoshis
              });

              totalBalance += utxo.satoshis;
            });
          }
        });
      });

      // if there is an unspent balance, create a spending transaction
      if (totalBalance > 0) {
        // calculate the fee based on number of inputs and one expected output
        final fee = Bitbox.BitcoinCash.getByteCount(signatures.length, 1);

        // calculate how much balance will be left over to spent after the fee
        final sendAmount = totalBalance - fee;

        // add the ouput based on the address provided in the testing data
        builder.addOutput(testData[network]["output_address"], sendAmount);

        // sign all inputs
        signatures.forEach((signature) {
          builder.sign(signature["vin"], signature["key_pair"], signature["original_amount"]);
        });

        // build the transaction
        final tx = builder.build();

        // compare the transaction raw hex with the output from the original bitbox
        expect(tx.toHex(), testData[network]["testing_tx_hex"]);

        // add the raw transaction to the list to be (optionally) broadcastd
        rawTx[network] = tx.toHex();
      }
    }
  });

  // broadcast the transactions if the appropriate flags have been raised
  test('Broadcasting the transaction', () async {
    for (int i = 0; i < networks.length; i++) {
      final network = networks[i];

      // check if there is a transaction for this network
      if (rawTx.containsKey(network)) {
        // check if this transaction is supposed to be broadcasted
        if ((network == "testnet" && BROADCAST_TESTNET_TRANSACTION)
            || (network == "mainnet" && BROADCAST_MAINNET_TRANSACTION)) {
          // set the appropraite rest api url
          Bitbox.Bitbox.setRestUrl(restUrl: network == "mainnet" ? Bitbox.Bitbox.restUrl : Bitbox.Bitbox.trestUrl);
          // broadcast the transaction and print its id
          final txid = await Bitbox.RawTransactions.sendRawTransaction(rawTx[network]);
          print("$network txid: $txid");

          expect(true, txid is String);
        }
      }
    }
  });
}
