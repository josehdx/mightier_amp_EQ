import 'communication/communication.dart';
import 'communication/namProCommunication.dart';
import 'device_data/processors_list.dart';
import 'effects/Processor.dart';
import 'NuxMightyPlugPro.dart';
import '../NuxDeviceControl.dart';
import 'presets/NamProPreset.dart';
import 'NuxFXID.dart';

/// Device profile for the Mighty NAM custom firmware.
class NuxMightyNamPro extends NuxMightyPlugPro {
  late final NamProCommunication _communication =
      NamProCommunication(this, config);

  @override
  DeviceCommunication get communication => _communication;

  @override
  NuxFXID get ampFXID => PlugProFXID.amp;
  
  @override
  NuxFXID get cabFXID => PlugProFXID.cab;

  NuxMightyNamPro(NuxDeviceControl devControl) : super(devControl) {
    presets.clear();
    channelNames.clear();
    
    // Create the NamProPresets properly
    for (int i = 0; i < channelsCount; i++) {
      var preset = NamProPreset(
          device: this, channel: i, channelName: (i + 1).toString());
      
      // Setting firmware version triggers our overridden NamProPreset.setFirmwareVersion,
      // locking in the proper 11-block topology using valid UI FXIDs.
      preset.setFirmwareVersion(version.index);

      // Force the exact 11-block topology for this preset using the corrected list
      for (int slot = 0; slot < effectsChainLength; slot++) {
        preset.setFXIDAtSlot(slot, NamProPreset.namBaseEffects[slot]);
        preset.setSelectedEffectForSlot(slot, 0, false);
      }
      
      presets.add(preset);
      channelNames.add("Channel ${preset.channelName}");
    }
  }

  @override
  void setFirmwareVersionByIndex(int ver) {
    super.setFirmwareVersionByIndex(ver);
    
    for (var preset in presets) {
      for (int slot = 0; slot < effectsChainLength; slot++) {
        preset.setFXIDAtSlot(slot, NamProPreset.namBaseEffects[slot]);
      }
    }
  }

  @override
  String get productName => "NUX Mighty NAM";

  @override
  String get productNameShort => "Mighty NAM";

  @override
  String get productStringId => "mighty_nam_pro";

  @override
  int get effectsChainLength => 11;

  @override
  String get presetClass => "mighty_nam_pro";

  @override
  bool get reorderableFXChain => false;

  @override
  List<String> get productBLENames => ["MIGHTY PLUG PRO", "MIGHTY NAM"];

  @override
  List<ProcessorInfo> get processorList => ProcessorsList.mightyNamProList;

  @override
  NamProPreset getCustomPreset(int channel) {
    var preset = NamProPreset(device: this, channel: channel, channelName: "");
    preset.setFirmwareVersion(productVersion);
    
    // Ensure the detached preset also has the correct 11-block layout
    for (int slot = 0; slot < effectsChainLength; slot++) {
      preset.setFXIDAtSlot(slot, NamProPreset.namBaseEffects[slot]);
    }
    return preset;
  }
}