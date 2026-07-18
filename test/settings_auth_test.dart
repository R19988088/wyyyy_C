import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/settings_page.dart';

void main() {
  test('decodes the inline QR SVG data URL', () {
    const svg =
        '<svg width="256" height="256" viewBox="0 0 256 256">'
        '<path fill="#171717" d="M4 5h2v3H4V5M9 8h1v1H9V8"/></svg>';
    final dataUrl =
        'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';

    expect(decodeQrSvg(dataUrl), svg);
  });

  test('maps every server QR login state to user-facing text', () {
    expect(qrStatusText('waiting'), '等待扫码');
    expect(qrStatusText('scanned'), '已扫码，请在手机上确认');
    expect(qrStatusText('expired'), '二维码已过期');
    expect(qrStatusText('confirmed'), '登录成功');
  });
}
