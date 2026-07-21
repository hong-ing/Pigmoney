import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";

// Firestore 초기화 (index.ts에서 이미 초기화됨)
const db = admin.firestore();

// 기프티쇼 API 설정 (Secret Manager)
const GIFTISHOW_BASE_URL = "https://bizapi.giftishow.com/bizApi";
const giftishowAuthCode = defineSecret("GIFTISHOW_AUTH_CODE");
const giftishowAuthToken = defineSecret("GIFTISHOW_AUTH_TOKEN");

interface GiftishowApiResponse {
  code: string;
  message?: string;
  result?: {
    result?: {
      orderNo?: string;
      pinNo?: string;
      couponImgUrl?: string;
    };
  };
}

/**
 * 기프티쇼 API POST 요청 공통 함수
 * @param {string} endpoint - API 엔드포인트
 * @param {Record<string, string>} params - 요청 파라미터
 * @return {Promise<GiftishowApiResponse>} API 응답
 */
async function giftishowPost(
  endpoint: string,
  params: Record<string, string>
): Promise<GiftishowApiResponse> {
  const url = `${GIFTISHOW_BASE_URL}${endpoint}`;

  // URLSearchParams로 form-urlencoded 형식 생성
  const formData = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    formData.append(key, value);
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: formData.toString(),
  });

  if (!response.ok) {
    throw new Error(`HTTP Error: ${response.status}`);
  }

  const jsonData = await response.json();
  return jsonData as GiftishowApiResponse;
}

/**
 * 기프티쇼 MMS 쿠폰 발송 함수
 *
 * Cloud Functions를 통해 기프티쇼 API를 호출하여 MMS 쿠폰을 발송합니다.
 * IP 화이트리스트가 필요한 경우 Cloud NAT를 통해 정적 IP를 사용합니다.
 */
export const sendGiftishowCoupon = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 30,
    memory: "256MiB",
    vpcConnector: "pigmoney-connector",
    vpcConnectorEgressSettings: "ALL_TRAFFIC",
    secrets: [giftishowAuthCode, giftishowAuthToken],
  },
  async (req, res) => {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({
        success: false,
        error: "METHOD_NOT_ALLOWED",
        message: "POST 요청만 허용됩니다"
      });
      return;
    }

    const {
      goodsCode,
      phoneNo,
      callbackNo,
      userId,
      trId,
      mmsTitle,
      mmsMsg,
      orderNo,
      gubun = "N", // 기본값: MMS 발송
      uid, // Firebase 사용자 UID (검증용)
    } = req.body ?? {};

    // 필수 파라미터 검증
    if (!goodsCode || !phoneNo || !callbackNo || !userId || !trId || !mmsTitle || !mmsMsg) {
      res.status(400).json({
        success: false,
        error: "MISSING_PARAMS",
        message: "필수 파라미터가 누락되었습니다",
        required: ["goodsCode", "phoneNo", "callbackNo", "userId", "trId", "mmsTitle", "mmsMsg"],
      });
      return;
    }

    // TR_ID 유효성 검증 (25자 이하)
    if (trId.length > 25) {
      res.status(400).json({
        success: false,
        error: "INVALID_TR_ID",
        message: "TR_ID는 25자 이하여야 합니다",
      });
      return;
    }

    // 전화번호 형식 검증
    const phoneRegex = /^01[0-9]{8,9}$/;
    if (!phoneRegex.test(phoneNo)) {
      res.status(400).json({
        success: false,
        error: "INVALID_PHONE_NO",
        message: "유효하지 않은 전화번호 형식입니다",
      });
      return;
    }

    // 사용자 검증 (uid가 제공된 경우)
    if (uid) {
      try {
        const userDoc = await db.doc(`users/${uid}`).get();
        if (!userDoc.exists) {
          res.status(404).json({
            success: false,
            error: "USER_NOT_FOUND",
            message: "사용자를 찾을 수 없습니다",
          });
          return;
        }
      } catch (error) {
        console.error("사용자 검증 오류:", error);
      }
    }

    try {
      console.log(`🎁 [기프티쇼] 쿠폰 발송 시작: trId=${trId}, goodsCode=${goodsCode}, phoneNo=${phoneNo}`);

      // 기프티쇼 API 파라미터 구성
      const apiParams: Record<string, string> = {
        custom_auth_code: giftishowAuthCode.value(),
        custom_auth_token: giftishowAuthToken.value(),
        dev_yn: "N", // 운영환경
        api_code: "0204", // 쿠폰 발송 API 코드
        goods_code: goodsCode,
        phone_no: phoneNo,
        callback_no: callbackNo,
        user_id: userId,
        tr_id: trId,
        mms_title: mmsTitle,
        mms_msg: mmsMsg,
        gubun: gubun,
      };

      if (orderNo) {
        apiParams.order_no = orderNo;
      }

      // 기프티쇼 API 호출
      const apiResponse = await giftishowPost("/send", apiParams);

      console.log("🎁 [기프티쇼] API 응답:", JSON.stringify(apiResponse));

      // API 응답 코드 확인
      if (apiResponse.code !== "0000") {
        console.error(`❌ [기프티쇼] API 오류: code=${apiResponse.code}, message=${apiResponse.message}`);
        res.status(200).json({
          success: false,
          code: apiResponse.code,
          message: apiResponse.message || "기프티쇼 API 오류가 발생했습니다",
        });
        return;
      }

      // 성공 응답
      const result = apiResponse.result?.result;
      console.log(`✅ [기프티쇼] 쿠폰 발송 성공: trId=${trId}, orderNo=${result?.orderNo}`);

      res.status(200).json({
        success: true,
        code: apiResponse.code,
        message: apiResponse.message || "쿠폰이 성공적으로 발송되었습니다",
        result: {
          orderNo: result?.orderNo,
          pinNo: result?.pinNo,
          couponImgUrl: result?.couponImgUrl,
        },
      });
    } catch (error: any) {
      console.error("❌ [기프티쇼] 쿠폰 발송 오류:", error);
      res.status(500).json({
        success: false,
        error: "SERVER_ERROR",
        message: "서버 오류가 발생했습니다",
        details: error.message,
      });
    }
  }
);

