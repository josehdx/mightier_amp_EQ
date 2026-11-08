import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../devices/NuxConstants.dart';

enum MidiSetupStatus {
  bluetoothOff,
  deviceIdle,
  deviceSearching,
  deviceFound,
  deviceConnecting,
  deviceConnected,
  deviceDisconnected,
  unknown
}

enum BleState { off, on }

enum BleDeviceState { disconnected, connecting, connected, disconnecting }

enum BleError {
  unavailable,
  permissionDenied,
  locationServiceOff,
  scanPermissionDenied
}

typedef ScanResultsCallback = void Function(
    List<BLEScanResult> nuxDevices, List<BLEScanResult> controllerDevices);

abstract class BLEScanResult {
  String get id;
  String get name;
  late BLEDevice _device;
  @protected
  set device(BLEDevice val) => _device = val;
  BLEDevice get device => _device;
}

abstract class BLEDevice {
  String get name;
  String get id;
  Stream<BleDeviceState> get state;
}

class BLEConnection {
  final Stream<List<int>> _dataStream;
  Stream<List<int>> get data => _dataStream;

  BLEConnection(this._dataStream);
}

abstract class BLEController {
  static const String midiServiceGuid = "03b80e5a-ede8-4b33-a751-6ce34ec4c700";
  static const String midiCharacteristicGuid =
      "7772e5db-3868-4112-a1a9-f2669d106bf3";

  MidiSetupStatus _currentStatus = MidiSetupStatus.unknown;
  final StreamController<MidiSetupStatus> _status =
      StreamController.broadcast();
  Stream<MidiSetupStatus> get status => _status.stream;

  BleState _bleState = BleState.off;
  @protected
  set bleState(BleState state) => _bleState = state;
  BleState get bleState => _bleState;

  @protected
  set currentStatus(MidiSetupStatus val) => _currentStatus = val;
  MidiSetupStatus get currentStatus => _currentStatus;

  BLEDevice? get connectedDevice;
  final StreamController<bool> _scanStatus = StreamController.broadcast();
  Stream<bool> get isScanningStream => _scanStatus.stream;
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  ListQueue<List<int>> dataQueue = ListQueue<List<int>>();

  @protected
  late List<String> Function() deviceListProvider;

  @protected
  late ScanResultsCallback onScanResults;
  @protected
  List<String> forcedDevices;

  BLEController(this.forcedDevices);

  void setAmpDeviceIdProvider(List<String> Function() provider) {
    deviceListProvider = provider;
  }

  Future init(ScanResultsCallback callback) async {
    onScanResults = callback;
  }

  Future<bool> isAvailable();

  void startScanning();
  void stopScanning();
  Future<BLEConnection?> connectToDevice(BLEDevice device);
  void disconnectDevice();
  StreamSubscription<List<int>> registerDataListener(
      Function(List<int>) listener);

  bool _isNfSysEx(List<int> data) {
    return data.length > 10 &&
        data[2] == MidiMessageValues.sysExStart &&
        data[8] == 0x4E &&
        data[9] == 0x46;
  }

  void sendData(List<int> data) {
    if (data.length > 3 &&
        data[2] == MidiMessageValues.controlChange &&
        dataQueue.isNotEmpty) {
      var inFlight = dataQueue.removeFirst();
      dataQueue.removeWhere((element) =>
          element.length > 3 &&
          element[2] == MidiMessageValues.controlChange &&
          element[3] == data[3]);
      dataQueue.addFirst(inFlight);
    }
    if (_isNfSysEx(data) && dataQueue.isNotEmpty) {
      var inFlight = dataQueue.removeFirst();
      dataQueue.removeWhere((element) => _isNfSysEx(element));
      dataQueue.addFirst(inFlight);
    }

    dataQueue.addLast(data);
    // Single-flight: _queueSender() returns immediately if a loop is already
    // running (even one that is asleep inside a DSP settle delay).
    _queueSender();
  }

  bool _isProgramChange(List<int> d) =>
      d.length > 2 && d[2] == MidiMessageValues.programChange;

  /// Drops queued messages. With [keepChannelChange] a Program Change that has
  /// not been written yet survives, so that "channel change + full preset
  /// resend" does not lose the channel change (the amp would then apply the
  /// parameters to the wrong channel).
  void clearDataQueue({bool keepChannelChange = false}) {
    if (keepChannelChange) {
      dataQueue.removeWhere((e) => !_isProgramChange(e));
    } else {
      dataQueue.clear();
    }
  }

  VoidCallback? _onQueueEmpty;

  void onDataQueueEmpty(VoidCallback onQueueEmpty) {
    if (dataQueue.isEmpty) {
      onQueueEmpty.call();
    } else {
      _onQueueEmpty = onQueueEmpty;
    }
  }

  void dispose();

  /// Time the amp's DSP needs to load a channel after a Program Change.
  /// Any CC/SysEx that arrives earlier is dropped or overwritten by the amp.
  static const Duration dspSettleDelay = Duration(milliseconds: 200);

  /// True while a send loop is alive. Guards against a second concurrent loop
  /// (which would bypass the DSP settle delay of the first one).
  bool _isSending = false;

  Future<void> _queueSender() async {
    if (_isSending) return;
    _isSending = true;
    try {
      await _drainQueue();
    } finally {
      _isSending = false;
    }
    _onQueueEmpty?.call();
    _onQueueEmpty = null;
  }

  Future<void> _drainQueue() async {
    while (dataQueue.isNotEmpty) {
      if (connectedDevice == null) {
        dataQueue.clear();
        break;
      }
      var data = dataQueue.first;
      try {
        if (isWriteReady) {
          bool noResponse = true;

          // PROTECT A2DP AUDIO: 
          // If the OS spams massive SysEx writes consecutively without response pacing,
          // it chokes the shared Bluetooth cache and drops music player audio.
          if ((Platform.isAndroid || Platform.isIOS) &&
              data.length > 6 &&
              data[2] == MidiMessageValues.sysExStart &&
              data[6] == SyxMsg.kSYX_MODULELINK) {
            noResponse = false;
            await Future.delayed(const Duration(milliseconds: 100));
          }
          
          await writeToCharacteristic(data, noResponse);

          // --- NEW: DSP SETTLE DELAY ---
          if (data.length > 2 && data[2] == MidiMessageValues.programChange) {
            // Give the amp time to load the preset from memory 
            // before blasting it with the new parameter CCs
            await Future.delayed(dspSettleDelay);
          } 
          // Existing dynamic pacing
          else if (Platform.isAndroid || Platform.isIOS) {
            // SysEx payload pacing to save the audio stream
            if (data.length > 20) {
              await Future.delayed(const Duration(milliseconds: 25));
            } else {
              await Future.delayed(const Duration(milliseconds: 8));
            }
          }
        } else {
          dataQueue.clear();
          break;
        }
      } catch (e) {
        debugPrint("BLE write error: $e");
      } finally {
        if (dataQueue.isNotEmpty && identical(dataQueue.first, data)) {
          dataQueue.removeFirst();
        }
      }
    }
  }

  @protected
  void setMidiSetupStatus(MidiSetupStatus status) {
    _currentStatus = status;
    _status.add(status);
  }

  @protected
  void setScanningStatus(bool scanning) {
    _isScanning = scanning;
    _scanStatus.add(scanning);
  }

  bool get isWriteReady;
  Future writeToCharacteristic(List<int> data, bool noResponse);
}