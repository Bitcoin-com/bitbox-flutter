import 'dart:typed_data';
import '../crypto/crypto.dart';
import '../utils/opcodes.dart';
import 'package:meta/meta.dart';
import 'package:bip32/src/utils/ecurve.dart' show isPoint;
import 'package:bs58check_dart/bs58check.dart' as bs58check;
import 'script.dart' as bscript;

import 'network.dart';

/// This is almost exact copy of https://github.com/anicdh/bitcoin_flutter/blob/master/lib/src/payments/p2pkh.dart
/// except using [Opcodes] static members instead of map
class P2SH {
  P2SHData data;
  Network network;

  P2SH({@required data, network}) {
    this.network = network ?? Network.bitcoinCash();
    this.data = data;
    _init();
  }

  _init() {
    if (data.address != null) {
      _getDataFromAddress(data.address);
      _getDataFromHash();
    } else if (data.hash != null) {
      _getDataFromHash();
    } else if (data.output != null) {
      if (!isValidOutput(data.output))
        throw new ArgumentError('Output is invalid');
      data.hash = data.output.sublist(2, 22);
      _getDataFromHash();
    } else if (data.scriptHash != null) {
      data.hash = Crypto.hash160(data.scriptHash);
      _getDataFromHash();
      _getDataFromChunk();
    } else if (data.input != null) {
      List<dynamic> _chunks = bscript.decompile(data.input);
      _getDataFromChunk(_chunks);
      if (_chunks.length != 2) throw new ArgumentError('Input is invalid');
      if (!bscript.isCanonicalScriptSignature(_chunks[0]))
        throw new ArgumentError('Input has invalid signature');
      if (!isPoint(_chunks[1]))
        throw new ArgumentError('Input has invalid pubkey');
    } else {
      throw new ArgumentError("Not enough data");
    }
  }

  void _getDataFromChunk([List<dynamic> _chunks]) {
    if (data.scriptHash == null && _chunks != null) {
      data.scriptHash = (_chunks[1] is int)
          ? new Uint8List.fromList([_chunks[1]])
          : _chunks[1];
      data.hash = Crypto.hash160(data.scriptHash);
      _getDataFromHash();
    }
    if (data.signature == null && _chunks != null)
      data.signature = (_chunks[0] is int)
          ? new Uint8List.fromList([_chunks[0]])
          : _chunks[0];
    if (data.input == null &&
        data.scriptHash != null &&
        data.signature != null) {
      data.input = bscript.compile([data.signature, data.scriptHash]);
    }
  }

  void _getDataFromHash() {
    if (data.address == null) {
      final payload = new Uint8List(21);
      payload.buffer.asByteData().setUint8(0, network.scriptHash);
      payload.setRange(1, payload.length, data.hash);
      data.address = bs58check.encode(payload);
    }
    if (data.output == null) {
      data.output =
          bscript.compile([Opcodes.OP_HASH160, data.hash, Opcodes.OP_EQUAL]);
    }
  }

  void _getDataFromAddress(String address) {
    Uint8List payload = bs58check.decode(address);
    final version = payload.buffer.asByteData().getUint8(0);
    if (version != network.scriptHash)
      throw new ArgumentError('Invalid version or Network mismatch');
    data.hash = payload.sublist(1);
    if (data.hash.length != 20) throw new ArgumentError('Invalid address');
  }
}

class P2SHData {
  String address;
  Uint8List hash;
  Uint8List output;
  Uint8List signature;
  Uint8List scriptHash;
  Uint8List input;
  P2SHData(
      {this.address,
      this.hash,
      this.output,
      this.scriptHash,
      this.input,
      this.signature});

  @override
  String toString() {
    return 'P2SHData{address: $address, hash: $hash, output: $output, signature: $signature, pubkey: $scriptHash, input: $input}';
  }
}

isValidOutput(Uint8List data) {
  return data.length == 23 &&
      data[0] == Opcodes.OP_HASH160 &&
      data[1] == 0x14 &&
      data[2] == Opcodes.OP_EQUAL;
}
