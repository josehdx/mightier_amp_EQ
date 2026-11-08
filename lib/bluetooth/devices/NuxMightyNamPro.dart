import 'communication/communication.dart';
import 'communication/namProCommunication.dart';
import 'device_data/processors_list.dart';
import 'effects/Processor.dart';
import 'NuxMightyPlugPro.dart';
import '../NuxDeviceControl.dart';
import 'presets/NamProPreset.dart';
import 'NuxFXID.dart';

class NuxMightyNamPro extends NuxMightyPlugPro {
  late final NamProCommunication _communication =
      NamProCommunication(this, config);

  @override
  DeviceCommunication get communication => _communication;

  // CRITICAL FIX: Map directly to the standard PlugPro UI identifiers
  // This allows the EffectChainBar to find and render their icons offline.
  @override
  NuxFXID get ampFXID => PlugProFXID.amp;
  
  @override
  NuxFXID get cabFXID => PlugProFXID.cab;

  NuxMightyNamPro(NuxDeviceControl devControl) : super(devControl) {
    presets.clear();
    channelNames.clear();
    
    for (int i = 0; i < channelsCount; i++) {
      var preset = NamProPreset(
          device: this, channel: i, channelName: (i + 1).toString());
      
      preset.setFirmwareVersion(version.index);
      
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
  bool get reorderableFXChain => true; // FIXED: Enabled drag-and-drop reordering

  @override
  List<String> get productBLENames => ["MIGHTY PLUG PRO", "MIGHTY NAM"];

  @override
  List<ProcessorInfo> get processorList => ProcessorsList.mightyNamProList;

  @override
  NamProPreset getCustomPreset(int channel) {
    var preset = NamProPreset(device: this, channel: channel, channelName: "");
    preset.setFirmwareVersion(productVersion);
    
    for (int slot = 0; slot < effectsChainLength; slot++) {
      preset.setFXIDAtSlot(slot, NamProPreset.namBaseEffects[slot]);
    }
    return preset;
  }
}