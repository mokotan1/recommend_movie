import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'login_screen.dart';

void main() async {
  // Flutter 엔진 초기화 (비동기 호출 위해 필요)
  WidgetsFlutterBinding.ensureInitialized();
  
  // 카카오 SDK 초기화 (네이티브 앱 키 필요 - 카카오 개발자 사이트에서 발급받은 키 입력)
  // TODO: 실제 앱 키는 보안상 제외함. 로컬 실행 시 키를 입력하세요.
  KakaoSdk.init(nativeAppKey: 'YOUR_NATIVE_APP_KEY_HERE');  

  // 디버그용: 키 해시 출력 (로그 확인 후 카카오 개발자 콘솔에 등록)
  try {
    print('Key Hash: ${await KakaoSdk.origin}');
  } catch (e) {
    print('Key Hash Error: $e');
  }
  
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
      home: const LoginScreen(), // 로그인 화면을 시작 화면으로 변경
    );
  }
}

class MovieSwipeScreen extends StatefulWidget {
  final int userAge; // 로그인 화면에서 전달받을 나이 (기본값 20)

  const MovieSwipeScreen({super.key, this.userAge = 20});

  @override
  State<MovieSwipeScreen> createState() => _MovieSwipeScreenState();
}

class _MovieSwipeScreenState extends State<MovieSwipeScreen> {
  final CardSwiperController controller = CardSwiperController();
  List<dynamic> movies = []; // 백엔드에서 받을 영화 리스트
  List<Map<String, dynamic>> userResponses = []; // 서버로 보낼 응답 데이터
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMoviesFromBackend(); // 앱 시작 시 백엔드 데이터 로드
  }

  // 1. 백엔드(main.py)에서 연령대별 영화 데이터 가져오기
  Future<void> _fetchMoviesFromBackend() async {
    try {
      // 전달받은 나이(userAge)를 기반으로 API 호출 URL 변경
      // 예: 20 -> "20-29", 30 -> "30-39"
      String ageQuery = "${widget.userAge}-${widget.userAge + 9}";

      // 에뮬레이터에서 내 컴퓨터 백엔드 접속 주소
      final response = await http.get(Uri.parse('http://10.0.2.2:8000/questions/$ageQuery'));

      if (response.statusCode == 200) {
        setState(() {
          movies = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("백엔드 연결 실패: $e");
      setState(() => isLoading = false);
    }
  }

  // 2. 스와이프 완료 후 백엔드에 취향 분석 요청
  Future<void> _sendAnalysisRequest() async {
    final response = await http.post(
      Uri.parse('http://10.0.2.2:8000/recommend'),
      headers: {"Content-Type": "application/json"},
      body: json.encode(userResponses),
    );

    if (response.statusCode == 200) {
      final result = json.decode(response.body);
      if (mounted) _showResultDialog(result); // 결과 팝업 표시
    }
  }

  void _showResultDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("취향 분석 완료! (${result['taste_analysis']['primary_factor']})"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (result['recommendation']['poster_url'] != null)
              Image.network(result['recommendation']['poster_url'], height: 200),
            const SizedBox(height: 10),
            Text("추천 영화: ${result['recommendation']['title']}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (movies.isEmpty) return const Scaffold(body: Center(child: Text("서버 데이터를 확인할 수 없습니다.")));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text('MovieSwipe AI (${widget.userAge}대)', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Text('본 영화는 오른쪽, 안 본 영화는 왼쪽으로!'),
            Expanded(
              child: CardSwiper(
                controller: controller,
                cardsCount: movies.length,
                cardBuilder: (context, index, _, __) => _buildMovieCard(movies[index]),
                onSwipe: (prev, curr, direction) {
                  // 사용자의 선택 데이터 기록 (백엔드 전송용)
                  userResponses.add({
                    "user_id": "test_user", // 실제 연동 시 사용자 ID 사용
                    "movie_id": movies[prev]['movie_id'],
                    "title": movies[prev]['title'],
                    "genre_ids": movies[prev]['genre_ids'],
                    "actors": movies[prev]['actors'],
                    "popularity": movies[prev]['popularity'],
                    "vote_average": movies[prev]['vote_average'],
                    "is_watched": direction == CardSwiperDirection.right
                  });
                  return true;
                },
                onEnd: () => _sendAnalysisRequest(), // 카드 다 넘기면 분석 요청
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
    );
  }

  Widget _buildMovieCard(dynamic movie) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: NetworkImage(movie['poster_url']), // TMDB 실제 포스터 이미지
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Colors.transparent, Colors.black87],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: Text(
          movie['title'],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
        ),
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
