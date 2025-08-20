import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/**
 * 장치 히스토리 데이터 클래스 (온도 + ORP)
 */
class TemperatureRecord {
  final int? id;
  final String deviceId;
  final String deviceName;
  final String deviceType; // TEMP, ORP
  final double currentTemp;
  final double setTemp;
  final double? orpRaw; // ORP 장치의 경우 원시값
  final double? orpCorrected; // ORP 장치의 경우 보정값
  final bool coolerState; // true일 때 빨간색으로 표시
  final DateTime timestamp;

  TemperatureRecord({
    this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.currentTemp,
    required this.setTemp,
    this.orpRaw,
    this.orpCorrected,
    required this.coolerState,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'deviceType': deviceType,
      'currentTemp': currentTemp,
      'setTemp': setTemp,
      'orpRaw': orpRaw,
      'orpCorrected': orpCorrected,
      'coolerState': coolerState ? 1 : 0,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  static TemperatureRecord fromMap(Map<String, dynamic> map) {
    return TemperatureRecord(
      id: map['id'],
      deviceId: map['deviceId'],
      deviceName: map['deviceName'],
      deviceType: map['deviceType'] ?? 'TEMP',
      currentTemp: map['currentTemp'],
      setTemp: map['setTemp'],
      orpRaw: map['orpRaw'],
      orpCorrected: map['orpCorrected'],
      coolerState: map['coolerState'] == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }
}

/**
 * 온도/ORP 히스토리 데이터베이스 서비스
 */
class TemperatureHistoryService {
  static Database? _database;
  static const String _tableName = 'temperature_history';

  /**
   * 데이터베이스 인스턴스 가져오기
   */
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /**
   * 데이터베이스 초기화
   */
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'temperature_history.db');
    
    return await openDatabase(
      path,
      version: 2, // 버전 업그레이드
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deviceId TEXT NOT NULL,
            deviceName TEXT NOT NULL,
            deviceType TEXT NOT NULL DEFAULT 'TEMP',
            currentTemp REAL NOT NULL,
            setTemp REAL NOT NULL,
            orpRaw REAL,
            orpCorrected REAL,
            coolerState INTEGER NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
        
        // 인덱스 생성 (빠른 조회를 위해)
        await db.execute('''
          CREATE INDEX idx_device_timestamp ON $_tableName (deviceId, timestamp)
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // 기존 테이블에 새 컬럼 추가
          await db.execute('ALTER TABLE $_tableName ADD COLUMN deviceType TEXT NOT NULL DEFAULT "TEMP"');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN orpRaw REAL');
          await db.execute('ALTER TABLE $_tableName ADD COLUMN orpCorrected REAL');
        }
      },
    );
  }

  /**
   * 온도/ORP 데이터 저장
   */
  Future<void> saveTemperatureRecord(TemperatureRecord record) async {
    final db = await database;
    await db.insert(_tableName, record.toMap());
    print('데이터 저장: ${record.deviceName} (${record.deviceType}) - ${record.currentTemp}°C');
  }

  /**
   * 특정 장치의 최근 24시간 데이터 가져오기
   */
  Future<List<TemperatureRecord>> getTodayTemperatureData(String deviceId) async {
    final db = await database;
    final now = DateTime.now();
    final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));

    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'deviceId = ? AND timestamp >= ?',
      whereArgs: [
        deviceId,
        twentyFourHoursAgo.millisecondsSinceEpoch,
      ],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) => TemperatureRecord.fromMap(maps[i]));
  }

  /**
   * 오래된 데이터 정리 (24시간 이상된 데이터 삭제)
   */
  Future<void> cleanOldData() async {
    final db = await database;
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
    
    final deletedCount = await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [twentyFourHoursAgo.millisecondsSinceEpoch],
    );
    
    if (deletedCount > 0) {
      print('$deletedCount개의 24시간 이상된 데이터를 삭제했습니다.');
    }
  }

  /**
   * 특정 장치의 모든 데이터 삭제
   */
  Future<void> deleteDeviceData(String deviceId) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'deviceId = ?',
      whereArgs: [deviceId],
    );
    print('장치 $deviceId의 모든 히스토리를 삭제했습니다.');
  }
}
