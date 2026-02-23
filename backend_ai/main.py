import os
import sqlite3
import httpx
import random
import asyncio # 병렬 처리를 위해 추가된 모듈
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

def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute('CREATE TABLE IF NOT EXISTS users (user_id TEXT PRIMARY KEY, age_group TEXT)')
        conn.commit()

init_db()

class WatchAction(BaseModel):
    user_id: str
    movie_id: int
    title: str
    genre_ids: List[int]
    popularity: float
    vote_average: float
    is_watched: bool

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
            # 1. 장르, 인기도, 평점 분석
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

            # 배우 및 감독 데이터 수집 로직 (신규 핵심 기능)
            async def fetch_credits(movie_id):
                res = await client.get(f"{BASE_URL}/movie/{movie_id}/credits", params={"api_key": TMDB_API_KEY, "language": "ko-KR"})
                return res.json() if res.status_code == 200 else {}

            # 스와이프한 모든 영화의 출연진 정보를 동시에 긁어옴
            tasks = [fetch_credits(m.movie_id) for m in watched_list]
            credits_data = await asyncio.gather(*tasks)

            actor_counts = {}
            director_counts = {}

            for credits in credits_data:
                # 영화별 주연급 배우 상위 5명 추출
                for cast in credits.get("cast", [])[:5]:
                    a_id = cast["id"]
                    actor_counts[a_id] = actor_counts.get(a_id, {"count": 0, "name": cast["name"]})
                    actor_counts[a_id]["count"] += 1

                # 감독 추출
                for crew in credits.get("crew", []):
                    if crew["job"] == "Director":
                        d_id = crew["id"]
                        director_counts[d_id] = director_counts.get(d_id, {"count": 0, "name": crew["name"]})
                        director_counts[d_id]["count"] += 1

            # 가장 많이 겹치는 배우/감독 도출
            top_actor = max(actor_counts.values(), key=lambda x: x["count"], default={"count": 0}) if actor_counts else {"count": 0}
            top_director = max(director_counts.values(), key=lambda x: x["count"], default={"count": 0}) if director_counts else {"count": 0}

            top_actor_id = max(actor_counts, key=lambda k: actor_counts[k]["count"]) if actor_counts else None
            top_director_id = max(director_counts, key=lambda k: director_counts[k]["count"]) if director_counts else None

            # 감독이나 배우가 2번 이상 겹치면 그 인물을 기반으로 추천!
            if top_director["count"] >= 2:
                taste_type = f"'{top_director['name']}' 감독 마니아"
                rec_params["with_crew"] = top_director_id
                rec_params["vote_average.gte"] = 7.0 # 특정 인물 조건이 붙으면 결과가 안 나올 수 있으므로 평점 완화
            elif top_actor["count"] >= 2:
                taste_type = f"'{top_actor['name']}' 배우 팬"
                rec_params["with_cast"] = top_actor_id
                rec_params["vote_average.gte"] = 7.0
            elif top_genre:
                rec_params["with_genres"] = top_genre

        # 최종 추천 쿼리 날리기
        res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
        results = res.json().get("results", [])

        filtered = [m for m in results if m["id"] not in evaluated_movie_ids]

        # 특정 배우로 검색했는데 볼만한 영화가 없으면 장르로 재검색
        if not filtered and ("with_cast" in rec_params or "with_crew" in rec_params):
            rec_params.pop("with_cast", None)
            rec_params.pop("with_crew", None)
            rec_params["vote_average.gte"] = 8.0 # 다시 8.0 명작 기준으로 복귀
            if top_genre: rec_params["with_genres"] = top_genre

            res = await client.get(f"{BASE_URL}/discover/movie", params=rec_params)
            results = res.json().get("results", [])
            filtered = [m for m in results if m["id"] not in evaluated_movie_ids]
            taste_type = "선호 장르 명작" # 멘트도 원래대로 복구

        if filtered:
            final_movie = random.choice(filtered[:15])
        else:
            final_movie = results[0] if results else None

    if not final_movie:
        raise HTTPException(status_code=404, detail="추천 영화를 찾을 수 없습니다.")

    return {
        "taste_analysis": {"primary_factor": taste_type, "avg_popularity": round(avg_pop, 2), "avg_rating": round(avg_vote, 2)},
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