// (c) 2020-2021 Dian Iliev (Tuntorius)
// This code is licensed under MIT license (see LICENSE.md for details)

import 'package:flutter/material.dart';
import 'package:mighty_plug_manager/bluetooth/NuxDeviceControl.dart'; 
import 'package:mighty_plug_manager/bluetooth/devices/NuxDevice.dart';
import 'package:mighty_plug_manager/bluetooth/devices/communication/plugProCommunication.dart';

import '../NuxConstants.dart';
import '../NuxFXID.dart';
import '../effects/Processor.dart';
import '../effects/plug_pro/Amps.dart';
import '../effects/plug_pro/Cabinet.dart';
import '../effects/plug_pro/Compressor.dart';
import '../effects/plug_pro/Delay.dart';
import '../effects/plug_pro/EFX.dart';
import '../effects/plug_pro/EQ.dart';
import '../effects/plug_pro/Modulation.dart';
import '../effects/NoiseGate.dart';
import '../effects/plug_pro/Reverb.dart';
import '../effects/plug_pro/EmptyEffects.dart';
import 'Preset.dart';
import 'preset_constants.dart';
import 'package:convert/convert.dart';
import 'package:mighty_plug_manager/utilities/SyncDebug.dart';

class PlugProPreset extends Preset {
  @override
  NuxDevice device;
  @override
  int channel;
  @override
  String channelName;
  
  @override
  Color get channelColor {
    if (channel >= 0 && channel < PresetConstants.channelColorsPro.length) {
      return PresetConstants.channelColorsPro[channel];
    }
    return Colors.blue; 
  }

  // CACHED INSTANCES
  final NoiseGatePro _noiseGate = NoiseGatePro();
  final WahDummyPro _wahDummy = WahDummyPro();

  late final List<Processor> _cmpList = [RoseCompPro(), KComp(), StudioComp()];
  
  late final List<Processor> _efxList = [
    DistortionPlus(), RCBoost(), ACBoost(), DistOne(),
    TSDrive(), BluesDrive(), MorningDrive(), EatDist(),
    RedDirt(), Crunch(), MuffFuzz(), Katana(), STSinger(), TouchWahPro()
  ];
  
  late final List<Processor> _modList = [
    ModCE1(), ModCE2(), STChorusPro(), Vibrato(), Detune(),
    FlangerPro(), Phase90(), Phase100(), SCFPro(),
    VibePro(), TremoloPro(), Rotary(), SCH1Pro(), MonoOctave()
  ];
  
  late final List<Processor> _delayList = [
    AnalogDelay(), AnalogDelayV2(), DigitalDelay(), 
    ModDelay(), TapeEcho(), PanDelay(), PhiDelayPro()
  ];
  
  late final List<Processor> _reverbList = [
    RoomReverb(), HallReverb(), SpringReverb(), PlateReverb(), ShimmerReverb(), DampReverbPro()
  ];

  @override
  final List<Amplifier> amplifierList = <Amplifier>[];
  final List<CabinetPro> cabinetList = <CabinetPro>[];

  late final List<Processor> eqList = [
    EQSixBand(),
    EQTenBand(),
  ];

  List<NuxFXID> processorAtSlot = [];

  bool wahEnabled = true;
  bool noiseGateEnabled = true;
  bool compressorEnabled = true;
  bool efxEnabled = true;
  bool ampEnabled = true;
  bool irEnabled = true;
  bool modulationEnabled = true;
  bool eqEnabled = true;
  bool delayEnabled = true;
  bool reverbEnabled = true;
  bool srEnabled = true;

  int selectedComp = 0;
  int selectedEfx = 0;
  int selectedAmp = 0;
  int selectedCabinet = 0;
  int selectedEQ = 0;
  int selectedMod = 0;
  int selectedDelay = 0;
  int selectedReverb = 0;

  // ---------------------------------------------------------------------
  // Channel volume (mirrors MightyMk2Preset).
  //
  // Before this change PlugProPreset inherited the empty Preset versions:
  // volume was always 0, setVolume/sendVolume did nothing, the on-screen
  // volume slider sent nothing and saved presets always carried volume 0.
  //
  // volumeFixEnabled = false restores that original behaviour for A/B tests.
  // ---------------------------------------------------------------------
  static bool volumeFixEnabled = true;

  double _volume = 0; // dB, -12..+12 (DecibelFormatterMPPro)

  // Exact byte last reported by the amp. Avoids the dB round trip, which
  // shifts some values by one step. Cleared whenever the app changes volume.
  int? _volumeRaw;

  /// The 0..100 byte that represents this preset's volume on the wire.
  int get volumeMidi {
    final raw = _volumeRaw;
    if (volumeFixEnabled && raw != null) return raw;
    return device.decibelFormatter!.valueToMidi7Bit(volume);
  }

