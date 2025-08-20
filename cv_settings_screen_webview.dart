import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'device.dart';
import 'device_provider.dart';

class CvSettingsScreenWebview extends StatefulWidget {
  final String deviceId;

  const CvSettingsScreenWebview({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<CvSettingsScreenWebview> createState() => _CvSettingsScreenWebviewState();
}

class _CvSettingsScreenWebviewState extends State<CvSettingsScreenWebview> {  WebViewController? _webViewController;
  bool _isStreamConnected = false;
  bool _isDisposing = false;
  double _viewerHeight = 250.0;
  bool _isFullScreen = false; // 전체 화면 모드 상태
  double _initialZoomLevel = 1.0; // 초기 확대 레벨 (1.0 = 100%)
  
  // WebView 뷰어 URL - 유일하게 작동하는 URL
  final String _streamUrl = 'http://spcwtech.mooo.com:7200/mobile';

  @override
  void initState() {
    super.initState();
    _isDisposing = false;
    _initializeWebView();
  }

  @override
  void dispose() {
    _isDisposing = true;
    super.dispose();
  }  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..enableZoom(true) // 줌 활성화 - 사용자가 핀치/더블탭으로 확대/축소 가능
      ..clearCache()
      ..clearLocalStorage()
      ..addJavaScriptChannel(
        'CSPBypass',
        onMessageReceived: (JavaScriptMessage message) {
          print('CSP Bypass message: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            print('[CvSettingsScreenWebview] Loading progress: $progress%');
          },
          onPageStarted: (String url) {
            print('[CvSettingsScreenWebview] Page started loading: $url');
            if (mounted && !_isDisposing) {
              setState(() {
                _isStreamConnected = false;
              });
            }
          },          onPageFinished: (String url) {
            print('[CvSettingsScreenWebview] Page finished loading: $url');
            // about:blank 로딩을 무시
            if (url == 'about:blank') {
              print('[CvSettingsScreenWebview] Ignoring about:blank page');
              return;
            }
              // 페이지가 로드되면 초기 확대/축소 레벨 설정 및 화면 최적화 (JavaScript 이용)
            if (url == _streamUrl) {
              _webViewController?.runJavaScript('''
                // 모바일 카메라 스트림 타이틀 숨기기
                (function() {
                  // 제목 및 불필요한 텍스트 요소 찾아서 숨기기
                  var h1Elements = document.querySelectorAll('h1, h2, h3, h4, h5');
                  for (var i = 0; i < h1Elements.length; i++) {
                    if (h1Elements[i].innerText.includes('Mobile Camera Stream')) {
                      h1Elements[i].style.display = 'none';
                    }
                  }
                  
                  // "FPS:" 텍스트를 포함한 모든 div 요소 스타일 조정
                  var divElements = document.querySelectorAll('div');
                  for (var i = 0; i < divElements.length; i++) {
                    if (divElements[i].innerText && divElements[i].innerText.includes('FPS:')) {
                      divElements[i].style.fontSize = '10px';
                      divElements[i].style.position = 'absolute';
                      divElements[i].style.bottom = '4px';
                      divElements[i].style.right = '4px';
                      divElements[i].style.backgroundColor = 'rgba(0,0,0,0.3)';
                      divElements[i].style.padding = '2px 4px';
                      divElements[i].style.borderRadius = '4px';
                      divElements[i].style.color = 'white';
                    }
                  }

                  // 비디오 스트림 요소 크기 최적화 (가장 큰 이미지나 비디오 요소 찾기)
                  var mediaElements = document.querySelectorAll('img, video, canvas');
                  if (mediaElements.length > 0) {
                    for (var i = 0; i < mediaElements.length; i++) {
                      var elem = mediaElements[i];
                      elem.style.width = '100%';
                      elem.style.maxWidth = '100%';
                      elem.style.height = 'auto';
                      elem.style.objectFit = 'contain';
                    }
                  }
                  
                  // 전체 페이지 스타일 최적화
                  document.body.style.margin = '0';
                  document.body.style.padding = '0';
                  document.body.style.display = 'flex';
                  document.body.style.justifyContent = 'center';
                  document.body.style.alignItems = 'center';
                  document.body.style.overflow = 'hidden';
                  document.body.style.backgroundColor = '#000';
                })();
                
                // 뷰포트 메타 태그 추가/수정
                var metaTag = document.querySelector('meta[name="viewport"]');
                if (!metaTag) {
                  metaTag = document.createElement('meta');
                  metaTag.name = 'viewport';
                  document.head.appendChild(metaTag);
                }
                metaTag.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes';
                
                // 페이지가 완전히 로드된 후 콘텐츠를 올바르게 배치
                setTimeout(function() {
                  window.scrollTo(0, 0);
                }, 300);
              ''').then((_) => 
                print('[CvSettingsScreenWebview] 스트림 화면 최적화 완료')
              ).catchError((error) => 
                print('[CvSettingsScreenWebview] JavaScript 오류: $error')
              );
            }
            
            if (mounted && !_isDisposing) {
              setState(() {
                _isStreamConnected = true;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('[CvSettingsScreenWebview] WebView error: ${error.description}');
            print('[CvSettingsScreenWebview] Error URL: ${error.url}');
            print('[CvSettingsScreenWebview] Error type: ${error.errorType}');
            print('[CvSettingsScreenWebview] Error code: ${error.errorCode}');
            
            if (mounted && !_isDisposing) {
              setState(() {
                _isStreamConnected = false;
              });
                // 네트워크 오류시 스낵바로 사용자에게 알림
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('스트림 연결 실패: ${error.description}'),
                ),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            print('[CvSettingsScreenWebview] Navigation request to: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      );  }
  void _startStream(Device device, DeviceProvider deviceProvider) {
    print('[CvSettingsScreenWebview _startStream] Starting WebView stream: $_streamUrl');
    
    // 직접 URL 로드하되 WebView 설정으로 스케일링 조정
    _webViewController?.loadRequest(Uri.parse(_streamUrl));
    
    setState(() {
      _isStreamConnected = true;
    });
  }

  void _stopStream(Device device, DeviceProvider deviceProvider) {
    print('[CvSettingsScreenWebview _stopStream] Stopping WebView stream');
    
    _webViewController?.loadHtmlString('''
    <!DOCTYPE html>
    <html>
    <head><title>Stream Stopped</title></head>
    <body style="background-color: black; color: white; text-align: center; font-family: Arial;">
        <h2>스트림이 중지되었습니다</h2>
        <p>시작 버튼을 눌러 스트림을 다시 시작하세요.</p>
    </body>
    </html>
    ''');
    
    setState(() {
      _isStreamConnected = false;
    });
    deviceProvider.stopCvStreaming(device);
  }

  // 전체 화면 모드 전환 함수
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      
      // 전체 화면 모드일 때는 높이를 화면 높이의 90%로 설정
      if (_isFullScreen) {
        // MediaQuery를 사용하여 화면 높이를 가져오고 상태바, 앱바 등의 높이를 제외한 값을 사용
        _viewerHeight = MediaQuery.of(context).size.height * 0.9;
      } else {
        // 기본 높이로 복원 (또는 마지막으로 설정한 높이)
        _viewerHeight = 250.0;
      }
    });
  }
  
  // 줌 레벨 조정 함수
  void _adjustZoomLevel(double zoomLevel) {
    if (_webViewController == null) return;
    
    _webViewController!.runJavaScript('''
      document.body.style.zoom = "$zoomLevel";
    ''').then((_) => 
      print('[CvSettingsScreenWebview] 확대/축소 레벨 ${zoomLevel}로 설정됨')
    ).catchError((error) => 
      print('[CvSettingsScreenWebview] 확대/축소 레벨 조정 오류: $error')
    );
    
    _initialZoomLevel = zoomLevel; // 현재 줌 레벨 저장
  }

  void _sendCameraCommand(String direction) {
    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    final device = deviceProvider.devices.firstWhere(
      (d) => d.id == widget.deviceId,
      orElse: () => throw StateError('Device not found'),
    );
    
    // MQTT 메시지 전송: uniqueID/CV/com {"move":"direction"}
    final String topic = '${device.id}/CV/com';
    final String message = '{"move":"$direction"}';
    
    print('[CvSettingsScreenWebview] Sending camera command: $topic -> $message');
    
    // TODO: 실제 MQTT 전송 로직을 여기에 구현
    deviceProvider.sendMqttMessage(topic, message);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('카메라 명령 전송: $direction'),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullScreen ? null : AppBar(
        title: const Text('CV 설정 (WebView 방식)'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_webViewController != null) {
                _webViewController!.reload();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('페이지를 새로 고침 중입니다...'), duration: Duration(seconds: 1)),
                );
              }
            },
            tooltip: '새로고침',
          ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, deviceProvider, child) {
          final device = deviceProvider.devices.firstWhere(
            (d) => d.id == widget.deviceId,
            orElse: () => throw StateError('Device not found'),
          );
          
          // 전체 화면 모드일 때의 UI
          if (_isFullScreen) {
            return Stack(
              children: [
                // 전체 화면 WebView
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black,
                  child: _webViewController != null 
                    ? WebViewWidget(controller: _webViewController!)
                    : const Center(child: CircularProgressIndicator()),
                ),
                
                // 전체 화면 컨트롤 오버레이 (상단 바)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                              onPressed: _toggleFullScreen,
                            ),
                            Text('${device.customName} - 전체화면 모드', 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.white),
                                  onPressed: () => _adjustZoomLevel(_initialZoomLevel - 0.2),
                                ),
                                Text('${(_initialZoomLevel * 100).round()}%', 
                                  style: const TextStyle(color: Colors.white)),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  onPressed: () => _adjustZoomLevel(_initialZoomLevel + 0.2),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 카메라 컨트롤 오버레이 (우측 하단 패널)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Card(
                    color: Colors.black.withOpacity(0.7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => _sendCameraCommand('up'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.withOpacity(0.7),
                              shape: const CircleBorder(),
                              minimumSize: const Size(50, 50),
                            ),
                            child: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () => _sendCameraCommand('left'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.withOpacity(0.7),
                                  shape: const CircleBorder(),
                                  minimumSize: const Size(50, 50),
                                ),
                                child: const Icon(Icons.keyboard_arrow_left, color: Colors.white),
                              ),
                              ElevatedButton(
                                onPressed: () => _sendCameraCommand('stop'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.withOpacity(0.7),
                                  shape: const CircleBorder(),
                                  minimumSize: const Size(50, 50),
                                ),
                                child: const Icon(Icons.stop, color: Colors.white),
                              ),
                              ElevatedButton(
                                onPressed: () => _sendCameraCommand('right'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.withOpacity(0.7),
                                  shape: const CircleBorder(),
                                  minimumSize: const Size(50, 50),
                                ),
                                child: const Icon(Icons.keyboard_arrow_right, color: Colors.white),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () => _sendCameraCommand('down'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.withOpacity(0.7),
                              shape: const CircleBorder(),
                              minimumSize: const Size(50, 50),
                            ),
                            child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          
          // 일반 모드 UI
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDeviceInfo(device),
                const SizedBox(height: 16),
                _buildStreamControls(device, deviceProvider),
                const SizedBox(height: 16),
                _buildStreamViewer(device),
                const SizedBox(height: 16),
                _buildCameraControls(device),
              ],
            ),
          );
        },
      ),
    );
  }  Widget _buildDeviceInfo(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('장치 정보', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('ID: ${device.id}'),
            Text('이름: ${device.customName}'),
            Text('스트림 URL: $_streamUrl'),
            Text('스트림 상태: ${_isStreamConnected ? "연결됨" : "연결 해제됨"}'),
          ],
        ),
      ),
    );
  }  Widget _buildStreamControls(Device device, DeviceProvider deviceProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('스트림 제어', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _startStream(device, deviceProvider),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('시작', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: () => _stopStream(device, deviceProvider),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('중지', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStreamViewer(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [            Row(              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text('영상 스트림', 
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _toggleFullScreen,
                      icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, size: 14),
                      label: Text(_isFullScreen ? '종료' : '전체화면', style: const TextStyle(fontSize: 10)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFullScreen ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${_viewerHeight.round()}px', 
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 줌 컨트롤 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _adjustZoomLevel(_initialZoomLevel - 0.2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                  child: const Icon(Icons.remove, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '확대 ${(_initialZoomLevel * 100).round()}%',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _adjustZoomLevel(_initialZoomLevel + 0.2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 전체화면 모드가 아닐 때만 슬라이더 표시
            if (!_isFullScreen)
              Slider(
                value: _viewerHeight,
                min: 150.0,
                max: 500.0,
                divisions: 35,
                label: '${_viewerHeight.round()}px',
                onChanged: (value) {
                  setState(() {
                    _viewerHeight = value;
                  });
                },
              ),
            const SizedBox(height: 8),            Container(
              width: double.infinity,
              height: _viewerHeight,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),                child: _webViewController != null
                    ? WebViewWidget(controller: _webViewController!)
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
            ),            const SizedBox(height: 8),
            Text(
              '현재 URL: $_streamUrl',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            Text(
              '상태: ${_isStreamConnected ? "연결됨" : "연결 대기중"}',
              style: TextStyle(
                fontSize: 10, 
                color: _isStreamConnected ? Colors.green : Colors.red,
              ),
            ),            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.zoom_in, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '💡 + / - 버튼으로 확대/축소 또는 화면을 핀치/더블탭 할 수 있어요',
                          style: TextStyle(
                            fontSize: 11, 
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.fullscreen, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '💡 전체화면 버튼으로 더 크게 볼 수 있어요',
                          style: TextStyle(
                            fontSize: 11, 
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControls(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('카메라 조작', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 위쪽 버튼
                  ElevatedButton(
                    onPressed: () => _sendCameraCommand('up'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: const Size(60, 60),
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 8),
                  // 좌우 버튼과 가운데 정지 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _sendCameraCommand('left'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          minimumSize: const Size(60, 60),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 30),
                      ),
                      ElevatedButton(
                        onPressed: () => _sendCameraCommand('stop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          minimumSize: const Size(60, 60),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.stop, color: Colors.white, size: 30),
                      ),
                      ElevatedButton(
                        onPressed: () => _sendCameraCommand('right'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          minimumSize: const Size(60, 60),
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.keyboard_arrow_right, color: Colors.white, size: 30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 아래쪽 버튼
                  ElevatedButton(
                    onPressed: () => _sendCameraCommand('down'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: const Size(60, 60),
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MQTT 명령 형식:', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text('Topic: ${device.id}/CV/com', 
                       style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  Text('Message: {"move":"up/down/left/right/stop"}', 
                       style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
