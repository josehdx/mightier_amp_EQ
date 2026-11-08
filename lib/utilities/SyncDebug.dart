// Temporary debugging + resync configuration.
//
// Copy to: lib/utilities/SyncDebug.dart   (replaces the previous version)
//
// Every line starts with "[SYNC nnnn hh:mm:ss.mmm]". Filter logcat on the tag
// "flutter", or search for "SYNC".

import 'package:flutter/foundation.dart';
import 'package:mighty_plug_manager/bluetooth/devices/NuxConstants.dart';
import 'package:mighty_plug_manager/bluetooth/devices/effects/Processor.dart';
import 'package:mighty_plug_manager/bluetooth/devices/presets/PlugProPreset.dart';
import 'package:mighty_plug_manager/utilities/MathEx.dart';

class SyncDebug {
  // Master switch for all log output.
  static bool enabled = true;

  // Channel resync (Pro / Space only, never NAM)
  static bool resyncEnabled = true;

  // STORED switch: read the amp's patch back and show it.
  static bool storedRefresh = true;

  // After a switch (stored or library) re-send the displayed volume values.
  static bool reassert = true;

  // Re-send the amp parameters flagged masterVolume (the amp "Master" knob).
  static bool reassertAmpMaster = true;

  // Re-send the whole selected amp block (gain, master, EQ ...). Heavier.
  static bool reassertAllAmp = false;

  // STORED switch: wait this long after the program change before reading back.
  static int settleMs = 300;

  // STORED switch: give up waiting for the readback after this long.
  static int readbackTimeoutMs = 1500;

  // LIBRARY switch: wait this long after the preset was applied, then re-send.
  static int libraryReassertMs = 500;

  // --- Mitigations for lost/garbled BLE MIDI while classic A2DP audio streams ---
  // Log how long every BLE write really took (TX lines are enqueue times only).
  static bool wireLog = true;

  // During a library apply, write PC/CC with response (the amp's BLE stack
  // confirms every message, which also throttles the burst).
  static bool reliableWrites = true;

  // After the amp acknowledges the apply (its reply to our FX-order SysEx),
  // re-send every parameter once into the now-settled DSP.
  static bool secondPass = true;

  // If no acknowledgement arrives, run the second pass this long after the
  // first pass was written.
  static int secondPassFallbackMs = 900;

  // Preset loading determinism
  // false = leave the carried-over value (does not override custom presets)
  // true  = reset missing parameters to factory defaults
  static bool defaultMissingKeys = false;

  static int _n = 0;
  static DateTime? _lastPc;

  static String hex(List<int> d, {int max = 48}) {
    final shown = d.length > max ? d.sublist(0, max) : d;
    final s = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return d.length > max ? '$s ... (+${d.length - max} bytes)' : s;
  }

