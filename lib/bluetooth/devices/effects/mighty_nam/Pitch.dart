// (c) mighty-nam custom firmware — DSP processor stub.

import '../../../devices/effects/MidiControllerHandles.dart';
import '../../value_formatters/ValueFormatter.dart';
import '../Processor.dart';

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

  @override
  List<Parameter> parameters = [
    Parameter(
      name: "Pitch",
      handle: "pitch",
      value: 0,
      formatter: ValueFormatters.percentage,
      devicePresetIndex: 0,
      midiCC: 0,
    ),
    Parameter(
      name: "Mix",
      handle: "mix",
      value: 50,
      formatter: ValueFormatters.percentage,
      devicePresetIndex: 1,
      midiCC: 0,
    ),
  ];
}