  @override
  double get volume => volumeFixEnabled ? _volume : 0;

  @override
  set volume(double vol) {
    setVolume(vol, true);
  }

  @override
  void setVolume(double vol, bool btTransmit) {
    if (!volumeFixEnabled) return; // original: no-op
    _volume = vol;
    _volumeRaw = null; // app-originated value: no exact byte any more
    if (btTransmit) sendVolume();
  }

  @override
  void sendVolume() {
    if (!volumeFixEnabled) return; // original: no-op
    final comm = device.communication;
    if (comm is PlugProCommunication) {
      comm.sendChannelVolume(volumeMidi);
    }
  }

  @override
  int get qrDataLength => 114;

  @override
  Color effectColor(int index) {
    if (index < 0 || index >= processorAtSlot.length) return Colors.grey;
    var proc = getFXIDFromSlot(index);
    var effect = device.getProcessorInfoByFXID(proc);
    return effect?.color ?? Colors.grey;
  }

  @override
  bool slotSwitchable(int index) {
    return true;
  }

  @override
  void setFirmwareVersion(int version) {}

  PlugProPreset(
      {required this.device, required this.channel, required this.channelName})
      : super(channel: channel, channelName: channelName, device: device) {
    amplifierList.addAll([
      JazzClean(), DeluxeRvb(), BassMate(), Tweedy(),
      TwinRvb(), HiWire(), CaliCrunch(), ClassA30(),
      Plexi100(), Plexi45(), Brit800(), Pl1987x50(),
      Slo100(), FiremanHBE(), DualRect(), DIEVH4(),
      AGL(), MLD(), OptimaAir(), Stageman(),
    ]);

    cabinetList.addAll([
      JZ120Pro(), DR112Pro(), TR212Pro(), HIWIRE412(),
      CALI112(), A112(), GB412Pro(), M1960AX(),
      M1960AV(), M1960TV(), SLO412(), FIREMAN412(),
      RECT412(), DIE412(), MATCH212(), UBER412(),
      BS410(), A212Pro(), M1960AHW(), M1936(),
      BUDDA112(), Z212(), SUPERVERB410(), VIBROKING310(),
      AGLDB810(), AMPSV212(), AMPSV410(), AMPSV810(),
      BASSGUY410(), EDEN410(), MKB410(), GHBIRDPro(),
      GJ15Pro(), MD45Pro(), UserCab()
    ]);

    for (int i = 0; i < PresetDataIndexPlugPro.defaultEffects.length; i++) {
      processorAtSlot.add(PresetDataIndexPlugPro.defaultEffects[i]);
    }
  }

  @override
  bool slotEnabled(int index) {
    var proc = getFXIDFromSlot(index);
    return _FXIDEnabled(proc);
  }

  bool _FXIDEnabled(NuxFXID fxid) {
    switch (fxid.value) {
      case PresetDataIndexPlugPro.Head_iWAH: return wahEnabled;
      case PresetDataIndexPlugPro.Head_iNG: return noiseGateEnabled;
      case PresetDataIndexPlugPro.Head_iCMP: return compressorEnabled;
      case PresetDataIndexPlugPro.Head_iEFX: return efxEnabled;
      case PresetDataIndexPlugPro.Head_iAMP: return ampEnabled;
      case PresetDataIndexPlugPro.Head_iEQ: return eqEnabled;
      case PresetDataIndexPlugPro.Head_iMOD: return modulationEnabled;
      case PresetDataIndexPlugPro.Head_iDLY: return delayEnabled;
      case PresetDataIndexPlugPro.Head_iRVB: return reverbEnabled;
      case PresetDataIndexPlugPro.Head_iCAB: return irEnabled;
      case PresetDataIndexPlugPro.Head_iSR: return srEnabled;
      default: return true;
    }
  }

  @override
  void setSlotEnabled(int index, bool value, bool notifyBT) {
    var proc = getFXIDFromSlot(index);
    switch (proc.value) {
      case PresetDataIndexPlugPro.Head_iWAH: wahEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iNG: noiseGateEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iCMP: compressorEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iEFX: efxEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iAMP: ampEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iEQ: eqEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iMOD: modulationEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iDLY: delayEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iRVB: reverbEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iCAB: irEnabled = value; break;
      case PresetDataIndexPlugPro.Head_iSR: srEnabled = value; break;
    }

    if (notifyBT) {
      device.communication.sendSlotEnabledState(index);
    }
    super.setSlotEnabled(index, value, false); 
  }

