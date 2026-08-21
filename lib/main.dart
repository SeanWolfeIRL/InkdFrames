import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/inkdframes_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const InkdFramesApp());
}
