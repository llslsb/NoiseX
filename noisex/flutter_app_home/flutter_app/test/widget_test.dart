import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/app.dart';

// 旧模板引用不存在的 MyApp 编译失败，改为对真实根组件的构造冒烟断言
void main() {
  test('NoiseXApp can be constructed', () {
    const app = NoiseXApp();
    expect(app, isNotNull);
  });
}
