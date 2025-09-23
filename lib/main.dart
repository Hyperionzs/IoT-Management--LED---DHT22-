import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';

void main() {
  runApp(const IoTDashboardApp());
}

class IoTDashboardApp extends StatelessWidget {
  const IoTDashboardApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DashboardScreen(),
    );
  }
}

class IoTProject {
  String id;
  String name;
  String description;
  String deviceIP;
  String serverUrl;
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
    required this.deviceIP,
    required this.serverUrl,
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
    'serverUrl': serverUrl,
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
    serverUrl: json['serverUrl'],
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<IoTProject> projects = [];
  bool isLoading = false;
  late MqttServerClient _mqttClient;
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false; // inferred from MQTT data recency
  String _latestTemperatureText = '-';
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSub;
  String _lastTempRaw = '';
  int _lastTempSetStateMs = 0;
  Timer? _deviceOnlineTimer;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(fn);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _connectMQTT();
    _startDeviceOnlineWatcher();
  }

  void _loadProjects() {
    // Sample data - dalam implementasi nyata, load dari database/API
    setState(() {
      projects = [
        IoTProject(
          id: '001',
          name: 'ESP8266 DHT22 Sensor',
          description: 'Monitoring suhu dengan DHT22 dan kontrol 3 LED (Kuning, Hijau, Putih)',
          deviceIP: '192.168.1.100',
          serverUrl: 'http://10.210.102.180/display_data.php',
          wifiSSID: 'Sugooi',
          wifiPassword: 'Saturned',
          yellowLedStatus: false,
          greenLedStatus: false,
          whiteLedStatus: false,
          lastTemperature: 28.5,
          lastLedMode: 'OFF',
          lastUpdate: DateTime.now().subtract(const Duration(minutes: 5)),
          isOnline: true,
        ),
        IoTProject(
          id: '002',
          name: 'Backup ESP8266 Device',
          description: 'Backup device untuk monitoring IoT',
          deviceIP: '192.168.1.101',
          serverUrl: 'http://10.210.102.180/display_data.php',
          wifiSSID: 'Sugooi',
          wifiPassword: 'Saturned',
          yellowLedStatus: false,
          greenLedStatus: false,
          whiteLedStatus: false,
          lastLedMode: 'OFF',
          lastUpdate: DateTime.now().subtract(const Duration(hours: 2)),
          isOnline: false,
        ),
      ];
    });
  }

