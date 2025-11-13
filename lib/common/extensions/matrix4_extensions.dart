import 'package:vector_math/vector_math_64.dart';

/// Matrix4 扩展,提供与旧版本 API 兼容的方法
extension Matrix4Extensions on Matrix4 {
  /// 兼容旧版本的 translateByDouble 方法
  /// 在新版本中使用 translate 方法
  Matrix4 translateByDoubleCompat(double x, double y, double z, [double w = 1]) {
    // 新版本 API
    return this..translate(x, y, z);
  }

  /// 兼容旧版本的 scaleByDouble 方法
  /// 在新版本中使用 scale 方法
  Matrix4 scaleByDoubleCompat(double x, [double? y, double? z, double? w]) {
    // 新版本 API
    return this..scale(x, y ?? x, z ?? x);
  }
}

/// 创建 Matrix4 的辅助方法
class Matrix4Compat {
  /// 创建平移矩阵
  static Matrix4 translation(double x, double y, double z) {
    return Matrix4.identity()..translate(x, y, z);
  }

  /// 创建缩放矩阵
  static Matrix4 scaling(double x, double y, double z) {
    return Matrix4.identity()..scale(x, y, z);
  }

  /// 组合平移和缩放
  static Matrix4 compose(
    double translateX,
    double translateY,
    double translateZ,
    double scaleX,
    double scaleY,
    double scaleZ,
  ) {
    return Matrix4.identity()
      ..translate(translateX, translateY, translateZ)
      ..scale(scaleX, scaleY, scaleZ);
  }
}
