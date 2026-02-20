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

  Future<void> _loginWithKakao() async {
    setState(() => _isSigningIn = true);
    try {
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } catch (error) {
          // 카카오톡 로그인 실패 시 웹으로 시도
          if (error is PlatformException && error.code == 'CANCELED') {
            setState(() => _isSigningIn = false);
            return;
          }
          token = await UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
      
      // 사용자 정보 요청 (연령대 포함)
      User user = await UserApi.instance.me();
      // "20~29", "30~39" 등의 문자열 반환 (AgeRange enum -> string 변환 필요)
      String? ageRangeStr = user.kakaoAccount?.ageRange?.toString(); 
      
      _navigateToMain(ageRangeStr);
    } catch (error) {
      debugPrint('카카오 로그인 실패: $error');
      _showError('카카오 로그인에 실패했습니다.');
    } finally {
      setState(() => _isSigningIn = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isSigningIn = false);
        return; // 사용자가 취소함
      }
      
      // 구글은 연령대 정보를 직접 주지 않으므로 null 처리 (이후 화면에서 입력받거나 기본값 사용)
      _navigateToMain(null);
    } catch (error) {
      debugPrint('구글 로그인 실패: $error');
      _showError('구글 로그인에 실패했습니다.');
    } finally {
      setState(() => _isSigningIn = false);
    }
  }

  void _navigateToMain(String? ageRange) {
    // 연령대 정보를 파싱해서 나이대로 변환 (예: "AgeRange.age_30_39" -> 30)
    int targetAge = 20; // 기본값
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF18202F),
      body: Center(
        child: _isSigningIn
            ? const CircularProgressIndicator()
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
                    Icons.chat_bubble, // 임시 아이콘
                    _loginWithKakao,
                  ),
                  const SizedBox(height: 16),
                  _loginButton(
                    'Google 로그인',
                    Colors.white,
                    Colors.black87,
                    Icons.g_mobiledata, // 임시 아이콘
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
            Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
