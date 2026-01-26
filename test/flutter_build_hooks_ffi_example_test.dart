import 'package:test/test.dart';

import 'package:flutter_build_hooks_ffi_example/flutter_build_hooks_ffi_example.dart';

void main() {
  test('invoke native function', () {
    expect(sum(24, 18), 42);
  });

  test('invoke async native callback', () async {
    expect(await sumAsync(24, 18), 42);
  });
}
