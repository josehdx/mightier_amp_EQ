import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_utils/qr_utils.dart';

import '../../../../bluetooth/NuxDeviceControl.dart';
import '../../../../platform/fileSaver.dart';
import '../../../../platform/platformUtils.dart';
import '../../../../platform/presetsStorage.dart';
import '../../../popups/alertDialogs.dart';
import '../../../popups/exportQRCode.dart';
import '../../../../bluetooth/devices/presets/preset_constants.dart'; // Added import

class PresetListMethods {

  // --- NEW DIALOG: SINGLE PRESET COLOR PICKER ---
  static void showChangeChannelDialog(BuildContext context, Map<String, dynamic> preset) {
    var dev = NuxDeviceControl.instance().getDeviceFromPresetClass(preset["product_id"]);
    if (dev == null) return;
    int channelsCount = dev.channelsCount;

    List<Color> colors;
    if (dev.productStringId == "mighty_plug_pro" || 
        dev.productStringId == "mighty_space" || 
        dev.productStringId == "mighty_nam_pro") {
      colors = PresetConstants.channelColorsPro;
    } else if (dev.productStringId == "mighty_plug_air") {
      colors = PresetConstants.channelColorsAir;
    } else {
      colors = PresetConstants.channelColorsPlug;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select Preset Color"),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: List.generate(channelsCount, (index) {
              return GestureDetector(
                onTap: () {
                  PresetsStorage().changeChannel(preset, index);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors[index % colors.length],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(2, 2),
                      )
                    ],
                  ),
                ),
              );
            }),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  static void exportQR(Map<String, dynamic> preset, BuildContext context) {
    var dev = NuxDeviceControl.instance()
        .getDeviceFromPresetClass(preset["product_id"]);
    var pVersion = preset["version"] ?? 0;
    if (dev != null) {
      int? originalVersion;
      if (dev.productVersion != pVersion) {
        originalVersion = dev.productVersion;
        dev.setFirmwareVersionByIndex(pVersion);
      }
      var qr = dev.jsonToQR(preset);
      if (qr != null) {
        QrUtils.generateQR(qr).then((Image img) {
          var qrExport = QRExportDialog(img, preset["name"], dev);
          showDialog(
            context: context,
            builder: (BuildContext context) => qrExport.buildDialog(context),
          ).then((value) {
            if (originalVersion != null) {
              dev.setFirmwareVersionByIndex(originalVersion);
            }
          });
        });
      }
    }
  }

  static void saveFileIos(String name, String data, BuildContext context) {
    AlertDialogs.showInputDialog(context,
        title: "Backup",
        description: "Enter backup name:",
        cancelButton: "Cancel",
        confirmButton: "Backup",
        value: name,
        validation: (String newName) {
          RegExp regex = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]+');
          return !regex.hasMatch(newName);
        },
        validationErrorMessage: "The file name contains invalid characters.",
        confirmColor: Theme.of(context).hintColor,
        onConfirm: (newName) async {
          await FilePicker().saveFile(newName, data);
        });
  }

  static void exportPreset(Map<String, dynamic> preset, BuildContext context) {
    var category = PresetsStorage().findCategoryOfPreset(preset);
    if (category != null) {
      String? data =
          PresetsStorage().presetToJson(category["name"], preset["name"]);

      if (data != null) {
        if (!PlatformUtils.isIOS) {
          saveFileString(
              "application/octet-stream", "${preset["name"]}.nuxpreset", data);
        } else {
          PresetListMethods.saveFileIos(preset["name"], data, context);
        }
      }
    }
  }
}