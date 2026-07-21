import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();

/**
 * 스냅플레이 오퍼월 포인트 적립 콜백 API
 *
 * Request Parameters (실제 스냅플레이 파라미터):
 * - pKey: string - 매체 key
 * - userId: string - Firebase UID (사용자 식별값)
 * - advTitle: string - 광고 타이틀
 * - point: float - 사용자에게 지급되는 포인트
 * - payAmount: float - 매체에 지급되는 금액
 * - trId: string - 지급에 대한 고유 ID (중복 방지용)
 *
 * Response:
 * - status: "ok" (성공) | "error" (실패)
 * - message: 응답 메시지
 */
export const snapplayCallback = functions.onRequest(
  {
    region: "asia-northeast3",
    cors: false, // 스냅플레이 서버에서만 호출
  },
  async (req, res) => {
    // 변수를 try 블록 밖에서 선언하여 catch 블록에서도 접근 가능하게 함
    let userId: string | undefined;
    let trId: string | undefined;
    let point = 0;

    try {
      // 스냅플레이 서버 IP 검증 (스냅플레이에서 IP 제공시 활성화)
      // TODO: 스냅플레이에서 제공하는 실제 서버 IP로 변경
      const allowedIPs: string[] = [
        // 스냅플레이 서버 IP가 제공되면 여기에 추가
      ];

      const clientIP = req.headers["x-forwarded-for"] || req.connection.remoteAddress || "";
      const ip = Array.isArray(clientIP) ? clientIP[0] : clientIP.toString().split(",")[0].trim();

      // IP 검증 (프로덕션에서 활성화)
      if (allowedIPs.length > 0 && !allowedIPs.includes(ip)) {
        logger.warn("허용되지 않은 IP 접근", { ip });
        res.status(403).json({ status: "error", message: "Forbidden" });
        return;
      }

      // GET/POST 모두 지원 - 실제 스냅플레이 파라미터 이름
      const pKey = (req.query.pKey || req.body.pKey) as string; // string
      userId = (req.query.userId || req.body.userId) as string; // string (Firebase UID)
      const advTitle = (req.query.advTitle || req.body.advTitle || "") as string; // string
      point = Number(req.query.point || req.body.point || 0); // float
      const payAmount = Number(req.query.payAmount || req.body.payAmount || 0); // float
      trId = (req.query.trId || req.body.trId) as string; // string

      // 디버깅용 상세 로그
      logger.info("========== 스냅플레이 콜백 수신 시작 ==========");
      logger.info("Request Method:", req.method);
      logger.info("Request Headers:", JSON.stringify(req.headers));
      logger.info("Request Query:", JSON.stringify(req.query));
      logger.info("Request Body:", JSON.stringify(req.body));
      logger.info("Client IP:", ip);

      logger.info("파싱된 파라미터 값:", {
        pKey: `${pKey} (string)`,
        userId: `${userId} (string)`,
        advTitle: `${advTitle} (string)`,
        point: `${point} (float)`,
        payAmount: `${payAmount} (float)`,
        trId: `${trId} (string)`,
        ip,
      });

      // 필수 파라미터 검증
      const missingParams = [];
      if (!userId) missingParams.push("userId");
      if (!trId) missingParams.push("trId");

      if (missingParams.length > 0) {
        logger.error("필수 파라미터 누락 - 누락된 파라미터:", missingParams);
        logger.error("받은 파라미터 전체:", {
          pKey,
          userId,
          advTitle,
          point,
          payAmount,
          trId,
          rawQuery: req.query,
          rawBody: req.body
        });
        res.status(400).json({
          status: "error",
          message: "Missing required parameters"
        });
        return;
      }

      // 스냅플레이는 체크코드를 보내지 않는 것으로 보임
      // 필요시 나중에 추가 구현

      // 포인트 값 결정
      const pointsToGive = point;

      logger.info("포인트 값 검증:", {
        point: {
          raw: req.query.point || req.body.point,
          parsed: point,
          type: typeof point
        },
        finalPoints: pointsToGive,
        isValid: pointsToGive > 0
      });

      // 포인트가 0이거나 유효하지 않은 경우
      if (isNaN(pointsToGive) || pointsToGive <= 0) {
        logger.warn("포인트가 0이거나 유효하지 않음", {
          point,
          pointsToGive,
          rawQuery: req.query,
          rawBody: req.body
        });
        // 포인트가 0인 경우도 성공으로 처리
        res.status(200).json({
          status: "ok",
          message: "Success (0 points)"
        });
        return;
      }

      // 포인트를 정수로 변환
      const pointsToAdd = Math.floor(pointsToGive);

      // 중복 지급 방지를 위한 트랜잭션 ID 확인
      const transactionRef = db.doc(`snapplay_transactions/${trId}`);
      const transactionDoc = await transactionRef.get();

      if (transactionDoc.exists) {
        logger.warn("중복된 트랜잭션 ID", {
          trId,
          userId,
          point: pointsToAdd
        });
        // 이미 처리된 트랜잭션이므로 성공 응답
        res.status(200).json({
          status: "ok",
          message: "Already processed"
        });
        return;
      }

      // 사용자 존재 확인 (없는 사용자에 대한 생성은 하지 않음)
      logger.info("사용자 확인 시작 - userId:", userId);
      const userRef = db.doc(`users/${userId}`);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        logger.error("사용자를 찾을 수 없음", {
          userId,
          path: `users/${userId}`,
          userDocExists: userDoc.exists
        });
        res.status(404).json({
          status: "error",
          message: "User not found"
        });
        return;
      }

      const currentUserData = userDoc.data();
      logger.info("현재 사용자 데이터:", {
        userId,
        currentSnapPlayMoney: currentUserData?.snapPlayMoney || 0,
        currentRouletteMoney: currentUserData?.snapPlayRouletteMoney || 0,
        currentDiceMoney: currentUserData?.snapPlayDiceMoney || 0,
        userName: currentUserData?.nickname
      });

      // 트랜잭션으로 포인트 적립 처리
      await db.runTransaction(async (transaction) => {
        // 트랜잭션 기록 저장
        transaction.set(transactionRef, {
          userId,
          advTitle,
          point: pointsToAdd,
          payAmount,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 사용자 포인트 적립 (광고 제목으로 구분)
        // pig_roulette 오퍼월 관련 광고는 snapPlayRouletteMoney에 적립
        // 나머지는 snapPlayMoney에 적립
        const isRouletteAd = advTitle?.includes("룰렛") ||
                                   advTitle?.toLowerCase().includes("roulette") ||
                                   advTitle?.toLowerCase().includes("pig_roulette");

        const isDiceAd = advTitle?.includes("주사위") ||
                                    advTitle?.toLowerCase().includes("dice") ||
                                    advTitle?.toLowerCase().includes("pig_dice");

        if (isRouletteAd) {
          transaction.set(
            userRef,
            {
              snapPlayRouletteMoney: admin.firestore.FieldValue.increment(pointsToAdd),
            },
            { merge: true }
          );
        } else if (isDiceAd) {
          transaction.set(
            userRef,
            {
              snapPlayDiceMoney: admin.firestore.FieldValue.increment(pointsToAdd),
            },
            { merge: true }
          );
        } else {
          transaction.set(
            userRef,
            {
              snapPlayMoney: admin.firestore.FieldValue.increment(pointsToAdd),
            },
            { merge: true }
          );
        }
      });

      // 적립 후 확인
      const updatedDoc = await userRef.get();
      const updatedData = updatedDoc.data();

      logger.info("========== 스냅플레이 포인트 적립 완료 ==========");
      logger.info("적립 결과:", {
        userId,
        trId,
        pointsToAdd,
        advTitle,
        isRoulette: advTitle?.includes("룰렛") || advTitle?.toLowerCase().includes("roulette"),
        beforeSnapPlayMoney: currentUserData?.snapPlayMoney || 0,
        beforeRouletteMoney: currentUserData?.snapPlayRouletteMoney || 0,
        beforeDiceMoney: currentUserData?.snapPlayDiceMoney || 0,
        afterSnapPlayMoney: updatedData?.snapPlayMoney || 0,
        afterRouletteMoney: updatedData?.snapPlayRouletteMoney || 0,
        afterDiceMoney: updatedData?.snapPlayDiceMoney || 0,
      });

      // 성공 응답
      res.status(200).json({
        status: "ok",
        message: "Success"
      });
    } catch (error) {
      logger.error("========== 스냅플레이 콜백 처리 오류 ==========");
      logger.error("오류 상세:", {
        error: error instanceof Error ? error.message : error,
        stack: error instanceof Error ? error.stack : undefined,
        userId,
        trId,
        point
      });
      res.status(500).json({
        status: "error",
        message: "Internal server error"
      });
    }
  }
);
