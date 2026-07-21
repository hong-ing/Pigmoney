import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();

/**
 * 핀크럭스 오퍼월 포인트 적립 콜백 API
 *
 * Request Parameters:
 * - appkey: 광고 코드 (최대 40자리)
 * - pubkey: 매체 코드 (6자리, 우리는 912065)
 * - usrkey: Firebase UID (사용자 식별값)
 * - app_title: 광고 제목
 * - coin: 지급할 포인트
 * - transid: 핀크럭스 트랜잭션 ID (최대 40자리)
 * - resign_flag: 중복 지급 허용 여부 (y/n)
 * - commission: 매체비
 * - menu_category1: 광고 유형 (옵션)
 *
 * Response:
 * - code: "00" (성공) | "01" | "05" | "11" | "99"
 */
export const pincruxCallback = functions.onRequest(
  {
    region: "asia-northeast3",
    cors: false, // 핀크럭스 서버에서만 호출
  },
  async (req, res) => {
    try {
      // 핀크럭스 서버 IP 검증 (문서 기준 화이트리스트)
      const allowedIPs = ["13.125.159.103", "15.164.71.152"];
      const clientIP = req.headers["x-forwarded-for"] || req.connection.remoteAddress || "";
      const ip = Array.isArray(clientIP) ? clientIP[0] : clientIP.toString().split(",")[0].trim();
      if (!allowedIPs.includes(ip)) {
        logger.warn("허용되지 않은 IP 접근", { ip });
        res.status(403).json({ code: "99" });
        return;
      }

      // GET/POST 모두 지원 - 문서 명세 파라미터
      const appkey = req.query.appkey || req.body.appkey;
      const pubkey = req.query.pubkey || req.body.pubkey;
      const usrkey = req.query.usrkey || req.body.usrkey;
      const appTitle = req.query.app_title || req.body.app_title;
      const coin = parseInt((req.query.coin as string) || (req.body.coin as string));
      const transid = req.query.transid || req.body.transid;
      const resignFlag = req.query.resign_flag || req.body.resign_flag || "n";
      // const commission = req.query.commission || req.body.commission; // optional - unused
      // const menuCategory1 = req.query.menu_category1 || req.body.menu_category1; // optional - unused

      logger.info("핀크럭스 콜백 수신", { appkey, pubkey, usrkey, appTitle, coin, transid, resignFlag });

      // 필수 파라미터 검증 (문서 기준)
      if (!appkey || !pubkey || !usrkey || !coin || !transid) {
        logger.error("필수 파라미터 누락", { appkey, pubkey, usrkey, coin, transid });
        res.json({ code: "01" });
        return;
      }

      // 매체 코드(pubkey) 검증 (고정 값)
      if (pubkey !== "912065") {
        logger.error("잘못된 pubkey", { pubkey });
        res.json({ code: "01" });
        return;
      }

      // coin 값 형식 검증
      if (isNaN(coin) || coin <= 0) {
        logger.error("잘못된 coin 값", { coin });
        res.json({ code: "01" });
        return;
      }

      // 사용자 존재 확인 (없는 사용자에 대한 생성은 하지 않음)
      const userRef = db.doc(`users/${usrkey}`);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        logger.error("사용자를 찾을 수 없음", { usrkey });
        res.json({ code: "05" });
        return;
      }

      await userRef.set(
        {
          pincruxMoney: admin.firestore.FieldValue.increment(coin),
        },
        { merge: true }
      );

      logger.info("핀크럭스 포인트 적립 성공", { usrkey, coin, transid });

      // 성공 응답
      res.json({ code: "00" });
    } catch (error) {
      logger.error("핀크럭스 콜백 처리 오류", error);
      res.json({ code: "99" }); // 알 수 없는 오류
    }
  }
);
