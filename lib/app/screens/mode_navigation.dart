import 'package:flutter/material.dart';

import 'mode_selection_screen.dart';

void returnToModeSelection(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const ModeSelectionScreen()),
    (route) => false,
  );
}
