import 'package:flutter/widgets.dart';

import 'design_lab.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const modeValue = String.fromEnvironment(
    'TASKVEIL_DESIGN_LAB_MODE',
    defaultValue: 'baseline',
  );
  const candidateId = String.fromEnvironment('TASKVEIL_DESIGN_LAB_CANDIDATE');
  final root = await buildDesignLabRoot(
    mode: parseDesignLabMode(modeValue),
    candidateId: candidateId,
  );
  runApp(root);
}