// ... existing code ...

  Future<void> _connectMQTT() async {
    try {
      // Create unique client ID
      final clientId = 'flutter_monitoring_iot_${DateTime.now().millisecondsSinceEpoch}';
      
      // Initialize MQTT client
      final String brokerHost = projects.isNotEmpty
          ? _extractHostFromUrlOrIp(projects.first.serverUrl, fallback: 'test.mosquitto.org')
          : 'test.mosquitto.org';
      _mqttClient = MqttServerClient(brokerHost, clientId);
      
      // Configure client settings
      _mqttClient.logging(on: false);
      _mqttClient.keepAlivePeriod = 30;
      _mqttClient.port = 1883;
      _mqttClient.autoReconnect = true;
      _mqttClient.connectTimeoutPeriod = 10000; // 10 seconds timeout
      
      // Set connection callbacks
      _mqttClient.onConnected = () {
        print('MQTT Connected successfully');
        _safeSetState(() {
          _isMqttConnected = true;
        });
      };
      
      _mqttClient.onDisconnected = () {
        print('MQTT Disconnected');
        _safeSetState(() {
          _isMqttConnected = false;
          _isDeviceOnline = false;
        });
      };
      
      _mqttClient.onAutoReconnect = () {
        print('MQTT Auto reconnecting...');
      };

      // Connect to broker
      print('Connecting to MQTT broker...');
      final connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .withWillTopic('willtopic')
          .withWillMessage('My Will message')
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      
      _mqttClient.connectionMessage = connectionMessage;
      
      final connectionStatus = await _mqttClient.connect();
      
      if (connectionStatus?.state == MqttConnectionState.connected) {
        print('MQTT Connected successfully');
        _safeSetState(() {
          _isMqttConnected = true;
        });
        
        // Subscribe to temperature topic
        _mqttClient.subscribe('Anggra/sensor/suhu', MqttQos.atMostOnce);
        print('Subscribed to Anggra/sensor/suhu');
        
        // Listen for messages
        _mqttSub = _mqttClient.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          if (c == null || c.isEmpty) return;
          
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message).trim();
          final topic = c[0].topic;
          
          print('Received message on topic: $topic');
          print('Payload: $payload');
          
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (payload == _lastTempRaw && nowMs - _lastTempSetStateMs < 500) {
            return;
          }
          
          _lastTempRaw = payload;
          _lastTempSetStateMs = nowMs;
          _markDeviceSeenNow();
          
          if (!mounted) return;
          
          // Parse JSON payload from ESP8266
          String displayText = payload;
          try {
            final jsonData = jsonDecode(payload);
            if (jsonData is Map<String, dynamic>) {
              final temperature = jsonData['Suhu'] ?? 'N/A';
              final ledStatus = jsonData['Status LED'] ?? 'N/A';
              final time = jsonData['Waktu'] ?? 'N/A';
              displayText = 'Suhu: $temperature, LED: $ledStatus, Waktu: $time';
              
              // Update project data if temperature is available
              if (temperature != 'N/A' && temperature.toString().contains('°C')) {
                final tempValue = double.tryParse(temperature.toString().replaceAll(' °C', ''));
                if (tempValue != null && projects.isNotEmpty) {
                  _safeSetState(() {
                    projects[0].lastTemperature = tempValue;
                    projects[0].lastUpdate = DateTime.now();
                  });
                }
              }
            }
          } catch (e) {
            print('JSON parsing error: $e');
            // If JSON parsing fails, use raw payload
            displayText = payload;
          }
          
          if (_latestTemperatureText != displayText) {
            _safeSetState(() {
              _latestTemperatureText = displayText;
            });
          }
        });
        
      } else {
        print('MQTT Connection failed: ${connectionStatus?.state}');
        _safeSetState(() {
          _isMqttConnected = false;
        });
      }
      
    } catch (e) {
      print('MQTT Connection error: $e');
      _safeSetState(() {
        _isMqttConnected = false;
        _isDeviceOnline = false;
      });
      
      // Try to reconnect after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _connectMQTT();
        }
      });
    }
  }

  void _startDeviceOnlineWatcher() {
    _deviceOnlineTimer?.cancel();
    _deviceOnlineTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // If last message older than 15s, mark offline
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final bool consideredOnline = (nowMs - _lastTempSetStateMs) < 15000 && _isMqttConnected;
      if (consideredOnline != _isDeviceOnline) {
        _safeSetState(() {
          _isDeviceOnline = consideredOnline;
          if (projects.isNotEmpty) {
            projects[0].isOnline = _isDeviceOnline;
          }
        });
      }
    });
  }

  void _markDeviceSeenNow() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if ((nowMs - _lastTempSetStateMs) > 0) {
      // already updated _lastTempSetStateMs in listener
    }
    if (!_isDeviceOnline) {
      _safeSetState(() {
        _isDeviceOnline = true;
        if (projects.isNotEmpty) {
          projects[0].isOnline = true;
        }
      });
    }
  }

  String _extractHostFromUrlOrIp(String value, {required String fallback}) {
    try {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final uri = Uri.parse(value);
        return uri.host.isNotEmpty ? uri.host : fallback;
      }
      // assume raw host/ip
      return value.isNotEmpty ? value : fallback;
    } catch (_) {
      return fallback;
    }
  }

  void _publishLedCommand(String command) {
    if (!_isMqttConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MQTT belum terhubung')),
      );
      return;
    }
    
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      _mqttClient.publishMessage('Anggra/sensor/led_control', MqttQos.atMostOnce, builder.payload!);
      print('Published command: $command');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Perintah terkirim: $command')),
      );
    } catch (e) {
      print('Publish error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim perintah: $e')),
      );
    }
  }

