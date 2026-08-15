import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const SecurePulseApp());
}

class SecurePulseApp extends StatelessWidget {
  const SecurePulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Pulse Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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
  // BLE UUIDs matching the Arduino Sketch
  final String serviceUuid = "19b10000-e8f2-537e-4f6c-d104768a1214";
  final String hrCharUuid = "19b10001-e8f2-537e-4f6c-d104768a1214";
  final String passCharUuid = "19b10002-e8f2-537e-4f6c-d104768a1214";

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? passCharacteristic;
  BluetoothCharacteristic? hrCharacteristic;
  StreamSubscription<List<int>>? hrSubscription;

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isAuthenticated = false;
  int currentBpm = 0;

  final TextEditingController _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    hrSubscription?.cancel();
    connectedDevice?.disconnect();
    _pinController.dispose();
    super.dispose();
  }

  // --- Bluetooth Scan & Refresh ---
  void _startScan() async {
    setState(() {
      scanResults.clear();
      isScanning = true;
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            scanResults = results;
          });
        }
      });
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => isScanning = false);
      });
    }
  }

  // --- Device Connection & Service Discovery ---
  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    setState(() => isScanning = false);

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      setState(() {
        connectedDevice = device;
        isAuthenticated = false;
        currentBpm = 0;
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == passCharUuid) {
              passCharacteristic = char;
            }
            if (char.uuid.toString().toLowerCase() == hrCharUuid) {
              hrCharacteristic = char;
            }
          }
        }
      }

      if (passCharacteristic != null && hrCharacteristic != null) {
        _showPinDialog();
      } else {
        _showSnackBar("Required pulse monitor characteristics not found!");
      }
    } catch (e) {
      _showSnackBar("Connection failed: $e");
    }
  }

  // --- Authentication Dialog ---
  void _showPinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Device Authentication"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter the PIN to access biometric pulse data:"),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: "PIN (Default: 1234)",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _disconnect();
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _authenticateDevice(_pinController.text.trim());
              },
              child: const Text("Unlock"),
            ),
          ],
        );
      },
    );
  }

  // --- PIN Authentication & Stream Subscription ---
  Future<void> _authenticateDevice(String pin) async {
    if (passCharacteristic == null || hrCharacteristic == null) return;

    try {
      // Send PIN string as bytes
      await passCharacteristic!.write(pin.codeUnits);
      
      setState(() {
        isAuthenticated = true;
      });

      // Enable notifications on Heart Rate Characteristic
      await hrCharacteristic!.setNotifyValue(true);
      hrSubscription = hrCharacteristic!.onValueReceived.listen((value) {
        if (value.isNotEmpty && mounted) {
          setState(() {
            currentBpm = value.first;
          });
        }
      });

      _showSnackBar("Authenticated successfully!");
    } catch (e) {
      _showSnackBar("Authentication failed: $e");
      _disconnect();
    }
  }

  void _disconnect() async {
    await hrSubscription?.cancel();
    await connectedDevice?.disconnect();
    setState(() {
      connectedDevice = null;
      isAuthenticated = false;
      currentBpm = 0;
      passCharacteristic = null;
      hrCharacteristic = null;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // --- UI Layout ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pulse Monitor"),
        actions: [
          IconButton(
            icon: Icon(isScanning ? Icons.sync : Icons.refresh),
            tooltip: "Scan for Devices",
            onPressed: isScanning ? null : _startScan,
          ),
        ],
      ),
      body: connectedDevice == null ? _buildDeviceList() : _buildPulseView(),
    );
  }

  // Device Discovery Menu
  Widget _buildDeviceList() {
    return Column(
      children: [
        if (isScanning) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Available Devices (${scanResults.length})",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ElevatedButton.icon(
                onPressed: isScanning ? null : _startScan,
                icon: const Icon(Icons.search, size: 18),
                label: const Text("Rescan"),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: scanResults.isEmpty
              ? Center(
                  child: Text(
                    isScanning ? "Scanning for Bluetooth devices..." : "No devices found. Tap Refresh to scan.",
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: scanResults.length,
                  itemBuilder: (context, index) {
                    final result = scanResults[index];
                    final name = result.device.platformName.isNotEmpty
                        ? result.device.platformName
                        : "Unknown Device";
                    
                    return ListTile(
                      leading: const Icon(Icons.bluetooth, color: Colors.blueAccent),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(result.device.remoteId.str),
                      trailing: ElevatedButton(
                        onPressed: () => _connectToDevice(result.device),
                        child: const Text("Connect"),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Pulse Display Screen
  Widget _buildPulseView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
              isAuthenticated ? "$currentBpm BPM" : "LOCKED",
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isAuthenticated
                  ? "Connected to ${connectedDevice?.platformName}"
                  : "Authenticating with Device...",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text("Disconnect Device"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}