  static void log(String msg) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    debugPrint('[SYNC ${(_n++).toString().padLeft(4, '0')} $ts] $msg');
  }

  static String _ccName(int cc) {
    switch (cc) {
      case MidiCCValuesPro.MASTER:
        return '(MASTER channel volume)';
      case MidiCCValuesPro.AMP_Para1:
        return '(AMP_Para1, usually Gain)';
      case MidiCCValuesPro.AMP_Para2:
        return '(AMP_Para2, usually amp Master)';
      default:
        return '';
    }
  }

  static String _describe(List<int> d) {
    final o = (d.length > 2 && d[0] >= 0x80 && d[1] >= 0x80 && d[2] >= 0x80)
        ? 2
        : 0;
    if (d.length <= o) return 'EMPTY';
    final status = d[o];

    if (status == MidiMessageValues.controlChange && d.length >= o + 3) {
      return 'CC ${d[o + 1]}=${d[o + 2]} ${_ccName(d[o + 1])}';
    }
    if (status == MidiMessageValues.programChange && d.length >= o + 2) {
      return 'PC ${d[o + 1]}';
    }
    if (status == MidiMessageValues.sysExStart && d.length >= o + 5) {
      return 'SYSEX privacy=${d[o + 3]} type=${d[o + 4]} len=${d.length}';
    }
    return 'status=0x${status.toRadixString(16)} len=${d.length}';
  }

  static String _sincePc(String desc) {
    if (desc.startsWith('PC ')) {
      _lastPc = DateTime.now();
      return '';
    }
    final t = _lastPc;
    if (t == null) return '';
    final ms = DateTime.now().difference(t).inMilliseconds;
    return ms <= 2000 ? ' [+${ms}ms after PC]' : '';
  }

  static void rx(List<int> d) {
    if (!enabled) return;
    final desc = _describe(d);
    log('RX  $desc${_sincePc(desc)} | ${hex(d)}');
  }

  static void tx(List<int> d) {
    if (!enabled) return;
    final desc = _describe(d);
    log('TX  $desc${_sincePc(desc)} | ${hex(d)}');
  }

  static Processor _amp(PlugProPreset p) {
    final list = p.amplifierList;
    final i = p.selectedAmp.clamp(0, list.length - 1).toInt();
    return list[i];
  }

  static int _wire(Parameter prm) => MathEx.map(prm.value,
          prm.formatter.min.toDouble(), prm.formatter.max.toDouble(), 0, 100)
      .round();

  static void dumpApp(String tag, PlugProPreset p) {
    if (!enabled) return;
    log('$tag | APP presetCh=${p.channel} deviceSelectedCh=${p.device.selectedChannel} '
        'volume=${p.volume.toStringAsFixed(2)}dB volumeMidi=${p.volumeMidi}');

    final amp = _amp(p);
    log('$tag | APP amp="${amp.name}" nuxIndex=${amp.nuxIndex} enabled=${p.ampEnabled}');
    for (final prm in amp.parameters) {
      log('$tag | APP   ${prm.handle.padRight(8)} idx=${prm.devicePresetIndex} '
          'cc=${prm.midiCC} value=${prm.value} wire=${_wire(prm)} '
          'limits=[${prm.limitMin},${prm.limitMax}]');
    }
  }

  static Map<String, int> snapshot(PlugProPreset p) {
    final amp = _amp(p);
    final m = <String, int>{'volume': p.volumeMidi, 'ampType': amp.nuxIndex};
    for (final prm in amp.parameters) {
      m[prm.handle] = _wire(prm);
    }
    return m;
  }

  static void diff(String tag, Map<String, int> before, Map<String, int> after) {
    if (!enabled) return;
    var changed = 0;
    after.forEach((k, v) {
      final b = before[k];
      if (b != v) {
        changed++;
        log('$tag | DIFF ${k.padRight(8)} shown=$b amp=$v <<< SCREEN DIFFERED FROM AMP');
      }
    });
    log('$tag | DIFF summary: '
        '${changed == 0 ? 'screen matched amp' : '$changed field(s) differed'}');
  }

  static void compare(String tag, PlugProPreset p, List<int> nuxData) {
    if (!enabled) return;
    int at(int i) => i >= 0 && i < nuxData.length ? nuxData[i] : -1;

    final f = p.device.decibelFormatter;
    final hwMaster = at(PresetDataIndexPlugPro.MASTER);
    final hwAmpByte = at(PresetDataIndexPlugPro.Head_iAMP);
    final hwAmpType = hwAmpByte < 0 ? -1 : (hwAmpByte & 0x3f);
    final hwAmpOn = hwAmpByte < 0 ? false : (hwAmpByte & 0x40) == 0;

    log('$tag | HW  payloadLen=${nuxData.length} bytes: ${hex(nuxData, max: 100)}');
    log('$tag | HW  MASTER raw=$hwMaster -> '
        '${(f == null || hwMaster < 0) ? '?' : f.midi7BitToValue(hwMaster).toStringAsFixed(2)}dB');
    log('$tag | HW  amp byte=$hwAmpByte type=$hwAmpType on=$hwAmpOn');

    final amp = _amp(p);
    final appMaster = p.volumeMidi;
    log('$tag | CMP volume   hw=$hwMaster app=$appMaster '
        '${hwMaster == appMaster ? 'OK' : '<<< MISMATCH'}');
    log('$tag | CMP amp type hw=$hwAmpType app=${amp.nuxIndex} '
        '${hwAmpType == amp.nuxIndex ? 'OK' : '<<< MISMATCH'}');
    log('$tag | CMP amp on   hw=$hwAmpOn app=${p.ampEnabled} '
        '${hwAmpOn == p.ampEnabled ? 'OK' : '<<< MISMATCH'}');

    for (final prm in amp.parameters) {
      final hw = at(prm.devicePresetIndex);
      final app = _wire(prm);
      log('$tag | CMP ${prm.handle.padRight(8)} idx=${prm.devicePresetIndex} '
          'hw=$hw app=$app ${hw == app ? 'OK' : '<<< MISMATCH'}');
    }
  }
}