/**
 * 기프티쇼 쿠폰 상세 정보 조회
 */
export const getGiftishowCouponDetail = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 15,
    memory: "256MiB",
    secrets: [giftishowAuthCode, giftishowAuthToken],
  },
  async (req, res) => {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const { trId } = req.body ?? {};

    if (!trId) {
      res.status(400).json({
        success: false,
        error: "MISSING_PARAMS",
        message: "trId가 필요합니다",
      });
      return;
    }

    try {
      console.log(`🔍 [기프티쇼] 쿠폰 조회: trId=${trId}`);

      const apiParams: Record<string, string> = {
        custom_auth_code: giftishowAuthCode.value(),
        custom_auth_token: giftishowAuthToken.value(),
        dev_yn: "N",
        api_code: "0201",
        tr_id: trId,
      };

      const apiResponse = await giftishowPost("/coupons", apiParams);

      console.log("🔍 [기프티쇼] 쿠폰 조회 응답:", JSON.stringify(apiResponse));

      res.status(200).json({
        success: apiResponse.code === "0000",
        code: apiResponse.code,
        message: apiResponse.message,
        result: apiResponse.result,
      });
    } catch (error: any) {
      console.error("❌ [기프티쇼] 쿠폰 조회 오류:", error);
      res.status(500).json({
        success: false,
        error: "SERVER_ERROR",
        message: "서버 오류가 발생했습니다",
        details: error.message,
      });
    }
  }
);

/**
 * 기프티쇼 상품 상세 정보 조회
 */
export const getGiftishowGoodsDetail = onRequest(
  {
    region: "asia-northeast3",
    timeoutSeconds: 15,
    memory: "256MiB",
    vpcConnector: "pigmoney-connector",
    vpcConnectorEgressSettings: "ALL_TRAFFIC",
    secrets: [giftishowAuthCode, giftishowAuthToken],
  },
  async (req, res) => {
    // CORS 헤더 설정
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    const { goodsCode } = req.body ?? {};

    if (!goodsCode) {
      res.status(400).json({
        success: false,
        error: "MISSING_PARAMS",
        message: "goodsCode가 필요합니다",
      });
      return;
    }

    try {
      console.log(`📦 [기프티쇼] 상품 조회: goodsCode=${goodsCode}`);

      const apiParams: Record<string, string> = {
        custom_auth_code: giftishowAuthCode.value(),
        custom_auth_token: giftishowAuthToken.value(),
        dev_yn: "N",
        api_code: "0111",
      };

      const apiResponse = await giftishowPost(`/goods/${goodsCode}`, apiParams);

      console.log(`📦 [기프티쇼] 상품 조회 응답 코드: ${apiResponse.code}`);

      res.status(200).json({
        success: apiResponse.code === "0000",
        code: apiResponse.code,
        message: apiResponse.message,
        result: apiResponse.result,
      });
    } catch (error: any) {
      console.error("❌ [기프티쇼] 상품 조회 오류:", error);
      res.status(500).json({
        success: false,
        error: "SERVER_ERROR",
        message: "서버 오류가 발생했습니다",
        details: error.message,
      });
    }
  }
);
