import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_list_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/inline_rename_field.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSpaceBloc extends Mock implements SpaceBloc {}

void main() {
  late MockSpaceBloc spaceBloc;
  var toggles = 0;

  setUp(() {
    spaceBloc = MockSpaceBloc();
    when(() => spaceBloc.stream).thenAnswer((_) => const Stream.empty());
    toggles = 0;
  });

  Future<void> pumpHeader(WidgetTester tester, {required bool isExpanded}) {
    final space = ViewPB(
      name: 'test space',
      extra: jsonEncode({
        ViewExtKeys.spaceIconKey: '',
        ViewExtKeys.spaceIconColorKey: '',
      }),
    );
    return tester.pumpWidget(
      BlocProvider<SpaceBloc>.value(
        value: spaceBloc,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: SpaceListHeader(
                space: space,
                isExpanded: isExpanded,
                onToggle: () => toggles++,
                onAddPage: (_) {},
                onCreateNewSpace: () {},
                onCollapseAllPages: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  FlowySvgData caretSvg(WidgetTester tester) => tester
      .widget<FlowySvg>(find.byType(FlowySvg).first)
      .svg;

  testWidgets('caret reflects expansion state', (tester) async {
    await pumpHeader(tester, isExpanded: true);
    expect(caretSvg(tester), FlowySvgs.workspace_drop_down_menu_show_s);

    await pumpHeader(tester, isExpanded: false);
    expect(caretSvg(tester), FlowySvgs.workspace_drop_down_menu_hide_s);
  });

  testWidgets('single tap toggles once', (tester) async {
    await pumpHeader(tester, isExpanded: true);
    await tester.tap(find.byType(SpaceListHeader));
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggles, 1);
    expect(find.byType(InlineRenameField), findsNothing);
  });

  testWidgets(
      'double tap opens in-place rename and leaves expansion unchanged '
      '(toggle count is even)', (tester) async {
    await pumpHeader(tester, isExpanded: true);
    await tester.tap(find.byType(SpaceListHeader));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(SpaceListHeader));
    await tester.pumpAndSettle();
    expect(toggles, 2, reason: 'second toggle undoes the first');
    expect(find.byType(InlineRenameField), findsOneWidget);
  });
}
