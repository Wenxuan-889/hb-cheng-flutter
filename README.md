自动升级

https://blog.csdn.net/weixin_44786530/article/details/136557888


# 升级操作
修改
pubspec.yaml
打包
flutter_distributor package --platform windows --targets exe
生成密钥
dart run auto_updater:sign_update dist/.....
修改文件
h5/exe/appcast.xml




# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