  // CRITICAL FIX: Safe mapping helper function for retrieving lists
  List<Processor> _effectsForFXID(NuxFXID fxid) {
    switch (fxid.value) {
      case PresetDataIndexPlugPro.Head_iWAH: return [_wahDummy];
      case PresetDataIndexPlugPro.Head_iCMP: return _cmpList;
      case PresetDataIndexPlugPro.Head_iEFX: return _efxList;
      case PresetDataIndexPlugPro.Head_iAMP: return amplifierList;
      case PresetDataIndexPlugPro.Head_iCAB: return cabinetList;
      case PresetDataIndexPlugPro.Head_iEQ:  return eqList;
      case PresetDataIndexPlugPro.Head_iNG:  return [_noiseGate];
      case PresetDataIndexPlugPro.Head_iMOD: return _modList;
      case PresetDataIndexPlugPro.Head_iDLY: return _delayList;
      case PresetDataIndexPlugPro.Head_iRVB: return _reverbList;
    }
    return [];
  }

  @override
  List<Processor> getEffectsForSlot(int slot) => _effectsForFXID(getFXIDFromSlot(slot));

  // CRITICAL FIX: Actively scan the array for the correct matching hardware ID
  @override
  int getEffectArrayIndexFromNuxIndex(NuxFXID fxid, int nuxIndex) {
    final list = _effectsForFXID(fxid);
    for (int i = 0; i < list.length; i++) {
      if (list[i].nuxIndex == nuxIndex) return i;
    }
    return 0; // Fall back to first effect instead of crashing
  }

  @override
  int getSelectedEffectForSlot(int slot) {
    var proc = getFXIDFromSlot(slot);
    int selected = 0;

    switch (proc.value) {
      case PresetDataIndexPlugPro.Head_iCMP: selected = selectedComp; break;
      case PresetDataIndexPlugPro.Head_iEFX: selected = selectedEfx; break;
      case PresetDataIndexPlugPro.Head_iAMP: selected = selectedAmp; break;
      case PresetDataIndexPlugPro.Head_iCAB: selected = selectedCabinet; break;
      case PresetDataIndexPlugPro.Head_iEQ: selected = selectedEQ; break;
      case PresetDataIndexPlugPro.Head_iMOD: selected = selectedMod; break;
      case PresetDataIndexPlugPro.Head_iDLY: selected = selectedDelay; break;
      case PresetDataIndexPlugPro.Head_iRVB: selected = selectedReverb; break;
    }

    // UI HARDENING: Prevent crash if hardware sends corrupted/out-of-bounds selection
    final listLength = getEffectsForSlot(slot).length;
    if (listLength == 0) return 0;
    return selected.clamp(0, listLength - 1);
  }

  @override
  void setSelectedEffectForSlot(int slot, int index, bool notifyBT) {
    var proc = getFXIDFromSlot(slot);
    _setSelectedEffectForFXID(proc, index);
    super.setSelectedEffectForSlot(slot, index, notifyBT);
  }

  void _setSelectedEffectForFXID(NuxFXID fxid, int index) {
    switch (fxid.value) {
      case PresetDataIndexPlugPro.Head_iCMP: selectedComp = index; break;
      case PresetDataIndexPlugPro.Head_iEFX: selectedEfx = index; break;
      case PresetDataIndexPlugPro.Head_iAMP: selectedAmp = index; break;
      case PresetDataIndexPlugPro.Head_iCAB: selectedCabinet = index; break;
      case PresetDataIndexPlugPro.Head_iEQ: selectedEQ = index; break;
      case PresetDataIndexPlugPro.Head_iMOD: selectedMod = index; break;
      case PresetDataIndexPlugPro.Head_iDLY: selectedDelay = index; break;
      case PresetDataIndexPlugPro.Head_iRVB: selectedReverb = index; break;
    }
  }

  @override
  NuxFXID getFXIDFromSlot(int slot) {
    if (slot < 0 || slot >= processorAtSlot.length) return NuxFXID.fromInt(0);
    return processorAtSlot[slot];
  }

  @override
  int? getSlotFromFXID(NuxFXID fxid) {
    for (int i = 0; i < processorAtSlot.length; i++) {
      if (processorAtSlot[i] == fxid) return i;
    }
    return null;
  }

  @override
  void setFXIDAtSlot(int slot, NuxFXID fxid) {
    while (processorAtSlot.length <= slot) {
      processorAtSlot.add(NuxFXID.fromInt(0));
    }
    processorAtSlot[slot] = fxid;
  }

  @override
  void swapProcessorSlots(int from, int to, notifyBT) {
    if (from >= processorAtSlot.length || to >= processorAtSlot.length) return;
    
    var fxFrom = processorAtSlot[from];

    if (from < to) {
      for (int i = from; i < to; i++) {
        processorAtSlot[i] = processorAtSlot[i + 1];
      }
    } else {
      for (int i = from; i > to; i--) {
        processorAtSlot[i] = processorAtSlot[i - 1];
      }
    }

    processorAtSlot[to] = fxFrom;

    if (notifyBT) {
      device.communication.sendSlotOrder();
      var fw = (device.communication as PlugProCommunication);
      if (device.getPreset(device.selectedChannel) == this) {
        fw.saveCurrentPreset(device.selectedChannel);
        fw.requestPresetByIndex(device.selectedChannel);
      }
    }
    super.swapProcessorSlots(from, to, notifyBT);
  }

