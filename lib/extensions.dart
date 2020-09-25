import 'package:flutter/material.dart';

import 'lang/localization.dart';

extension Localization on BuildContext {
  /// Extension method on [BuildContext] that provides access to the localized
  /// list of strings generated by the flutter_sheet_localization library.
  AppLocalizations_Labels strings() => AppLocalizations.of(this);

  /// Extension method on [BuildContext] that provides access to the current
  /// locale of the device.
  Locale locale() => Localizations.localeOf(this);
}

extension CustomStringMethods on String {
  /// Extension method on [String] that properly capitalizes Greek strings,
  /// removing any unnecessary accents in the capitalized string. The method
  /// otherwise works identically to ["string".toUpperCase()] in other
  /// languages. For example:
  ///
  /// `"Εργα τέχνης"` becomes `"ΕΡΓΑ ΤΕΧΝΗΣ"` and not `"ΈΡΓΑ ΤΈΧΝΗΣ"`
  ///
  /// (NOTE: the accented capital vowels in the example above may not show up
  /// properly here in the IDE, but they usually do in other text editors).
  ///
  /// One case that this method does not deal with is vowels with διαλυτικά,
  /// e.g. ΐ, ΰ, etc.
  ///
  /// The [ReCase](https://pub.dev/packages/recase) package may be used to
  /// achieve this functionality (one disadvantage is that it replaces spaces
  /// with "_").
  String customToUpperCase() {
    RegExp greek = RegExp(r'[α-ωΑ-Ω]');
    if (this.contains(greek)) {
      Map<String, String> greekAccentMap = Map.fromIterables(
        ["ά", "έ", "ή", "ί", "ό", "ύ", "ώ"],
        ["α", "ε", "η", "ι", "ο", "υ", "ω"],
      );

      return greekAccentMap.entries
          .fold(
              this.toLowerCase(),
              (String prev, MapEntry<String, String> vowelToReplace) =>
                  prev.replaceAll(vowelToReplace.key, vowelToReplace.value))
          .toUpperCase();
    }
    return this.toUpperCase();
  }
}
