import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'main.dart'; // MovieSwipeScreen으로 이동하기 위해 import

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  bool _isSigningIn = false;

  // 카카오 로그인 함수
  Future<void> _loginWithKakao() async {
    setState(() => _isSigningIn = true);
    try {
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          if (error is PlatformException && error.code == 'CANCELED') {
            if (mounted) setState(() => _isSigningIn = false);
            return;
          }
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      User user = await UserApi.instance.me();
      String? ageRangeStr = user.kakaoAccount?.ageRange?.toString();

      _navigateToMain(ageRangeStr);
      // 성공 시 화면을 이동하므로 여기서 함수가 종료됩니다. (setState 필요 없음)

    } catch (error) {
      debugPrint('카카오 로그인 실패: $error');
      _showError('카카오 로그인에 실패했습니다.');
      if (mounted) setState(() => _isSigningIn = false); // 에러 발생 시 로딩 끄기
    }
  }

  // 구글 로그인 함수
  Future<void> _loginWithGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // 사용자가 뒤로가기 등으로 로그인을 취소한 경우
        if (mounted) setState(() => _isSigningIn = false);
        return;
      }

      // 로그인 성공 시 메인으로 이동
      _navigateToMain(null);

    } catch (error) {
      debugPrint('구글 로그인 실패: $error');
      _showError('구글 로그인에 실패했습니다.');
      if (mounted) setState(() => _isSigningIn = false); // 에러 발생 시 로딩 끄기
    }
  }

  void _navigateToMain(String? ageRange) {
    int targetAge = 20;
    if (ageRange != null) {
      if (ageRange.contains('20')) targetAge = 20;
      else if (ageRange.contains('30')) targetAge = 30;
      else if (ageRange.contains('40')) targetAge = 40;
      else if (ageRange.contains('50')) targetAge = 50;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MovieSwipeScreen(userAge: targetAge)),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18202F),
      body: Center(
        child: _isSigningIn
            ? const CircularProgressIndicator(color: Colors.white)
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'MOVIE RECOMMEND',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 50),
            _loginButton(
              '카카오 로그인',
              const Color(0xFFFEE500),
              Colors.black87,
              Icons.chat_bubble,
              _loginWithKakao,
            ),
            const SizedBox(height: 16),
            _loginButton(
              'Google 로그인',
              Colors.white,
              Colors.black87,
              Icons.g_mobiledata,
              _loginWithGoogle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginButton(String text, Color bgColor, Color textColor, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: textColor,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}