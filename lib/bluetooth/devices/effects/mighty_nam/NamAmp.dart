import '../../NuxConstants.dart';
import '../../value_formatters/ValueFormatter.dart';
import '../MidiControllerHandles.dart';
import '../Processor.dart';

/// Native units of the six mighty-nam tone controls (same as the desktop app):
///
///   Input  : 0..96   raw, 48 = 0 dB, 0.5 dB steps (-24 .. +24 dB)
///   Bass   : 0..24   raw, 12 = flat, 1 dB steps   (-12 .. +12 dB)
///   Middle : 0..24   raw, 12 = flat
///   Treble : 0..24   raw, 12 = flat
///   Mix    : 0..100  percent
///   Output : 0..96   raw, 48 = 0 dB (-24 .. +24 dB)
enum NamToneKind { gain, eq, mix }

class NamToneFormatter extends ValueFormatter {
  final NamToneKind kind;
  NamToneFormatter(this.kind);

  @override
  InputType get inputType => InputType.SliderInput;

  @override
  int get min => 0;

  @override
  int get max =>
      kind == NamToneKind.gain ? 96 : (kind == NamToneKind.eq ? 24 : 100);

  int _clamp(int v) => v < 0 ? 0 : (v > max ? max : v);

  /// Identity: the slider already works in raw firmware units.
  @override
  int valueToMidi7Bit(double value) => _clamp(value.round());

  @override
  double midi7BitToValue(int midi7bit) => _clamp(midi7bit).toDouble();

  @override
  String toLabel(double value) {
    final int raw = _clamp(value.round());
    if (kind == NamToneKind.gain) {
      final double db = (raw - 48) / 2;
      return '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB';
    }
    if (kind == NamToneKind.eq) {
      final int db = raw - 12;
      return '${db > 0 ? '+' : ''}$db dB';
    }
    return '$raw %';
  }
}

/// NAM Amp processor for the mighty-nam firmware.
///
/// The six tone controls are NOT stock amplifier CC parameters any more. On
/// NAMLNK21+ the firmware takes them through the custom "NG" SysEx message
/// (see NamProCommunication.sendNamTone), in the native units above. They are
/// stored in preset bytes 27..32 (AMP_Para1..6) with the marker 78 / 1 at
/// bytes 33 / 34.
class NamAmp extends Amplifier {
  static const List<int> toneMax = [96, 24, 24, 24, 100, 96];
  static const List<int> toneNeutral = [48, 12, 12, 12, 100, 48];

  /// True for the six tone parameters (custom SysEx, midiCC == -1, preset
  /// bytes 27..32). FX A/B parameters use bytes 3..9 so they never match.
  static bool isToneParam(Parameter p) =>
      p.midiCC == -1 &&
      p.devicePresetIndex >= PresetDataIndexPlugPro.AMP_Para1 &&
      p.devicePresetIndex <= PresetDataIndexPlugPro.AMP_Para6;

  @override
  final String name = "NAM Model";

  @override
  int get nuxIndex => 0;

  @override
  int? get nuxEffectTypeIndex => PresetDataIndexPlugPro.Head_iAMP;

  @override
  int? get nuxEnableIndex => nuxEffectTypeIndex;

  @override
  int get nuxEnableMask => 0x40;

  @override
  bool get nuxEnableInverted => true;

  @override
  EffectEditorUI get editorUI => EffectEditorUI.Sliders;

  @override
  int get midiCCEnableValue => MidiCCValuesPro.Head_iAMP;

  @override
  int get midiCCSelectionValue => MidiCCValuesPro.Head_iAMP;

  @override
  int get defaultCab => 0;

  @override
  MidiControllerHandle? get midiControlOff => MidiControllerHandles.ampOff;
  @override
  MidiControllerHandle? get midiControlOn => MidiControllerHandles.ampOn;
  @override
  MidiControllerHandle? get midiControlToggle => MidiControllerHandles.ampToggle;
  @override
  MidiControllerHandle? get midiControlPrev => MidiControllerHandles.ampPrev;
  @override
  MidiControllerHandle? get midiControlNext => MidiControllerHandles.ampNext;

