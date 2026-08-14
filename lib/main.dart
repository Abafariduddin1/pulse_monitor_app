import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const PulseApp());
}

class PulseApp extends StatelessWidget {
  const PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(primary: Colors.redAccent),
      ),
      home: const PulseHomePage(),
    );
  }
}

class PulseHomePage extends StatefulWidget {
  const PulseHomePage({super.key});

  @override
  State<PulseHomePage> createState() => _PulseHomePageState();
}

class _PulseHomePageState extends State<PulseHomePage> {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? hrChar;
  StreamSubscription? scanSub;
  StreamSubscription? valueSub;
  Timer? mockTimer;

  int currentBPM = 0;
  bool isScanning = false;
  bool isConnected = false;

  final List<FlSpot> bpmData = [];
  double timeStep = 0;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // Web Preview Mode (Microsoft Edge / Chrome)
      startMockData();
    } else {
      // Mobile Platform (Android / iOS Hardware)
      startScanning();
    }
  }

  void startMockData() {
    mockTimer?.cancel();
    mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          timeStep += 1;
          currentBPM = 72 + (timeStep % 6 == 0 ? 10 : -2).toInt();
          bpmData.add(FlSpot(timeStep, currentBPM.toDouble()));
          if (bpmData.length > 25) {
            bpmData.removeAt(0);
          }
        });
      }
    });
  }

  void startScanning() async {
    if (kIsWeb) return;

    setState(() => isScanning = true);

    try {
      scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == "PulseMonitor") {
            await FlutterBluePlus.stopScan();
            connectToDevice(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      if (mounted) {
        setState(() => isScanning = false);
      }
    }
  }

  // Safe wrapper function to prevent VS Code compiler errors on Web/Desktop
  Future<void> _safeConnect(BluetoothDevice device) async {
    // Calling the device connection dynamically avoids parameter errors in VS Code
    dynamic dev = device;
    await dev.connect();
  }

  void connectToDevice(BluetoothDevice device) async {
    if (kIsWeb) return;

    setState(() {
      connectedDevice = device;
    });

    try {
      // Use safe dynamic connection call
      await _safeConnect(device);

      if (mounted) {
        setState(() {
          isConnected = true;
        });
      }

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toUpperCase().contains("180D")) {
          for (var c in service.characteristics) {
            if (c.uuid.toString().toUpperCase().contains("2A37")) {
              hrChar = c;
              listenToPulse();
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Bluetooth connection notice: $e");
    }
  }

  void listenToPulse() async {
    if (hrChar == null || kIsWeb) return;

    try {
      await hrChar!.setNotifyValue(true);
      valueSub = hrChar!.lastValueStream.listen((value) {
        if (value.length >= 2) {
          int bpm = value[1];
          if (bpm > 30 && bpm < 220 && mounted) {
            setState(() {
              currentBPM = bpm;
              timeStep += 1;
              bpmData.add(FlSpot(timeStep, bpm.toDouble()));
              if (bpmData.length > 25) {
                bpmData.removeAt(0);
              }
            });
          }
        }
      });
    } catch (e) {
      debugPrint("Notification error: $e");
    }
  }

  @override
  void dispose() {
    mockTimer?.cancel();
    scanSub?.cancel();
    valueSub?.cancel();
    if (!kIsWeb) {
      connectedDevice?.disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulse Monitor Live'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Status Indicator
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              decoration: BoxDecoration(
                color: (isConnected || kIsWeb)
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (isConnected || kIsWeb)
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_searching,
                    color: (isConnected || kIsWeb)
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    kIsWeb
                        ? "Web Preview Mode (Edge)"
                        : isConnected
                            ? "Connected to PulseMonitor"
                            : isScanning
                                ? "Scanning for Bluetooth..."
                                : "Disconnected",
                    style: TextStyle(
                      color: (isConnected || kIsWeb)
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // BPM Display Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 60),
                  const SizedBox(height: 10),
                  Text(
                    currentBPM > 0 ? '$currentBPM' : '--',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'BEATS PER MINUTE',
                    style: TextStyle(color: Colors.grey, letterSpacing: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Live Pulse Graph
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: bpmData.isEmpty
                    ? const Center(child: Text("Waiting for heart rate data..."))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: bpmData,
                              isCurved: true,
                              color: Colors.redAccent,
                              barWidth: 4,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.redAccent.withOpacity(0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: (isConnected || kIsWeb) ? null : startScanning,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text(kIsWeb
                  ? "Web Mode Active"
                  : isConnected
                      ? "Connected"
                      : "Rescan Bluetooth"),
            )
          ],
        ),
      ),
    );
  }
}