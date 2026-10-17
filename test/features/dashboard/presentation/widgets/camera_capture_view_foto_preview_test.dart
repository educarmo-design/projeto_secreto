import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';

/// RELATÓRIO 20261016_0007 — pedido explícito do fundador: mostrar a
/// própria foto tirada na tela de resultado do Rótulo Nutricional.
/// `CameraCaptureView` em si não é testável (`CameraController` do
/// pacote `camera` não é mockável — limitação pré-existente, documentada
/// em vários RELATÓRIOS anteriores). Este teste isola só o MECANISMO
/// novo — o mesmo par `Image.memory(bytes, errorBuilder: ...)` que
/// `_buildResultadoRotulo` agora usa — sem precisar da câmera, mesmo
/// espírito de `camera_capture_view_macro_card_theme_test.dart`.
void main() {
  setUpAll(() async {
    await i18n.initialize('pt');
  });

  /// O menor PNG válido possível: assinatura + IHDR (1×1) + IDAT + IEND —
  /// 67 bytes, 1 pixel transparente. Usado só pra provar que bytes de
  /// imagem DE VERDADE decodificam e renderizam via `Image.memory`, sem
  /// acionar o `errorBuilder`.
  Uint8List pngMinimoValido() => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
        0x42, 0x60, 0x82,
      ]);

  Widget criarPreview(Uint8List bytes) {
    return MaterialApp(
      home: Scaffold(
        body: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            bytes,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 200,
              width: double.infinity,
              color: Colors.white12,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    i18n.tr('dashboard.camera_rotulo_foto_indisponivel'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('bytes válidos de imagem renderizam Image.memory, sem acionar o errorBuilder', (tester) async {
    await tester.pumpWidget(criarPreview(pngMinimoValido()));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Imagem indisponível'), findsNothing);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });

  testWidgets('bytes inválidos/corrompidos acionam o errorBuilder — nunca quebra a tela', (tester) async {
    await tester.pumpWidget(criarPreview(Uint8List.fromList([1, 2, 3, 4, 5])));
    await tester.pumpAndSettle();

    expect(find.text('Imagem indisponível'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    // A tela não quebra — nenhum erro sobe pro `ErrorWidget`/tela vermelha.
    expect(tester.takeException(), isNull);
  });
}