  static Parameter _tone(String name, String handle, NamToneKind kind,
      double value, int presetIndex,
      {MidiControllerHandle? controller, bool master = false}) {
    final p = Parameter(
      name: name,
      handle: handle,
      value: value,
      formatter: NamToneFormatter(kind),
      masterVolume: master,
      devicePresetIndex: presetIndex,
      midiCC: -1, // -1 = custom SysEx ("NG"), never a CC
      midiControllerHandle: controller,
    );
    // Library presets saved by the old 0-100 % build may hold out-of-range
    // values: clamp them so the sliders can never be driven outside min/max.
    p.limitMin = 0;
    p.limitMax = p.formatter.max.toDouble();
    return p;
  }

  @override
  List<Parameter> parameters = [
    _tone("Input", "gain", NamToneKind.gain, 48, PresetDataIndexPlugPro.AMP_Para1,
        controller: MidiControllerHandles.ampGain),
    _tone("Bass", "bass", NamToneKind.eq, 12, PresetDataIndexPlugPro.AMP_Para2,
        controller: MidiControllerHandles.ampBass),
    _tone("Middle", "middle", NamToneKind.eq, 12,
        PresetDataIndexPlugPro.AMP_Para3,
        controller: MidiControllerHandles.ampMiddle),
    _tone("Treble", "treble", NamToneKind.eq, 12,
        PresetDataIndexPlugPro.AMP_Para4,
        controller: MidiControllerHandles.ampTreble),
    _tone("Mix", "mix", NamToneKind.mix, 100, PresetDataIndexPlugPro.AMP_Para5),
    _tone("Output", "level", NamToneKind.gain, 48,
        PresetDataIndexPlugPro.AMP_Para6,
        controller: MidiControllerHandles.ampVolume, master: true),
  ];

  /// The six raw firmware values, always within range.
  List<int> toneValues() => [for (final p in parameters) p.midiValue];

  /// Sets the six parameters from raw firmware values (clamped).
  void applyTone(List<int> raw) {
    if (raw.length < 6) return;
    for (int i = 0; i < 6; i++) {
      parameters[i].midiValue = raw[i].clamp(0, toneMax[i]);
    }
  }

  /// Preset bytes hold RAW firmware values (not 0..100 %), so the generic
  /// 0..100 -> min..max mapping of Processor must not be used here.
  /// Without the 78 / 1|2 marker the preset predates the tone controls and
  /// the neutral tone applies (same rule as the desktop app).
  @override
  void setupFromNuxPayload(List<int> nuxData) {
    final int mark1 = PresetDataIndexPlugPro.AMP_Para7;
    final int mark2 = PresetDataIndexPlugPro.AMP_Para8;
    List<int> tone = toneNeutral;
    if (nuxData.length > mark2 &&
        nuxData[mark1] == 78 &&
        (nuxData[mark2] == 1 || nuxData[mark2] == 2) &&
        nuxData.length > PresetDataIndexPlugPro.AMP_Para6) {
      tone = [
        for (int i = 0; i < 6; i++)
          nuxData[PresetDataIndexPlugPro.AMP_Para1 + i].clamp(0, toneMax[i])
      ];
    }
    applyTone(tone);
  }

  @override
  void getNuxPayload(List<int> nuxData, bool enabled) {
    if (nuxEffectTypeIndex != null) nuxData[nuxEffectTypeIndex!] = nuxIndex;
    for (final p in parameters) {
      nuxData[p.devicePresetIndex] = p.midiValue; // raw firmware units
    }
    // marker: tone present, version 1 (no USB recording gain byte)
    nuxData[PresetDataIndexPlugPro.AMP_Para7] = 78;
    nuxData[PresetDataIndexPlugPro.AMP_Para8] = 1;
    if (nuxEnableIndex != null) {
      int value = (enabled != nuxEnableInverted ? 0xff : 0) & nuxEnableMask;
      nuxData[nuxEnableIndex!] |= value;
    }
  }
}