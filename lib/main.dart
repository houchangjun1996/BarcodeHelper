import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

// --- Main Entry Point ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (context) => InspectionProvider(prefs),
      child: const BarcodeScannerApp(),
    ),
  );
}

// --- App State Management (Provider) ---
class InspectionProvider with ChangeNotifier {
  final SharedPreferences _prefs;

  // --- State Variables ---
  String _benchmarkCode = "WAITING...";
  int _okCount = 0;
  int _ngCount = 0;
  bool _isAlarming = false;
  bool _isScanning = true;
  MobileScannerController cameraController = MobileScannerController();

  // --- De-duplication Logic ---
  String? _lastScannedCode;
  DateTime? _lastScannedTime;

  // --- Alarm System ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alarmFlashTimer;

  // --- Getters ---
  String get benchmarkCode => _benchmarkCode;
  int get okCount => _okCount;
  int get ngCount => _ngCount;
  bool get isAlarming => _isAlarming;
  bool get isScanning => _isScanning;

  // --- Constructor ---
  InspectionProvider(this._prefs) {
    _loadData();
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  // --- Data Persistence ---
  Future<void> _loadData() async {
    _benchmarkCode = _prefs.getString('benchmarkCode') ?? 'SET-BENCHMARK';
    _okCount = _prefs.getInt('okCount') ?? 0;
    _ngCount = _prefs.getInt('ngCount') ?? 0;
    notifyListeners();
  }

  Future<void> _saveData() async {
    await _prefs.setString('benchmarkCode', _benchmarkCode);
    await _prefs.setInt('okCount', _okCount);
    await _prefs.setInt('ngCount', _ngCount);
  }

  // --- Core Logic ---
  void onBarcodeDetected(BarcodeCapture capture) {
    if (!_isScanning || _isAlarming) return;

    final String? code = capture.barcodes.first.rawValue;
    if (code == null) return;

    final now = DateTime.now();

    // De-duplication logic
    if (code == _lastScannedCode &&
        _lastScannedTime != null &&
        now.difference(_lastScannedTime!) < const Duration(milliseconds: 300)) {
      return; // Ignore same code within 300ms
    }

    _lastScannedCode = code;
    _lastScannedTime = now;

    // Comparison logic
    if (code == _benchmarkCode) {
      _okCount++;
    } else {
      _ngCount++;
      _triggerAlarm();
    }
    _saveData();
    notifyListeners();
  }

  void _triggerAlarm() {
    _isAlarming = true;
    _playAlarmSound();
    _startAlarmFlash();
    notifyListeners();
  }

  void stopAlarm() {
    _isAlarming = false;
    _stopAlarmSound();
    _stopAlarmFlash();
    notifyListeners();
  }

  void updateBenchmarkCode(String newCode) {
    if (newCode.isNotEmpty) {
      _benchmarkCode = newCode.toUpperCase();
      _saveData();
      notifyListeners();
    }
  }

  void resetCounts() {
    _okCount = 0;
    _ngCount = 0;
    _saveData();
    notifyListeners();
  }

  void toggleScanning() {
    _isScanning = !_isScanning;
    if (_isScanning) {
      cameraController.start();
    } else {
      cameraController.stop();
    }
    notifyListeners();
  }

  // --- Alarm Helpers ---
  Future<void> _playAlarmSound() async {
    await _audioPlayer.play(AssetSource('audio/alarm.mp3'));
  }

  void _stopAlarmSound() {
    _audioPlayer.stop();
  }

  void _startAlarmFlash() {
    _alarmFlashTimer?.cancel();
    _alarmFlashTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      // This state change will be picked up by the UI to flash the background
      notifyListeners();
    });
  }

  void _stopAlarmFlash() {
    _alarmFlashTimer?.cancel();
  }

  @override
  void dispose() {
    _alarmFlashTimer?.cancel();
    _audioPlayer.dispose();
    cameraController.dispose();
    super.dispose();
  }
}

// --- UI (View) ---
class BarcodeScannerApp extends StatelessWidget {
  const BarcodeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.lightBlue,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.robotoMonoTextTheme(ThemeData.dark().textTheme),
      ),
      home: const InspectionScreen(),
    );
  }
}

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key});

  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  final TextEditingController _benchmarkController = TextEditingController();
  bool _isFlashing = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    // A local timer to handle the visual flash effect without rebuilding the whole widget tree
    _flashTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final provider = context.read<InspectionProvider>();
      if (provider.isAlarming) {
        setState(() {
          _isFlashing = !_isFlashing;
        });
      } else if (_isFlashing) {
        setState(() {
          _isFlashing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _benchmarkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InspectionProvider>();

    return Scaffold(
      backgroundColor: _isFlashing ? Colors.red.shade700 : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('流水线条码质检'),
        centerTitle: true,
        backgroundColor: Colors.black26,
      ),
      body: Column(
        children: [
          // --- Benchmark Code Display ---
          _buildBenchmarkBar(context, provider),
          
          // --- Camera Preview ---
          Expanded(
            flex: 3,
            child: _buildCameraView(provider),
          ),
          
          // --- Statistics Display ---
          _buildStatsPanel(provider),
          
          // --- Control Panel ---
          if (!provider.isAlarming) _buildControlPanel(context, provider),
          
          // --- Stop Alarm Button ---
          if (provider.isAlarming) _buildStopAlarmButton(provider),
        ],
      ),
    );
  }

  Widget _buildBenchmarkBar(BuildContext context, InspectionProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('基准码:', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              provider.benchmarkCode,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: () => _showBenchmarkDialog(context, provider),
            tooltip: '修改基准码',
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView(InspectionProvider provider) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: provider.isScanning ? Colors.green : Colors.grey,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            MobileScanner(
              controller: provider.cameraController,
              onDetect: provider.onBarcodeDetected,
            ),
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 2.0),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (!provider.isScanning)
              Container(
                color: Colors.black.withAlpha((255 * 0.5).round()),
                child: const Center(
                  child: Text('扫描已暂停', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsPanel(InspectionProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('OK', provider.okCount, Colors.green.shade400)),
          const SizedBox(width: 16),
          Expanded(child: _buildStatCard('NG', provider.ngCount, Colors.red.shade400)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          Text(count.toString(), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, InspectionProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: provider.resetCounts,
            icon: const Icon(Icons.refresh),
            label: const Text('重置计数'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: () => _showBenchmarkDialog(context, provider),
            icon: const Icon(Icons.input),
            label: const Text('手动输入'),
          ),
          ElevatedButton.icon(
            onPressed: provider.toggleScanning,
            icon: Icon(provider.isScanning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            label: Text(provider.isScanning ? '停止' : '开始'),
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.isScanning ? Colors.grey.shade700 : Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopAlarmButton(InspectionProvider provider) {
    return Container(
      width: double.infinity,
      height: 150,
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: provider.stopAlarm,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pan_tool, size: 48),
            SizedBox(height: 8),
            Text('停止报警', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _showBenchmarkDialog(BuildContext context, InspectionProvider provider) {
    _benchmarkController.text = provider.benchmarkCode;
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置基准码'),
          content: TextField(
            controller: _benchmarkController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '输入或扫描基准条码',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              provider.updateBenchmarkCode(value);
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                provider.updateBenchmarkCode(_benchmarkController.text);
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
