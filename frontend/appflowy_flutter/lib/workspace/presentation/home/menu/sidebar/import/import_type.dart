import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
// [fork:retire-non-core-surfaces]
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ImportType {
  historyDocument,
  historyDatabase,
  markdownOrText,
  csv,
  afDatabase;

  @override
  String toString() {
    switch (this) {
      case ImportType.historyDocument:
        return LocaleKeys.importPanel_documentFromV010.tr();
      case ImportType.historyDatabase:
        return LocaleKeys.importPanel_databaseFromV010.tr();
      case ImportType.markdownOrText:
        return LocaleKeys.importPanel_textAndMarkdown.tr();
      case ImportType.csv:
        return LocaleKeys.importPanel_csv.tr();
      case ImportType.afDatabase:
        return LocaleKeys.importPanel_database.tr();
    }
  }

  WidgetBuilder get icon => (context) {
        final FlowySvgData svg;
        switch (this) {
          case ImportType.historyDatabase:
            svg = FlowySvgs.document_s;
          case ImportType.historyDocument:
          case ImportType.csv:
          case ImportType.afDatabase:
            svg = FlowySvgs.board_s;
          case ImportType.markdownOrText:
            svg = FlowySvgs.text_s;
        }

        return FlowySvg(
          svg,
          color: Theme.of(context).colorScheme.tertiary,
        );
      };

  bool get enableOnRelease {
    switch (this) {
      case ImportType.historyDatabase:
      case ImportType.historyDocument:
      case ImportType.afDatabase:
        return kDebugMode;
      default:
        return true;
    }
  }

  /// [fork:retire-non-core-surfaces] The view layout importing this file
  /// **creates**. Stated here rather than only at the import call site so the
  /// retirement check reads as "does this make a retired thing?" instead of a
  /// hard-coded list of three enum names that nothing keeps honest.
  ///
  /// CSV is the one that stings a little: it is a genuinely useful import and it
  /// is retired only because its output is a Grid. If a CSV ever needs to land
  /// in Ludwig it should arrive as an in-page table (`simple_table`, already
  /// 11k lines and shipping) — which is a feature to scope, not a filter to
  /// loosen here.
  ViewLayoutPB get createdLayout => switch (this) {
        ImportType.historyDocument ||
        ImportType.markdownOrText =>
          ViewLayoutPB.Document,
        ImportType.historyDatabase ||
        ImportType.csv ||
        ImportType.afDatabase =>
          ViewLayoutPB.Grid,
      };

  List<String> get allowedExtensions {
    switch (this) {
      case ImportType.historyDocument:
        return ['afdoc'];
      case ImportType.historyDatabase:
      case ImportType.afDatabase:
        return ['afdb'];
      case ImportType.markdownOrText:
        return ['md', 'txt'];
      case ImportType.csv:
        return ['csv'];
    }
  }

  bool get allowMultiSelect {
    switch (this) {
      case ImportType.historyDocument:
      case ImportType.historyDatabase:
      case ImportType.csv:
      case ImportType.afDatabase:
      case ImportType.markdownOrText:
        return true;
    }
  }
}
