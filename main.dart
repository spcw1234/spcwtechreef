import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device_provider.dart';
import 'tank_provider.dart';
import 'tank_management_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DeviceProvider()),
        ChangeNotifierProvider(create: (context) => TankProvider()),
      ],
      child: MaterialApp(
        title: 'SPCWTECH Control',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const TankManagementScreen(),
      ),
    );
  }
}
