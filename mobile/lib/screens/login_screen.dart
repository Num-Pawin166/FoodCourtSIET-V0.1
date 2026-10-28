import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../google_auth.dart';
import '../google_button_stub.dart' if (dart.library.js_interop) '../google_button_web.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  // Google
  String _domain = 'kmitl.ac.th';
  bool _googleReady = false;
  String? _googleNote;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleSub;

  @override
  void initState() {
    super.initState();
    _setupGoogle();
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _setupGoogle() async {
    try {
      final cfg = await context.read<AppState>().api.authConfig();
      _domain = cfg['allowed_domain'] ?? _domain;
      final clientId = cfg['google_client_id'] as String?;
      if (clientId == null || clientId.isEmpty) {
        if (mounted) setState(() => _googleNote = 'ยังไม่ได้ตั้งค่า Google Sign-In ที่เซิร์ฟเวอร์');
        return;
      }
      await GoogleAuth.init(clientId: clientId, domain: _domain);
      _googleSub = GoogleAuth.events.listen(_onGoogleEvent, onError: _onGoogleError);
      if (mounted) setState(() => _googleReady = true);
    } catch (e) {
      if (mounted) setState(() => _googleNote = 'ใช้ Google Sign-In ไม่ได้: $e');
    }
  }

  Future<void> _onGoogleEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;
    final idToken = event.user.authentication.idToken;
    if (idToken == null) return _showError('ไม่ได้รับข้อมูลยืนยันตัวตนจาก Google');
    await _run(() => context.read<AppState>().loginWithGoogle(idToken), signOutOnError: true);
  }

  void _onGoogleError(Object e) {
    // ผู้ใช้ปิดหน้าต่างเลือกบัญชีเอง ไม่ต้องแจ้ง
    if (e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled) return;
    _showError(e is GoogleSignInException ? (e.description ?? e.code.name) : e);
  }

  Future<void> _googleTap() async {
    try {
      await GoogleAuth.authenticate(); // ผลลัพธ์มาทาง _onGoogleEvent
    } catch (e) {
      _onGoogleError(e);
    }
  }

  Future<void> _passwordLogin() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return _showError('กรุณากรอกข้อมูลให้ครบ');
    await _run(() => context.read<AppState>().login(_username.text, _password.text));
  }

  Future<void> _run(Future<void> Function() fn, {bool signOutOnError = false}) async {
    setState(() => _loading = true);
    try {
      await fn();
    } catch (e) {
      // เช่น อีเมลไม่ใช่ @kmitl.ac.th → ออกจาก Google ด้วย จะได้เลือกบัญชีใหม่ได้
      if (signOutOnError) await GoogleAuth.signOut().catchError((_) {});
      _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(Object e) {
    if (mounted) showMsg(context, e, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(children: [
                const FoodCourtLogo(size: 84),
                const SizedBox(height: 40),
                _googleSection(),
                const SizedBox(height: 20),
                const Row(children: [
                  Expanded(child: Divider(color: AppColors.line)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('หรือใช้รหัสผ่าน', style: TextStyle(fontSize: 12, color: AppColors.muted))),
                  Expanded(child: Divider(color: AppColors.line)),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _username,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Name', prefixIcon: Icon(Icons.person, color: AppColors.ink2)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  onSubmitted: (_) => _passwordLogin(),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock, color: AppColors.ink2),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20, color: AppColors.muted),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PinkButton(onPressed: _passwordLogin, loading: _loading, child: const Text('Login')),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleSection() {
    final Widget button;
    if (!_googleReady) {
      button = OutlinedButton.icon(
        onPressed: null,
        icon: const _GoogleG(),
        label: Text(_googleNote ?? 'กำลังโหลด...', style: const TextStyle(fontSize: 13)),
        style: _googleStyle,
      );
    } else if (GoogleAuth.canAuthenticate) {
      button = OutlinedButton.icon(
        onPressed: _loading ? null : _googleTap,
        icon: const _GoogleG(),
        label: const Text('เข้าสู่ระบบด้วย Google', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
        style: _googleStyle,
      );
    } else {
      button = SizedBox(height: 44, child: buildGoogleWebButton()); // เว็บ: ปุ่มของ Google
    }
    return Column(children: [
      SizedBox(width: double.infinity, child: Center(child: button)),
      const SizedBox(height: 8),
      Text('สำหรับนักศึกษาและบุคลากร ใช้อีเมล @$_domain เท่านั้น', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
    ]);
  }

  static final _googleStyle = OutlinedButton.styleFrom(
    minimumSize: const Size(double.infinity, 52),
    backgroundColor: Colors.white,
    side: const BorderSide(color: Color(0xFFD9D9D9)),
    shape: const StadiumBorder(),
  );
}

/// โลโก้ "G" 4 สีของ Google (ตาม Google Sign-In branding)
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
  <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
  <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
  <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

  @override
  Widget build(BuildContext context) => SvgPicture.string(_svg, width: 20, height: 20);
}