  void setVolumeRaw(int vol) {
    // SAFEGUARD: Catch buggy legacy presets that saved MIDI 0 (-12 dB) 
    // and force them to MIDI 50 (0.0 dB) to prevent the DSP race condition.
    if (vol == 0) vol = 50;

    setVolume(device.decibelFormatter!.midi7BitToValue(vol), false);
    if (volumeFixEnabled) _volumeRaw = vol; // keep the exact amp byte
  }

  @override
  void setupPresetFromNuxDataArray(List<int> nuxData) {
    if (nuxData.length < 10) return;

    SyncDebug.dumpApp('PRE-PARSE ch$channel', this); // SYNCDEBUG

    var loadedPreset = hex.encode(nuxData);

    NuxDeviceControl.instance().diagData.lastNuxPreset = loadedPreset;
    NuxDeviceControl.instance().updateDiagnosticsData(nuxPreset: loadedPreset);

    for (int i = 0; i < PresetDataIndexPlugPro.effectTypesIndex.length; i++) {
      int nuxSlot = PresetDataIndexPlugPro.effectTypesIndex[i];
      NuxFXID fxid = NuxFXID.fromInt(nuxSlot);

      //set proper effect
      int effectParam = nuxData[nuxSlot];
      int effectIndex = effectParam & 0x3f;
      bool effectOn = (effectParam & 0x40) == 0;

      effectIndex = getEffectArrayIndexFromNuxIndex(fxid, effectIndex);

      _setSelectedEffectForFXID(fxid, effectIndex);

      int? slot = getSlotFromFXID(fxid);
      if (slot != null) setSlotEnabled(slot, effectOn, false);
    }

    for (int i = 0; i < device.processorList.length; i++) {
      var fxid = getFXIDFromSlot(i);
      if (fxid.value == PresetDataIndexPlugPro.Head_iSR ||
          fxid.value == PresetDataIndexPlugPro.Head_iWAH) continue;
      
      var effects = getEffectsForSlot(i);
      var selected = getSelectedEffectForSlot(i);
      
      if (selected >= 0 && selected < effects.length) {
         effects[selected].setupFromNuxPayload(nuxData);
      }
    }

    if (volumeFixEnabled) {
      if (nuxData.length > PresetDataIndexPlugPro.MASTER) {
        setVolumeRaw(nuxData[PresetDataIndexPlugPro.MASTER]);
        if (device.presets[device.selectedChannel] == this) {
          // let the on-screen volume slider follow the amp
          device.deviceControl.masterVolumeNotifier.value = _volume;
        }
      } else {
        debugPrint("Error: master volume outside of preset data!");
      }
    } else {
      // original behaviour (volume dropped)
      double masterVol = nuxData[PresetDataIndexPlugPro.MASTER].toDouble();
      setVolume(masterVol, false);
    }

    SyncDebug.compare('POST-PARSE ch$channel', this, nuxData); // SYNCDEBUG
  }

  @override
  List<int> createNuxDataFromPreset() {
    List<int> data = List.filled(qrDataLength, 0);
    List<int> qrData = [];
    qrData.add(device.deviceQRId);
    qrData.add(device.deviceQRVersion);

    data[PresetDataIndexPlugPro.MASTER] = volumeMidi;

    for (int i = 0; i < PresetDataIndexPlugPro.effectTypesIndex.length; i++) {
      var nuxSlot = PresetDataIndexPlugPro.effectTypesIndex[i];
      NuxFXID fxid = NuxFXID.fromInt(nuxSlot);

      var slot = getSlotFromFXID(fxid);
      if (slot != null) {
        var effects = getEffectsForSlot(slot);
        var selected = getSelectedEffectForSlot(slot);

        if (selected >= 0 && selected < effects.length) {
          effects[selected].getNuxPayload(data, slotEnabled(slot));
        }
      }
    }

    int start = PresetDataIndexPlugPro.LINK1;
    for (int i = 0; i < processorAtSlot.length; i++) {
      if (processorAtSlot[i].value == PresetDataIndexPlugPro.Head_iSR ||
          processorAtSlot[i].value == PresetDataIndexPlugPro.Head_iWAH) {
        continue;
      }
      data[start] = processorAtSlot[i].toInt();
      start++;
    }

    qrData.addAll(data);
    return qrData;
  }
}