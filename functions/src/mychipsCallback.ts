import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();

/**
 * 마이칩스 오퍼월 포인트 적립 콜백 API
 *
 * Request Parameters:
 * - user_id: Firebase UID (사용자 식별값)
 * - click_id: 클릭 식별값 (필수)
 * - user_payout_in_vc: 지급할 가상화폐(포인트) (float)
 * - user_payout: 사용자 지급액 (float)
 * - payout: 지급액 (float)
 * - postback_id: 전환/이벤트 고유 식별값 (integer)
 * - adunit_id: 애드유닛 ID (string)
 * - configured_event_id: 구성된 이벤트 ID (integer)
 * - campaign_id: 캠페인 ID (integer)
 * - event_name: 이벤트명 (string)
 *
 * Response:
 * - status: "ok" (성공) | "error" (실패)
 * - message: 응답 메시지
 */
export const mychipsCallback = functions.onRequest(
  {
    region: "asia-northeast3",
    cors: false, // 마이칩스 서버에서만 호출
  },
  async (req, res) => {
    // 변수를 try 블록 밖에서 선언하여 catch 블록에서도 접근 가능하게 함
    let userId: string | undefined;
    let clickId: string | undefined;
    let userPayoutInVc = 0;
    try {
      // 마이칩스 서버 IP 검증 (마이칩스에서 IP 제공시 활성화)
      // TODO: 마이칩스에서 제공하는 실제 서버 IP로 변경
      const allowedIPs: string[] = [
        "168.63.37.145",
        "20.54.96.37",
        "13.70.194.104",
        "34.146.139.91",
        "34.54.234.115",
        "34.54.248.253",
        "34.64.93.62",
        "34.47.93.43",
        "34.84.180.208",
        "48.209.163.104",
        "4.207.193.125",
        "48.209.162.122"
      ];

      const clientIP = req.headers["x-forwarded-for"] || req.connection.remoteAddress || "";
      const ip = Array.isArray(clientIP) ? clientIP[0] : clientIP.toString().split(",")[0].trim();

      // IP 검증 (프로덕션에서 활성화)
      if (allowedIPs.length > 0 && !allowedIPs.includes(ip)) {
        logger.warn("허용되지 않은 IP 접근", { ip });
        res.status(403).json({ status: "error", message: "Forbidden" });
        return;
      }

      // GET/POST 모두 지원 - 마이칩스 파라미터 타입
      userId = (req.query.user_id || req.body.user_id) as string; // string
      clickId = (req.query.click_id || req.body.click_id) as string; // string
      userPayoutInVc = Number(req.query.user_payout_in_vc || req.body.user_payout_in_vc || 0); // float
      const userPayout = Number(req.query.user_payout || req.body.user_payout || 0); // float
      const payout = Number(req.query.payout || req.body.payout || 0); // float
      const campaignId = Number(req.query.campaign_id || req.body.campaign_id || 0); // integer
      const postbackId = Number(req.query.postback_id || req.body.postback_id || 0); // integer
      const configuredEventId = Number(req.query.configured_event_id || req.body.configured_event_id || 0); // integer
      const adunitId = (req.query.adunit_id || req.body.adunit_id) as string; // string
      const eventName = (req.query.event_name || req.body.event_name || "") as string; // string

      // 디버깅용 상세 로그
      logger.info("========== 마이칩스 콜백 수신 시작 ==========");
      logger.info("Request Method:", req.method);
      logger.info("Request Headers:", JSON.stringify(req.headers));
      logger.info("Request Query:", JSON.stringify(req.query));
      logger.info("Request Body:", JSON.stringify(req.body));
      logger.info("Client IP:", ip);

      logger.info("파싱된 파라미터 값:", {
        userId: `${userId} (string)`,
        clickId: `${clickId} (string)`,
        userPayoutInVc: `${userPayoutInVc} (float)`,
        userPayout: `${userPayout} (float)`,
        payout: `${payout} (float)`,
        campaignId: `${campaignId} (integer)`,
        postbackId: `${postbackId} (integer)`,
        configuredEventId: `${configuredEventId} (integer)`,
        adunitId: `${adunitId} (string)`,
        eventName: `${eventName} (string)`,
        ip,
      });

      // 필수 파라미터 검증 (마이칩스 문서 기준)
      // 실제 필수: user_id, click_id
      // 나머지는 선택적이지만 일반적으로 전송됨
      const missingParams = [];
      if (!userId) missingParams.push("user_id");
      if (!clickId) missingParams.push("click_id");

      // 선택 파라미터 체크 (로깅용)
      const optionalParams = {
        userPayoutInVc: userPayoutInVc || 0,
        userPayout: userPayout || 0,
        payout: payout || 0,
        campaignId: campaignId || 0,
        postbackId: postbackId || 0,
        configuredEventId: configuredEventId || 0,
        adunitId: adunitId || "",
        eventName: eventName || ""
      };

      logger.info("선택 파라미터 상태:", optionalParams);

      if (missingParams.length > 0) {
        logger.error("필수 파라미터 누락 - 누락된 파라미터:", missingParams);
        logger.error("받은 파라미터 전체:", {
          userId,
          clickId,
          userPayoutInVc,
          userPayout,
          postbackId,
          adunitId,
          configuredEventId,
          campaignId,
          payout,
          rawQuery: req.query,
          rawBody: req.body
        });
        res.status(400).json({
          status: "error",
          message: "Missing required parameters"
        });
        return;
      }

      // 포인트 값 결정 (user_payout_in_vc 우선, 없으면 user_payout 사용)
      const pointsToGive = userPayoutInVc > 0 ? userPayoutInVc : (userPayout > 0 ? userPayout : 0);

      logger.info("포인트 값 검증:", {
        userPayoutInVc: {
          raw: req.query.user_payout_in_vc || req.body.user_payout_in_vc,
          parsed: userPayoutInVc,
          type: typeof userPayoutInVc
        },
        userPayout: {
          raw: req.query.user_payout || req.body.user_payout,
          parsed: userPayout,
          type: typeof userPayout
        },
        finalPoints: pointsToGive,
        isValid: pointsToGive > 0
      });

      // 포인트가 0이거나 유효하지 않은 경우
      if (isNaN(pointsToGive) || pointsToGive <= 0) {
        logger.warn("포인트가 0이거나 유효하지 않음", {
          userPayoutInVc,
          userPayout,
          pointsToGive,
          rawQuery: req.query,
          rawBody: req.body
        });
        // 포인트가 0인 경우도 성공으로 처리 (마이칩스 요구사항)
        res.status(200).json({
          status: "ok",
          message: "Success (0 points)"
        });
        return;
      }

      // 포인트를 정수로 변환
      const pointsToAdd = Math.floor(pointsToGive);

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
        currentMyChipsMoney: currentUserData?.myChipsMoney || 0,
        userName: currentUserData?.name
      });

      // pincruxCallback과 동일한 방식으로 포인트 적립
      logger.info("포인트 적립 시작:", {
        userId,
        pointsToAdd,
        beforeMoney: currentUserData?.myChipsMoney || 0
      });

      await userRef.set(
        {
          myChipsMoney: admin.firestore.FieldValue.increment(pointsToAdd),
        },
        { merge: true }
      );

      // 적립 후 확인
      const updatedDoc = await userRef.get();
      const updatedData = updatedDoc.data();

      logger.info("========== 마이칩스 포인트 적립 완료 ==========");
      logger.info("적립 결과:", {
        userId,
        clickId,
        pointsToAdd,
        campaignId,
        postbackId,
        beforeMoney: currentUserData?.myChipsMoney || 0,
        afterMoney: updatedData?.myChipsMoney || 0,
        actualIncrease: (updatedData?.myChipsMoney || 0) - (currentUserData?.myChipsMoney || 0)
      });

      // 성공 응답 (마이칩스 규격)
      res.status(200).json({
        status: "ok",
        message: "Success"
      });
    } catch (error) {
      logger.error("========== 마이칩스 콜백 처리 오류 ==========");
      logger.error("오류 상세:", {
        error: error instanceof Error ? error.message : error,
        stack: error instanceof Error ? error.stack : undefined,
        userId,
        clickId,
        userPayoutInVc
      });
      res.status(500).json({
        status: "error",
        message: "Internal server error"
      });
    }
  }
);
