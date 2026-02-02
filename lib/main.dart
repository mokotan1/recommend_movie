import 'package:flutter/material.dart';

void main() {
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 디버그 띠 제거
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color.fromARGB(255, 18, 32, 47),
      ),
      home: const MovieSwipeScreen(), // 이름 변경됨
    );
  }
}

// 클래스 이름을 Container에서 MovieSwipeScreen으로 변경하여 충돌 해결
class MovieSwipeScreen extends StatelessWidget {
  const MovieSwipeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 팁: ListView 대신 SafeArea를 써서 상단 노치 영역을 보호하세요.
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center( // 중앙 정렬 추가
            child: Column(
              children: [
                // 내부의 위젯들은 이제 플러터 공식 Container를 정상적으로 사용합니다.
                Container(
                  width: 448,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 상단 타이틀 영역
                      _buildHeader(),
                      const SizedBox(height: 32),
                      // 영화 카드 영역 (Stack)
                      _buildMovieCard(),
                      const SizedBox(height: 64),
                      // 하단 컨트롤러 영역
                      _buildControlButtons(),
                      const SizedBox(height: 32),
                      // 통계 영역
                      _buildStats(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 가독성을 위해 위젯을 함수로 분리했습니다.
  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'MovieSwipe',
          style: TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '영화를 봤는지 스와이프하세요',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildMovieCard() {
    // 피그마에서 가져온 복잡한 Stack 구조를 이 자리에 넣으시면 됩니다.
    // 현재는 간단한 예시로 대체합니다.
    return Center(
      child: Container(
        width: 350,
        height: 500,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          image: const DecorationImage(
            image: NetworkImage("https://placehold.co/350x500"),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleButton(Colors.red, Icons.close),
        const SizedBox(width: 24),
        _circleButton(Colors.blue, Icons.done),
      ],
    );
  }

  Widget _circleButton(Color color, IconData icon) {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }

  Widget _buildStats() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(children: [Text('남은 영화'), Text('7', style: TextStyle(fontSize: 24))]),
        SizedBox(width: 32),
        Column(children: [Text('봤어요'), Text('0', style: TextStyle(color: Colors.blue, fontSize: 24))]),
        SizedBox(width: 32),
        Column(children: [Text('안 봤어요'), Text('0', style: TextStyle(color: Colors.grey, fontSize: 24))]),
      ],
    );
  }
}