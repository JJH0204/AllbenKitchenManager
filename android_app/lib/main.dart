import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/kitchen_provider.dart';
import 'ui/screens/home_screen.dart';

/// 파일명: lib/main.dart
/// 작성의도: 애플리케이션의 진입점(Entry Point)입니다.
/// 기능 원리: `KitchenProvider`를 앱 전체에 주입(Provider Pattern)하고, 
///          초기화 로직 및 메인 화면(`HomeScreen`)을 실행합니다.


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final kitchenProvider = KitchenProvider();
  await kitchenProvider.initApp();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: kitchenProvider)],
      child: const KitchenAndroidApp(),
    ),
  );
}

class KitchenAndroidApp extends StatelessWidget {
  const KitchenAndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kitchine Android App',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
