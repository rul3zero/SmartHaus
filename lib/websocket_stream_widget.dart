import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WebSocketStreamWidget extends StatefulWidget {
  final String wsUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, dynamic, dynamic)? error;
  final Function(Uint8List?)? onFrameUpdate;
  final Function(bool)? onConnectionStatusChanged;

  const WebSocketStreamWidget({
    super.key,
    required this.wsUrl,
    this.fit = BoxFit.contain,
    this.error,
    this.onFrameUpdate,
    this.onConnectionStatusChanged,
  });

  @override
  State<WebSocketStreamWidget> createState() => _WebSocketStreamWidgetState();
}

class _WebSocketStreamWidgetState extends State<WebSocketStreamWidget> {
  WebSocketChannel? _channel;
  Uint8List? _imageBytes;
  bool _connected = false;
  String _errorMessage = '';
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _disconnectWebSocket();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(WebSocketStreamWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wsUrl != widget.wsUrl) {
      _disconnectWebSocket();
      _connectWebSocket();
    }
  }

  void _connectWebSocket() {
    try {
      _disconnectWebSocket(); // Ensure any existing connection is closed

      debugPrint('Connecting to WebSocket: ${widget.wsUrl}');

      _channel = WebSocketChannel.connect(Uri.parse(widget.wsUrl));

      _channel!.stream.listen(
        (dynamic message) {
          // Reset reconnect counter on successful data
          _reconnectAttempts = 0;

          if (message is List<int>) {
            // Handle binary data (JPEG frame)
            setState(() {
              _imageBytes = Uint8List.fromList(message);
              _connected = true;
            });
            // Notify parent widget of frame update and connection status
            widget.onFrameUpdate?.call(_imageBytes);
            widget.onConnectionStatusChanged?.call(true);
          } else {
            // Handle text messages (e.g., status updates)
            debugPrint('WebSocket text message: $message');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          setState(() {
            _connected = false;
            _errorMessage = 'Connection error: $error';
          });
          widget.onConnectionStatusChanged?.call(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          setState(() {
            _connected = false;
          });
          widget.onConnectionStatusChanged?.call(false);
          _scheduleReconnect();
        },
      );

      // Send a message to start streaming
      _channel!.sink.add('stream_start');
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      setState(() {
        _connected = false;
        _errorMessage = 'Failed to connect: $e';
      });
      widget.onConnectionStatusChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void _disconnectWebSocket() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempts < maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = Duration(
        seconds: _reconnectAttempts * 2,
      ); // Exponential backoff

      debugPrint(
        'Scheduling reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s',
      );

      _reconnectTimer = Timer(delay, () {
        if (mounted) {
          _connectWebSocket();
        }
      });
    } else {
      debugPrint('Max reconnect attempts reached');
      setState(() {
        _errorMessage =
            'Failed to connect after $maxReconnectAttempts attempts';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage.isNotEmpty && widget.error != null) {
      return widget.error!(context, _errorMessage, null);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (_imageBytes != null)
          Image.memory(
            _imageBytes!,
            fit: widget.fit,
            gaplessPlayback: true, // Prevents flickering during updates
          )
        else
          const Center(child: CircularProgressIndicator()),
        if (!_connected)
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _reconnectAttempts > 0
                    ? 'Reconnecting... (Attempt $_reconnectAttempts)'
                    : 'Connecting...',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}
