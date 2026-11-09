import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_database_app/src/theme.dart';
import 'package:music_database_app/src/widgets/common.dart';

const cyberpunkTheme = AppThemeDef(
  'Cyberpunk',
  AppPalette(
    background: Color(0xFF0E0A0D),
    surface: Color(0xFF170F13),
    surfaceHigh: Color(0xFF16191D),
    chip: Color(0xFF1C2226),
    accent: Color(0xFF5FE3E8),
    onAccent: Color(0xFF051416),
    textPrimary: Color(0xFFD8F4F5),
    textSecondary: Color(0xFFD65A50),
    badge: Color(0xFFE0524A),
    divider: Color(0xFF3A1D20),
    navBar: Color(0xFF0A0C0F),
    snackBackground: Color(0xFF0F2A2D),
    snackForeground: Color(0xFF8FF3F6),
    coverColors: [Color(0xFF7A2420), Color(0xFF16585C)],
    likedGradient: [Color(0xFF8C2A2A), Color(0xFF5FE3E8)],
    outline: Color(0xFFB8403A),
    rounded: false,
    chamfered: true,
    panelHeaders: true,
    uppercaseTitles: true,
  ),
);

void main() {
  test('a chamfered palette cuts corners on chips, cards and buttons', () {
    final p = cyberpunkTheme.palette;
    expect(p.pillShape, isA<ChamferedBorder>());
    expect(p.buttonShape, isA<ChamferedBorder>());
    final card = p.boxShape(12) as ChamferedBorder;
    expect(card.notch, p.accent);
    expect(p.radius(12), BorderRadius.zero);
    expect(dummifyTheme.palette.pillShape, isA<StadiumBorder>());
  });

  test('ChamferedBorder leaves out the cut corners', () {
    const border = ChamferedBorder(cut: 10);
    final path = border.getOuterPath(const Rect.fromLTWH(0, 0, 100, 50));
    expect(path.contains(const Offset(1, 1)), isFalse);
    expect(path.contains(const Offset(99, 49)), isFalse);
    expect(path.contains(const Offset(99, 1)), isTrue);
    expect(path.contains(const Offset(50, 25)), isTrue);
  });

  testWidgets('Cyberpunk headings are capitals and fit a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(cyberpunkTheme),
        home: Scaffold(
          body: Column(
            children: [
              const TabHeader(title: 'Biblioteka'),
              const SectionTitle(
                'Ostatnio słuchane i bardzo długi nagłówek sekcji',
              ),
              SectionTitle(
                'Przypięte',
                icon: Icons.push_pin,
                trailing: const Icon(Icons.more_horiz),
              ),
              Card(
                shape: cyberpunkTheme.palette.boxShape(12),
                child: const SizedBox(height: 60),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('BIBLIOTEKA'), findsOneWidget);
    expect(find.text('PRZYPIĘTE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
