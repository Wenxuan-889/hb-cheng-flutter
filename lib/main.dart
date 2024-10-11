import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:auto_updater/auto_updater.dart'; // 用于自动更新应用
import 'package:flutter/services.dart'; // 处理平台相关的异常
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:async'; // 处理异步操作和流
import 'package:window_manager/window_manager.dart'; // 管理窗口操作
import 'package:webview_windows/webview_windows.dart'; // 使用 WebView 来显示网页内容
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';

// 定义一个全局的导航键，用于在任意地方访问 Navigator
final navigatorKey = GlobalKey<NavigatorState>();

// 定义一个常量，表示要加载的 URL
const HOST_INDEX = "http://192.168.200.5:81";

List<String> portList = [''];
// 应用程序的入口点
void main() async {
  // 确保 WidgetsFlutterBinding 已经初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    // size: Size(800, 600),
    title: "危废称打印一体机管理系统【企业版】",
    center: true,
    backgroundColor: Colors.transparent,
    // skipTaskbar: false,
    // titleBarStyle: TitleBarStyle.hidden, // 隐藏标题栏
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.maximize();
    // await windowManager.setAlwaysOnTop(true); // 保持窗口置顶
    // await windowManager.setFullScreen(true);
  });

  String tempPath = "./SQLite3.dll";
  if (File(tempPath).existsSync()) {
    print('sqlite3.dll 文件存在');
  } else {
    print('sqlite3.dll 文件不存在');
    await downloadFile("$HOST_INDEX/exe/sqlite3/SQLite3.dll", './SQLite3.dll');
  }

  int i = 0;
  portList = [];
  while (i < 105) {
    portList.add('COM$i');
    // 在这里执行你的操作
    i++;
  }
  sqfliteFfiInit();

  // update();

  // 运行 Flutter 应用
  runApp(MyApp());

  // 监听窗口关闭事件
  windowManager.addListener(_WindowListener());
}

Future<void> downloadFile(String fileUrl, String savePath) async {
  var response = await http.get(Uri.parse(fileUrl));
  var file = File(savePath);

  await file.writeAsBytes(response.bodyBytes);

  print('文件下载完成');
}

void update() async {
  // 设置自动更新的 feed URL
  String feedURL = HOST_INDEX + '/exe/appcast.xml';
  await autoUpdater.setFeedURL(feedURL);

  // 检查更新
  await autoUpdater.checkForUpdates();

  // 设置定时检查更新的间隔时间（单位：秒）
  // await autoUpdater.setScheduledCheckInterval(3600);
}

// 定义主应用程序的小部件
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // 设置 navigatorKey
      home: ExampleBrowser(), // 设置首页为 ExampleBrowser 小部件
    );
  }
}

// 定义 ExampleBrowser 小部件
class ExampleBrowser extends StatefulWidget {
  @override
  State<ExampleBrowser> createState() => _ExampleBrowser();
}

// ExampleBrowser 的状态类
class _ExampleBrowser extends State<ExampleBrowser> {
  // 创建 WebView 控制器
  final _controller = WebviewController();

  // 创建文本控制器，用于 URL 输入框
  // final _textController = TextEditingController();

  // 存储流订阅
  final List<StreamSubscription> _subscriptions = [];

  // 标志 WebView 是否暂停
  bool _isWebviewSuspended = false;
  var availablePorts = [];
  List<Map<String, dynamic>> _cachedData = [];
  String _valueByKey = '';
  var databaseFactory;
  var db;
  var selectedPort = "";
  @override
  void initState() {
    super.initState();
    initPlatformState();
    _initDatabase();
  }

  void initPorts() async {
    await _getValueByKey('rfid_port');
    selectedPort = _valueByKey;
  }

