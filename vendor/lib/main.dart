import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'reviews.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/vendor_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final reviews = await ReviewFeed.init();
  runApp(ChangeNotifierProvider(create: (_) => AppState(reviews: reviews)..restore(), child: const VendorApp()));
}

class VendorApp extends StatelessWidget {
  const VendorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'FoodCourt ร้านค้า',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: state.restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.pink)))
          : state.user == null
              ? const LoginScreen()
              : const VendorShell(),
    );
  }
}
