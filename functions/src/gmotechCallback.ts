import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();

/**
 * GMO TECH (SmaAD) 오퍼월 포인트 적립 콜백 API
 *
 * Request Parameters:
 * - user: Firebase UID (사용자 고유 ID, 필수)
 * - adid: 광고 ID (SmaAD 관리)
 * - title: 광고 캠페인명
 * - orders_id: 성과 ID (성과별 유니크 ID)
 * - pay: 매체 리워드 단가(엔)
 * - m_pay: 매체 보상액(원) - 원화 거래 시 사용
 * - user_pay: 유저 리워드 금액(엔)
 * - m_user_pay: 사용자 보상액(원) - 원화 거래 시 사용 (우선 사용)
 * - user_pay2: 유저 리워드 금액(매체 지정 포인트)
 * - time_utc: 성과 발생 일시(UTC, yyyymmddhhmmss)
 * - time_jst: 성과 발생 일시(JST, yyyymmddhhmmss)
 * - approved: 승인 상태 (0: 미승인, 1: 승인, 2: 거부)
 * - course_id: 코스 ID (멀티스테이지 캠페인용, 최대 128자)
 *
 * Response:
 * - HTTP 200 (성공)
 */
export const gmotechCallback = functions.onRequest(
  {
    region: "asia-northeast3",
    cors: false, // GMO TECH 서버에서만 호출
  },
  async (req, res) => {
    try {
      // GMO TECH (SmaAD) 서버 IP 검증
      const allowedIPs = ["54.199.216.236", "54.199.242.223"];
      const clientIP = req.headers["x-forwarded-for"] || req.connection.remoteAddress || "";
      const ip = Array.isArray(clientIP) ? clientIP[0] : clientIP.toString().split(",")[0].trim();

      if (!allowedIPs.includes(ip)) {
        logger.warn("허용되지 않은 IP 접근 (GMO TECH)", { ip });
        res.status(403).send("Forbidden");
        return;
      }

      // GET 방식으로 전송되는 파라미터 받기
      const user = req.query.user as string;
      const adid = req.query.adid as string;
      const title = req.query.title as string;
      const ordersId = req.query.orders_id as string;
      const pay = req.query.pay as string;
      const mPay = req.query.m_pay as string;
      const userPay = req.query.user_pay as string;
      const mUserPay = req.query.m_user_pay as string;
      const userPay2 = req.query.user_pay2 as string;
      const timeUtc = req.query.time_utc as string;
      const timeJst = req.query.time_jst as string;
      const approved = req.query.approved as string;
      const courseId = req.query.course_id as string;

      logger.info("========== GMO TECH 콜백 수신 ==========");
      logger.info("파라미터:", {
        user,
        adid,
        title,
        ordersId,
        pay,
        mPay,
        userPay,
        mUserPay,
        userPay2,
        timeUtc,
        timeJst,
        approved,
        courseId,
        ip
      });

      // 필수 파라미터 검증
      if (!user) {
        logger.error("필수 파라미터 누락: user");
        res.status(400).send("Bad Request: Missing user parameter");
        return;
      }

      // approved 파라미터 검증 - "1"(승인)인 경우에만 포인트 적립
      // 0: 미승인, 1: 승인, 2: 거부
      if (approved !== "1") {
        logger.info("비승인 상태 - 포인트 적립 안 함", {
          user,
          ordersId,
          approved: approved || "undefined",
          reason: approved === "0" ? "미승인" : approved === "2" ? "거부" : "승인 아님"
        });
        res.status(200).send("OK");
        return;
      }

      // approved === "1" (승인) - 포인트 적립 진행
      logger.info("승인 상태 확인 - 포인트 적립 진행", { user, ordersId });

      // 포인트 값 결정 (원화 우선)
      const pointsToGive = parseInt(userPay2);


      logger.info("포인트 값 결정:", {
        mUserPay,
        userPay2,
        userPay,
        finalPoints: pointsToGive
      });

      // 포인트가 0이거나 유효하지 않은 경우
      if (isNaN(pointsToGive) || pointsToGive <= 0) {
        logger.warn("포인트가 0이거나 유효하지 않음", {
          mUserPay,
          userPay2,
          userPay,
          pointsToGive
        });
        // 포인트가 0인 경우도 성공으로 처리
        res.status(200).send("OK");
        return;
      }

      // 사용자 존재 확인
      const userRef = db.doc(`users/${user}`);
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        logger.error("사용자를 찾을 수 없음", { user });
        res.status(404).send("User not found");
        return;
      }

      const currentUserData = userDoc.data();
      logger.info("현재 사용자 데이터:", {
        user,
        currentGmotechMoney: currentUserData?.gmotechMoney || 0,
        nickname: currentUserData?.nickname
      });

      // 포인트 적립
      logger.info("포인트 적립 시작:", {
        user,
        pointsToGive,
        ordersId,
        adid,
        title,
        beforeMoney: currentUserData?.gmotechMoney || 0
      });

      await userRef.set(
        {
          gmotechMoney: admin.firestore.FieldValue.increment(pointsToGive),
        },
        { merge: true }
      );

      // 적립 후 확인
      const updatedDoc = await userRef.get();
      const updatedData = updatedDoc.data();

      logger.info("========== GMO TECH 포인트 적립 완료 ==========");
      logger.info("적립 결과:", {
        user,
        ordersId,
        pointsToGive,
        adid,
        title,
        beforeMoney: currentUserData?.gmotechMoney || 0,
        afterMoney: updatedData?.gmotechMoney || 0,
        actualIncrease: (updatedData?.gmotechMoney || 0) - (currentUserData?.gmotechMoney || 0)
      });

      // 성공 응답 (GMO TECH 규격: HTTP 200)
      res.status(200).send("OK");
    } catch (error) {
      logger.error("========== GMO TECH 콜백 처리 오류 ==========");
      logger.error("오류 상세:", {
        error: error instanceof Error ? error.message : error,
        stack: error instanceof Error ? error.stack : undefined
      });
      res.status(500).send("Internal Server Error");
    }
  }
);
