import 'dart:async';

import 'package:flutter/foundation.dart';

import '../NuxConstants.dart';
import '../NuxDevice.dart';
import '../NuxFXID.dart';
import '../effects/Processor.dart';
import '../presets/NamProPreset.dart';
import 'plugProCommunication.dart';

const List<int> _kNfHeader = [0x43, 0x58, 0x70, 0x04, 0x02, 0x4E, 0x46, 0x01];
const int _kNfReplyMinLength = 50;
const int _kNfOpOffset = 11;
const int _kNfPayloadOffset = 17;

// "NG" = NAM tone controls (Input, Bass, Middle, Treble, Mix, Output).
// Same frame as "NF" but with 'G' (0x47) and a 6 byte payload.
const List<int> _kNgHeader = [0x43, 0x58, 0x70, 0x04, 0x02, 0x4E, 0x47, 0x01];
const int _kNgReplyLength = 24; // 22 SysEx bytes + 2 BLE-MIDI header bytes
const int _kNgOpOffset = 11;
const int _kNgSlotOffset = 16; // active slot echoed by the firmware
const int _kNgPayloadOffset = 17;

class NamProCommunication extends PlugProCommunication {
  int _nfNonce = 0;

  // Active model CRC harvested from the proprietary "NP" diagnostic poll
  List<int> activeModelCrc = [0, 0, 0, 0, 0];
  bool _crcReady = false;

  // The model CRC belongs to the model loaded on the CURRENT channel, so it is
  // stale after every channel change. While a channel sync is in progress we
  // wait for a fresh CRC and then READ the channel's FX A/B state from the amp
  // instead of overwriting it with the app's (possibly default) values.
  bool _pendingNfRead = false;

  // Latest NF write requested while a channel sync was running (e.g. a library
  // preset applied right after a channel change). It is flushed once the fresh
  // CRC arrives instead of being dropped and then overwritten by the read.
  List<int>? _queuedNfWrite;

  // NAM tone ("NG") writes are coalesced: a slider drag only ever sends the
  // newest value (max ~25 frames/s) and waits for a valid CRC like NF does.
  List<int>? _toneToSend;
  List<int>? _queuedNamTone;
  List<int> _lastToneSent = const [];
  Timer? _toneTimer;
  Timer? _channelSyncTimer;
  Timer? _crcTimeout;

  bool get _channelSyncBusy =>
      _pendingNfRead || (_channelSyncTimer?.isActive ?? false);

