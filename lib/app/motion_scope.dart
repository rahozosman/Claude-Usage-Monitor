import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../features/settings/settings_controller.dart';
import 'theme/app_motion.dart';

/// `context.motion` — the motion tokens honouring the animation toggle.
extension MotionContext on BuildContext {
  AppMotion get motion {
    final enabled = select<SettingsController, bool>((s) => s.settings.animationsEnabled);
    return enabled ? AppMotion.on : AppMotion.off;
  }
}
