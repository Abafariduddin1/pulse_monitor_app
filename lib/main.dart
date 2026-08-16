import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const SecurePulseApp());
}

class SecurePulseApp extends StatelessWidget {
  const SecurePulseApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Pulse',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HeartRateScreen(),
    );
  }
}

class HeartRateScreen extends StatefulWidget {
  const HeartRateScreen({Key? key}) : super(key: key);
  @override
  _HeartRateScreenState createState() => _HeartRateScreenState();
}

class _HeartRateScreenState extends State<HeartRateScreen> {
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? authCharacteristic;
  BluetoothCharacteristic? heartRateCharacteristic;
  BluetoothCharacteristic? alertCharacteristic;

  bool isScanning = false;
  bool isConnected = false;
  bool isAuthenticated = false;
  int currentHeartRate = 0;

  final String deviceName = "PulseShield";
  final String authCharUuid = "12345678-1234-5678-1234-567812345678";
  final String hrCharUuid = "2A37";
  final String alertCharUuid = "19B10003-E8F2-537E-4F6C-D104768A1214";

  // Graph data
  List<FlSpot> ecgData = [];
  Timer? graphTimer;
  double timeX = 0;

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
        // Generate an ECG-like pulse based on current BPM
        double yValue = 0;
        if (currentHeartRate > 0) {
          double cycle = (60 / currentHeartRate);
          double positionInCycle = timeX % cycle;
          
          if (positionInCycle < 0.1) {
            yValue = 3.0 * math.sin((positionInCycle / 0.1) * math.pi); // Spike
          } else if (positionInCycle > 0.15 && positionInCycle < 0.25) {
            yValue = 1.0 * math.sin(((positionInCycle - 0.15) / 0.1) * math.pi); // T-wave
          }
        }
        
        ecgData.add(FlSpot(timeX, yValue));
        if (ecgData.length > 60) ecgData.removeAt(0); // Keep window sliding
      });
    });
  }

  @override
  void dispose() {
    graphTimer?.cancel();
    super.dispose();
  }

  void scanAndConnect() async {
    setState(() => isScanning = true);
    
    // Stop any active scans before starting a new one
    await FlutterBluePlus.stopScan();

    // Listen to scan results
    var subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // Print found devices to console for easy debugging
        print('Found device: ${r.device.advName} / ${r.device.platformName}');

        // Check advName, platformName, or localName
        if (r.device.advName == deviceName || 
            r.device.platformName == deviceName || 
            r.advertisementData.localName == deviceName) {
          
          FlutterBluePlus.stopScan();
          subscription.cancel();
          connectToDevice(r.device);
          break;
        }
      }
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

    // Reset scanning state if timeout finishes without finding device
    await Future.delayed(const Duration(seconds: 8));
    if (mounted && !isConnected) {
      setState(() => isScanning = false);
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    // Added the license parameter back in to satisfy flutter_blue_plus
    await device.connect(
      license: License.nonprofit, 
      autoConnect: false,
    );
    
    setState(() {
      targetDevice = device;
      isConnected = true;
      isScanning = false;
    });
    discoverServices(device);
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var char in service.characteristics) {
        String uuid = char.uuid.toString().toUpperCase();
        if (uuid == hrCharUuid) heartRateCharacteristic = char;
        if (uuid == authCharUuid) authCharacteristic = char;
        if (uuid == alertCharUuid) alertCharacteristic = char;
      }
    }
  }

  void authenticateAndListen(String pin) async {
    if (authCharacteristic != null) {
      await authCharacteristic!.write(pin.codeUnits);
      await Future.delayed(const Duration(milliseconds: 500));
      List<int> response = await authCharacteristic!.read();
      String responseStr = String.fromCharCodes(response);

      if (responseStr == "UNLOCKED") {
        setState(() => isAuthenticated = true);
        
        // Listen to Heart Rate
        await heartRateCharacteristic?.setNotifyValue(true);
        heartRateCharacteristic?.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            setState(() => currentHeartRate = value[0]);
          }
        });

        // Listen to Fall Alerts
        await alertCharacteristic?.setNotifyValue(true);
        alertCharacteristic?.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            if (value[0] == 1) _showAlert("PRE-FALL WARNING", "Sudden stumble detected!", Colors.orange);
            if (value[0] == 2) _showAlert("CRITICAL FALL", "Impact and stillness detected!", Colors.red);
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid PIN")));
      }
    }
  }

  void _showAlert(String title, String message, Color color) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: color,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("I'm OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure Pulse & Fall Detection'), backgroundColor: Colors.black),
      body: Center(
        child: !isConnected
            ? ElevatedButton(
                onPressed: isScanning ? null : scanAndConnect,
                child: Text(isScanning ? 'Scanning...' : 'Connect to PulseShield'),
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
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.favorite, color: Colors.red, size: 80),
                      Text(
                        "$currentHeartRate BPM",
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 40),
                      // Animated Heart Rate Graph
                      SizedBox(
                        height: 150,
                        width: MediaQuery.of(context).size.width * 0.9,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true, drawVerticalLine: false),
                            titlesData: FlTitlesData(show: false),
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
                                dotData: FlDotData(show: false),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}