import os
import sqlite3
import httpx
import random
import asyncio
from typing import List, Dict
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware

load_dotenv()

app = FastAPI(title="Advanced Movie Recommend System")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

TMDB_API_KEY = os.getenv("TMDB_API_KEY")
BASE_URL = "https://api.themoviedb.org/3"
DB_PATH = "movie_app.db"

# --- DB 초기화 (timeout=5.0 적용 완료) ---
def init_db():
    with sqlite3.connect(DB_PATH, timeout=5.0) as conn:
        cursor = conn.cursor()

        # 1. users 테이블
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                social_id TEXT UNIQUE,
                social_provider TEXT,
                age_group TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # 2. watched_history 테이블
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS watched_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT,
                movie_id INTEGER,
                title TEXT,
                history_genre_ids TEXT,
                popularity REAL,
                vote_average REAL,
                is_watched BOOLEAN,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # 3. recommended_history 테이블
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS recommended_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT,
                taste_type TEXT,
                recommended_genre_ids TEXT,
                recommended_movie_id INTEGER,
                recommended_movie_title TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()

init_db()

# --- 데이터 모델 ---
class SocialLogin(BaseModel):
    user_id: str
    social_provider: str
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
    """소셜 로그인 시 제공자(provider)와 함께 DB에 기록"""
    with sqlite3.connect(DB_PATH, timeout=5.0) as conn:
        cursor = conn.cursor()

        cursor.execute("SELECT id FROM users WHERE social_id = ?", (data.user_id,))
        row = cursor.fetchone()

        if row:
            user_db_id = row[0]
            cursor.execute("UPDATE users SET age_group = ?, social_provider = ? WHERE id = ?",
                           (data.age_group, data.social_provider, user_db_id))
        else:
            cursor.execute("INSERT INTO users (social_id, social_provider, age_group) VALUES (?, ?, ?)",
                           (data.user_id, data.social_provider, data.age_group))
            user_db_id = cursor.lastrowid

        conn.commit()

    return {"status": "success", "user_sequence_id": user_db_id, "age_group": data.age_group}

