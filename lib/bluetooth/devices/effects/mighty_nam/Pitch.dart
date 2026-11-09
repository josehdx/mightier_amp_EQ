// (c) mighty-nam custom firmware — DSP processor stub.

import '../../../devices/effects/MidiControllerHandles.dart';
import '../../value_formatters/ValueFormatter.dart';
import '../Processor.dart';
// Reuse the NAM formatter so scaling (0-24 hardware range) matches NamPitch.
// NOTE: adjust this path if your folder layout differs.
import '../mighty_nam/ExtraFX.dart';

class NamPitchLegacy extends Processor {
  @override
  final String name = "Pitch";

  @override
  int get nuxIndex => 102;

  @override
  int? get nuxEffectTypeIndex => null;

  @override
  int? get nuxEnableIndex => null;

  @override
  EffectEditorUI get editorUI => EffectEditorUI.Sliders;

  @override
  int get midiCCEnableValue => 0;

  @override
  int get midiCCSelectionValue => 0;

  @override
  MidiControllerHandle? get midiControlOff => null;
  @override
  MidiControllerHandle? get midiControlOn => null;
  @override
  MidiControllerHandle? get midiControlToggle => null;
  @override
  MidiControllerHandle? get midiControlPrev => null;
  @override
  MidiControllerHandle? get midiControlNext => null;

  // devicePresetIndex MUST be in 3..9 or NamProPreset.generateNfPayload()
  // silently drops the parameter.
  //   3 = Pitch (0-24 hardware, 50% UI == 0 semitones)
  //   4 = Mix   (0-100)
  @override
  List<Parameter> parameters = [
    Parameter(
      name: "Pitch",
      handle: "pitch",
      value: 50,
      formatter: FxValueFormatter(3),
      devicePresetIndex: 3,
      midiCC: -1, // -1 routes changes through sendNfPayload()
    ),
    Parameter(
      name: "Mix",
      handle: "mix",
      value: 50,
      formatter: FxValueFormatter(4),
      devicePresetIndex: 4,
      midiCC: -1,
    ),
  ];
}