  void _scheduleChannelSync({required int delayMs}) {
    _crcReady = false;
    _pendingNfRead = true;
    _queuedNfWrite = null; // anything queued so far belonged to the old channel
    _queuedNamTone = null;
    _toneToSend = null;
    _channelSyncTimer?.cancel();
    _crcTimeout?.cancel();
    _channelSyncTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!device.deviceControl.isConnected) {
        _pendingNfRead = false;
        return;
      }
      requestModelCrc();
      // Safety net: never stay blocked if the CRC reply gets lost.
      _crcTimeout = Timer(const Duration(seconds: 2), () {
        _pendingNfRead = false;
      });
    });
  }

  /// The app switched channel: the amp loads the new model after the Program
  /// Change (+ ~300 ms DSP settle in the BLE queue), so refresh afterwards.
  @override
  List<int> setChannel(int channel) {
    _scheduleChannelSync(delayMs: 700);
    return super.setChannel(channel);
  }

  NamProCommunication(NuxDevice device, NuxDeviceConfiguration config)
      : super(device, config);

  /// Requests the active model CRC from the firmware's diagnostic "NP" Page 5.
  void requestModelCrc() {
    if (!device.deviceControl.isConnected) return;
    _crcReady = false;

    final List<int> frame = [
      0x80, 0x80, // BLE MIDI timestamp
      MidiMessageValues.sysExStart,
      0x43, 0x58, SysexPrivacy.kSYSEX_PRIVATE, 0x04, 0x02,
      0x4E, 0x50, // 'N', 'P'
      0x05, // Page 5
      MidiMessageValues.sysExEnd
    ];
    device.deviceControl.sendBLEData(frame);
  }

  void sendNfPayload(List<int> config32) {
    if (!device.deviceControl.isConnected) return;

    // Without the model CRC the firmware rejects the write. Request it and
    // let the reply handler resend the payload once it arrives.
    if (!_crcReady) {
      _queuedNfWrite = List<int>.from(config32);
      if (!_channelSyncBusy) requestModelCrc();
      return;
    }

    _nfNonce = (_nfNonce % 16383) + 1;
    final int token = _nfNonce;
    final int slot = device.selectedChannel;

    debugPrint(
        ">>> TRANSMITTING NF SYSEX (${config32.length} bytes) | CRC: $activeModelCrc");

    // Strict 52-byte MIDI SysEx (F0..F7) with the 2-byte BLE header in front.
    // NOTE: the custom NAM firmware does NOT take a trailing checksum byte.
    // The model CRC (5 bytes) below is the only integrity/security field.
    // Appending an extra byte makes the frame 53 bytes and the amp drops it,
    // which is why slider edits and FX A/B moves never took effect.
    final List<int> payload = [
      0x80, 0x80, // BLE MIDI timestamps
      MidiMessageValues.sysExStart,
      0x43, 0x58, SysexPrivacy.kSYSEX_PRIVATE, 0x04, 0x02, 0x4E, 0x46, 0x01,
      0x01, // Write op
      slot == 255 ? 127 : slot,
      token & 127,
      (token >> 7) & 127,
      0x00,
      ...activeModelCrc, // 5 model CRC bytes (firmware lock)
      ...config32, // exactly 32 bytes of Faust configuration
      MidiMessageValues.sysExEnd,
    ];

    device.deviceControl.sendBLEData(payload);
  }

  /// Routes a custom-SysEx parameter / effect to the right message: NAM tone
  /// controls -> "NG", FX A / FX B -> "NF".
  void sendCustomState(NamProPreset preset,
      {Parameter? param, Processor? effect}) {
    final bool tone = (param != null && preset.isNamToneParam(param)) ||
        (effect != null && preset.isNamToneEffect(effect));
    if (tone) {
      sendNamTone(preset.generateNamTone());
    } else {
      sendNfPayload(preset.generateNfPayload());
    }
  }

  /// Sends the six NAM tone controls (raw firmware units) to the amp.
  void sendNamTone(List<int> tone) {
    if (tone.length != 6) return;
    _toneToSend = List<int>.from(tone);
    if (_toneTimer?.isActive ?? false) return;
    _toneTimer = Timer(const Duration(milliseconds: 40), _flushNamTone);
  }

  void _flushNamTone() {
    final tone = _toneToSend;
    _toneToSend = null;
    if (tone == null || !device.deviceControl.isConnected) return;
    if (!_crcReady) {
      _queuedNamTone = tone;
      if (!_channelSyncBusy) requestModelCrc();
      return;
    }
    _transmitNamTone(tone);
  }

  void _transmitNamTone(List<int> tone) {
    _nfNonce = (_nfNonce % 16383) + 1;
    final int token = _nfNonce;
    final int slot = device.selectedChannel;
    _lastToneSent = List<int>.from(tone);

    debugPrint(">>> TRANSMITTING NG (NAM tone) $tone | slot $slot");

    // Strict frame, no checksum byte (same layout as the NF write).
    final List<int> frame = [
      0x80, 0x80,
      MidiMessageValues.sysExStart,
      0x43, 0x58, SysexPrivacy.kSYSEX_PRIVATE, 0x04, 0x02, 0x4E, 0x47, 0x01,
      0x01, // write op
      slot == 255 ? 127 : slot,
      token & 127,
      (token >> 7) & 127,
      0x00,
      ...activeModelCrc,
      ...tone,
      MidiMessageValues.sysExEnd,
    ];
    device.deviceControl.sendBLEData(frame);
  }

  void requestNamTone() {
    if (!device.deviceControl.isConnected) return;
    _nfNonce = (_nfNonce % 16383) + 1;
    final int token = _nfNonce;
    final List<int> frame = [
      0x80, 0x80,
      MidiMessageValues.sysExStart,
      0x43, 0x58, SysexPrivacy.kSYSEX_PRIVATE, 0x04, 0x02, 0x4E, 0x47, 0x01,
      0x00, // read op
      0x00, // slot (the reply reports the active slot)
      token & 127,
      (token >> 7) & 127,
      MidiMessageValues.sysExEnd,
    ];
    device.deviceControl.sendBLEData(frame);
  }

  bool _isNgReply(List<int> data) {
    if (data.length != _kNgReplyLength) return false;
    if (data[2] != MidiMessageValues.sysExStart) return false;
    for (int i = 0; i < _kNgHeader.length; i++) {
      if (data[3 + i] != _kNgHeader[i]) return false;
    }
    return true;
  }

  void _handleNgReply(List<int> data) {
    final int op = data[_kNgOpOffset] & ~0x40;
    final List<int> tone =
        data.sublist(_kNgPayloadOffset, _kNgPayloadOffset + 6);

    if (op == 1) {
      // Write echo: only log a mismatch (never fight a slider drag).
      if (_lastToneSent.length == 6 && tone.join(',') != _lastToneSent.join(',')) {
        debugPrint(
            "NamProComm: NG write not confirmed. sent=$_lastToneSent amp=$tone");
      }
      return;
    }

    // Ignore a reply that belongs to another (stale) channel.
    final int activeSlot = data[_kNgSlotOffset];
    if (activeSlot <= 6 && activeSlot != device.selectedChannel) return;

    final preset = device.getPreset(device.selectedChannel);
    if (preset is NamProPreset) {
      preset.applyNamTone(tone);
      device.deviceControl.forceNotifyListeners();
    }
  }

  @override
  void sendSlotOrder() {
    if (!device.deviceControl.isConnected) return;
    final preset = device.getPreset(device.selectedChannel);

    if (preset is NamProPreset) {
      final List<NuxFXID> stockBlocks = preset.processorAtSlot
          .where((id) => id != MightyNamFXID.fxA && id != MightyNamFXID.fxB)
          .toList();

      final List<int> nuxOrder = [stockBlocks.length];
      for (var fxid in stockBlocks) {
        nuxOrder.add(fxid.toInt());
      }

      final stockMsg = createSysExMessagePro(
        SysexPrivacy.kSYSEX_PRIVATE,
        SyxMsg.kSYX_MODULELINK,
        SyxDir.kSYXDIR_SET,
        nuxOrder,
      );
      device.deviceControl.sendBLEData(stockMsg);
      sendNfPayload(preset.generateNfPayload());
    } else {
      super.sendSlotOrder();
    }
  }

  @override
  void saveCurrentPreset(int index) {
    var preset = device.getPreset(index);
    if (preset is NamProPreset) {
      sendNfPayload(preset.generateNfPayload());
    }
    super.saveCurrentPreset(index);
  }

  void requestNfPayload({int op = 0, int? slot}) {
    if (!device.deviceControl.isConnected) return;
    _nfNonce = (_nfNonce % 16383) + 1;
    final int token = _nfNonce;
    final int targetSlot = slot ?? device.selectedChannel;

    final List<int> frame = [
      0x80, 0x80,
      MidiMessageValues.sysExStart,
      0x43, 0x58, SysexPrivacy.kSYSEX_PRIVATE, 0x04, 0x02, 0x4E, 0x46, 0x01,
      op & 0x7F,
      targetSlot == 255 ? 127 : targetSlot,
      token & 127,
      (token >> 7) & 127,
      MidiMessageValues.sysExEnd,
    ];

    device.deviceControl.sendBLEData(frame);
  }

  bool _isNfReply(List<int> data) {
    if (data.length < _kNfReplyMinLength) return false;
    if (data[2] != MidiMessageValues.sysExStart) return false;
    for (int i = 0; i < _kNfHeader.length; i++) {
      if (data[3 + i] != _kNfHeader[i]) return false;
    }
    return true;
  }

  void _handleNfReply(List<int> data) {
    final int opEcho = data[_kNfOpOffset];
    final int requestedOp = opEcho & ~0x40;
    if (requestedOp == 1) return;

    final int payloadStart = _kNfPayloadOffset;
    if (data.length < payloadStart + 32) return;

    final List<int> config32 = data.sublist(payloadStart, payloadStart + 32);
    final preset = device.getPreset(device.selectedChannel);
    if (preset is NamProPreset) {
      preset.applyNfPayload(config32);
      device.deviceControl.forceNotifyListeners();
    }
  }

  @override
  void onDataReceive(List<int> data) {
    // 1. Proprietary "NP" diagnostic replies (Page 5 = active model CRC)
    if (data.length >= 17 &&
        data[2] == MidiMessageValues.sysExStart &&
        data[3] == 0x43 &&
        data[4] == 0x58 &&
        data[5] == 0x70 &&
        data[6] == 0x04 &&
        data[7] == 0x02 &&
        data[8] == 0x01) {
      final int page = data[9];
      final int status = data[10];

      if (page == 0x05 && status == 0) {
        activeModelCrc = data.sublist(11, 16);
        _crcReady = true;
        _crcTimeout?.cancel();
        debugPrint(
            "NamProComm: Harvested Active Model CRC (ch ${device.selectedChannel}): $activeModelCrc");

        final queuedNf = _queuedNfWrite;
        final queuedTone = _queuedNamTone;
        final bool wasSyncing = _pendingNfRead;
        _queuedNfWrite = null;
        _queuedNamTone = null;
        _pendingNfRead = false;

        // Step 1: writes the app asked for while the CRC was stale: the app wins.
        if (queuedNf != null) sendNfPayload(queuedNf);
        if (queuedTone != null) _transmitNamTone(queuedTone);

        // Step 2: channel changed: pull what the amp holds for this channel.
        if (wasSyncing) {
          if (queuedNf == null) requestNfPayload(op: 0);
          if (queuedTone == null) requestNamTone();
        }

        // Step 3: plain CRC refresh with nothing pending: re-assert the FX state.
        if (queuedNf == null && queuedTone == null && !wasSyncing) {
          final preset = device.getPreset(device.selectedChannel);
          if (preset is NamProPreset) {
            sendNfPayload(preset.generateNfPayload());
          }
        }
      }
      return;
    }

    // 1b. "NG" (NAM tone) replies
    if (_isNgReply(data)) {
      _handleNgReply(data);
      return;
    }

    // 2. "NF" parameter read replies
    if (_isNfReply(data)) {
      _handleNfReply(data);
      return;
    }

    // 3. Standard NUX processing
    if (data.length > 9 &&
        data[2] == MidiMessageValues.sysExStart &&
        data[5] == SysexPrivacy.kSYSEX_PRIVATE &&
        data[6] == SyxMsg.kSYX_CURPRESET &&
        data[9] == 0x32) {
      super.onDataReceive(data);

      // Channel reported by the amp: refresh CRC, then read FX A/B state.
      _scheduleChannelSync(delayMs: 150);
      return;
    }

    super.onDataReceive(data);
  }
}