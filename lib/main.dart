import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; //앱 종료(SystemNavigator)를 위해 추가된 패키지
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_screen.dart';

void main() async {
  // Flutter 엔진 초기화 (비동기 호출 위해 필요)
  WidgetsFlutterBinding.ensureInitialized();
  
  // 카카오 SDK 초기화 (네이티브 앱 키 필요 - 카카오 개발자 사이트에서 발급받은 키 입력)
  // TODO: 여기에 실제 네이티브 앱 키를 넣으세요!
  KakaoSdk.init(nativeAppKey: 'a392d68a91bde52cb94501eeaa9bcf1f');
  
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color.fromARGB(255, 18, 32, 47),
      ),
      home: const LoginScreen(),
    );
  }
}

class MovieSwipeScreen extends StatefulWidget {
  final int userAge;
  const MovieSwipeScreen({super.key, this.userAge = 20});

  @override
  State<MovieSwipeScreen> createState() => _MovieSwipeScreenState();
}

class _MovieSwipeScreenState extends State<MovieSwipeScreen> {
  final CardSwiperController controller = CardSwiperController();
  List<dynamic> movies = [];
  List<Map<String, dynamic>> userResponses = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMoviesFromBackend();
  }

  Future<void> _fetchMoviesFromBackend() async {
    try {
      String ageQuery = "${widget.userAge}-${widget.userAge + 9}";
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      final response = await http.get(Uri.parse('http://10.0.2.2:8000/questions/$ageQuery?t=$timestamp'));

      if (response.statusCode == 200) {
        setState(() {
          movies = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("데이터 로드 실패: $e");
      setState(() => isLoading = false);
    }
  }

  Future<void> _sendAnalysisRequest() async {
    final response = await http.post(
      Uri.parse('http://10.0.2.2:8000/recommend'),
      headers: {"Content-Type": "application/json"},
      body: json.encode(userResponses),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      if (mounted) _showResultDialog(result);
    }
  }

  // 앱 종료 확인 팝업창 띄우기 함수
  Future<bool> _showExitConfirmation() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C273D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("앱 종료", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("어플리케이션을 종료하시겠습니까?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // 취소 시 false 반환
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => SystemNavigator.pop(), // 진짜 앱 종료 코드
            child: const Text("종료", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showResultDialog(Map<String, dynamic> result) {
    String tasteType = result['taste_analysis']['primary_factor'];

    String specialMessage = (tasteType == "확고한 주관")
        ? "취향이 아주 확고하시네요!\n당신을 위해 한국에서 사랑받은 최고의 명작을 골라왔어요."
        : "당신의 취향을 저격할 인생 영화입니다.";

    String overview = result['recommendation']['overview'] ?? "";
    if (overview.isEmpty) overview = "줄거리 정보가 제공되지 않는 영화입니다.";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C273D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("분석 완료!\n($tasteType)",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(specialMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 15),
              if (result['recommendation']['poster_url'] != "")
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(result['recommendation']['poster_url'], height: 220, fit: BoxFit.cover),
                ),
              const SizedBox(height: 15),
              Text(result['recommendation']['title'],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                  textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text("개봉 연도: ${result['recommendation']['release_date'].toString().split('-')[0]}년",
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 15),
              Container(
                constraints: const BoxConstraints(maxHeight: 100),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    overview,
                    style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  isLoading = true;
                  userResponses.clear();
                });
                _fetchMoviesFromBackend();
              },
              child: const Text("다시 하기", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      // 매번 새로 생성하기보다 인스턴스를 재사용하거나, 명시적으로 처리
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      await googleSignIn.disconnect(); // 연결을 완전히 해제하여 채널 종료 유도

      try {
        if (await AuthApi.instance.hasToken()) await UserApi.instance.logout();
      } catch (_) {}

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false
        );
      }
    } catch (e) {
      debugPrint('로그아웃 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // 💡 PopScope: 안드로이드 기기의 '뒤로 가기' 버튼을 제어하여 실수로 앱이 꺼지는 것을 방지
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmation();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // 💡 좌측 상단에 종료 버튼 (전원 아이콘) 추가
          leading: IconButton(
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 28),
            onPressed: () => _showExitConfirmation(),
            tooltip: '앱 종료',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: GestureDetector(
                onTap: () => _logout(context),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.white, size: 24),
                    SizedBox(height: 4),
                    Text('로그아웃', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Text('MovieSwipe AI (${widget.userAge}대)', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('한국에서 사랑받은 명작들을 스와이프하세요!'),
              Expanded(
                child: CardSwiper(
                  key: ValueKey(movies.hashCode),
                  controller: controller,
                  cardsCount: movies.length,
                  cardBuilder: (context, index, _, __) => _buildMovieCard(movies[index]),
                  onSwipe: (prev, curr, direction) {
                    userResponses.add({
                      "user_id": "test_user", "movie_id": movies[prev]['movie_id'],
                      "title": movies[prev]['title'], "genre_ids": movies[prev]['genre_ids'],
                      "popularity": movies[prev]['popularity'], "vote_average": movies[prev]['vote_average'],
                      "is_watched": direction == CardSwiperDirection.right
                    });
                    return true;
                  },
                  onEnd: () => _sendAnalysisRequest(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _actionButton(Colors.red, Icons.close, () => controller.swipe(CardSwiperDirection.left)),
                  const SizedBox(width: 40),
                  _actionButton(Colors.blue, Icons.done, () => controller.swipe(CardSwiperDirection.right)),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovieCard(dynamic movie) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(image: NetworkImage(movie['poster_url']), fit: BoxFit.cover),
      ),
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Text(movie['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _actionButton(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60, height: 60,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 30),
      ),
    );
  }
}