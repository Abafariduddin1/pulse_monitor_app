import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp; // Prefix to avoid License collision

void main() {
  runApp(const SecurePulseApp());
}

class SecurePulseApp extends StatelessWidget {
  const SecurePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Pulse',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
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
  fbp.BluetoothDevice? targetDevice;
  fbp.BluetoothCharacteristic? authCharacteristic;
  fbp.BluetoothCharacteristic? hrCharacteristic;
  StreamSubscription<List<int>>? hrSubscription;

  bool isScanning = false;
  bool isConnected = false;
  bool isAuthenticated = false;
  int currentHeartRate = 0;
  String statusMessage = "Press Scan to find PulseShield";

  final String targetDeviceName = "PulseShield";
  final String hrServiceUuid = "180D";
  final String hrCharUuid = "2A37";
  final String authCharUuid = "12345678-1234-5678-1234-567812345678";

  @override
  void dispose() {
    hrSubscription?.cancel();
    targetDevice?.disconnect();
    super.dispose();
  }

  Future<void> startScan() async {
    setState(() {
      isScanning = true;
      statusMessage = "Scanning for $targetDeviceName...";
    });

    try {
      await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      fbp.FlutterBluePlus.scanResults.listen((results) {
        for (fbp.ScanResult r in results) {
          if (r.device.advName == targetDeviceName) {
            fbp.FlutterBluePlus.stopScan();
            setState(() {
              targetDevice = r.device;
              isScanning = false;
              statusMessage = "Found device. Connecting...";
            });
            connectToDevice();
            break;
          }
        }
      });
    } catch (e) {
      setState(() {
        isScanning = false;
        statusMessage = "Scan failed: $e";
      });
    }
  }

  Future<void> connectToDevice() async {
    if (targetDevice == null) return;

    try {
      // USING THE PREFIXED LICENSE ENUM TO AVOID COLLISION
      await targetDevice!.connect(
        license: fbp.License.nonprofit,
        autoConnect: false,
        mtu: 512,
      );

      setState(() {
        isConnected = true;
        statusMessage = "Connected. Discovering services...";
      });

      List<fbp.BluetoothService> services = await targetDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toUpperCase() == hrServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toUpperCase() == hrCharUuid) {
              hrCharacteristic = char;
            } else if (char.uuid.toString().toUpperCase() == authCharUuid) {
              authCharacteristic = char;
            }
          }
        }
      }

      if (authCharacteristic != null) {
        setState(() {
          statusMessage = "Device Locked. Awaiting PIN.";
        });
        _showPinDialog();
      } else {
        setState(() {
          statusMessage = "Security characteristic not found.";
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = "Connection failed: $e";
        isConnected = false;
      });
    }
  }

  void _showPinDialog() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enter PIN"),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(hintText: "4-digit PIN"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              authenticate(pinController.text);
            },
            child: const Text("Unlock"),
          )
        ],
      ),
    );
  }

  Future<void> authenticate(String pin) async {
    if (authCharacteristic == null) return;

    await authCharacteristic!.write(utf8.encode(pin), withoutResponse: false);
    
    // Slight delay to allow Arduino to process the PIN
    await Future.delayed(const Duration(milliseconds: 500));
    
    List<int> response = await authCharacteristic!.read();
    String responseStr = utf8.decode(response);

    if (responseStr == "UNLOCKED") {
      setState(() {
        isAuthenticated = true;
        statusMessage = "Unlocked! Reading heart rate...";
      });
      startListeningToHeartRate();
    } else {
      setState(() {
        statusMessage = "Incorrect PIN. Try again.";
      });
      targetDevice?.disconnect();
      setState(() {
        isConnected = false;
      });
    }
  }

  Future<void> startListeningToHeartRate() async {
    if (hrCharacteristic == null) return;

    await hrCharacteristic!.setNotifyValue(true);
    hrSubscription = hrCharacteristic!.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        setState(() {
          currentHeartRate = value[0];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Secure Pulse"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite,
              color: isAuthenticated ? Colors.red : Colors.grey,
              size: 100,
            ),
            const SizedBox(height: 20),
            Text(
              isAuthenticated ? "$currentHeartRate BPM" : "--",
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: (isScanning || isConnected) ? null : startScan,
              child: Text(isScanning ? "Scanning..." : "Scan for Device"),
            ),
          ],
        ),
      ),
    );
  }
}