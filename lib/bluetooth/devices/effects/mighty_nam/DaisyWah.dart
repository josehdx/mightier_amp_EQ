// (c) mighty-nam custom firmware — DSP processor stub.

import '../../../devices/effects/MidiControllerHandles.dart';
import '../../value_formatters/ValueFormatter.dart';
import '../Processor.dart';
import 'ExtraFX.dart';

class NamDaisyWah extends NamExtraFX {
  @override
  final String name = "Daisy Wah";

  NamDaisyWah({bool isFxB = false}) : super(103, isFxB: isFxB);
}
