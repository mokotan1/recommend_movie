import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart'; // 웹 브라우저/앱 실행을 위한 패키지 추가
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final String dbUserId; // 파이썬 DB에서 발급받은 진짜 유저 순번

  const MovieSwipeScreen({super.key, this.userAge = 20, required this.dbUserId});

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

      final response = await http.get(Uri.parse('http://192.168.45.142:8000/questions/$ageQuery?t=$timestamp'));

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
    try {
      final response = await http.post(
        Uri.parse('http://192.168.45.142:8000/recommend'),
        headers: {"Content-Type": "application/json"},
        body: json.encode(userResponses),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (mounted) _showResultDialog(result);
      } else {
        debugPrint("서버 에러: ${response.statusCode} - ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("추천에 실패했습니다. 취향을 조금 더 다양하게 선택해 보세요! (에러: ${response.statusCode})"),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("네트워크 에러: $e");
    }
  }

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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => SystemNavigator.pop(),
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

    // OTT 정보 및 시청 링크 가져오기
    List<dynamic> providers = result['recommendation']['providers'] ?? [];
    String watchLink = result['recommendation']['watch_link'] ?? "";

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

              // 포스터 클릭 시 OTT 링크로 이동 기능
              if (result['recommendation']['poster_url'] != "")
                GestureDetector(
                  onTap: () async {
                    if (watchLink.isNotEmpty) {
                      final Uri url = Uri.parse(watchLink);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("현재 제공되는 OTT 링크가 없습니다.")),
                        );
                      }
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.network(result['recommendation']['poster_url'], height: 200, fit: BoxFit.cover),
                      ),
                      if (watchLink.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 15),
              Text(result['recommendation']['title'],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                  textAlign: TextAlign.center),
              const SizedBox(height: 5),
              Text("개봉 연도: ${result['recommendation']['release_date'].toString().split('-')[0]}년",
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 15),

              // 제공되는 OTT 플랫폼 아이콘들 보여주기
              if (providers.isNotEmpty) ...[
                const Text("지금 바로 볼 수 있는 곳", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: providers.map((p) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(p['logo_url'], width: 35, height: 35),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 15),
              ],

              Container(
                constraints: const BoxConstraints(maxHeight: 80),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(
                  child: Text(overview, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4), textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 보러 가기 버튼
              if (watchLink.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () async {
                    final Uri url = Uri.parse(watchLink);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  label: const Text("보러 가기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              // 다시 하기 버튼
              ElevatedButton(
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
            ],
          )
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
      try { if (await AuthApi.instance.hasToken()) await UserApi.instance.logout(); } catch (_) {}
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
      }
    } catch (e) { debugPrint('로그아웃 실패: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

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
                      "user_id": widget.dbUserId, // DB 순번 기록
                      "movie_id": movies[prev]['movie_id'],
                      "title": movies[prev]['title'],
                      "genre_ids": movies[prev]['genre_ids'],
                      "popularity": movies[prev]['popularity'],
                      "vote_average": movies[prev]['vote_average'],
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