// functions/src/resetDaily.ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

const db = admin.firestore();

interface ResetResult {
  userId: string;
  success: boolean;
  error?: unknown;  // any 대신 unknown 사용
  attempts: number;
}

/**
 * 사용자 데이터가 올바르게 리셋되었는지 검증
 * @param {Record<string, unknown>} userData - 검증할 사용자 데이터
 * @param {string} expectedDateLabel - 예상되는 날짜 라벨
 * @return {boolean} 리셋이 올바르게 되었으면 true
 */
function validateReset(userData: Record<string, unknown>, expectedDateLabel: string): boolean {
  // 1. 필드 값 검증
  if (userData.luckyBagCount !== 200) return false;
  if (userData.rewardRefillCount !== 50) return false;
  if (userData.resetVersion !== expectedDateLabel) return false;

  // 2. attendanceData 검증
  const attendanceData = userData.attendanceData as Record<string, unknown>;
  if (!attendanceData || !attendanceData.slots) return false;

  const slots = attendanceData.slots as Array<Record<string, unknown>>;
  if (slots.length !== 3) return false;

  // 3. 각 슬롯 검증
  for (const slot of slots) {
    if (slot.status !== 0 || slot.reward !== 0 || slot.coinType !== 0) return false;
    const slotId = slot.id as string;
    if (!slotId.includes(expectedDateLabel)) return false;
  }

  return true;
}

/**
 * 단일 사용자의 일일 데이터를 리셋
 * @param {admin.firestore.DocumentReference} userRef - 사용자 문서 레퍼런스
 * @param {string} dateLabel - 리셋할 날짜 라벨
 * @param {number} attemptNumber - 시도 횟수
 * @return {Promise<ResetResult>} 리셋 결과
 */
