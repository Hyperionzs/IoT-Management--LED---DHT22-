import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';
import 'dart:io';

void main() {
  runApp(const IoTDashboardApp());
}

class IoTDashboardApp extends StatelessWidget {
  const IoTDashboardApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart IoT Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
        ),
      ),
      home: const IoTDashboardScreen(),
    );
  }
}

// ========== Auto-Discovery Functions ==========
class ESP8266Discovery {
  static Future<List<String>> scanForESP8266() async {
    List<String> foundDevices = [];
    
    // Get local network range
    String? localIP = await _getLocalIP();
    if (localIP == null) return foundDevices;
    
    String networkBase = localIP.substring(0, localIP.lastIndexOf('.'));
    
    print('Scanning network: $networkBase.1-254');
    
    // Scan IP range
    for (int i = 1; i <= 254; i++) {
      String ip = '$networkBase.$i';
      
      try {
        var response = await http
            .get(
              Uri.parse('http://$ip/wifi_status'),
            )
            .timeout(const Duration(seconds: 1));
        
        if (response.statusCode == 200) {
          try {
            var data = json.decode(response.body);
            if (data['connected'] != null && data['device'] == 'ESP8266-Sensor') {
              foundDevices.add(ip);
              print('Found ESP8266 at: $ip');
            }
          } catch (e) {
            // Not a valid ESP8266 response
          }
        }
      } catch (e) {
        // IP tidak merespons atau timeout
      }
    }
    
    return foundDevices;
  }
  
  static Future<String?> _getLocalIP() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('Error getting local IP: $e');
    }
    return null;
  }
  
  static Future<String?> getESP8266IP() async {
    // Coba mDNS dulu
    try {
      var response = await http
          .get(
            Uri.parse('http://esp8266-sensor.local/wifi_status'),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return 'esp8266-sensor.local';
      }
    } catch (e) {
      print('mDNS failed: $e');
    }
    
    // Fallback: scan network
    List<String> devices = await scanForESP8266();
    if (devices.isNotEmpty) {
      return devices.first;
    }
    
    return null;
  }
  
  static Future<Map<String, dynamic>?> getESP8266Info(String ip) async {
    try {
      var response = await http
          .get(
            Uri.parse('http://$ip/wifi_status'),
          )
          .timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Error getting ESP8266 info: $e');
    }
    return null;
  }
}

// ========== Updated IoTProject Class ==========
class IoTProject {
  String id;
  String name;
  String description;
  String? deviceIP; // Auto-discovered
  String? mqttHost; // Auto-discovered
  String? serverUrl; // Optional
  int mqttPort;
  String wifiSSID;
  String wifiPassword;
  bool yellowLedStatus;
  bool greenLedStatus;
  bool whiteLedStatus;
  double? lastTemperature;
  String lastLedMode;
  DateTime lastUpdate;
  bool isOnline;

  IoTProject({
    required this.id,
    required this.name,
    required this.description,
    this.deviceIP,
    this.mqttHost,
    this.serverUrl,
    this.mqttPort = 1883,
    required this.wifiSSID,
    required this.wifiPassword,
    this.yellowLedStatus = false,
    this.greenLedStatus = false,
    this.whiteLedStatus = false,
    this.lastTemperature,
    this.lastLedMode = "OFF",
    required this.lastUpdate,
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'deviceIP': deviceIP,
    'mqttHost': mqttHost,
    'serverUrl': serverUrl,
    'mqttPort': mqttPort,
    'wifiSSID': wifiSSID,
    'wifiPassword': wifiPassword,
    'yellowLedStatus': yellowLedStatus,
    'greenLedStatus': greenLedStatus,
    'whiteLedStatus': whiteLedStatus,
    'lastTemperature': lastTemperature,
    'lastLedMode': lastLedMode,
    'lastUpdate': lastUpdate.toIso8601String(),
    'isOnline': isOnline,
  };

  factory IoTProject.fromJson(Map<String, dynamic> json) => IoTProject(
    id: json['id'],
    name: json['name'],
    description: json['description'],
    deviceIP: json['deviceIP'],
    mqttHost: json['mqttHost'],
    serverUrl: json['serverUrl'],
    mqttPort: json['mqttPort'] ?? 1883,
    wifiSSID: json['wifiSSID'],
    wifiPassword: json['wifiPassword'],
    yellowLedStatus: json['yellowLedStatus'] ?? false,
    greenLedStatus: json['greenLedStatus'] ?? false,
    whiteLedStatus: json['whiteLedStatus'] ?? false,
    lastTemperature: json['lastTemperature']?.toDouble(),
    lastLedMode: json['lastLedMode'] ?? "OFF",
    lastUpdate: DateTime.parse(json['lastUpdate']),
    isOnline: json['isOnline'] ?? false,
  );
}

// ========== Main Dashboard Screen ==========
class IoTDashboardScreen extends StatefulWidget {
  const IoTDashboardScreen({Key? key}) : super(key: key);

