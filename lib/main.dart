import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
      title: 'Smart IoT Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// Animated Widget for better UX
class AnimatedCounter extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const AnimatedCounter({
    Key? key,
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class PulsingDot extends StatefulWidget {
  final Color color;
  final bool isActive;

  const PulsingDot({Key? key, required this.color, required this.isActive}) : super(key: key);

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = Tween(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_animation.value),
            shape: BoxShape.circle,
            boxShadow: widget.isActive ? [
              BoxShadow(
                color: widget.color.withOpacity(0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ] : null,
          ),
        );
      },
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double? height;
  final double? width;
  final EdgeInsets? padding;

  const GlassContainer({
    Key? key,
    required this.child,
    this.color,
    this.height,
    this.width,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WifiConfigSection extends StatefulWidget {
  final IoTProject project;
  final Future<void> Function(IoTProject, String, String) onSetWifi;

  const _WifiConfigSection({required this.project, required this.onSetWifi});

  @override
  State<_WifiConfigSection> createState() => _WifiConfigSectionState();
}

class _WifiConfigSectionState extends State<_WifiConfigSection> with TickerProviderStateMixin {
  late TextEditingController _ssidCtrl;
  late TextEditingController _passCtrl;
  bool _obscure = true;
  bool _isExpanded = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _ssidCtrl = TextEditingController(text: widget.project.wifiSSID);
    _passCtrl = TextEditingController(text: widget.project.wifiPassword);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      color: const Color(0xFF6366F1).withOpacity(0.05),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
                if (_isExpanded) {
                  _animationController.forward();
                } else {
                  _animationController.reverse();
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.wifi, color: Color(0xFF6366F1), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Konfigurasi WiFi',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: _isExpanded ? _buildConfigForm() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigForm() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _ssidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SSID WiFi',
                    prefixIcon: Icon(Icons.router),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.onSetWifi(widget.project, _ssidCtrl.text.trim(), _passCtrl.text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemperatureDisplay extends StatelessWidget {
  final String text;
  final bool isMqttConnected;
  final double? lastTemperature;
  final DateTime lastUpdate;

  const _TemperatureDisplay({
    required this.text,
    required this.isMqttConnected,
    this.lastTemperature,
    required this.lastUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6B35).withOpacity(0.1),
            const Color(0xFFFF8A50).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.thermostat, color: Color(0xFFFF6B35), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sensor DHT22',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isMqttConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulsingDot(
                        color: Colors.white,
                        isActive: isMqttConnected,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMqttConnected ? 'Online' : 'Offline',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (lastTemperature != null)
            Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sensors, size: 18, color: Color(0xFFFF6B35)),
                  const SizedBox(width: 8),
                  Text(
                    'Terakhir: ${lastTemperature!.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDateTime(lastUpdate),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}j lalu';
    } else {
      return '${difference.inDays}h lalu';
    }
  }
}

class IoTProject {
  String id;
  String name;
  String description;
  String deviceIP;
  String mqttHost;
  String serverUrl;
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
    required this.deviceIP,
    required this.mqttHost,
    required this.serverUrl,
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
    mqttHost: json['mqttHost'] ?? 'test.mosquitto.org',
    serverUrl: json['serverUrl'],
    mqttPort: (json['mqttPort'] is String)
        ? int.tryParse(json['mqttPort']) ?? 1883
        : (json['mqttPort'] ?? 1883),
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

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  List<IoTProject> projects = [];
  bool isLoading = false;
  late MqttServerClient _mqttClient;
  bool _isMqttConnected = false;
  bool _isDeviceOnline = false;
  bool _isRefreshingMqtt = false;
  String _latestTemperatureText = 'Menunggu data sensor...';
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSub;
  String _lastTempRaw = '';
  int _lastTempSetStateMs = 0;
  Timer? _deviceOnlineTimer;
  Timer? _refreshTimeoutTimer;

  late AnimationController _fadeController;
  late AnimationController _slideController;

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
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _loadProjects();
    _connectMQTT();
    _startDeviceOnlineWatcher();
    
    _fadeController.forward();
    _slideController.forward();
  }

  void _loadProjects() {
    setState(() {
      projects = [
        IoTProject(
          id: '001',
          name: 'ESP8266 Smart Sensor',
          description: 'Monitoring suhu DHT22 dengan kontrol LED multi-mode',
          deviceIP: '10.238.122.200',
          mqttHost: 'test.mosquitto.org',
          serverUrl: 'http://10.238.122.180/display_data.php',
          mqttPort: 1883,
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
      ];
    });
  }

  Future<void> _connectMQTT() async {
    try {
      final clientId = 'smart_iot_dashboard_${DateTime.now().millisecondsSinceEpoch}';
      
      String brokerHost = 'test.mosquitto.org';
      if (projects.isNotEmpty) {
        final p = projects.first;
        brokerHost = p.mqttHost.isNotEmpty
            ? p.mqttHost
            : (p.deviceIP.isNotEmpty
                ? p.deviceIP
                : _extractHostFromUrlOrIp(p.serverUrl, fallback: 'test.mosquitto.org'));
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
      MqttClientConnectionStatus? connectionStatus = await _mqttClient.connect();

      if (connectionStatus?.state != MqttConnectionState.connected) {
        try {
          await _mqttSub?.cancel();
          if (_mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
            _mqttClient.disconnect();
          }
          _mqttClient = buildClient(useWebSocket: true, port: 8081);
          connectionStatus = await _mqttClient.connect();
        } catch (e) {
          print('WebSocket connect error: $e');
        }
      }

      if (connectionStatus?.state == MqttConnectionState.connected) {
        _safeSetState(() {
          _isMqttConnected = true;
        });
        
        _mqttClient.subscribe('Anggra/sensor/suhu', MqttQos.atMostOnce);
        
        _mqttSub = _mqttClient.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          if (c == null || c.isEmpty) return;
          
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message).trim();
          
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (payload == _lastTempRaw && nowMs - _lastTempSetStateMs < 500) {
            return;
          }
          
          _lastTempRaw = payload;
          _lastTempSetStateMs = nowMs;
          _markDeviceSeenNow();
          
          if (!mounted) return;
          
          String displayText = payload;
          try {
            final jsonData = jsonDecode(payload);
            if (jsonData is Map<String, dynamic>) {
              final double? temperature = (jsonData['temperature'] is num)
                  ? (jsonData['temperature'] as num).toDouble()
                  : double.tryParse('${jsonData['temperature']}');
              final String ledStatus = '${jsonData['ledStatus'] ?? 'N/A'}';
              final String mode = '${jsonData['mode'] ?? 'N/A'}';
              final String time = '${jsonData['timestamp'] ?? 'N/A'}';
              
              displayText = 'Suhu: ${temperature?.toStringAsFixed(1) ?? 'N/A'}°C | LED: $ledStatus | Mode: $mode';

              if (temperature != null && projects.isNotEmpty) {
                _safeSetState(() {
                  projects[0].lastTemperature = temperature;
                  projects[0].lastUpdate = DateTime.now();
                });
              }
            }
          } catch (e) {
            displayText = payload;
          }
          
          if (_latestTemperatureText != displayText) {
            _safeSetState(() {
              _latestTemperatureText = displayText;
            });
          }
        });
        
      } else {
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
      return value.isNotEmpty ? value : fallback;
    } catch (_) {
      return fallback;
    }
  }

  void _publishLedCommand(String command) {
    if (!_isMqttConnected) {
      _showSnackBar('MQTT belum terhubung', isError: true);
      return;
    }
    
    try {
      HapticFeedback.lightImpact();
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      _mqttClient.publishMessage('Anggra/sensor/led_control', MqttQos.atMostOnce, builder.payload!);
      
      _showSnackBar('Perintah "$command" berhasil dikirim', isError: false);
    } catch (e) {
      _showSnackBar('Gagal mengirim perintah: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  void dispose() {
    _mqttSub?.cancel();
    _deviceOnlineTimer?.cancel();
    _refreshTimeoutTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    if (_mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
      _mqttClient.disconnect();
    }
    super.dispose();
  }

  Future<void> _updateConfiguration(IoTProject project) async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://${project.deviceIP}/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'wifiSSID': project.wifiSSID,
          'wifiPassword': project.wifiPassword,
          'serverUrl': project.serverUrl,
          'mqttHost': project.mqttHost.isNotEmpty ? project.mqttHost : project.deviceIP,
          'mqttPort': project.mqttPort,
          'mqttTopicTemp': 'Anggra/sensor/suhu',
          'mqttTopicLedCtrl': 'Anggra/sensor/led_control',
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar('Konfigurasi berhasil diperbarui', isError: false);
      } else {
        _showSnackBar('Gagal memperbarui konfigurasi: HTTP ${response.statusCode}', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _setWifiConfig(IoTProject project, String ssid, String password) async {
    if (ssid.isEmpty) {
      _showSnackBar('SSID tidak boleh kosong', isError: true);
      return;
    }
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://${project.deviceIP}/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'wifiSSID': ssid,
          'wifiPassword': password,
        }),
      );

      if (response.statusCode == 200) {
        _safeSetState(() {
          project.wifiSSID = ssid;
          project.wifiPassword = password;
        });
        _showSnackBar('WiFi tersimpan. Restart perangkat untuk menerapkan.', isError: false);
      } else {
        _showSnackBar('Gagal set WiFi: HTTP ${response.statusCode}', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error WiFi: $e', isError: true);
    } finally {
      setState(() {
        isLoading = false;
      });
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
                                FadeTransition(
                                  opacity: _fadeController,
                                  child: const Text(
                                    'Smart IoT Dashboard',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).animate(_slideController),
                                  child: Text(
                                    'Monitor dan kontrol perangkat IoT Anda',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.9),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (_isRefreshingMqtt)
                                      const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                    Icon(
                                      _isMqttConnected ? Icons.cloud_done : Icons.cloud_off,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ],
                                ),
                                onPressed: _isRefreshingMqtt ? null : (_isMqttConnected ? _disconnectMQTT : _refreshMqttStatus),
                                tooltip: _isMqttConnected ? 'Putuskan MQTT' : 'Hubungkan MQTT',
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
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (isLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (projects.isEmpty) {
                    return Center(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.devices_other,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Belum ada perangkat',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tambahkan perangkat IoT pertama Anda',
                            style: TextStyle(
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final project = projects[index];
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, 0.3 + (index * 0.1)),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _slideController,
                      curve: Curves.easeOutCubic,
                    )),
                    child: FadeTransition(
                      opacity: _fadeController,
                      child: EnhancedProjectCard(
                        project: project,
                        onConfigUpdate: _updateConfiguration,
                        onEdit: () => _showProjectDialog(project),
                        temperatureText: _latestTemperatureText,
                        isMqttConnected: _isMqttConnected,
                        onSendLedCommand: _publishLedCommand,
                        onSetWifi: _setWifiConfig,
                      ),
                    ),
                  );
                },
                childCount: projects.isEmpty ? 1 : projects.length,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fadeController,
        child: FloatingActionButton.extended(
          onPressed: () => _showProjectDialog(null),
          backgroundColor: const Color(0xFF667EEA),
          elevation: 4,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Tambah Perangkat',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _showProjectDialog(IoTProject? project) {
    showDialog(
      context: context,
      builder: (context) => EnhancedProjectDialog(
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

  Future<void> _refreshMqttStatus() async {
    if (_isRefreshingMqtt) return;
    _safeSetState(() {
      _isRefreshingMqtt = true;
    });
    
    _refreshTimeoutTimer?.cancel();
    _refreshTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_isRefreshingMqtt && !_isMqttConnected) {
        _safeSetState(() {
          _isRefreshingMqtt = false;
        });
        _showSnackBar('Koneksi MQTT timeout', isError: true);
      }
    });
    
    try {
      final alreadyConnected = _isMqttConnected && _mqttClient.connectionStatus?.state == MqttConnectionState.connected;
      if (alreadyConnected) {
        _refreshTimeoutTimer?.cancel();
        _showSnackBar('MQTT sudah terhubung', isError: false);
        return;
      }

      try { await _mqttSub?.cancel(); } catch (_) {}
      if (_mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
        _mqttClient.disconnect();
      }
      await _connectMQTT();

      _refreshTimeoutTimer?.cancel();
      
      if (!_isMqttConnected) {
        _showSnackBar('MQTT tidak terhubung', isError: true);
      }
    } finally {
      _safeSetState(() {
        _isRefreshingMqtt = false;
      });
    }
  }

  void _disconnectMQTT() {
    try {
      _mqttSub?.cancel();
    } catch (_) {}
    if (_mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
      _mqttClient.disconnect();
    }
    _safeSetState(() {
      _isMqttConnected = false;
      _isDeviceOnline = false;
    });
  }
}

class EnhancedProjectCard extends StatefulWidget {
  final IoTProject project;
  final Function(IoTProject) onConfigUpdate;
  final VoidCallback onEdit;
  final String temperatureText;
  final bool isMqttConnected;
  final void Function(String) onSendLedCommand;
  final Future<void> Function(IoTProject, String, String) onSetWifi;

  const EnhancedProjectCard({
    Key? key,
    required this.project,
    required this.onConfigUpdate,
    required this.onEdit,
    required this.temperatureText,
    required this.isMqttConnected,
    required this.onSendLedCommand,
    required this.onSetWifi,
  }) : super(key: key);

  @override
  State<EnhancedProjectCard> createState() => _EnhancedProjectCardState();
}

class _EnhancedProjectCardState extends State<EnhancedProjectCard> with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late AnimationController _buttonController;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 8,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              Colors.grey[50]!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildDeviceInfo(),
              const SizedBox(height: 16),
              _WifiConfigSection(project: widget.project, onSetWifi: widget.onSetWifi),
              const SizedBox(height: 16),
              _TemperatureDisplay(
                text: widget.temperatureText,
                isMqttConnected: widget.isMqttConnected,
                lastTemperature: widget.project.lastTemperature,
                lastUpdate: widget.project.lastUpdate,
              ),
              const SizedBox(height: 20),
              _buildControlsHeader(),
              const SizedBox(height: 16),
              _buildControls(),
              const SizedBox(height: 20),
              _buildConfigButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.memory, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.project.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.project.description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.project.isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PulsingDot(
                    color: Colors.white,
                    isActive: widget.project.isOnline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.project.isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: widget.onEdit,
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[100],
                foregroundColor: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeviceInfo() {
    return GlassContainer(
      color: Colors.blue[50]!.withOpacity(0.5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.router, color: Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Informasi Perangkat',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'IP: ${widget.project.deviceIP}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatDateTime(widget.project.lastUpdate),
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFBF00).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.lightbulb_outline, color: Color(0xFFFFBF00), size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Kontrol LED Smart',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
              if (_isExpanded) {
                _expandController.forward();
              } else {
                _expandController.reverse();
              }
            });
          },
          icon: AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            child: const Icon(Icons.keyboard_arrow_down),
          ),
          label: Text(_isExpanded ? 'Sembunyikan' : 'Tampilkan'),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: _isExpanded ? _buildExpandedControls() : _buildBasicControls(),
    );
  }

  Widget _buildBasicControls() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildControlButton('ON', 'Aktifkan', const Color(0xFF10B981), Icons.power_settings_new),
        _buildControlButton('OFF', 'Matikan', const Color(0xFFEF4444), Icons.power_off),
        _buildControlButton('ALL_ON', 'Semua Hidup', const Color(0xFF3B82F6), Icons.lightbulb),
        _buildControlButton('ALL_OFF', 'Semua Mati', Colors.grey[600]!, Icons.lightbulb_outline),
      ],
    );
  }

  Widget _buildExpandedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBasicControls(),
        const SizedBox(height: 16),
        _buildSectionTitle('Mode Blink', Icons.flash_on),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildControlButton('BLINK_SLOW', 'Lambat', const Color(0xFFFBBF24), Icons.speed),
            _buildControlButton('BLINK_MEDIUM', 'Sedang', const Color(0xFFEA580C), Icons.speed),
            _buildControlButton('BLINK_FAST', 'Cepat', const Color(0xFFDC2626), Icons.speed),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Kontrol Individual', Icons.tune),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildControlButton('YELLOW_ON', 'Kuning ON', const Color(0xFFEAB308), Icons.circle),
            _buildControlButton('YELLOW_OFF', 'Kuning OFF', Colors.grey[400]!, Icons.circle_outlined),
            _buildControlButton('GREEN_ON', 'Hijau ON', const Color(0xFF22C55E), Icons.circle),
            _buildControlButton('GREEN_OFF', 'Hijau OFF', Colors.grey[400]!, Icons.circle_outlined),
            _buildControlButton('WHITE_ON', 'Putih ON', Colors.grey[800]!, Icons.circle),
            _buildControlButton('WHITE_OFF', 'Putih OFF', Colors.grey[400]!, Icons.circle_outlined),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Mode Lanjutan', Icons.auto_awesome),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildControlButton('SEQUENCE', 'Sekuensial', const Color(0xFF8B5CF6), Icons.shuffle),
            _buildControlButton('WAVE', 'Gelombang', const Color(0xFF06B6D4), Icons.water),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButton(String command, String label, Color color, IconData icon) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      shadowColor: color.withOpacity(0.3),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onSendLedCommand(command);
          
          _buttonController.forward().then((_) {
            _buttonController.reverse();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedScale(
          scale: 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => widget.onConfigUpdate(widget.project),
        icon: const Icon(Icons.upload_outlined),
        label: const Text('Update Konfigurasi Perangkat'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF667EEA),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
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
      return '${difference.inMinutes}m lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}j lalu';
    } else {
      return '${difference.inDays}h lalu';
    }
  }
}

class EnhancedProjectDialog extends StatefulWidget {
  final IoTProject? project;
  final Function(IoTProject) onSave;

  const EnhancedProjectDialog({
    Key? key,
    this.project,
    required this.onSave,
  }) : super(key: key);

  @override
  State<EnhancedProjectDialog> createState() => _EnhancedProjectDialogState();
}

class _EnhancedProjectDialogState extends State<EnhancedProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _deviceIPController;
  late TextEditingController _mqttHostController;
  late TextEditingController _mqttPortController;
  late TextEditingController _serverUrlController;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _nameController = TextEditingController(text: project?.name ?? '');
    _descriptionController = TextEditingController(text: project?.description ?? '');
    _deviceIPController = TextEditingController(text: project?.deviceIP ?? '');
    _mqttHostController = TextEditingController(text: project?.mqttHost ?? 'test.mosquitto.org');
    _mqttPortController = TextEditingController(text: (project?.mqttPort ?? 1883).toString());
    _serverUrlController = TextEditingController(text: project?.serverUrl ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.grey[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    widget.project == null ? 'Tambah Perangkat Baru' : 'Edit Perangkat',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormField(
                        controller: _nameController,
                        label: 'Nama Perangkat',
                        icon: Icons.device_hub,
                        validator: (value) => value?.isEmpty == true ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _descriptionController,
                        label: 'Deskripsi',
                        icon: Icons.description,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _deviceIPController,
                        label: 'IP Address / Host',
                        icon: Icons.router,
                        hint: 'contoh: 192.168.1.100 atau domain.com',
                        validator: (value) => value?.isEmpty == true ? 'IP/Host wajib diisi' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _mqttHostController,
                        label: 'MQTT Broker Host',
                        icon: Icons.cloud,
                        hint: 'contoh: test.mosquitto.org',
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _mqttPortController,
                        label: 'MQTT Port',
                        icon: Icons.settings_ethernet,
                        hint: 'default: 1883',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Port wajib diisi';
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) return 'Port tidak valid (1-65535)';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildFormField(
                        controller: _serverUrlController,
                        label: 'Server URL (Optional)',
                        icon: Icons.link,
                        hint: 'contoh: http://server.com/api/data',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saveProject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF667EEA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Simpan Perangkat',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      validator: validator,
    );
  }

  void _saveProject() {
    if (_formKey.currentState?.validate() == true) {
      final project = IoTProject(
        id: widget.project?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        deviceIP: _deviceIPController.text.trim(),
        mqttHost: _mqttHostController.text.trim().isNotEmpty ? _mqttHostController.text.trim() : 'test.mosquitto.org',
        serverUrl: _serverUrlController.text.trim(),
        mqttPort: int.tryParse(_mqttPortController.text) ?? 1883,
        wifiSSID: widget.project?.wifiSSID ?? '',
        wifiPassword: widget.project?.wifiPassword ?? '',
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
      
      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 8),
              Text(widget.project == null ? 'Perangkat berhasil ditambahkan' : 'Perangkat berhasil diperbarui'),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _deviceIPController.dispose();
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}