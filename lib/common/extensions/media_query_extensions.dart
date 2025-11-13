import 'package:flutter/material.dart';

/// MediaQuery 扩展,确保与 Flutter 3.32+ 兼容
extension MediaQueryExtensions on BuildContext {
  /// 获取屏幕高度
  double get mediaQueryHeight {
    try {
      // Flutter 3.32+ 使用 MediaQuery.sizeOf
      return MediaQuery.sizeOf(this).height;
    } catch (e) {
      // 降级到旧版本 API
      return MediaQuery.of(this).size.height;
    }
  }

  /// 获取屏幕宽度
  double get mediaQueryWidth {
    try {
      // Flutter 3.32+ 使用 MediaQuery.sizeOf
      return MediaQuery.sizeOf(this).width;
    } catch (e) {
      // 降级到旧版本 API
      return MediaQuery.of(this).size.width;
    }
  }

  /// 获取屏幕尺寸
  Size get mediaQuerySize {
    try {
      return MediaQuery.sizeOf(this);
    } catch (e) {
      return MediaQuery.of(this).size;
    }
  }

  /// 获取设备像素比
  double get mediaQueryDevicePixelRatio {
    try {
      return MediaQuery.devicePixelRatioOf(this);
    } catch (e) {
      return MediaQuery.of(this).devicePixelRatio;
    }
  }

  /// 获取安全区域内边距
  EdgeInsets get mediaQueryPadding {
    try {
      return MediaQuery.paddingOf(this);
    } catch (e) {
      return MediaQuery.of(this).padding;
    }
  }

  /// 获取视口内边距
  EdgeInsets get mediaQueryViewPadding {
    try {
      return MediaQuery.viewPaddingOf(this);
    } catch (e) {
      return MediaQuery.of(this).viewPadding;
    }
  }

  /// 获取视口插入
  EdgeInsets get mediaQueryViewInsets {
    try {
      return MediaQuery.viewInsetsOf(this);
    } catch (e) {
      return MediaQuery.of(this).viewInsets;
    }
  }
}
