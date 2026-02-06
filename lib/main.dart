import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

void main() {
  runApp(const FigmaToCodeApp());
}

class Movie {
  final String title;
  final Color color;
  Movie({required this.title, required this.color});
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
      home: const MovieSwipeScreen(),
    );
  }
}

class MovieSwipeScreen extends StatefulWidget {
  const MovieSwipeScreen({super.key});

  @override
  State<MovieSwipeScreen> createState() => _MovieSwipeScreenState();
}

class _MovieSwipeScreenState extends State<MovieSwipeScreen> {
  final CardSwiperController controller = CardSwiperController();

  final List<Movie> movies = [
    Movie(title: '영화 1', color: Colors.redAccent),
    Movie(title: '영화 2', color: Colors.blueAccent),
    Movie(title: '영화 3', color: Colors.greenAccent),
    Movie(title: '영화 4', color: Colors.orangeAccent),
    Movie(title: '영화 5', color: Colors.purpleAccent),
  ];

  int watchedCount = 0;
  int unwatchedCount = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text(
              'MovieSwipe Test',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const Text('좌우로 스와이프하여 영화를 골라보세요'),

            Expanded(
              child: CardSwiper(
                controller: controller,
                cardsCount: movies.length,

                cardBuilder: (context, index) {
                  return _buildMovieCard(movies[index]);
                },

                onSwipe: (previousIndex, currentIndex, direction) {
                  setState(() {
                    if (direction == CardSwiperDirection.right) {
                      watchedCount++;
                    } else if (direction == CardSwiperDirection.left) {
                      unwatchedCount++;
                    }
                  });
                },
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                isLoop: true,
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _actionButton(Colors.red, Icons.close, () => controller.swipeLeft()),
                const SizedBox(width: 40),
                _actionButton(Colors.blue, Icons.done, () => controller.swipeRight()),
              ],
            ),
            const SizedBox(height: 30),

            Text(
              '봤어요: $watchedCount  |  안 봤어요: $unwatchedCount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(Movie movie) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: movie.color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10
          )
        ],
      ),
      child: Text(
        movie.title,
        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  Widget _actionButton(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70, height: 70,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 35),
      ),
    );
  }
}