import 'package:mighty_plug_manager/bluetooth/devices/NuxDevice.dart';
import 'NuxFXID.dart';
import 'effects/Processor.dart';
import 'presets/Preset.dart';

abstract class NuxReorderableDevice<T extends Preset> extends NuxDevice {
  NuxReorderableDevice(super.deviceControl);

  NuxFXID get ampFXID;
  NuxFXID get cabFXID;

  @override
  bool get reorderableFXChain => true;

  @override
  int get amplifierSlotIndex {
    var preset = getPreset(selectedChannel);
    // FIX: Iterate boundary instead of falling back to ampFXID.value directly
    for (int i = 0; i < effectsChainLength; i++) {
      if (preset.getFXIDFromSlot(i) == ampFXID) {
        return i;
      }
    }
    return 0; // Fallback
  }

  @override
  int get cabinetSlotIndex {
    var preset = getPreset(selectedChannel);
    // FIX: Iterate boundary instead of falling back to cabFXID.value directly
    for (int i = 0; i < effectsChainLength; i++) {
      if (preset.getFXIDFromSlot(i) == cabFXID) {
        return i;
      }
    }
    return 0; // Fallback
  }

  @override
  ProcessorInfo? getProcessorInfoByFXID(NuxFXID fxid) {
    for (var proc in processorList) {
      if (proc.nuxFXID == fxid) return proc;
    }
    return null;
  }

  @override
  int? getSlotByEffectKeyName(String key) {
    var pi = getProcessorInfoByKey(key);
    if (pi != null) {
      T p = getPreset(selectedChannel) as T;
      var index = p.getSlotFromFXID(pi.nuxFXID);
      if (index != null) return index;
    }
    return null;
  }
}