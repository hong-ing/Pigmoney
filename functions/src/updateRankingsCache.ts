import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

const db = admin.firestore();

const RANKING_LIMIT = 300;
const NICKNAME_CHUNK_SIZE = 30;

interface RankingEntry {
  rank: number;
  uid: string;
  nickname: string;
  score: number;
}

/**
 * 배열을 지정된 크기로 나누기
 * @template T
 * @param {Array<T>} array - 나눌 배열
 * @param {number} size - 각 청크의 크기
 * @return {Array<Array<T>>} 나눠진 배열의 배열
 */
function chunkArray<T>(array: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < array.length; i += size) {
    chunks.push(array.slice(i, i + size));
  }
  return chunks;
}

/**
 * 새벽 5시를 하루/한달의 시작으로 보는 게임 날짜의 dateKey, monthKey 계산 (KST 기준)
 * @return {{dateKey: string, monthKey: string}} 게임 날짜 키
 */
function getGameDateKeys(): { dateKey: string; monthKey: string } {
  const nowKst = new Date(Date.now() + 9 * 60 * 60 * 1000);
  const gameDate = nowKst.getHours() < 5 ?
    new Date(nowKst.getTime() - 24 * 60 * 60 * 1000) :
    nowKst;

  const year = gameDate.getFullYear();
  const month = String(gameDate.getMonth() + 1).padStart(2, "0");
  const day = String(gameDate.getDate()).padStart(2, "0");

  return {
    dateKey: `${year}-${month}-${day}`,
    monthKey: `${year}-${month}`,
  };
}

/**
 * 특정 랭킹 컬렉션에서 상위 300개를 조회하고 nickname을 보충하여 반환
 * @param {string} collectionPath - 랭킹 컬렉션 경로 (예: rankings/daily/2026-07-14)
 * @return {Promise<RankingEntry[]>} 순위가 매겨진 랭킹 목록
 */
async function fetchTopRankings(collectionPath: string): Promise<RankingEntry[]> {
  const qs = await db.collection(collectionPath)
    .orderBy("score", "desc")
    .limit(RANKING_LIMIT)
    .get();

  if (qs.empty) return [];

  // nickname이 없는 기존 데이터를 위한 fallback 처리
  const missingNicknames: Record<string, string> = {};
  const uidsToFetch: string[] = [];

  for (const doc of qs.docs) {
    const data = doc.data();
    if (data.nickname == null) {
      uidsToFetch.push(doc.id);
    }
  }

  if (uidsToFetch.length > 0) {
    for (const chunk of chunkArray(uidsToFetch, NICKNAME_CHUNK_SIZE)) {
      const usersQ = await db.collection("users")
        .where(admin.firestore.FieldPath.documentId(), "in", chunk)
        .get();

      for (const u of usersQ.docs) {
        missingNicknames[u.id] = (u.data().nickname as string | undefined) ?? u.id;
      }
    }
  }

  let rank = 1;
  return qs.docs.map((doc) => {
    const uid = doc.id;
    const data = doc.data();
    const score = (data.score as number | undefined) ?? 0;
    const nickname = (data.nickname as string | undefined) ?? missingNicknames[uid] ?? uid;

    return { rank: rank++, uid, nickname, score };
  });
}

/** 5분마다: 일별/월별 랭킹을 미리 계산해서 rankingsCache에 저장 */
export const updateRankingsCache = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    retryCount: 3,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const startTime = Date.now();
    const { dateKey, monthKey } = getGameDateKeys();

    console.log(`🏆 랭킹 캐시 갱신 시작... dateKey=${dateKey}, monthKey=${monthKey}`);

    const [dailyRankings, monthlyRankings] = await Promise.all([
      fetchTopRankings(`rankings/daily/${dateKey}`),
      fetchTopRankings(`rankings/monthly/${monthKey}`),
    ]);

    await Promise.all([
      db.doc("rankingsCache/daily_current").set({
        dateKey,
        rankings: dailyRankings,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      db.doc("rankingsCache/monthly_current").set({
        monthKey,
        rankings: monthlyRankings,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
    ]);

    const elapsedTime = Date.now() - startTime;
    console.log(
      `✅ 랭킹 캐시 갱신 완료: daily=${dailyRankings.length}명, monthly=${monthlyRankings.length}명, ` +
      `소요 시간=${elapsedTime}ms`
    );
  }
);