// ... existing code ...

  @override
  void dispose() {
    _mqttSub?.cancel();
    _deviceOnlineTimer?.cancel();
    if (_mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
      _mqttClient.disconnect();
    }
    super.dispose();
  }

  Future<void> _toggleLED(IoTProject project, String ledType, bool newState) async {
    setState(() {
      isLoading = true;
    });

    try {
      // Simulasi HTTP request ke ESP8266
      final response = await http.post(
        Uri.parse('http://${project.deviceIP}/control'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'led': ledType,
          'state': newState,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          if (ledType == 'yellow') {
            project.yellowLedStatus = newState;
          } else if (ledType == 'green') {
            project.greenLedStatus = newState;
          } else if (ledType == 'white') {
            project.whiteLedStatus = newState;
          }
          project.lastUpdate = DateTime.now();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('LED $ledType berhasil ${newState ? "dinyalakan" : "dimatikan"}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengontrol LED: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _updateConfiguration(IoTProject project) async {
    setState(() {
      isLoading = true;
    });

    try {
      // Kirim konfigurasi baru ke ESP32
      final response = await http.post(
        Uri.parse('http://${project.deviceIP}/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'wifiSSID': project.wifiSSID,
          'wifiPassword': project.wifiPassword,
          'serverUrl': project.serverUrl,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konfigurasi berhasil diperbarui'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memperbarui konfigurasi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT Dashboard'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProjects,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return ProjectCard(
                  project: project,
                  onLEDToggle: _toggleLED,
                  onConfigUpdate: _updateConfiguration,
                  onEdit: () => _showProjectDialog(project),
                temperatureText: _latestTemperatureText,
                isMqttConnected: _isMqttConnected,
                onSendLedCommand: _publishLedCommand,
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProjectDialog(null),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showProjectDialog(IoTProject? project) {
    showDialog(
      context: context,
      builder: (context) => ProjectDialog(
        project: project,
        onSave: (newProject) {
          setState(() {
            if (project == null) {
              projects.add(newProject);
            } else {
              final index = projects.indexWhere((p) => p.id == project.id);
              if (index != -1) {
                projects[index] = newProject;
              }
            }
          });
        },
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  final IoTProject project;
  final Function(IoTProject, String, bool) onLEDToggle;
  final Function(IoTProject) onConfigUpdate;
  final VoidCallback onEdit;
  final String temperatureText;
  final bool isMqttConnected;
  final void Function(String) onSendLedCommand;
  
  // Allow external online indicator via project.isOnline

  const ProjectCard({
    Key? key,
    required this.project,
    required this.onLEDToggle,
    required this.onConfigUpdate,
    required this.onEdit,
    required this.temperatureText,
    required this.isMqttConnected,
    required this.onSendLedCommand,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                      Text(
                        project.description,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Chip(
                      avatar: CircleAvatar(
                        backgroundColor: project.isOnline ? Colors.green : Colors.red,
                        radius: 6,
                      ),
                      label: Text(project.isOnline ? 'Online' : 'Offline'),
                      backgroundColor: project.isOnline ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: onEdit,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Device Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.device_hub, size: 20),
                  const SizedBox(width: 8),
                  Text('IP: ${project.deviceIP}'),
                  const Spacer(),
                  Text(
                    'Update: ${_formatDateTime(project.lastUpdate)}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            // Temperature from MQTT and DHT22
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.thermostat, size: 20, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Suhu DHT22 (MQTT): $temperatureText',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isMqttConnected ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(isMqttConnected ? Icons.cloud_done : Icons.cloud_off, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              isMqttConnected ? 'MQTT ON' : 'MQTT OFF',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (project.lastTemperature != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.sensors, size: 16, color: Colors.orange.shade600),
                        const SizedBox(width: 8),
                        Text(
                          'Suhu Terakhir: ${project.lastTemperature!.toStringAsFixed(1)}°C',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            // LED Controls
            const Text(
              'Kontrol LED ESP8266',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            
            // Basic Controls
            const Text(
              'Kontrol Dasar:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => onSendLedCommand('ON'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('ON'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white),
                  child: const Text('OFF'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('ALL_ON'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                  child: const Text('ALL ON'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('ALL_OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('ALL OFF'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Blink Controls
            const Text(
              'Kontrol Blink:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => onSendLedCommand('BLINK_SLOW'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.white),
                  child: const Text('BLINK SLOW'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('BLINK_MEDIUM'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  child: const Text('BLINK MEDIUM'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('BLINK_FAST'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('BLINK FAST'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Individual LED Controls
            const Text(
              'Kontrol Individual:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => onSendLedCommand('YELLOW_ON'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow.shade700, foregroundColor: Colors.white),
                  child: const Text('YELLOW ON'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('YELLOW_OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade600, foregroundColor: Colors.white),
                  child: const Text('YELLOW OFF'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('GREEN_ON'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                  child: const Text('GREEN ON'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('GREEN_OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade600, foregroundColor: Colors.white),
                  child: const Text('GREEN OFF'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('WHITE_ON'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
                  child: const Text('WHITE ON'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('WHITE_OFF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade600, foregroundColor: Colors.white),
                  child: const Text('WHITE OFF'),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Advanced Controls
            const Text(
              'Kontrol Lanjutan:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => onSendLedCommand('SEQUENCE'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                  child: const Text('SEQUENCE'),
                ),
                ElevatedButton(
                  onPressed: () => onSendLedCommand('WAVE'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  child: const Text('WAVE'),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Config Update Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => onConfigUpdate(project),
                icon: const Icon(Icons.upload),
                label: const Text('Update Konfigurasi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLEDControl(String label, bool isOn, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOn ? color.withOpacity(0.2) : Colors.grey.shade100,
          border: Border.all(
            color: isOn ? color : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.lightbulb,
              color: isOn ? color : Colors.grey,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isOn ? color : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOn ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isOn ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m yang lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h yang lalu';
    } else {
      return '${difference.inDays}d yang lalu';
    }
  }
}

class ProjectDialog extends StatefulWidget {
  final IoTProject? project;
  final Function(IoTProject) onSave;

  const ProjectDialog({
    Key? key,
    this.project,
    required this.onSave,
  }) : super(key: key);

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _deviceIPController;
  late TextEditingController _serverUrlController;
  late TextEditingController _wifiSSIDController;
  late TextEditingController _wifiPasswordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _nameController = TextEditingController(text: project?.name ?? '');
    _descriptionController = TextEditingController(text: project?.description ?? '');
    _deviceIPController = TextEditingController(text: project?.deviceIP ?? '');
    _serverUrlController = TextEditingController(text: project?.serverUrl ?? '');
    _wifiSSIDController = TextEditingController(text: project?.wifiSSID ?? '');
    _wifiPasswordController = TextEditingController(text: project?.wifiPassword ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.project == null ? 'Tambah Project Baru' : 'Edit Project'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Project',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty == true ? 'Nama project wajib diisi' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _deviceIPController,
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    hintText: 'contoh: test.mosquitto.org atau 10.210.102.180',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty == true ? 'Host wajib diisi' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'contoh: http://10.210.102.180/display_data.php',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _wifiSSIDController,
                  decoration: const InputDecoration(
                    labelText: 'WiFi SSID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _wifiPasswordController,
                  decoration: InputDecoration(
                    labelText: 'WiFi Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _saveProject,
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  void _saveProject() {
    if (_formKey.currentState?.validate() == true) {
      final project = IoTProject(
        id: widget.project?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        deviceIP: _deviceIPController.text,
        serverUrl: _serverUrlController.text,
        wifiSSID: _wifiSSIDController.text,
        wifiPassword: _wifiPasswordController.text,
        yellowLedStatus: widget.project?.yellowLedStatus ?? false,
        greenLedStatus: widget.project?.greenLedStatus ?? false,
        whiteLedStatus: widget.project?.whiteLedStatus ?? false,
        lastTemperature: widget.project?.lastTemperature,
        lastLedMode: widget.project?.lastLedMode ?? "OFF",
        lastUpdate: DateTime.now(),
        isOnline: widget.project?.isOnline ?? false,
      );

      widget.onSave(project);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _deviceIPController.dispose();
    _serverUrlController.dispose();
    _wifiSSIDController.dispose();
    _wifiPasswordController.dispose();
    super.dispose();
  }
}