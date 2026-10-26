import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/config.dart';
import 'core/native/emergency_native.dart';
import 'data/repositories_impl.dart';
import 'features/auth/login_screen.dart';
import 'features/contacts/contacts_screen.dart';
import 'features/emergency/emergency_screen.dart';
import 'features/history/history_screen.dart';
import 'features/settings/settings_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = InMemoryTokenStore();
  final client = ApiClient(baseUrl: AppConfig.defaultBackendUrl, tokenStore: tokens);
  final state = AppState(
    tokens: tokens,
    client: client,
    authRepo: AuthRepositoryImpl(client, tokens),
    contactRepo: ContactRepositoryImpl(client),
    emergencyRepo: EmergencyRepositoryImpl(client),
    native: EmergencyNative(),
  )..restoreSession();

  runApp(EmergencyApp(state: state));
}

class EmergencyApp extends StatelessWidget {
  final AppState state;
  const EmergencyApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFB3261E), useMaterial3: true),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      routes: {
        '/login': (context) => LoginScreen(state: state),
        '/home': (context) => HomeShell(state: state),
      },
      home: state.isLoggedIn
          ? HomeShell(state: state)
          : LoginScreen(state: state),
    );
  }
}

class HomeShell extends StatefulWidget {
  final AppState state;
  const HomeShell({super.key, required this.state});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // C-020: auth is reactive — when AppState drops `user` (manual logout OR
    // server-side session death via AUTH_EXPIRED), route back to login from ONE
    // place. Previously only manual logout navigated; a dead session left the user
    // stuck on the emergency screen behind an endless 401 loop.
    widget.state.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (!widget.state.isLoggedIn) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      EmergencyScreen(state: widget.state),
      ContactsScreen(state: widget.state),
      HistoryScreen(state: widget.state),
      SettingsScreen(state: widget.state),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('پلتفرم ایمنی شخصی')),
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.emergency), label: 'اضطراری'),
          NavigationDestination(icon: Icon(Icons.contacts), label: 'مخاطبین'),
          NavigationDestination(icon: Icon(Icons.history), label: 'تاریخچه'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'تنظیمات'),
        ],
      ),
    );
  }
}
