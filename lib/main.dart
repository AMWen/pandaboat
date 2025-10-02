import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'tabs/live_tab.dart';
import 'tabs/log_tab.dart';
import 'data/constants.dart';

void main() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(logPrefix);
  await Hive.openBox<String>(namePrefix);
  await Hive.openBox<String>(accelPrefix);
  runApp(PandaboatApp());
}

class PandaboatApp extends StatelessWidget {
  const PandaboatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PandaBoat',
      theme: ThemeData(
        colorSchemeSeed: primaryColor,
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          titleTextStyle: TextStyles.titleText,
          iconTheme: IconThemeData(color: secondaryColor),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: secondaryColor,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(primary: primaryColor, secondary: secondaryColor),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          titleTextStyle: TextStyles.titleText,
          iconTheme: IconThemeData(color: secondaryColor),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: secondaryColor,
        ),
      ),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _pageController = PageController();
  bool _isRecording = false;
  String? _currentLogId;

  late List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = [
      LiveTab(onRecordingChanged: setRecording, onLogIdChanged: setCurrentLogId),
      LogTab(
        isRecording: _isRecording,
        currentLogId: _currentLogId,
        pageController: _pageController,
      ),
    ];
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onItemTapped(int index) {
    if (_isRecording) return; // Ignore taps during recording

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void setRecording(bool recording) {
    setState(() {
      _isRecording = recording;
      // Rebuild tabs with new recording state
      _tabs[1] = LogTab(
        isRecording: _isRecording,
        currentLogId: _currentLogId,
        pageController: _pageController,
      );
    });
  }

  void setCurrentLogId(String? logId) {
    setState(() {
      _currentLogId = logId;
      // Rebuild tabs with new log ID
      _tabs[1] = LogTab(
        isRecording: _isRecording,
        currentLogId: _currentLogId,
        pageController: _pageController,
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const AlwaysScrollableScrollPhysics(), // Allow swiping during recording
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        selectedItemColor: secondaryColor,
        unselectedItemColor: dullColor,
        selectedLabelStyle: TextStyles.labelText,
        unselectedLabelStyle: TextStyles.labelText,
        backgroundColor: primaryColor,
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.speed), label: 'Live'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Logs'),
        ],
      ),
    );
  }
}
