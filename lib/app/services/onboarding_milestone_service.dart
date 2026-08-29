import 'package:shared_preferences/shared_preferences.dart';

class OnboardingMilestoneService {
  static const String _storageKey = 'inkdframes_onboarding_milestones_v1';

  static const String arrivalSeen = 'arrivalSeen';
  static const String enteredHome = 'enteredHome';
  static const String bagDiscovered = 'bagDiscovered';
  static const String cobwebsCleared = 'cobwebsCleared';
  static const String spiderMet = 'spiderMet';
  static const String bagOpened = 'bagOpened';
  static const String creationDeskVisited = 'creationDeskVisited';
  static const String firstAnimationStarted = 'firstAnimationStarted';
  static const String onionSkinDiscovered = 'onionSkinDiscovered';
  static const String firstMotionPlayed = 'firstMotionPlayed';
  static const String firstProjectSaved = 'firstProjectSaved';
  static const String projectWallVisited = 'projectWallVisited';
  static const String welcomeHomeComplete = 'welcomeHomeComplete';

  static Future<Set<String>> completed() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_storageKey)?.toSet() ?? <String>{};
  }

  static Future<bool> has(String milestone) async {
    final milestones = await completed();
    return milestones.contains(milestone);
  }

  static Future<void> complete(String milestone) async {
    final preferences = await SharedPreferences.getInstance();
    final milestones =
        preferences.getStringList(_storageKey)?.toSet() ?? <String>{};

    if (!milestones.add(milestone)) {
      return;
    }

    await preferences.setStringList(_storageKey, milestones.toList()..sort());
  }

  static Future<void> resetForDevelopment() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }
}
