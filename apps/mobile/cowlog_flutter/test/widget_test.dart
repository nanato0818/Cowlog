import 'package:flutter_test/flutter_test.dart';

import 'package:cowlog_flutter/main.dart';
import 'package:cowlog_flutter/state/app_store.dart';

void main() {
  testWidgets('Cowlog shows its main navigation', (tester) async {
    await tester.pumpWidget(CowlogApp(store: AppStore()));

    expect(find.text('優先一覧'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('首輪・番号'), findsOneWidget);
  });
}