  Future<bool> _isCachedDataTableExists() async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='cachedData'");
    return tables.isNotEmpty;
  }

  Future<void> _initDatabase() async {
    databaseFactory = databaseFactoryFfi;
    final databasePath = await databaseFactory.getDatabasesPath();
    // bool exists = await databaseFactory.databaseExists(databasePath);
    db = await databaseFactory.openDatabase(databasePath);
    if (await _isCachedDataTableExists()) {
    } else {
      await db.execute(
          'CREATE TABLE cachedData(key TEXT INTEGER PRIMARY KEY, value TEXT)');
    }
    final data = await db.query('cachedData');
    setState(() {
      _cachedData = data;
    });

    initPorts();
    return;
  }

  Future<void> _saveData(String key, String value) async {
    await db.insert(
      'cachedData',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final data = await db.query('cachedData');
    setState(() {
      _cachedData = data;
    });
    return;
  }

  Future<void> _getValueByKey(String key) async {
    final List<Map<String, dynamic>> result = await db.query(
      'cachedData',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (result.isNotEmpty) {
      setState(() {
        _valueByKey = result.first['value'];
      });
    } else {
      setState(() {
        _valueByKey = "";
      });
    }
    return;
  }

  int bccVerify(List<int> data) {
    int bcc = 0;
    for (int byte in data) {
      bcc ^= byte;
    }
    int ecc = (~bcc) & 0xFF;
    return ecc;
  }

// 连接并读取卡号
  Future<void> connectAndReadCard() async {
    final serialPort = SerialPort(selectedPort);
    print(serialPort.isOpen);
    serialPort.config.baudRate = 9600;
    if (!serialPort.openReadWrite()) {
      print('Failed to open serial port');

      await _controller.postWebMessage(jsonEncode(
          {"message": '串口打开失败', "messagetype": "msg", "type": "warning"}));
      return;
    }
    // 读取卡号
    // var message = '20 00 27 00 D8 03';
    List<int> message = [0x20, 0x00, 0x27, 0x00, 0xD8, 0x03];
    String cardId = "";
    serialPort.write(Uint8List.fromList(message));
    // 读取数据
    SerialPortReader reader = SerialPortReader(serialPort, timeout: 3);
    StreamSubscription<Uint8List> subscription = reader.stream.listen((data) {
      //data为Uint8List 类似java的byte[]
      if (data.length > 13) {
        if (data[0] == 0x20 && data[13] == 0x03) {
          List<int> rfidData = data.sublist(1, data.length - 2);
          List<int> bccData = data.sublist(data.length - 2, data.length - 1);
          if (bccVerify(rfidData) == bccData[0]) {
            String rfidHexString =
                rfidData.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
            cardId = rfidHexString.substring(14);
            _controller.postWebMessage(jsonEncode({
              "nowcard": cardId,
              "port": selectedPort,
              "messagetype": "rfidres",
              "type": "success"
            }));
          }
        }
      }
      serialPort.close();
    });
  }

  // 初始化平台状态
  Future<void> initPlatformState() async {
    // 初始化 WebView 环境（可选）
    // await WebviewController.initializeEnvironment(additionalArguments: '--show-fps-counter');

    try {
      // 初始化 WebView 控制器
      await _controller.initialize();

      // 监听 URL 变化，更新文本控制器
      // _subscriptions.add(_controller.url.listen((url) {
      //   _textController.text = url.replaceAll(HOST_INDEX, "系统");
      // }));

      // 监听全屏元素变化，设置窗口是否全屏
      _subscriptions
          .add(_controller.containsFullScreenElementChanged.listen((flag) {
        debugPrint('Contains fullscreen element: $flag');
        windowManager.setFullScreen(flag);
      }));

//
      // _subscriptions.add(_controller.webMessage.listen((event) {
      //   debugPrint(event);
      // }));

      _controller.webMessage.listen((event) async {
        var parsedData = event;
        print(parsedData);
        if (parsedData["type"] == "downloadfile") {
          var response;
          if (parsedData["queryParams"] != null) {
            response = await http.post(
              Uri.parse(HOST_INDEX + parsedData["msg"]),
              headers: {
                'Authorization': parsedData["token"],
                'Content-Type': 'application/x-www-form-urlencoded'
              },
              body: tansParams(parsedData["queryParams"]),
            );
          } else {
            response = await http.get(
              Uri.parse(HOST_INDEX + parsedData["msg"]),
              headers: {
                'Authorization': parsedData["token"],
              },
            );
          }
          if (response.statusCode == 200) {
            savaFile(parsedData["name"], response.bodyBytes);
          } else {
            print('无法获取Blob数据。响应状态码：${response.statusCode}');
            await _controller.postWebMessage(jsonEncode({
              "message": '无法获取Blob数据。响应状态码：${response.statusCode}',
              "messagetype": "msg",
              "type": "error"
            }));
          }
        } else if (parsedData["type"] == "readrfid") {
          // await _getValueByKey('rfid_port');
          if (selectedPort == "") {
            await _controller.postWebMessage(jsonEncode({
              "message": '请选择RFID串口号',
              "messagetype": "msg",
              "type": "warning"
            }));
          } else {
            await connectAndReadCard();
          }
        }
      });

      // 设置 WebView 的背景颜色为透明
      await _controller.setBackgroundColor(Colors.white);

      // 设置弹出窗口策略为拒绝
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      // 加载初始 URL
      await _controller.loadUrl(HOST_INDEX);

      // 如果组件未挂载，则直接返回
      if (!mounted) return;

      // 重新构建 UI
      setState(() {});
    } on PlatformException catch (e) {
      // 捕获平台异常，并显示错误对话框
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
            context: context,
            builder: (_) => AlertDialog(
                  title: Text('Error'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Code: ${e.code}'),
                      Text('Message: ${e.message}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      child: Text('Continue'),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ],
                ));
      });
    }
  }

  // 组合视图：根据 WebView 的状态返回不同的 Widget
  Widget compositeView() {
    if (!_controller.value.isInitialized) {
      return const Text(
        'Not Initialized',
        style: TextStyle(
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      var textSelectedport = "请选择RFID串口号";
      return Padding(
        padding: EdgeInsets.all(0),
        child: Column(
          children: [
            Card(
              shadowColor: const Color.fromARGB(255, 114, 114, 114),
              surfaceTintColor: const Color.fromARGB(255, 255, 255, 255),
              elevation: 20,
              child: Row(children: [
                // 地址栏
                // Expanded(
                //   child: TextField(
                //     decoration: InputDecoration(
                //       hintText: 'URL',
                //       contentPadding: EdgeInsets.all(10.0),
                //     ),
                //     style: TextStyle(
                //         fontWeight: FontWeight.bold, color: Colors.grey),
                //     enabled: false,
                //     textAlignVertical: TextAlignVertical.center,
                //     controller: _textController,
                //     onSubmitted: (val) {
                //       _controller.loadUrl(val); // 提交 URL 后加载新页面
                //     },
                //   ),
                // ),
                const Text(
                  " ",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.home),
                  tooltip: '首页',
                  splashRadius: 20,
                  onPressed: () {
                    _controller.loadUrl(HOST_INDEX);
                  },
                ),
                // 刷新按钮
                IconButton(
                  icon: Icon(Icons.refresh),
                  tooltip: '刷新',
                  splashRadius: 20,
                  onPressed: () {
                    _controller.reload(); // 重新加载当前页面
                  },
                ),
                // 控制台
                IconButton(
                  icon: Icon(Icons.developer_mode),
                  tooltip: '终端',
                  splashRadius: 20,
                  onPressed: () {
                    _controller.openDevTools(); // 打开开发者工具
                  },
                ),
                IconButton(
                  icon: Icon(Icons.update),
                  tooltip: '升级',
                  splashRadius: 20,
                  onPressed: () {
                    update(); // 打开开发者工具
                  },
                ),
                const Text(
                  "🆔RFID：",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton(
                    menuWidth: 250,
                    // value: selectedPort,
                    hint: (selectedPort == ""
                        ? Text('选择RFID串口')
                        : Text(selectedPort)),
                    items:
                        portList.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      _saveData('rfid_port', newValue.toString());
                      setState(() {
                        selectedPort = newValue.toString();
                      });
                    })
                // IconButton(
                //   icon: Icon(Icons.minimize),
                //   tooltip: '最小化',
                //   splashRadius: 20,
                //   alignment: Alignment(0, 5),
                //   onPressed: () {
                //     // 最小化窗口
                //     windowManager.minimize();
                //   },
                // ),
                // IconButton(
                //   icon: Icon(Icons.crop_square),
                //   tooltip: '最大化',
                //   onPressed: () {
                //     // 最大化或恢复窗口
                //     windowManager.isMaximized().then((isMaximized) {
                //       if (isMaximized) {
                //         windowManager.unmaximize();
                //       } else {
                //         windowManager.maximize();
                //       }
                //     });
                //   },
                // ),
                // IconButton(
                //   icon: Icon(Icons.close),
                //   tooltip: '关闭',
                //   onPressed: () {
                //     // 关闭窗口
                //     windowManager.close();
                //   },
                // ),
              ]),
            ),
            Expanded(
                child: Card(
                    color: Colors.transparent,
                    elevation: 0,
                    clipBehavior: Clip.antiAliasWithSaveLayer,
                    child: Stack(
                      children: [
                        Webview(
                          _controller,
                          permissionRequested: _onPermissionRequested, // 处理权限请求
                        ),
                        StreamBuilder<LoadingState>(
                            stream: _controller.loadingState,
                            builder: (context, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data == LoadingState.loading) {
                                return LinearProgressIndicator(); // 显示加载进度条
                              } else {
                                return SizedBox(); // 不显示任何内容
                              }
                            }),
                      ],
                    ))),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: _isWebviewSuspended ? '恢复软件渲染' : '暂停软件渲染',
        onPressed: () async {
          if (_isWebviewSuspended) {
            await _controller.resume(); // 恢复 WebView
          } else {
            await _controller.suspend(); // 暂停 WebView
          }
          setState(() {
            _isWebviewSuspended = !_isWebviewSuspended;
          });
        },
        child: Icon(_isWebviewSuspended ? Icons.play_arrow : Icons.pause),
      ),
      // appBar: AppBar(
      //     title: StreamBuilder<String>(
      //   stream: _controller.title,
      //   builder: (context, snapshot) {
      //     return Text(
      //         snapshot.hasData ? snapshot.data! : 'WebView (Windows) Example');
      //   },
      // )),
      body: Center(
        child: compositeView(),
      ),
    );
  }

  // 处理 WebView 权限请求
  Future<WebviewPermissionDecision> _onPermissionRequested(
      String url, WebviewPermissionKind kind, bool isUserInitiated) async {
    final decision = await showDialog<WebviewPermissionDecision>(
      context: navigatorKey.currentContext!,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('WebView permission requested'),
        content: Text('WebView has requested permission \'$kind\''),
        actions: <Widget>[
          TextButton(
            onPressed: () =>
                Navigator.pop(context, WebviewPermissionDecision.deny),
            child: const Text('Deny'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, WebviewPermissionDecision.allow),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    return decision ?? WebviewPermissionDecision.none;
  }

  @override
  void dispose() {
    // 取消所有订阅
    _subscriptions.forEach((s) => s.cancel());

    // 释放 WebView 控制器资源
    _controller.dispose();
    super.dispose();
  }

  void savaFile(filename, List<int> body) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    // 检查用户是否选择了保存路径
    if (selectedDirectory != null) {
      String? filepath = path.join(selectedDirectory, filename);
      var file = File(filepath);
      await file.writeAsBytes(body);
      print('Blob 文件保存在：${file.path}');
      await _controller.postWebMessage(jsonEncode({
        "message": '文件保存在：${file.path}',
        "messagetype": "msg",
        "type": "success"
      }));
      await OpenFile.open(selectedDirectory);
    } else {
      print('未选择保存路径');
      await _controller.postWebMessage(jsonEncode(
          {"message": '未选择保存路径', "messagetype": "msg", "type": "warning"}));
    }
  }

  String tansParams(Map<String, dynamic> params) {
    String result = '';
    params.forEach((propName, value) {
      String part = Uri.encodeComponent(propName) + '=';
      if (value != null && value != '' && value != 'undefined') {
        if (value is Map) {
          value.forEach((key, subValue) {
            if (subValue != null && subValue != '' && subValue != 'undefined') {
              String params = '$propName[$key]';
              String subPart = Uri.encodeComponent(params) + '=';
              result +=
                  subPart + Uri.encodeComponent(subValue.toString()) + '&';
            }
          });
        } else {
          result += part + Uri.encodeComponent(value.toString()) + '&';
        }
      }
    });
    // 移除最后一个多余的 '&'
    if (result.isNotEmpty) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    // 确保在关闭窗口时终止进程
    await windowManager.destroy();
    exit(0);
  }
}
