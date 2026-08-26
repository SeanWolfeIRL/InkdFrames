import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/brush_preset.dart';

class BrushPresetService {
  static const String _storageKey = 'inkdframes_brush_presets';

  Future<List<BrushPreset>> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final rawPresets = prefs.getStringList(_storageKey) ?? const <String>[];

    final presets = <BrushPreset>[];

    for (final rawPreset in rawPresets) {
      try {
        final decoded = jsonDecode(rawPreset);

        if (decoded is Map) {
          presets.add(BrushPreset.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore malformed presets rather than breaking the preset library.
      }
    }

    presets.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return presets;
  }

  Future<void> savePresets(List<BrushPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = presets
        .map((preset) => jsonEncode(preset.toJson()))
        .toList();

    await prefs.setStringList(_storageKey, encoded);
  }

  Future<void> addPreset(BrushPreset preset) async {
    final presets = await loadPresets();
    final normalizedName = preset.name.trim().toLowerCase();

    presets.removeWhere(
      (existing) =>
          existing.id == preset.id ||
          existing.name.trim().toLowerCase() == normalizedName,
    );

    presets.insert(0, preset);

    await savePresets(presets);
  }

  Future<void> deletePreset(String presetId) async {
    final presets = await loadPresets();

    presets.removeWhere((preset) => preset.id == presetId);

    await savePresets(presets);
  }
}
