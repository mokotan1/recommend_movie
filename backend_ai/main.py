import os
import sqlite3
import httpx
import random
from typing import List, Dict
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware

# 환경 변수 로드
load_dotenv()

app = FastAPI(title="Korea-Released Masterpiece Recommend System")

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 설정 및 DB 초기화 ---
TMDB_API_KEY = os.getenv("TMDB_API_KEY")
BASE_URL = "https://api.themoviedb.org/3"
DB_PATH = "movie_app.db"

def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                user_id TEXT PRIMARY KEY,
                age_group TEXT
            )
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS watched_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT,
                movie_id INTEGER,
                title TEXT,
                genre_ids TEXT,
                popularity REAL,
                vote_average REAL,
                FOREIGN KEY (user_id) REFERENCES users (user_id)
            )
        ''')
        conn.commit()

init_db()

# --- 데이터 모델 ---
class SocialLogin(BaseModel):
    user_id: str
    age_group: str

class WatchAction(BaseModel):
    user_id: str
    movie_id: int
    title: str
    genre_ids: List[int]
    popularity: float
    vote_average: float
    is_watched: bool

# --- API 엔드포인트 ---

@app.post("/login")
async def login(data: SocialLogin):
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO users (user_id, age_group) VALUES (?, ?)",
                       (data.user_id, data.age_group))
    return {"status": "success", "age_group": data.age_group}

@app.get("/questions/{age_group}")
async def get_movie_questions(age_group: str):
    """연령대별 대표 영화 10편을 한국 개봉작 중에서 '완전히 랜덤'하게 추출"""
    year_map = {"10-19": "2024", "20-29": "2018", "30-39": "2010", "40-49": "2003", "50-59": "1995", "60-69": "1985"}
    target_year = year_map.get(age_group, "2024")

    async with httpx.AsyncClient() as client:
        params = {
            "api_key": TMDB_API_KEY,
            "language": "ko-KR",
            "region": "KR", # 한국 개봉작 조건 유지
            "primary_release_year": target_year,
            "vote_count.gte": 100, # 👉 무작위로 뽑더라도 최소한의 대중성 보장
            "sort_by": "popularity.desc",
            "page": random.randint(1, 40) # 👉 1~40페이지(약 800편)로 후보군 대폭 확장
        }
        response = await client.get(f"{BASE_URL}/discover/movie", params=params)
        results = response.json().get("results", [])

        # 👉 한 페이지(최대 20개) 내에서 10개를 완전히 무작위로 추출 및 순서 셔플
        if len(results) >= 10:
            movies = random.sample(results, 10)
        else:
            movies = results

        return [{
            "movie_id": m["id"],
            "title": m["title"],
            "poster_url": f"https://image.tmdb.org/t/p/w500{m['poster_path']}" if m.get('poster_path') else "",
            "genre_ids": m["genre_ids"],
            "popularity": m["popularity"],
            "vote_average": m["vote_average"]
        } for m in movies]

@app.post("/recommend")
async def analyze_and_recommend(data: List[WatchAction]):
    """분석된 취향으로 한국 개봉작 중 평점 8.0 이상의 명작 추천"""
    if not data:
        raise HTTPException(status_code=400, detail="응답 데이터가 없습니다.")

    # 추천 시 방금 본 영화 제외를 위한 리스트
    evaluated_movie_ids = {m.movie_id for m in data}
    watched_list = [m for m in data if m.is_watched]

    # 기본 추천 조건: 한국 개봉작 + 평점 8.0 이상 + 투표수 500 이상
    rec_params = {
        "api_key": TMDB_API_KEY,
        "language": "ko-KR",
        "region": "KR",
        "sort_by": "vote_count.desc",
        "vote_count.gte": 500,
        "vote_average.gte": 8.0
    }

    if not watched_list:
        # 전부 왼쪽 스와이프 시 처리
        taste_type = "확고한 주관"
        top_genre = None
        avg_pop, avg_vote = 0.0, 0.0
    else:
        genre_counts = {}
        total_pop, total_vote = 0, 0

        for m in watched_list:
            total_pop += m.popularity
            total_vote += m.vote_average
            for gid in m.genre_ids:
                genre_counts[gid] = genre_counts.get(gid, 0) + 1

        count = len(watched_list)
        avg_pop = total_pop / count
        avg_vote = total_vote / count
        top_genre = max(genre_counts, key=genre_counts.get) if genre_counts else None
        taste_type = "선호 장르 명작"

    async with httpx.AsyncClient() as client:
        if top_genre:
            rec_params["with_genres"] = top_genre

        res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
        results = res.json().get("results", [])

        # 방금 질문으로 나온 영화들은 추천 결과에서 깔끔하게 제외
        filtered = [m for m in results if m["id"] not in evaluated_movie_ids]

        if filtered:
            # 상위 15개 추천작 중 랜덤하게 골라 매번 색다른 결과 제공
            final_movie = random.choice(filtered[:15])
        else:
            final_movie = results[0] if results else None

    if not final_movie:
        raise HTTPException(status_code=404, detail="추천 영화를 찾을 수 없습니다.")

    return {
        "taste_analysis": {
            "primary_factor": taste_type,
            "avg_popularity": round(avg_pop, 2),
            "avg_rating": round(avg_vote, 2)
        },
        "recommendation": {
            "title": final_movie["title"],
            "overview": final_movie["overview"],
            "release_date": final_movie.get("release_date", "미정"),
            "poster_url": f"https://image.tmdb.org/t/p/w500{final_movie['poster_path']}" if final_movie.get('poster_path') else ""
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)