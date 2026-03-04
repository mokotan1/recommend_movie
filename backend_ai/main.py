import os
import sqlite3
import httpx
import random
from typing import List
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware
from urllib.parse import quote

load_dotenv()

app = FastAPI(title="MovieSwipe AI")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

TMDB_API_KEY = os.getenv("TMDB_API_KEY")
BASE_URL = "https://api.themoviedb.org/3"
DB_PATH = "movie_app.db"


# ---------------- DB ----------------
def init_db():
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("""
        CREATE TABLE IF NOT EXISTS watched_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT,
            movie_id INTEGER,
            title TEXT,
            is_watched BOOLEAN,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
        """)
        conn.commit()

init_db()


# ---------------- 모델 ----------------
class WatchAction(BaseModel):
    user_id: str
    movie_id: int
    title: str
    genre_ids: List[int]
    popularity: float
    vote_average: float
    is_watched: bool


# ---------------- 추천 API ----------------
@app.post("/recommend")
async def recommend(data: List[WatchAction]):

    if not data:
        raise HTTPException(status_code=400, detail="데이터 없음")

    evaluated_ids = {m.movie_id for m in data}

    async with httpx.AsyncClient() as client:
        params = {
            "api_key": TMDB_API_KEY,
            "language": "ko-KR",
            "region": "KR",
            "sort_by": "vote_count.desc",
            "vote_count.gte": 500,
            "vote_average.gte": 8.0
        }

        res = await client.get(f"{BASE_URL}/discover/movie", params=params)
        results = res.json().get("results", [])

        filtered = [m for m in results if m["id"] not in evaluated_ids]

        if not filtered:
            raise HTTPException(status_code=404, detail="추천 영화 없음")

        final_movie = random.choice(filtered[:15])

        # -------- OTT 제공자 가져오기 (🚀 핵심: 서버에서 로직 처리) --------
        providers_list = []
        prov_res = await client.get(
            f"{BASE_URL}/movie/{final_movie['id']}/watch/providers",
            params={"api_key": TMDB_API_KEY}
        )

        if prov_res.status_code == 200:
            kr_data = prov_res.json().get("results", {}).get("KR", {})
            encoded_title = quote(final_movie["title"])

            for p in kr_data.get("flatrate", []):
                provider_name = p.get("provider_name", "").lower()
                logo_url = f"https://image.tmdb.org/t/p/original{p.get('logo_path')}"

                app_url = ""
                package_name = ""

                # 🚀 우리가 찾은 '무적의 OTT 연결 공식'을 파이썬에 적용!
                if "netflix" in provider_name:
                    app_url = f"https://www.netflix.com/search?q={encoded_title}"
                elif "disney" in provider_name:
                    app_url = f"https://www.disneyplus.com/search?q={encoded_title}"
                elif "watcha" in provider_name:
                    package_name = "com.frograms.watcha"
                elif "tving" in provider_name:
                    package_name = "net.cj.cjhv.gs.tving"
                elif "wavve" in provider_name or "pooq" in provider_name:
                    package_name = "kr.co.captv.pooqV2"
                elif "amazon" in provider_name or "prime" in provider_name:
                    package_name = "com.amazon.avod.thirdpartyclient"
                else:
                    continue # 기타 알 수 없는 OTT는 제외

                # 플러터 앱으로 정답(URL 또는 패키지명)을 내려줍니다.
                providers_list.append({
                    "name": p.get("provider_name"),
                    "logo_url": logo_url,
                    "app_url": app_url,
                    "package_name": package_name
                })

    return {
        "taste_analysis": {
            "primary_factor": "선호 장르 명작"
        },
        "recommendation": {
            "title": final_movie["title"],
            "overview": final_movie["overview"],
            "release_date": final_movie.get("release_date", ""),
            "poster_url": f"https://image.tmdb.org/t/p/w500{final_movie['poster_path']}",
            "providers": providers_list,
            "watch_link": kr_data.get("link", "") # 만약의 경우를 대비한 TMDB 링크 추가
        }
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)