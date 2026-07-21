import 'dart:convert';

import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/sidebar_dock_side.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/sidebar_space_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_more_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppearanceSettingsCubit extends Mock
    implements AppearanceSettingsCubit {}

class MockAppearanceSettingsState extends Mock
    implements AppearanceSettingsState {}

class MockSpaceBloc extends Mock implements SpaceBloc {}

class MockSpaceState extends Mock implements SpaceState {}

void main() {
  late MockAppearanceSettingsCubit appearanceCubit;
  late MockAppearanceSettingsState appearanceState;
  late MockSpaceBloc spaceBloc;
  late MockSpaceState spaceState;

  setUp(() {
    // ViewAddButton lists plugin builders from the service locator at build
    // time; an empty sandbox is enough for layout.
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());

    appearanceCubit = MockAppearanceSettingsCubit();
    appearanceState = MockAppearanceSettingsState();
    when(() => appearanceCubit.state).thenReturn(appearanceState);
    when(() => appearanceCubit.stream)
        .thenAnswer((_) => const Stream.empty());

    spaceBloc = MockSpaceBloc();
    spaceState = MockSpaceState();
    when(() => spaceBloc.state).thenReturn(spaceState);
    when(() => spaceBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => spaceState.isExpanded).thenReturn(false);
  });

  tearDown(() async {
    await getIt.unregister<PluginSandbox>();
  });

  Future<void> pumpHeader(WidgetTester tester, SidebarDockSide dockSide) async {
    when(() => appearanceState.sidebarDockSide).thenReturn(dockSide);
    final space = ViewPB(
      name: 'test',
      extra: jsonEncode({
        ViewExtKeys.spaceIconKey: '',
        ViewExtKeys.spaceIconColorKey: '',
      }),
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AppearanceSettingsCubit>.value(value: appearanceCubit),
          BlocProvider<SpaceBloc>.value(value: spaceBloc),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: SidebarSpaceHeader(
                space: space,
                onAdded: (_) {},
                onCreateNewSpace: () {},
                onCollapseAllPages: () {},
                isExpanded: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('space header trailing icons', () {
    testWidgets(
        'sidebar docked LEFT: ··· is outermost (right of +, away from the name)',
        (tester) async {
      await pumpHeader(tester, SidebarDockSide.left);

      final addDx = tester.getCenter(find.byType(ViewAddButton)).dx;
      final moreDx = tester.getCenter(find.byType(SpaceMorePopup)).dx;
      expect(
        addDx,
        lessThan(moreDx),
        reason: 'docked left the name sits left, so outermost = rightmost: '
            'the + button must render left of the ··· button',
      );
    });

    testWidgets(
        'sidebar docked RIGHT: ··· is outermost (left of +, away from the name)',
        (tester) async {
      await pumpHeader(tester, SidebarDockSide.right);

      final addDx = tester.getCenter(find.byType(ViewAddButton)).dx;
      final moreDx = tester.getCenter(find.byType(SpaceMorePopup)).dx;
      expect(
        moreDx,
        lessThan(addDx),
        reason: 'docked right the name sits right, so outermost = leftmost: '
            'the ··· button must render left of the + button',
      );
    });
  });
}
