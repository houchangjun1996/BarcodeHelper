
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

// --- Main Entry Point ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (context) => InspectionProvider(prefs, firstCamera),
      child: const BarcodeScannerApp(),
    ),
  );
}

// --- App State Management (Provider) ---
class InspectionProvider with ChangeNotifier {
  final SharedPreferences _prefs;
  final CameraDescription _cameraDescription;

  // --- State Variables ---
  String _benchmarkCode = "WAITING...";
  int _okCount = 0;
  int _ngCount = 0;
  bool _isAlarming = false;
  bool _isCameraInitialized = false;
  int _captureInterval = 500; // Default capture interval in milliseconds

  CameraController? cameraController;
  Timer? _captureTimer;
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  // --- Alarm System ---
  final AudioPlayer _audioPlayer = AudioPlayer();

  // --- Getters ---
  String get benchmarkCode => _benchmarkCode;
  int get okCount => _okCount;
  int get ngCount => _ngCount;
  bool get isAlarming => _isAlarming;
  bool get isCameraInitialized => _isCameraInitialized;
  int get captureInterval => _captureInterval;
  bool get isCapturing => _captureTimer?.isActive ?? false;

  // --- Constructor ---
  InspectionProvider(this._prefs, this._cameraDescription) {
    _loadData();
    _initializeCamera();
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  // --- Camera & Scanning Logic ---
  Future<void> _initializeCamera() async {
    cameraController = CameraController(
      _cameraDescription,
      ResolutionPreset.medium, // Use medium resolution for faster processing
      enableAudio: false,
    );
    try {
      await cameraController!.initialize();
      // Attempt to set the lowest possible exposure time for motion blur reduction
      await cameraController!.setExposureMode(ExposureMode.auto);
      _isCameraInitialized = true;
      startCapturing(); // Start capturing by default
    } catch (e) {
      // Handle camera initialization error
      print("Camera initialization failed: $e");
    }
    notifyListeners();
  }

  void startCapturing() {
    if (isCapturing || !_isCameraInitialized) return;
    _captureTimer = Timer.periodic(Duration(milliseconds: _captureInterval), (_) {
      _captureAndProcessImage();
    });
    notifyListeners();
  }

  void stopCapturing() {
    _captureTimer?.cancel();
    notifyListeners();
  }

  Future<void> _captureAndProcessImage() async {
    if (cameraController == null || !cameraController!.value.isInitialized || cameraController!.value.isTakingPicture) {
      return;
    }

    try {
      final XFile imageFile = await cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(imageFile.path);
      
      final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);

      for (final barcode in barcodes) {
        if (barcode.rawValue != null) {
          _processBarcode(barcode.rawValue!);
          break; // Process the first valid barcode found
        }
      }
    } catch (e) {
      print("Error capturing or processing image: $e");
    }
  }

  void _processBarcode(String code) {
    if (_isAlarming) return;

    if (code == _benchmarkCode) {
      _okCount++;
    } else {
      _ngCount++;
      _triggerAlarm();
    }
    _saveData();
    notifyListeners();
  }

  void updateCaptureInterval(int newInterval) {
    if (newInterval > 0) {
      _captureInterval = newInterval;
      if (isCapturing) {
        // Restart timer with new interval
        stopCapturing();
        startCapturing();
      }
      _prefs.setInt('captureInterval', _captureInterval);
      notifyListeners();
    }
  }

  // --- Data, Alarm, and Lifecycle Management ---
  Future<void> _loadData() async {
    _benchmarkCode = _prefs.getString('benchmarkCode') ?? 'SET-BENCHMARK';
    _okCount = _prefs.getInt('okCount') ?? 0;
    _ngCount = _prefs.getInt('ngCount') ?? 0;
    _captureInterval = _prefs.getInt('captureInterval') ?? 500;
    notifyListeners();
  }

  Future<void> _saveData() async {
    await _prefs.setString('benchmarkCode', _benchmarkCode);
    await _prefs.setInt('okCount', _okCount);
    await _prefs.setInt('ngCount', _ngCount);
  }

  void _triggerAlarm() {
    _isAlarming = true;
    _playAlarmSound();
    notifyListeners();
  }

  void stopAlarm() {
    _isAlarming = false;
    _stopAlarmSound();
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

  Future<void> _playAlarmSound() async {
    await _audioPlayer.play(AssetSource('audio/alarm.mp3'));
  }

  void _stopAlarmSound() {
    _audioPlayer.stop();
  }

  @override
  void dispose() {
    stopCapturing();
    cameraController?.dispose();
    _barcodeScanner.close();
    _audioPlayer.dispose();
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

class _InspectionScreenState extends State<InspectionScreen> with WidgetsBindingObserver {
  Timer? _flashTimer;
  bool _isFlashing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flashTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      final provider = context.read<InspectionProvider>();
      if(provider.isAlarming && mounted){
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
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final provider = context.read<InspectionProvider>();
    if (!provider.isCameraInitialized) return;

    if (state == AppLifecycleState.inactive) {
      provider.cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      provider._initializeCamera();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InspectionProvider>();

    return Scaffold(
      backgroundColor: _isFlashing ? Colors.red.shade700 : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('流水线条码质检 (v1.2)'),
        centerTitle: true,
        backgroundColor: Colors.black26,
      ),
      body: Column(
        children: [
          _buildBenchmarkBar(context, provider),
          Expanded(
            flex: 3,
            child: _buildCameraView(provider),
          ),
          _buildStatsPanel(provider),
           if (!provider.isAlarming) _buildControlPanel(context, provider),
          if (provider.isAlarming) _buildStopAlarmButton(provider),
        ],
      ),
    );
  }
  
  Widget _buildCameraView(InspectionProvider provider) {
    if (!provider.isCameraInitialized || provider.cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: provider.isCapturing ? Colors.green : Colors.grey,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            CameraPreview(provider.cameraController!),
            if (!provider.isCapturing)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: Text('拍摄已暂停', style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
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
            onPressed: () => _showIntervalDialog(context, provider),
            icon: const Icon(Icons.timer_outlined),
            label: Text('${provider.captureInterval} ms'),
          ),
          ElevatedButton.icon(
            onPressed: provider.resetCounts,
            icon: const Icon(Icons.refresh),
            label: const Text('重置'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
          ),
          ElevatedButton.icon(
            onPressed: provider.isCapturing ? provider.stopCapturing : provider.startCapturing,
            icon: Icon(provider.isCapturing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            label: Text(provider.isCapturing ? '停止' : '开始'),
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.isCapturing ? Colors.grey.shade700 : Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
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
    final controller = TextEditingController(text: provider.benchmarkCode);
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置基准码'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: '输入或扫描基准条码'),
            onSubmitted: (value) {
              provider.updateBenchmarkCode(value);
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                provider.updateBenchmarkCode(controller.text);
                Navigator.of(context).pop();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showIntervalDialog(BuildContext context, InspectionProvider provider) {
    final controller = TextEditingController(text: provider.captureInterval.toString());
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置拍照间隔 (ms)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '毫秒'),
            onSubmitted: (value) {
              final newInterval = int.tryParse(value);
              if (newInterval != null) {
                provider.updateCaptureInterval(newInterval);
              }
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                 final newInterval = int.tryParse(controller.text);
                if (newInterval != null) {
                  provider.updateCaptureInterval(newInterval);
                }
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
