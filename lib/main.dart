import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const SecurePulseApp());
}

class SecurePulseApp extends StatelessWidget {
  const SecurePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrthoWearable Pulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HeartRateScreen(),
    );
  }
}

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({super.key});

  @override
  State<HeartRateScreen> createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? authCharacteristic;
  BluetoothCharacteristic? heartRateCharacteristic;
  BluetoothCharacteristic? postureCharacteristic;
  BluetoothCharacteristic? alertCharacteristic;

  bool isScanning = false;
  bool isConnected = false;
  bool isAuthenticated = false;
  int currentHeartRate = 0;
  bool isStanding = false;

  // Custom UUIDs matching Arduino BLE firmware
  final String deviceName = "OrthoWearable";
  final String serviceUuid = "19B10000-E8F2-537E-4F6C-D104768A1214";
  final String bpmCharUuid = "19B10001-E8F2-537E-4F6C-D104768A1214";
  final String postureCharUuid = "19B10002-E8F2-537E-4F6C-D104768A1214";
  final String alertCharUuid = "19B10003-E8F2-537E-4F6C-D104768A1214";
  final String authCharUuid = "12345678-1234-5678-1234-567812345678";

  // Real-time graph simulation
  List<FlSpot> ecgData = [];
  Timer? graphTimer;
  double timeX = 0;

  StreamSubscription<List<ScanResult>>? scanSubscription;

  @override
  void initState() {
    super.initState();
    _startGraphSimulation();
  }

  void _startGraphSimulation() {
    graphTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;

      setState(() {
        timeX += 0.05;
        double yValue = 0;
        if (currentHeartRate > 0) {
          double cycle = (60 / currentHeartRate);
          double positionInCycle = timeX % cycle;

          if (positionInCycle < 0.1) {
            yValue = 3.0 * math.sin((positionInCycle / 0.1) * math.pi); // R-Spike
          } else if (positionInCycle > 0.15 && positionInCycle < 0.25) {
            yValue = 1.0 * math.sin(((positionInCycle - 0.15) / 0.1) * math.pi); // T-Wave
          }
        }

        ecgData.add(FlSpot(timeX, yValue));
        if (ecgData.length > 60) ecgData.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    graphTimer?.cancel();
    scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> scanAndConnect() async {
    if (!mounted) return;
    setState(() => isScanning = true);

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please turn on Bluetooth on your device.")),
        );
        setState(() => isScanning = false);
      }
      return;
    }

    await FlutterBluePlus.stopScan();

    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.advName;
        bool matchesUuid = r.advertisementData.serviceUuids
            .any((uuid) => uuid.toString().toUpperCase().contains("19B10000"));

        if (name == deviceName || matchesUuid) {
          FlutterBluePlus.stopScan();
          scanSubscription?.cancel();
          connectToDevice(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(serviceUuid)],
      timeout: const Duration(seconds: 10),
    );

    await Future.delayed(const Duration(seconds: 10));
    if (mounted && !isConnected) {
      setState(() => isScanning = false);
    }
  }

Future<void> connectToDevice(BluetoothDevice device) async {
    // Add the required license parameter to remove the error
    await device.connect(
      license: License.nonprofit, 
      autoConnect: false,
    );

    if (!mounted) return;
    setState(() {
      targetDevice = device;
      isConnected = true;
      isScanning = false;
    });

    discoverServices(device);
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var char in service.characteristics) {
        String uuid = char.uuid.toString().toUpperCase();
        if (uuid == bpmCharUuid) heartRateCharacteristic = char;
        if (uuid == postureCharUuid) postureCharacteristic = char;
        if (uuid == alertCharUuid) alertCharacteristic = char;
        if (uuid == authCharUuid) authCharacteristic = char;
      }
    }

    // Bypass PIN requirement if Arduino code doesn't implement an auth characteristic
    if (authCharacteristic == null) {
      setState(() => isAuthenticated = true);
      _subscribeToSensors();
    }
  }

  Future<void> authenticateAndListen(String pin) async {
    if (authCharacteristic != null) {
      await authCharacteristic!.write(pin.codeUnits);
      await Future.delayed(const Duration(milliseconds: 500));
      List<int> response = await authCharacteristic!.read();
      String responseStr = String.fromCharCodes(response);

      if (!mounted) return;

      if (responseStr == "UNLOCKED") {
        setState(() => isAuthenticated = true);
        _subscribeToSensors();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid PIN")),
        );
      }
    }
  }

  Future<void> _subscribeToSensors() async {
    // 1. Listen to Heart Rate (BPM)
    if (heartRateCharacteristic != null) {
      await heartRateCharacteristic!.setNotifyValue(true);
      heartRateCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty && mounted) {
          setState(() => currentHeartRate = value[0]);
        }
      });
    }

    // 2. Listen to Posture (Sitting = 0, Standing = 1)
    if (postureCharacteristic != null) {
      await postureCharacteristic!.setNotifyValue(true);
      postureCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty && mounted) {
          setState(() => isStanding = (value[0] == 1));
        }
      });
    }

    // 3. Listen to Orthostatic Hypotension Alert
    if (alertCharacteristic != null) {
      await alertCharacteristic!.setNotifyValue(true);
      alertCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty && mounted) {
          if (value[0] == 1) {
            _showAlert(
              "ORTHOSTATIC WARNING",
              "Rapid heart rate jump detected upon standing! Please sit down immediately.",
              Colors.redAccent,
            );
          }
        }
      });
    }
  }

  void _showAlert(String title, String message, Color color) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: color,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text("I'm Sitting Down", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OrthoWearable Dashboard'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: !isConnected
            ? ElevatedButton(
                onPressed: isScanning ? null : scanAndConnect,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                child: Text(isScanning ? 'Scanning for OrthoWearable...' : 'Connect to OrthoWearable'),
              )
            : !isAuthenticated
                ? Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Enter PIN", style: TextStyle(fontSize: 24, color: Colors.white)),
                        const SizedBox(height: 20),
                        TextField(
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (value) => authenticateAndListen(value),
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Colors.grey,
                            hintText: '1234',
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Heart Rate Indicator
                        const Icon(Icons.favorite, color: Colors.red, size: 70),
                        Text(
                          "$currentHeartRate BPM",
                          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 20),

                        // Posture Indicator Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            color: isStanding ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isStanding ? Colors.orange : Colors.blue),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isStanding ? Icons.directions_walk : Icons.airline_seat_recline_normal,
                                color: isStanding ? Colors.orange : Colors.blue,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isStanding ? "Posture: Standing" : "Posture: Sitting",
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Real-time ECG Sliding Graph
                        SizedBox(
                          height: 160,
                          width: MediaQuery.of(context).size.width * 0.9,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: true, drawVerticalLine: false),
                              titlesData: const FlTitlesData(show: false),
                              borderData: FlBorderData(show: false),
                              minY: -2,
                              maxY: 4,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: ecgData,
                                  isCurved: true,
                                  color: Colors.greenAccent,
                                  barWidth: 3,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(show: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}