async function resetSingleUser(
  userRef: admin.firestore.DocumentReference,
  dateLabel: string,
  attemptNumber: number
): Promise<ResetResult> {
  const userId = userRef.id;

  try {
    // 게임 날짜 기준으로 슬롯 데이터 생성
    const defaultSlots = [
      { id: `morning-${dateLabel}`, timeName: "아침",  timeRangeLabel: "07-10시",  startHour: 7,  endHour: 10, status: 0, coinType: 0, reward: 0 },
      { id: `dinner-${dateLabel}`,  timeName: "저녁",  timeRangeLabel: "19-22시", startHour: 19, endHour: 22, status: 0, coinType: 0, reward: 0 },
      { id: `all-${dateLabel}`,     timeName: "완벽출석", timeRangeLabel:"한번더!",   startHour: 0,  endHour: 0, status: 0, coinType: 0, reward: 0 },
    ];

    // 업데이트 실행
    await userRef.update({
      "luckyBagCount": 200,
      "rewardRefillCount": 50,
      "pigBankBreakLevel": 0,
      "autoEarnPigLevel": 1,
      "resetVersion": dateLabel,
      "attendanceData": {
        showAllClearCelebration: false,
        slots: defaultSlots,
      },
      // 만보기 데이터 리셋 (걸음수는 자정 리셋 - resetStepsAtMidnight에서 처리)
      "workData.currentRound": 1,
      "workData.state": "idle",
      "workData.timerStartTime": null,
      "workData.pendingReward": 0,
      "workData.lastResetDate": dateLabel,
    });

    // 업데이트 후 즉시 검증
    const updatedDoc = await userRef.get();
    const updatedData = updatedDoc.data();

    if (!updatedData || !validateReset(updatedData, dateLabel)) {
      throw new Error("업데이트 후 검증 실패");
    }

    return { userId, success: true, attempts: attemptNumber };
  } catch (error) {
    console.error(`❌ 사용자 ${userId} 리셋 실패 (시도 ${attemptNumber}):`, error);
    return { userId, success: false, error, attempts: attemptNumber };
  }
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

/** 매일 05:00 KST : 출석, 행운상자, 리필 모두 초기화 */
export const resetDailyFields = onSchedule(
  {
    schedule: "0 5 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    retryCount: 3,
    memory: "2GiB", // 메모리 증가
    timeoutSeconds: 540, // 타임아웃 9분으로 증가
  },
  async () => {
    const startTime = Date.now();
    console.log("🔄 일일 리셋 시작...");

    // ✅ 클라이언트와 동일한 게임 날짜 계산
    const nowKst = new Date(Date.now() + 9 * 60 * 60 * 1000);
    const gameDate = nowKst.getHours() < 5 ?
      new Date(nowKst.getTime() - 24 * 60 * 60 * 1000) :
      nowKst;

    const year = gameDate.getFullYear();
    const month = String(gameDate.getMonth() + 1).padStart(2, "0");
    const day = String(gameDate.getDate()).padStart(2, "0");
    const dateLabel = `${year}-${month}-${day}`;

    console.log(`📅 리셋 날짜: ${dateLabel}`);

    // 1단계: 모든 사용자 문서 레퍼런스 가져오기
    const userRefs = await db.collection("users").listDocuments();
    console.log(`👥 총 사용자 수: ${userRefs.length}`);

    // 2단계: 배치 처리 (500명씩)
    const BATCH_SIZE = 500;
    const userChunks = chunkArray(userRefs, BATCH_SIZE);
    console.log(`📦 배치 수: ${userChunks.length}개 (${BATCH_SIZE}명씩)`);

    let totalSuccess = 0;
    let totalFailed = 0;
    const allFailedUserIds: string[] = [];

    for (let i = 0; i < userChunks.length; i++) {
      const chunk = userChunks[i];
      console.log(`🔄 배치 ${i + 1}/${userChunks.length} 처리 중... (${chunk.length}명)`);

      // 배치 내 사용자 리셋
      const results = await Promise.all(
        chunk.map((ref) => resetSingleUser(ref, dateLabel, 1))
      );

      const successCount = results.filter((r) => r.success).length;
      const failedResults = results.filter((r) => !r.success);

      totalSuccess += successCount;

      // 실패한 사용자 재시도 (최대 2회)
      if (failedResults.length > 0) {
        console.log(`  ⚠️ 배치 ${i + 1} 실패: ${failedResults.length}명, 재시도 중...`);

        const failedRefs = failedResults.map((r) => {
          const ref = chunk.find((ref) => ref.id === r.userId);
          return ref;
        }).filter((ref): ref is admin.firestore.DocumentReference => ref !== undefined);

        // 1초 대기 후 재시도
        await new Promise((resolve) => setTimeout(resolve, 1000));

        const retryResults = await Promise.all(
          failedRefs.map((ref) => resetSingleUser(ref, dateLabel, 2))
        );

        const retrySuccess = retryResults.filter((r) => r.success).length;
        totalSuccess += retrySuccess;

        const stillFailed = retryResults.filter((r) => !r.success);
        totalFailed += stillFailed.length;
        allFailedUserIds.push(...stillFailed.map((r) => r.userId));
      }

      console.log(`  ✅ 배치 ${i + 1} 완료: 성공 ${successCount + (failedResults.length > 0 ? 0 : 0)}명`);

      // 메모리 해제를 위한 짧은 대기 (배치 간)
      if (i < userChunks.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }

    // 3단계: 결과 로깅
    const elapsedTime = Date.now() - startTime;
    console.log("📊 최종 리셋 결과:");
    console.log(`✅ 성공: ${totalSuccess}/${userRefs.length}명`);
    console.log(`❌ 실패: ${totalFailed}명`);
    console.log(`⏱️ 소요 시간: ${elapsedTime}ms (${Math.round(elapsedTime / 1000)}초)`);

    // 실패한 사용자 상세 로깅
    if (allFailedUserIds.length > 0) {
      console.error("🚨 리셋 실패 사용자 ID:", allFailedUserIds.slice(0, 50)); // 최대 50개만 로깅

      // 심각한 오류인 경우 알림 (예: 10% 이상 실패)
      if (allFailedUserIds.length > userRefs.length * 0.1) {
        console.error("🚨🚨🚨 심각: 10% 이상의 사용자 리셋 실패!");
      }
    }

    // 성공률이 낮은 경우 에러 throw (Functions가 재시도하도록)
    if (totalSuccess < userRefs.length * 0.95) {
      throw new Error(`리셋 성공률이 95% 미만: ${totalSuccess}/${userRefs.length}`);
    }

    console.log("✅ 일일 리셋 완료!");
  }
);

/** 매일 00:00 KST : 걸음수만 자정 리셋 */
export const resetStepsAtMidnight = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "Asia/Seoul",
    region: "asia-northeast3",
    retryCount: 3,
    memory: "1GiB",
    timeoutSeconds: 300,
  },
  async () => {
    const startTime = Date.now();
    console.log("🔄 걸음수 자정 리셋 시작...");

    const userRefs = await db.collection("users").listDocuments();
    console.log(`👥 총 사용자 수: ${userRefs.length}`);

    const BATCH_SIZE = 500;
    const userChunks = chunkArray(userRefs, BATCH_SIZE);
    let totalSuccess = 0;
    let totalFailed = 0;

    for (let i = 0; i < userChunks.length; i++) {
      const chunk = userChunks[i];
      console.log(`🔄 배치 ${i + 1}/${userChunks.length} 처리 중... (${chunk.length}명)`);

      const results = await Promise.all(
        chunk.map(async (ref) => {
          try {
            await ref.update({
              "workData.accumulatedSteps": 0,
            });
            return { success: true };
          } catch (error) {
            console.error(`❌ 사용자 ${ref.id} 걸음수 리셋 실패:`, error);
            return { success: false, userId: ref.id };
          }
        })
      );

      totalSuccess += results.filter((r) => r.success).length;
      totalFailed += results.filter((r) => !r.success).length;

      if (i < userChunks.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }

    const elapsedTime = Date.now() - startTime;
    console.log("📊 걸음수 리셋 결과:");
    console.log(`✅ 성공: ${totalSuccess}/${userRefs.length}명`);
    console.log(`❌ 실패: ${totalFailed}명`);
    console.log(`⏱️ 소요 시간: ${elapsedTime}ms (${Math.round(elapsedTime / 1000)}초)`);

    if (totalSuccess < userRefs.length * 0.95) {
      throw new Error(`걸음수 리셋 성공률이 95% 미만: ${totalSuccess}/${userRefs.length}`);
    }

    console.log("✅ 걸음수 자정 리셋 완료!");
  }
);
