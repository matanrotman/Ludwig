import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/trash/application/trash_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_trash_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/trash.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTrashBloc extends Mock implements TrashBloc {}

void main() {
  late MockTrashBloc trashBloc;

  setUp(() {
    trashBloc = MockTrashBloc();
    when(() => trashBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Future<void> pumpIcon(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SidebarTrashIcon(trashBloc: trashBloc)),
      ),
    );
  }

  FlowySvgData shownSvg(WidgetTester tester) =>
      tester.widget<FlowySvg>(find.byType(FlowySvg)).svg;

  testWidgets('empty trash shows the normal icon', (tester) async {
    when(() => trashBloc.state).thenReturn(TrashState.init());
    await pumpIcon(tester);
    expect(shownSvg(tester), FlowySvgs.icon_delete_s);
  });

  testWidgets('non-empty trash shows the full-trash icon', (tester) async {
    when(() => trashBloc.state).thenReturn(
      TrashState.init().copyWith(objects: [TrashPB(id: 'a', name: 'page')]),
    );
    await pumpIcon(tester);
    expect(shownSvg(tester), fullTrashIcon);
  });
}