@app.get("/questions/{age_group}")
async def get_movie_questions(age_group: str):
    year_map = {"10-19": "2024", "20-29": "2018", "30-39": "2010", "40-49": "2003", "50-59": "1995", "60-69": "1985"}
    target_year = year_map.get(age_group, "2024")

    async with httpx.AsyncClient() as client:
        params = {
            "api_key": TMDB_API_KEY,
            "language": "ko-KR",
            "region": "KR",
            "primary_release_year": target_year,
            "vote_count.gte": 100,
            "sort_by": "popularity.desc",
            "page": random.randint(1, 40)
        }
        response = await client.get(f"{BASE_URL}/discover/movie", params=params)
        results = response.json().get("results", [])

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
    if not data:
        raise HTTPException(status_code=400, detail="데이터가 없습니다.")

    evaluated_movie_ids = {m.movie_id for m in data}
    watched_list = [m for m in data if m.is_watched]

    current_user_id = data[0].user_id if data else "unknown"

    rec_params = {
        "api_key": TMDB_API_KEY,
        "language": "ko-KR",
        "region": "KR",
        "sort_by": "vote_count.desc",
        "vote_count.gte": 500,
        "vote_average.gte": 8.0
    }

    taste_type = "선호 장르 명작"
    avg_pop, avg_vote = 0.0, 0.0

    async with httpx.AsyncClient() as client:
        if not watched_list:
            taste_type = "확고한 주관"
            top_genre = None
        else:
            genre_counts = {}
            total_pop, total_vote = 0, 0
            for m in watched_list:
                total_pop += m.popularity
                total_vote += m.vote_average
                for gid in m.genre_ids:
                    genre_counts[gid] = genre_counts.get(gid, 0) + 1

            count = len(watched_list)
            avg_pop, avg_vote = total_pop / count, total_vote / count
            top_genre = max(genre_counts, key=genre_counts.get) if genre_counts else None

            async def fetch_credits(movie_id):
                res = await client.get(f"{BASE_URL}/movie/{movie_id}/credits", params={"api_key": TMDB_API_KEY, "language": "ko-KR"})
                return res.json() if res.status_code == 200 else {}

            tasks = [fetch_credits(m.movie_id) for m in watched_list]
            credits_data = await asyncio.gather(*tasks)

            actor_counts = {}
            director_counts = {}

            for credits in credits_data:
                for cast in credits.get("cast", [])[:5]:
                    a_id = cast["id"]
                    actor_counts[a_id] = actor_counts.get(a_id, {"count": 0, "name": cast["name"]})
                    actor_counts[a_id]["count"] += 1

                for crew in credits.get("crew", []):
                    if crew["job"] == "Director":
                        d_id = crew["id"]
                        director_counts[d_id] = director_counts.get(d_id, {"count": 0, "name": crew["name"]})
                        director_counts[d_id]["count"] += 1

            top_actor = max(actor_counts.values(), key=lambda x: x["count"], default={"count": 0}) if actor_counts else {"count": 0}
            top_director = max(director_counts.values(), key=lambda x: x["count"], default={"count": 0}) if director_counts else {"count": 0}

            top_actor_id = max(actor_counts, key=lambda k: actor_counts[k]["count"]) if actor_counts else None
            top_director_id = max(director_counts, key=lambda k: director_counts[k]["count"]) if director_counts else None

            if top_director["count"] >= 2:
                taste_type = f"'{top_director['name']}' 감독 마니아"
                rec_params["with_crew"] = top_director_id
                rec_params["vote_average.gte"] = 7.0
            elif top_actor["count"] >= 2:
                taste_type = f"'{top_actor['name']}' 배우 팬"
                rec_params["with_cast"] = top_actor_id
                rec_params["vote_average.gte"] = 7.0
            elif top_genre:
                rec_params["with_genres"] = top_genre

        res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
        results = res.json().get("results", [])

        filtered = [m for m in results if m["id"] not in evaluated_movie_ids]

        if not filtered and ("with_cast" in rec_params or "with_crew" in rec_params):
            rec_params.pop("with_cast", None)
            rec_params.pop("with_crew", None)
            rec_params["vote_average.gte"] = 8.0
            if top_genre: rec_params["with_genres"] = top_genre

            res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
            results = res.json().get("results", [])
            filtered = [m for m in results if m["id"] not in evaluated_movie_ids]
            taste_type = "선호 장르 명작"

        if filtered:
            final_movie = random.choice(filtered[:15])
        else:
            final_movie = results[0] if results else None

    if not final_movie:
        raise HTTPException(status_code=404, detail="추천 영화를 찾을 수 없습니다.")

    # --- OTT(스트리밍) 제공자 정보 가져오기 ---
    providers_list = []
    watch_link = ""
    async with httpx.AsyncClient() as client:
        prov_res = await client.get(f"{BASE_URL}/movie/{final_movie['id']}/watch/providers", params={"api_key": TMDB_API_KEY})
        if prov_res.status_code == 200:
            kr_data = prov_res.json().get("results", {}).get("KR", {})
            watch_link = kr_data.get("link", "") # TMDB 자체 OTT 안내 링크

            # 정액제(스트리밍) 서비스 리스트 추출 (넷플릭스, 왓챠, 디즈니+ 등)
            for p in kr_data.get("flatrate", []):
                providers_list.append({
                    "name": p.get("provider_name"),
                    "logo_url": f"https://image.tmdb.org/t/p/original{p.get('logo_path')}"
                })

    # --- 업데이트된 DB 기록 로직 (timeout=5.0 적용) ---
    with sqlite3.connect(DB_PATH, timeout=5.0) as conn:
        cursor = conn.cursor()

        # 1. 평가(질문)로 쓰인 영화들 저장 (history_genre_ids 사용)
        for m in data:
            cursor.execute('''
                INSERT INTO watched_history 
                (user_id, movie_id, title, history_genre_ids, popularity, vote_average, is_watched) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (current_user_id, m.movie_id, m.title, str(m.genre_ids), m.popularity, m.vote_average, m.is_watched))

        # 2. 최종 추천된 영화 결과 저장 (recommended_history 테이블 & recommended_genre_ids 사용)
        cursor.execute('''
            INSERT INTO recommended_history 
            (user_id, taste_type, recommended_genre_ids, recommended_movie_id, recommended_movie_title) 
            VALUES (?, ?, ?, ?, ?)
        ''', (current_user_id, taste_type, str(final_movie.get("genre_ids", [])), final_movie["id"], final_movie["title"]))

        conn.commit()

    return {
        "taste_analysis": {"primary_factor": taste_type, "avg_popularity": round(avg_pop, 2), "avg_rating": round(avg_vote, 2)},
        "recommendation": {
            "title": final_movie["title"],
            "overview": final_movie["overview"],
            "release_date": final_movie.get("release_date", "미정"),
            "poster_url": f"https://image.tmdb.org/t/p/w500{final_movie['poster_path']}" if final_movie.get('poster_path') else "",
            "providers": providers_list,
            "watch_link": watch_link
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)