  @override
  State<IoTDashboardScreen> createState() => _IoTDashboardScreenState();
}

class _IoTDashboardScreenState extends State<IoTDashboardScreen>
    with TickerProviderStateMixin {
  List<IoTProject> projects = [];
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false;
  MqttServerClient? _mqttClient;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSub;
  late AnimationController _slideController;
  // Removed unused _slideAnimation to fix unused_field warning
  // WiFi config controllers
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  RawDatagramSocket? _udpSocket;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    // _slideAnimation was unused; initialization removed
    
    _loadProjects();
    _connectMQTT();
    _startAutoDiscovery();
    _startUdpListener();

    // Prefill WiFi controllers from first project when available
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (projects.isNotEmpty) {
        _ssidController.text = projects.first.wifiSSID;
        _passwordController.text = projects.first.wifiPassword;
      }
    });
  }
  void _startUdpListener() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 12345, reuseAddress: true);
      _udpSocket?.broadcastEnabled = true;
      _udpSocket?.readEventsEnabled = true;
      _udpSocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket?.receive();
          if (dg == null) return;
          try {
            final payload = utf8.decode(dg.data);
            final data = json.decode(payload);
            if (data is Map && data['device'] == 'ESP8266-Sensor') {
              _safeSetState(() {
                if (projects.isNotEmpty) {
                  projects.first.deviceIP = data['ip'] ?? projects.first.deviceIP;
                  projects.first.mqttHost = data['mqttHost'] ?? projects.first.mqttHost;
                  projects.first.mqttPort = (data['mqttPort'] is int) ? data['mqttPort'] : projects.first.mqttPort;
                  projects.first.serverUrl = data['serverUrl'] ?? projects.first.serverUrl;
                  projects.first.isOnline = true;
                }
                _isDeviceOnline = true;
              });
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      print('UDP listener error: $e');
    }
  }

  void _startAutoDiscovery() async {
    // Auto-discover ESP8266 devices
    String? espIP = await ESP8266Discovery.getESP8266IP();
    if (espIP != null && projects.isNotEmpty) {
      setState(() {
        projects.first.deviceIP = espIP;
        projects.first.isOnline = true;
      });
      
      // Get device info
      Map<String, dynamic>? info = await ESP8266Discovery.getESP8266Info(espIP);
      if (info != null) {
        setState(() {
          projects.first.mqttHost = info['mqttHost'] ?? 'test.mosquitto.org';
          projects.first.mqttPort = info['mqttPort'] ?? 1883;
          projects.first.serverUrl = info['serverUrl'] ?? '';
        });
      }
    }
  }

  void _loadProjects() {
    setState(() {
      projects = [
        IoTProject(
          id: '001',
          name: 'ESP8266 Smart Sensor',
          description: 'Auto-discovered ESP8266 device',
          wifiSSID: 'Sugooi',
          wifiPassword: 'Saturned',
          yellowLedStatus: false,
          greenLedStatus: false,
          whiteLedStatus: false,
          lastTemperature: null,
          lastLedMode: 'OFF',
          lastUpdate: DateTime.now().subtract(const Duration(minutes: 5)),
          isOnline: false,
        ),
      ];
    });
  }

  Future<void> _connectMQTT() async {
    try {
      final clientId = 'smart_iot_dashboard_${DateTime.now().millisecondsSinceEpoch}';
      
      String brokerHost = 'test.mosquitto.org';
      if (projects.isNotEmpty && projects.first.mqttHost != null) {
        brokerHost = projects.first.mqttHost!;
      }

      MqttServerClient buildClient({required bool useWebSocket, required int port}) {
        final client = MqttServerClient(brokerHost, clientId);
        client.logging(on: false);
        client.keepAlivePeriod = 30;
        client.port = port;
        client.autoReconnect = true;
        client.connectTimeoutPeriod = 10000;
        client.useWebSocket = useWebSocket;

        client.onConnected = () {
          print('MQTT Connected successfully');
          _safeSetState(() {
            _isMqttConnected = true;
          });
        };

        client.onDisconnected = () {
          print('MQTT Disconnected');
          _safeSetState(() {
            _isMqttConnected = false;
            _isDeviceOnline = false;
            if (projects.isNotEmpty) {
              projects.first.isOnline = false;
            }
          });
        };

        final connectionMessage = MqttConnectMessage()
            .withClientIdentifier(clientId)
            .startClean()
            .withWillQos(MqttQos.atLeastOnce);
        client.connectionMessage = connectionMessage;
        return client;
      }

      final int tcpPort = (projects.isNotEmpty ? projects.first.mqttPort : 1883);
      _mqttClient = buildClient(useWebSocket: false, port: tcpPort);
      MqttClientConnectionStatus? connectionStatus = await _mqttClient?.connect();

      if (connectionStatus?.state != MqttConnectionState.connected) {
        try {
          await _mqttSub?.cancel();
          _mqttClient?.disconnect();
        } catch (e) {
          print('Error during MQTT cleanup: $e');
        }
        return;
      }

      _mqttSub = _mqttClient?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        
        try {
          final data = json.decode(pt);
          _handleMQTTData(data);
        } catch (e) {
          print('Error parsing MQTT data: $e');
        }
      });

      // Subscribe to topics
      if (projects.isNotEmpty) {
        _mqttClient?.subscribe('Anggra/sensor/suhu', MqttQos.atLeastOnce);
        _mqttClient?.subscribe('Anggra/sensor/led_control', MqttQos.atLeastOnce);
      }

    } catch (e) {
      print('MQTT connection error: $e');
    }
  }

  void _handleMQTTData(Map<String, dynamic> data) {
    if (data['device'] == 'ESP8266-Sensor') {
      _safeSetState(() {
        _isDeviceOnline = true;
        if (projects.isNotEmpty) {
          projects.first.isOnline = true;
        }
        if (data['temperature'] != null) {
          projects.first.lastTemperature = data['temperature'].toDouble();
        }
        if (data['ledStatus'] != null) {
          projects.first.lastLedMode = data['ledStatus'];
        }
        projects.first.lastUpdate = DateTime.now();
      });
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Smart IoT Dashboard',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Auto-Discovery Enabled',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Flexible(
                              child: Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                children: [
                                  _buildStatusIndicator(
                                    'MQTT',
                                    _isMqttConnected,
                                    Icons.cloud,
                                  ),
                                  _buildStatusIndicator(
                                    'Device',
                                    _isDeviceOnline,
                                    Icons.device_hub,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildProjectCard(),
                const SizedBox(height: 20),
                _buildControlPanel(),
                const SizedBox(height: 20),
                _buildWifiConfigPanel(),
                const SizedBox(height: 20),
                _buildAutoDiscoveryPanel(),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProjectDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
        backgroundColor: const Color(0xFF2196F3),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isConnected, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isConnected ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isConnected ? Colors.green : Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard() {
    if (projects.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text('No devices found. Add a device to get started.'),
          ),
        ),
      );
    }

    final project = projects.first;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: project.isOnline ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.device_hub,
                    color: project.isOnline ? Colors.green : Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project.description,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: project.isOnline ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    project.isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (project.deviceIP != null) ...[
              _buildInfoRow('Device IP', project.deviceIP!),
              const SizedBox(height: 8),
            ],
            if (project.mqttHost != null) ...[
              _buildInfoRow('MQTT Host', project.mqttHost!),
              const SizedBox(height: 8),
            ],
            if (project.lastTemperature != null) ...[
              _buildInfoRow('Temperature', '${project.lastTemperature!.toStringAsFixed(1)}°C'),
              const SizedBox(height: 8),
            ],
            _buildInfoRow('LED Mode', project.lastLedMode),
            const SizedBox(height: 8),
            _buildInfoRow('Last Update', _formatDateTime(project.lastUpdate)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LED Control',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildControlButton('ON', Icons.power, Colors.green),
                _buildControlButton('OFF', Icons.power_off, Colors.red),
                _buildControlButton('BLINK_SLOW', Icons.flash_on, Colors.orange),
                _buildControlButton('BLINK_MEDIUM', Icons.flash_on, Colors.amber),
                _buildControlButton('BLINK_FAST', Icons.flash_on, Colors.purple),
                _buildControlButton('SEQUENCE', Icons.timeline, Colors.blue),
                _buildControlButton('WAVE', Icons.waves, Colors.teal),
                _buildControlButton('ALL_ON', Icons.lightbulb, Colors.green.shade700),
                _buildControlButton('ALL_OFF', Icons.lightbulb_outline, Colors.grey),
                _buildControlButton('YELLOW_ON', Icons.circle, Colors.yellow.shade700),
                _buildControlButton('YELLOW_OFF', Icons.circle_outlined, Colors.yellow.shade900),
                _buildControlButton('GREEN_ON', Icons.circle, Colors.green.shade700),
                _buildControlButton('GREEN_OFF', Icons.circle_outlined, Colors.green.shade900),
                _buildControlButton('WHITE_ON', Icons.circle, Colors.blueGrey),
                _buildControlButton('WHITE_OFF', Icons.circle_outlined, Colors.blueGrey.shade700),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(String command, IconData icon, Color color) {
    return ElevatedButton.icon(
      onPressed: () => _sendMQTTCommand(command),
      icon: Icon(icon, size: 18),
      label: Text(command),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildAutoDiscoveryPanel() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text(
                  'Auto-Discovery',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Auto-Discovery menemukan IP perangkat ESP8266 secara otomatis tanpa input IP manual.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Gunakan saat pertama kali setup atau setelah mengganti WiFi (SSID/Password).\n'
              '• Aplikasi mencoba mDNS (esp8266-sensor.local) lalu scan jaringan lokal.\n'
              '• Setelah apply WiFi dan reboot, tunggu 10–20 detik lalu tekan Scan agar IP baru terdeteksi.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _startAutoDiscovery,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan for Devices'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiConfigPanel() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text(
                  'WiFi Configuration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'WiFi SSID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: const InputDecoration(
                labelText: 'WiFi Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() { _obscurePassword = !_obscurePassword; });
                },
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                label: Text(_obscurePassword ? 'Show password' : 'Hide password'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _applyWifiConfigToDevice,
                    icon: const Icon(Icons.send),
                    label: const Text('Apply to Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _disconnectWifiOnDevice,
                    icon: const Icon(Icons.wifi_off),
                    label: const Text('Disconnect WiFi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyWifiConfigToDevice() async {
    if (projects.isEmpty) return;
    String? deviceIP = projects.first.deviceIP;
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID dan Password tidak boleh kosong'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      // If IP not known, try to discover automatically
      if (deviceIP == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mencari perangkat...')),
        );
        deviceIP = await ESP8266Discovery.getESP8266IP();
        if (deviceIP == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device IP belum ditemukan. Coba Scan di Auto-Discovery.'), backgroundColor: Colors.orange),
          );
          return;
        }
        setState(() {
          projects.first.deviceIP = deviceIP;
          projects.first.isOnline = true;
        });
      }

      final uri = Uri.parse('http://$deviceIP/config');
      final res = await http
          .post(
            uri,
            headers: { 'Content-Type': 'application/json' },
            body: json.encode({
              'wifiSSID': ssid,
              'wifiPassword': password,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        // Update local project copy
        setState(() {
          projects.first.wifiSSID = ssid;
          projects.first.wifiPassword = password;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi config tersimpan. Device akan reboot...'), backgroundColor: Colors.green),
        );

        // Trigger reboot to apply WiFi
        try {
          await http.get(Uri.parse('http://$deviceIP/reboot')).timeout(const Duration(seconds: 3));
        } catch (_) {}

        // After reboot, wait and auto-scan for the device on new network
        await _waitForDeviceAfterReboot();
      } else if (res.statusCode == 422) {
        final body = res.body.isNotEmpty ? res.body : '{"reason":"Invalid"}';
        try {
          final msg = json.decode(body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal: ${msg['reason'] ?? 'SSID tidak ditemukan'}'), backgroundColor: Colors.orange),
          );
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SSID tidak ditemukan'), backgroundColor: Colors.orange),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan config (${res.statusCode})'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')), 
      );
    }
  }

  Future<void> _waitForDeviceAfterReboot() async {
    // Give the device time to reboot and join WiFi
    await Future.delayed(const Duration(seconds: 10));
    String? newIP;
    final int maxAttempts = 3;
    for (int i = 0; i < maxAttempts; i++) {
      newIP = await ESP8266Discovery.getESP8266IP();
      if (newIP != null) break;
      await Future.delayed(const Duration(seconds: 5));
    }

    if (newIP != null) {
      setState(() {
        projects.first.deviceIP = newIP;
        projects.first.isOnline = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Perangkat terdeteksi kembali di: $newIP'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perangkat belum terdeteksi. Coba tekan Scan di Auto-Discovery.'), backgroundColor: Colors.orange),
      );
    }
  }

  Future<void> _disconnectWifiOnDevice({bool clear = false}) async {
    if (projects.isEmpty || projects.first.deviceIP == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device IP belum diketahui. Gunakan Auto-Discovery.')),
      );
      return;
    }
    final ip = projects.first.deviceIP!;
    try {
      final uri = Uri.parse('http://$ip/wifi_disconnect${clear ? '?clear=1' : ''}');
      final res = await http.post(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        _safeSetState(() {
          _isDeviceOnline = false;
          projects.first.isOnline = false;
          if (clear) {
            projects.first.wifiSSID = '';
            projects.first.wifiPassword = '';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WiFi disconnected')), 
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal disconnect (${res.statusCode})'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')), 
      );
    }
  }

  void _sendMQTTCommand(String command) {
    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      _mqttClient?.publishMessage(
        'Anggra/sensor/led_control',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    }
  }

  void _showAddProjectDialog() {
    showDialog(
      context: context,
      builder: (context) => _AutoDiscoveryProjectDialog(
        onSave: (project) {
          setState(() {
            projects.add(project);
          });
        },
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _mqttSub?.cancel();
    _mqttClient?.disconnect();
    _slideController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    try { _udpSocket?.close(); } catch (_) {}
    super.dispose();
  }
}

// ========== Auto-Discovery Project Dialog ==========
class _AutoDiscoveryProjectDialog extends StatefulWidget {
  final Function(IoTProject) onSave;

  const _AutoDiscoveryProjectDialog({required this.onSave});

  @override
  State<_AutoDiscoveryProjectDialog> createState() => _AutoDiscoveryProjectDialogState();
}

class _AutoDiscoveryProjectDialogState extends State<_AutoDiscoveryProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _wifiSSIDController;
  late TextEditingController _wifiPasswordController;
  bool _isScanning = false;
  String? _discoveredIP;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'ESP8266 Device');
    _descriptionController = TextEditingController(text: 'Auto-discovered ESP8266 device');
    _wifiSSIDController = TextEditingController();
    _wifiPasswordController = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.radar, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  const Text(
                    'Add ESP8266 Device',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'Please enter device name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wifiSSIDController,
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value?.isEmpty == true ? 'Please enter WiFi SSID' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wifiPasswordController,
                decoration: const InputDecoration(
                  labelText: 'WiFi Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (value) => value?.isEmpty == true ? 'Please enter WiFi password' : null,
              ),
              const SizedBox(height: 20),
              if (_discoveredIP != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text('Device found at: $_discoveredIP'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isScanning ? null : _scanForDevices,
                      icon: _isScanning 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                      label: Text(_isScanning ? 'Scanning...' : 'Scan for Devices'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveProject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scanForDevices() async {
    setState(() {
      _isScanning = true;
    });

    String? discoveredIP = await ESP8266Discovery.getESP8266IP();
    
    setState(() {
      _isScanning = false;
      _discoveredIP = discoveredIP;
    });

    if (discoveredIP != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device found at: $discoveredIP'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No devices found. Make sure ESP8266 is connected to the same network.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _saveProject() {
    if (_formKey.currentState?.validate() == true) {
      final project = IoTProject(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        deviceIP: _discoveredIP,
        mqttHost: 'test.mosquitto.org', // Default MQTT host
        wifiSSID: _wifiSSIDController.text.trim(),
        wifiPassword: _wifiPasswordController.text.trim(),
        lastUpdate: DateTime.now(),
        isOnline: _discoveredIP != null,
      );

      widget.onSave(project);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _wifiSSIDController.dispose();
    _wifiPasswordController.dispose();
    super.dispose();
  }
}
