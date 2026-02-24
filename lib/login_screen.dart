import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main.dart';

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

  // [핵심 추가] 파이썬 백엔드로 유저 정보를 보내고 고유 DB 아이디(순번)를 받아오는 함수
  Future<String?> _sendLoginDataToBackend(String socialId, String provider, String ageGroup) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.45.142:8000/login'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "user_id": socialId,
          "social_provider": provider,
          "age_group": ageGroup,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['user_sequence_id'].toString(); // DB에서 발급해준 순번 (예: "1", "2")
      } else {
        debugPrint("서버 에러: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("네트워크 에러: $e");
      return null;
    }
  }

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

      // 유저 정보 가져오기
      User user = await UserApi.instance.me();
      String socialId = user.id.toString(); // 카카오 고유 아이디
      String? ageRangeStr = user.kakaoAccount?.ageRange?.toString();

      String ageGroup = "20-29"; // 기본값
      if (ageRangeStr != null) {
        if (ageRangeStr.contains('10') || ageRangeStr.contains('15')) ageGroup = "10-19";
        else if (ageRangeStr.contains('20')) ageGroup = "20-29";
        else if (ageRangeStr.contains('30')) ageGroup = "30-39";
        else if (ageRangeStr.contains('40')) ageGroup = "40-49";
        else if (ageRangeStr.contains('50')) ageGroup = "50-59";
      }

      // 백엔드에 정보 저장 후 고유 DB 순번 받아오기
      String? dbUserId = await _sendLoginDataToBackend(socialId, "kakao", ageGroup);

      if (dbUserId != null) {
        _navigateToMain(ageGroup, dbUserId);
      } else {
        _showError('서버 연결에 실패했습니다.');
        if (mounted) setState(() => _isSigningIn = false);
      }

    } catch (error) {
      debugPrint('카카오 로그인 실패: $error');
      _showError('카카오 로그인에 실패했습니다.');
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  // 구글 로그인 함수
  Future<void> _loginWithGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) setState(() => _isSigningIn = false);
        return;
      }

      String socialId = googleUser.id;
      String ageGroup = "20-29"; // 구글은 나이 정보를 쉽게 주지 않으므로 20대로 기본 설정

      // 백엔드에 정보 저장 후 고유 DB 순번 받아오기
      String? dbUserId = await _sendLoginDataToBackend(socialId, "google", ageGroup);

      if (dbUserId != null) {
        _navigateToMain(ageGroup, dbUserId);
      } else {
        _showError('서버 연결에 실패했습니다.');
        if (mounted) setState(() => _isSigningIn = false);
      }

    } catch (error) {
      debugPrint('구글 로그인 실패: $error');
      _showError('구글 로그인에 실패했습니다.');
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  // 메인 화면으로 넘어갈 때 발급받은 DB 순번(dbUserId)도 같이 넘겨줌!
  void _navigateToMain(String ageGroup, String dbUserId) {
    int targetAge = 20;
    if (ageGroup.contains('10')) targetAge = 10;
    else if (ageGroup.contains('20')) targetAge = 20;
    else if (ageGroup.contains('30')) targetAge = 30;
    else if (ageGroup.contains('40')) targetAge = 40;
    else if (ageGroup.contains('50')) targetAge = 50;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => MovieSwipeScreen(userAge: targetAge, dbUserId: dbUserId)),
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