import os
import sqlite3
import httpx
from typing import List, Dict
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware

# 환경 변수 로드 (TMDB_API_KEY 저장 필요)
load_dotenv()

app = FastAPI(title="Movie Taste Analysis System")

# 1. CORS 설정 (Flutter 연동 필수)
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
    """연령대별 대표 영화 5편을 TMDB에서 가져와 질문으로 반환"""
    year_map = {"10-19": "2024", "20-29": "2018", "30-39": "2010", "40-49": "2003", "50-59": "1995", "60-69": "1985"}
    target_year = year_map.get(age_group, "2024")

    async with httpx.AsyncClient() as client:
        params = {
            "api_key": TMDB_API_KEY,
            "language": "ko-KR",
            "region": "KR",  # 한국 지역 제한
            "primary_release_year": target_year,
            "sort_by": "revenue.desc",  # 흥행(수익) 순 정렬
            "page": 1
        }
        response = await client.get(f"{BASE_URL}/discover/movie", params=params)
        movies = response.json().get("results", [])[:5]

        return [{
            "movie_id": m["id"],
            "title": m["title"],
            "poster_url": f"https://image.tmdb.org/t/p/w500{m['poster_path']}",
            "genre_ids": m["genre_ids"],
            "popularity": m["popularity"],
            "vote_average": m["vote_average"]
        } for m in movies]

@app.post("/recommend")
async def analyze_and_recommend(data: List[WatchAction]):
    """사용자가 본 영화들을 분석하여 4가지 지표(장르, 배우, 화제성, 별점) 기반 추천"""
    if not data:
        raise HTTPException(status_code=400, detail="응답 데이터가 없습니다.")

    watched_list = [m for m in data if m.is_watched]

    # 1. 취향 지표 초기화
    genre_counts = {}
    total_pop = 0
    total_vote = 0

    for m in watched_list:
        total_pop += m.popularity
        total_vote += m.vote_average
        for gid in m.genre_ids:
            genre_counts[gid] = genre_counts.get(gid, 0) + 1

    # 2. 취향 분석
    count = len(watched_list) if watched_list else 1
    avg_pop = total_pop / count
    avg_vote = total_vote / count
    top_genre = max(genre_counts, key=genre_counts.get) if genre_counts else None

    # 3. 분석 결과에 따른 추천 가중치 결정
    # 별점 7.5 이상 선호 시 '작품성', 화제성 100 이상 선호 시 '트렌드'
    if avg_vote > 7.5:
        taste_type = "별점(작품성)"
        sort_query = "vote_average.desc"
    elif avg_pop > 100:
        taste_type = "화제성(트렌드)"
        sort_query = "popularity.desc"
    else:
        taste_type = f"장르(ID:{top_genre})"
        sort_query = "popularity.desc"

    # 4. 분석된 취향으로 TMDB 최종 추천 영화 1편 쿼리
    async with httpx.AsyncClient() as client:
        rec_params = {
            "api_key": TMDB_API_KEY,
            "language": "ko-KR",
            "region": "KR",  # 한국 지역 제한
            "with_genres": top_genre,
            "sort_by": sort_query,
            "vote_count.gte": 100 # 한국 기준이므로 투표 수 제한 하향
        }
        res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
        final_movie = res.json().get("results", [])[0]

    return {
        "taste_analysis": {
            "primary_factor": taste_type,
            "avg_popularity": round(avg_pop, 2),
            "avg_rating": round(avg_vote, 2)
        },
        "recommendation": {
            "title": final_movie["title"],
            "overview": final_movie["overview"],
            "poster_url": f"https://image.tmdb.org/t/p/w500{final_movie['poster_path']}"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)