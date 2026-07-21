import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

admin.initializeApp();
const db = admin.firestore();
const ITERATIONS = 100000;

function pbkdf2(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    crypto.pbkdf2(password, salt, ITERATIONS, 32, "sha256",
      (err, derived) => err ? reject(err) : resolve(derived),
    );
  });
}

export { resetDailyFields, resetStepsAtMidnight } from "./resetDaily";
export { updateRankingsCache } from "./updateRankingsCache";
export { pincruxCallback }        from "./pincruxCallback";
export { mychipsCallback }        from "./mychipsCallback";
export { snapplayCallback }       from "./snapplayCallback";
export { gmotechCallback }        from "./gmotechCallback";
export { signInGoogle }           from "./googleAuth";
export { signUpGoogle }           from "./googleAuth";
export { linkGoogleAccount }      from "./googleAuth";
export { signInKakao }            from "./kakaoAuth";
export { signUpKakao }            from "./kakaoAuth";
export { linkKakaoAccount }       from "./kakaoAuth";
export { signInApple }            from "./appleAuth";
export { signUpApple }            from "./appleAuth";
export { linkAppleAccount }       from "./appleAuth";
export { sendGiftishowCoupon }    from "./giftishowApi";
export { getGiftishowCouponDetail } from "./giftishowApi";
export { getGiftishowGoodsDetail } from "./giftishowApi";

/**
 * 기존 사용자 deviceId 마이그레이션
 * - 유저 정보에 deviceId가 없으면 추가
 */
export const migrateDeviceId = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, deviceId } = req.body ?? {};

    if (!uid || !deviceId) {
      res.status(400).json({
        success: false,
        error: "MISSING_PARAMS",
        message: "uid와 deviceId가 필요합니다"
      });
      return;
    }

    // deviceId 유효성 검사
    if (deviceId === "" || deviceId === "unknown" || deviceId === "null") {
      res.status(400).json({
        success: false,
        error: "INVALID_DEVICE_ID",
        message: "유효하지 않은 기기 ID입니다"
      });
      return;
    }

    try {
      // 1) 사용자 문서 확인
      const userDoc = await db.doc(`users/${uid}`).get();
      if (!userDoc.exists) {
        res.status(404).json({
          success: false,
          error: "USER_NOT_FOUND",
          message: "사용자를 찾을 수 없습니다"
        });
        return;
      }

      const userData = userDoc.data();

      // 2) 이미 deviceId가 있는 경우 스킵
      if (userData?.deviceId && userData.deviceId !== "") {
        res.json({
          success: true,
          message: "이미 deviceId가 등록되어 있습니다",
          alreadyExists: true
        });
        return;
      }

      // 3) deviceId 중복 체크 - 다른 사용자가 사용 중인지 확인
      const existingDeviceIdQuery = await db.collection("users")
        .where("deviceId", "==", deviceId)
        .limit(1)
        .get();

      if (!existingDeviceIdQuery.empty) {
        const existingDoc = existingDeviceIdQuery.docs[0];
        if (existingDoc.id !== uid) {
          // 다른 사용자가 이미 사용 중
          res.status(409).json({
            success: false,
            error: "DEVICE_ID_ALREADY_USED",
            message: "다른 계정에서 이미 사용 중인 기기입니다"
          });
          return;
        }
      }

      // 4) 유저 문서에 deviceId 추가
      await db.doc(`users/${uid}`).update({
        deviceId: deviceId
      });

      console.log(`✅ deviceId 마이그레이션 완료: uid=${uid}, deviceId=${deviceId}`);

      res.json({
        success: true,
        message: "deviceId가 성공적으로 등록되었습니다"
      });
    } catch (error: any) {
      console.error("deviceId 마이그레이션 오류:", error);
      res.status(500).json({
        success: false,
        error: "SERVER_ERROR",
        message: "서버 오류가 발생했습니다",
        details: error.message
      });
    }
  }
);

/**
 * User-Agent에서 디바이스 모델 추출
 * Android: "Mozilla/5.0 (Linux; Android 13; SM-S918N) AppleWebKit/..." → "SM-S918N"
 * iOS: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X)..." → "iPhone"
 * @param {string} userAgent - User-Agent 문자열
 * @return {string} 추출된 디바이스 모델
 */
function extractDeviceModel(userAgent: string): string {
  // Android 패턴: (Linux; Android [version]; [model])
  const androidMatch = userAgent.match(/\(Linux;\s*Android\s*[\d.]+;\s*([^)]+)\)/i);
  if (androidMatch && androidMatch[1]) {
    // "SM-S918N Build/..." 같은 경우 Build 이전 부분만 추출
    const model = androidMatch[1].split(/\s+Build/i)[0].trim();
    return model;
  }

  // iOS 패턴
  if (/iphone/i.test(userAgent)) return "iPhone";
  if (/ipad/i.test(userAgent)) return "iPad";

  return "";
}

/**
 * 초대 링크 처리 - 앱이 설치되어 있으면 앱으로, 아니면 스토어로 리다이렉트
 * URL: https://cashbank-a1c93.web.app/invite/{CODE}
 */
export const handleInviteLink = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    // URL에서 초대코드 추출 (/invite/CODE)
    const pathParts = req.path.split("/").filter((p) => p);
    const inviteCode = pathParts[pathParts.length - 1] || "";

    // 디바이스 fingerprint 생성 (User-Agent + IP 기반)
    const userAgent = req.headers["user-agent"] || "";
    const ip = req.headers["x-forwarded-for"] || req.ip || "";
    const fingerprint = crypto
      .createHash("sha256")
      .update(`${userAgent}${ip}`)
      .digest("hex")
      .substring(0, 32);

    // 디바이스 모델 추출 (deferred deep link 매칭용)
    const deviceModel = extractDeviceModel(userAgent as string);
    console.log(`handleInviteLink: fingerprint=${fingerprint}, deviceModel=${deviceModel}, inviteCode=${inviteCode}`);

    // 초대코드 유효성 검사
    if (inviteCode && inviteCode.length >= 6) {
      // Firestore에 deferred deep link 저장 (7일 TTL)
      await db.collection("deferredDeepLinks").doc(fingerprint).set({
        inviteCode: inviteCode.toUpperCase(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        userAgent,
        deviceModel, // 디바이스 모델 추가 저장
        clientIp: typeof ip === "string" ? ip.split(",")[0].trim() : String(ip), // 첫 번째 IP만 저장
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7일 후 만료
      });
    }

    // 플랫폼 감지
    const isIOS = /iphone|ipad|ipod/i.test(userAgent);
    const isAndroid = /android/i.test(userAgent);

    // 스토어 URL (Android는 referrer 파라미터 포함)
    const referrerParam = inviteCode ? `&referrer=${encodeURIComponent(`invite_code=${inviteCode.toUpperCase()}`)}` : "";
    const playStoreUrl = `https://play.google.com/store/apps/details?id=com.reviewtube.pigmoney${referrerParam}`;
    const appStoreUrl = "https://apps.apple.com/kr/app/id6504533668";

    console.log(`handleInviteLink: Platform=${isAndroid ? "Android" : isIOS ? "iOS" : "Other"}, playStoreUrl=${playStoreUrl}`);

    if (isAndroid) {
      // Android: Intent URL 사용 (앱 없으면 자동으로 Play Store로 이동)
      const intentUrl = `intent://invite/${inviteCode}#Intent;scheme=pigmoney;package=com.reviewtube.pigmoney;S.browser_fallback_url=${encodeURIComponent(playStoreUrl)};end`;
      res.redirect(302, intentUrl);
    } else if (isIOS) {
      // iOS: 앱 스키마 시도 후 App Store로 리다이렉트
      const appSchemeUrl = `pigmoney://invite/${inviteCode}`;
      const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>피그머니</title>
  <style>
    body {
      margin: 0;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #FFF0F5;
    }
    .spinner {
      width: 40px;
      height: 40px;
      border: 4px solid #FFB6C1;
      border-top: 4px solid #FF69B4;
      border-radius: 50%;
      animation: spin 1s linear infinite;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
  </style>
</head>
<body>
  <div class="spinner"></div>
  <script>
    var appUrl = "${appSchemeUrl}";
    var storeUrl = "${appStoreUrl}";
    window.location.href = appUrl;
    setTimeout(function() {
      window.location.href = storeUrl;
    }, 1500);
    document.addEventListener('visibilitychange', function() {
      if (document.hidden) clearTimeout();
    });
  </script>
</body>
</html>
      `;
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.send(html);
    } else {
      // 기타 (PC 등): Play Store로 리다이렉트
      res.redirect(302, playStoreUrl);
    }
  }
);

/**
 * Deferred Deep Link 조회 - 앱 설치 후 저장된 초대코드 조회
 */
export const getDeferredInviteCode = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { fingerprint, adId, deviceModel } = req.body ?? {};
    // 요청자의 IP 추출 (링크 클릭 시 저장한 IP와 매칭용)
    const rawIp = req.headers["x-forwarded-for"] || req.ip || "";
    const clientIp = typeof rawIp === "string" ? rawIp.split(",")[0].trim() : String(rawIp);

    if (!fingerprint && !adId && !deviceModel) {
      res.status(400).json({ found: false, error: "MISSING_PARAMS" });
      return;
    }

    console.log(`getDeferredInviteCode: fingerprint=${fingerprint}, adId=${adId}, deviceModel=${deviceModel}, clientIp=${clientIp}`);

    try {
      let inviteCode: string | null = null;
      let docId: string | null = null;

      // 1) fingerprint로 먼저 검색
      if (fingerprint) {
        const doc = await db.collection("deferredDeepLinks").doc(fingerprint).get();
        if (doc.exists) {
          const data = doc.data();
          // 만료 여부 확인
          if (data?.expiresAt && data.expiresAt.toDate() > new Date()) {
            inviteCode = data.inviteCode;
            docId = fingerprint;
            console.log(`Found by fingerprint: ${inviteCode}`);
          }
        }
      }

      // 2) adId로도 검색 (fingerprint가 다를 수 있으므로)
      if (!inviteCode && adId) {
        const adIdQuery = await db.collection("deferredDeepLinks")
          .where("adId", "==", adId)
          .orderBy("createdAt", "desc")
          .limit(1)
          .get();

        if (!adIdQuery.empty) {
          const doc = adIdQuery.docs[0];
          const data = doc.data();
          if (data?.expiresAt && data.expiresAt.toDate() > new Date()) {
            inviteCode = data.inviteCode;
            docId = doc.id;
            console.log(`Found by adId: ${inviteCode}`);
          }
        }
      }

      // 3) IP + deviceModel 조합으로 검색 (같은 네트워크 + 같은 기기 종류)
      if (!inviteCode && clientIp && deviceModel) {
        const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
        const ipModelQuery = await db.collection("deferredDeepLinks")
          .where("clientIp", "==", clientIp)
          .where("deviceModel", "==", deviceModel)
          .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(oneDayAgo))
          .orderBy("createdAt", "desc")
          .limit(1)
          .get();

        if (!ipModelQuery.empty) {
          const doc = ipModelQuery.docs[0];
          const data = doc.data();
          if (data?.expiresAt && data.expiresAt.toDate() > new Date()) {
            inviteCode = data.inviteCode;
            docId = doc.id;
            console.log(`Found by IP+deviceModel: ${inviteCode}`);
          }
        }
      }

      if (inviteCode) {
        // 사용된 deferred link 삭제 (일회성)
        if (docId) {
          await db.collection("deferredDeepLinks").doc(docId).delete();
        }

        res.json({
          found: true,
          inviteCode,
        });
      } else {
        res.json({ found: false });
      }
    } catch (error: any) {
      console.error("Deferred deep link 조회 오류:", error);
      res.status(500).json({ found: false, error: "SERVER_ERROR" });
    }
  }
);

/**
 * 기프티콘 구매 자격 검증 (서버 측 검증)
 * - 회원가입 후 3일 경과 여부를 서버 시간 기준으로 검증
 */
export const verifyGiftPurchaseEligibility = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid } = req.body ?? {};

    if (!uid) {
      res.status(400).json({
        eligible: false,
        error: "MISSING_PARAMS",
        message: "uid가 필요합니다"
      });
      return;
    }

    try {
      // 디버깅 로그
      console.log(`[검증 시작] uid=${uid}`);

      // 사용자 문서 가져오기
      const userDoc = await db.doc(`users/${uid}`).get();
      console.log(`[문서 조회] exists=${userDoc.exists}`);

      if (!userDoc.exists) {
        console.log(`[에러] 사용자 문서 없음: uid=${uid}`);
        res.status(404).json({
          eligible: false,
          error: "USER_NOT_FOUND",
          message: "사용자를 찾을 수 없습니다"
        });
        return;
      }

      const userData = userDoc.data();
      if (!userData?.joinDate) {
        res.status(400).json({
          eligible: false,
          error: "INVALID_USER_DATA",
          message: "가입 정보가 올바르지 않습니다"
        });
        return;
      }

      // 서버 시간과 가입 시간 비교 (서버 타임스탬프 사용)
      const joinDate = userData.joinDate.toDate(); // Firestore Timestamp to Date
      const serverNow = new Date(); // 서버의 현재 시간

      // 밀리초를 일(day)로 변환
      const daysSinceJoin = Math.floor(
        (serverNow.getTime() - joinDate.getTime()) / (1000 * 60 * 60 * 24)
      );

      console.log(`구매 자격 검증: uid=${uid}, joinDate=${joinDate.toISOString()}, serverNow=${serverNow.toISOString()}, daysSinceJoin=${daysSinceJoin}`);

      if (daysSinceJoin < 1) {
        // 1일 미만 - 구매 불가
        res.status(200).json({
          eligible: false,
          error: "NOT_ELIGIBLE_YET",
          message: "가입 후 24시간 이후에 구매할 수 있습니다.",
        });
        return;
      }

      // blockDeviceIdList 검증 - 맨 마지막에 검증
      const deviceId = userData.deviceId;
      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        const blockDoc = await db.collection("blockDeviceIdList").doc(deviceId).get();
        if (blockDoc.exists) {
          console.log(`🚫 blockDeviceIdList에 등록된 deviceId 감지: ${deviceId}`);
          res.status(200).json({
            eligible: false,
            error: "BLOCKED_DEVICE",
            message: "관리자에게 문의 바랍니다"
          });
          return;
        }
      }

      // 3일 이상 + blockDeviceIdList 검증 통과 - 구매 가능
      res.status(200).json({
        eligible: true,
        daysSinceJoin,
        message: "구매 가능합니다"
      });
    } catch (error: any) {
      console.error("구매 자격 검증 오류:", error);
      res.status(500).json({
        eligible: false,
        error: "SERVER_ERROR",
        message: "서버 오류가 발생했습니다",
        details: error.message
      });
    }
  }
);

/**
 * IP 및 디바이스 차단 확인 (기프티콘 구매 전 호출)
 * - app_config/purchase_block.blockedIps 에서 차단 IP 관리
 * - 차단 시 해당 IP의 모든 유저 purchaseValid=1, deviceId를 blockDeviceIdList에 추가
 */
export const checkIpBlock = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, deviceId } = req.body ?? {};

    if (!uid) {
      res.status(400).json({ blocked: false, error: "MISSING_PARAMS" });
      return;
    }

    try {
      // 1. 요청자의 실제 IP 가져오기
      const forwardedFor = req.headers["x-forwarded-for"];
      const clientIp = typeof forwardedFor === "string" ?
        forwardedFor.split(",")[0].trim() :
        req.ip || "";

      console.log(`[IP차단확인] uid=${uid}, deviceId=${deviceId}, clientIp=${clientIp}`);

      // 2. 차단 IP 목록 조회
      const blockDoc = await db.doc("app_config/purchase_block").get();
      if (!blockDoc.exists) {
        res.status(200).json({ blocked: false });
        return;
      }

      const blockedIps: string[] = blockDoc.data()?.blockedIps ?? [];

      // 매 구매 시도 시 현재 IP와 저장된 IP 비교 → 다르면 갱신
      if (clientIp) {
        const userDoc = await db.doc(`users/${uid}`).get();
        const savedIp = userDoc.data()?.ipAddress || "";
        if (savedIp !== clientIp) {
          await db.doc(`users/${uid}`).update({ ipAddress: clientIp });
          console.log(`[IP갱신] ${savedIp || "(없음)"} → ${clientIp} (uid=${uid})`);
        }
      }

      if (!clientIp || !blockedIps.includes(clientIp)) {
        res.status(200).json({ blocked: false });
        return;
      }

      // 3. 차단된 IP - 해당 IP를 가진 모든 유저 일괄 차단
      console.log(`🚫 차단된 IP 감지: ${clientIp} (uid=${uid})`);

      const usersWithIp = await db.collection("users")
        .where("ipAddress", "==", clientIp)
        .get();

      let blockedCount = 0;

      for (const userDoc of usersWithIp.docs) {
        const userData = userDoc.data();
        const userUid = userDoc.id;
        const userDeviceId = userData.deviceId || "";
        const userNickname = userData.nickname || "";

        // purchaseValid를 1로 변경
        await db.doc(`users/${userUid}`).update({ purchaseValid: 1 });

        // blockDeviceIdList에 디바이스 추가
        if (userDeviceId && userDeviceId !== "" && userDeviceId !== "unknown") {
          await db.collection("blockDeviceIdList").doc(userDeviceId).set({
            blockedAt: admin.firestore.FieldValue.serverTimestamp(),
            reason: "blocked_ip",
            ip: clientIp,
            uid: userUid,
            nickname: userNickname,
          });
        }

        blockedCount++;
        console.log(`  차단 완료: uid=${userUid}, nickname=${userNickname}, deviceId=${userDeviceId}`);
      }

      // 4. 현재 요청 유저도 차단 (ipAddress가 아직 저장 안된 경우 대비)
      const currentUserDoc = await db.doc(`users/${uid}`).get();
      const currentNickname = currentUserDoc.data()?.nickname || "";
      await db.doc(`users/${uid}`).update({
        purchaseValid: 1,
        ipAddress: clientIp,
      });

      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        await db.collection("blockDeviceIdList").doc(deviceId).set({
          blockedAt: admin.firestore.FieldValue.serverTimestamp(),
          reason: "blocked_ip",
          ip: clientIp,
          uid: uid,
          nickname: currentNickname,
        });
      }

      console.log(`🚫 IP 차단 처리 완료: ip=${clientIp}, 일괄차단=${blockedCount}명, 현재유저=uid=${uid}`);

      res.status(200).json({
        blocked: true,
        reason: "ip",
        ip: clientIp,
        blockedUsers: blockedCount,
      });
    } catch (error: any) {
      console.error("IP 차단 확인 오류:", error);
      res.status(500).json({ blocked: false, error: "SERVER_ERROR" });
    }
  }
);

/**
 * 초대코드 검증 함수 (회원가입 전 사용)
 */
export const validateInviteCode = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { inviteCode, deviceId } = req.body ?? {};

    if (!inviteCode) {
      res.status(400).json({ valid: false, message: "INVALID_CODE" });
      return;
    }

    try {
      // 기기 ID 중복 확인 - deviceIdList 컬렉션에서 체크
      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        const deviceIdDoc = await db.collection("deviceIdList").doc(deviceId).get();
        if (deviceIdDoc.exists) {
          res.status(200).json({
            valid: false,
            message: "SAME_DEVICE_ERROR",
            detail: "기기당 초대코드는 한 번만 입력 가능합니다."
          });
          return;
        }
      }

      // 초대코드로 사용자 찾기
      const inviterQuery = await db.collection("users")
        .where("inviteCode", "==", inviteCode)
        .limit(1)
        .get();

      if (inviterQuery.empty) {
        res.status(200).json({ valid: false, message: "CODE_NOT_FOUND" });
        return;
      }

      const inviterDoc = inviterQuery.docs[0];
      const inviterData = inviterDoc.data();

      // 무제한 친구 초대 - 유효한 초대코드면 OK
      res.status(200).json({
        valid: true,
        inviterUid: inviterDoc.id,
        inviterNickname: inviterData.nickname
      });
    } catch (error) {
      console.error("초대코드 검증 에러:", error);
      res.status(500).json({ valid: false, message: "SERVER_ERROR" });
    }
  }
);
export const signInNickname = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { nickname, password } = req.body ?? {};
    if (!nickname || !password) {
      res.status(400).send("BAD_REQUEST"); return;
    }

    // 요청자의 IP 추출
    const rawIp = req.headers["x-forwarded-for"] || req.ip || "";
    const clientIp = typeof rawIp === "string" ? rawIp.split(",")[0].trim() : String(rawIp);

    /* 1) nickname → uid 매핑 */
    const nickSnap = await db.doc(`nicknames/${nickname}`).get();
    if (!nickSnap.exists) {
      res.status(404).send("USER_NOT_FOUND"); return;
    }
    const uid = (nickSnap.data() as { uid: string }).uid;

    /* 2) 비밀번호 검증 */
    const userSnap = await db.doc(`users/${uid}`).get();
    const { passwordHash } = userSnap.data() as { passwordHash: string };

    const buf     = Buffer.from(passwordHash, "base64");
    const salt    = buf.subarray(0, 16);
    const stored  = buf.subarray(16);
    const derived = await pbkdf2(password, salt);
    if (!crypto.timingSafeEqual(stored, derived)) {
      res.status(401).send("INVALID_PASSWORD"); return;
    }

    // 로그인 시 IP 주소 갱신
    await db.doc(`users/${uid}`).update({
      ipAddress: clientIp,
    });

    /* 3) Custom Token (uid) 발급 */
    const token = await admin.auth().createCustomToken(uid, { role: "user" });
    res.json({ token });
  },
);


/** 비밀번호 변경 */
export const changePassword = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { nickname, oldPassword, newPassword } = req.body ?? {};
    if (!nickname || !oldPassword || !newPassword) {
      res.status(400).send("BAD_REQUEST"); return;
    }

    // 1) 기존 해시 가져오기
    const snap = await db.doc(`users/${nickname}`).get();
    if (!snap.exists) {
      res.status(404).send("USER_NOT_FOUND"); return;
    }
    const { passwordHash } = snap.data() as { passwordHash: string };

    // 2) 기존 비밀번호 검증
    const buf = Buffer.from(passwordHash, "base64");
    const salt = buf.subarray(0, 16);
    const stored = buf.subarray(16);
    const derived = await pbkdf2(oldPassword, salt);
    if (!crypto.timingSafeEqual(stored, derived)) {
      res.status(401).send("INVALID_PASSWORD"); return;
    }

    // 3) 새 해시 생성
    const newSalt = crypto.randomBytes(16);
    const newDerived = await pbkdf2(newPassword, newSalt);
    const newHash = Buffer.concat([newSalt, newDerived]).toString("base64");

    // 4) users/{nickname} 문서 업데이트
    await db.doc(`users/${nickname}`).update({ passwordHash: newHash });
    res.send("OK");
  }
);

/** 회원 탈퇴 - 모든 사용자 관련 데이터 삭제 */
export const deleteAccount = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, password } = req.body ?? {};
    if (!uid) {
      res.status(400).send("BAD_REQUEST"); return;
    }

    try {
      // 1) 사용자 정보 가져오기
      const userSnap = await db.doc(`users/${uid}`).get();
      if (!userSnap.exists) {
        res.status(404).send("USER_NOT_FOUND"); return;
      }

      const userData = userSnap.data() as {
        passwordHash?: string;
        nickname: string;
        isKakao?: boolean;
        isGoogle?: boolean;
        isApple?: boolean;
        kakaoId?: string;
        googleId?: string;
        appleId?: string;
      };
      const { passwordHash, nickname, isKakao, isGoogle, isApple, kakaoId, googleId, appleId } = userData;

      // 디버깅 로그 - 사용자 데이터 확인
      console.log("[회원 탈퇴 요청] uid:", uid, "nickname:", nickname);
      console.log("[필드 확인] isKakao:", isKakao, "isGoogle:", isGoogle, "isApple:", isApple, "kakaoId:", kakaoId || "null", "googleId:", googleId || "null", "appleId:", appleId || "null", "passwordHash:", passwordHash ? "exists" : "null");

      // 2) 비밀번호 검증 (소셜 로그인 사용자가 아닌 경우에만)
      // isKakao/isGoogle/isApple 필드 또는 kakaoId/googleId/appleId 필드가 있으면 소셜 로그인 사용자
      const isSocialLogin = isKakao || isGoogle || isApple || !!kakaoId || !!googleId || !!appleId;
      console.log("[소셜 로그인 판단]", isSocialLogin);

      if (!isSocialLogin) {
        console.log("[일반 사용자] 비밀번호 검증 필요");
        if (!password || !passwordHash) {
          console.log("[PASSWORD_REQUIRED] password:", !!password, "passwordHash:", !!passwordHash);
          res.status(400).send("PASSWORD_REQUIRED"); return;
        }

        const buf = Buffer.from(passwordHash, "base64");
        const salt = buf.subarray(0, 16);
        const stored = buf.subarray(16);
        const derived = await pbkdf2(password, salt);
        if (!crypto.timingSafeEqual(stored, derived)) {
          console.log("[INVALID_PASSWORD]");
          res.status(401).send("INVALID_PASSWORD"); return;
        }
      } else {
        console.log("[소셜 로그인 사용자] 비밀번호 검증 스킵");
      }

      console.log("[회원 탈퇴 시작]");

      // 3) 삭제할 문서 참조 수집 (batch 제한 500개 대응)
      const deleteRefs: FirebaseFirestore.DocumentReference[] = [];

      // 3-1) 사용자 메인 문서 삭제
      deleteRefs.push(db.doc(`users/${uid}`));

      // 3-2) 닉네임 매핑 삭제
      deleteRefs.push(db.doc(`nicknames/${nickname}`));

      // 3-3) 사용자 하위 컬렉션들 삭제
      const earningsQuery = await db.collection(`users/${uid}/earnings`).get();
      earningsQuery.docs.forEach((doc) => deleteRefs.push(doc.ref));

      const dailyQuery = await db.collection(`users/${uid}/daily`).get();
      dailyQuery.docs.forEach((doc) => deleteRefs.push(doc.ref));

      const monthlyQuery = await db.collection(`users/${uid}/monthly`).get();
      monthlyQuery.docs.forEach((doc) => deleteRefs.push(doc.ref));

      console.log(`하위 컬렉션 삭제 준비 완료: earnings=${earningsQuery.size}, daily=${dailyQuery.size}, monthly=${monthlyQuery.size}`);

      // 4) 주문 데이터 삭제
      const ordersQuery = await db.collection("orders").where("uid", "==", uid).get();
      ordersQuery.docs.forEach((doc) => deleteRefs.push(doc.ref));
      console.log(`주문 데이터 삭제 준비 완료: ${ordersQuery.size}건`);

      // 5) 랭킹 데이터 삭제 (일별/월별)
      const now = new Date();
      const utcMs = now.getTime();
      const kstMs = utcMs + 9 * 60 * 60 * 1000;
      const kstDate = new Date(kstMs);

      const gameDate = kstDate.getHours() < 5 ?
        new Date(kstMs - 24 * 60 * 60 * 1000) :
        kstDate;

      const yy = gameDate.getFullYear();
      const mm = String(gameDate.getMonth() + 1).padStart(2, "0");
      const dd = String(gameDate.getDate()).padStart(2, "0");

      const dateKey = `${yy}-${mm}-${dd}`;
      const monthKey = `${yy}-${mm}`;

      // 현재 날짜의 랭킹 데이터 삭제
      deleteRefs.push(db.doc(`rankings/daily/${dateKey}/${uid}`));
      deleteRefs.push(db.doc(`rankings/monthly/${monthKey}/${uid}`));

      // 과거 랭킹 데이터도 삭제 (최근 30일, 12개월)
      for (let i = 0; i < 30; i++) {
        const pastKstMs = kstMs - i * 24 * 60 * 60 * 1000;
        const pastKstDate = new Date(pastKstMs);

        const pastGameDate = pastKstDate.getHours() < 5 ?
          new Date(pastKstMs - 24 * 60 * 60 * 1000) :
          pastKstDate;

        const pastDateKey = `${pastGameDate.getFullYear()}-${String(pastGameDate.getMonth() + 1).padStart(2, "0")}-${String(pastGameDate.getDate()).padStart(2, "0")}`;
        deleteRefs.push(db.doc(`rankings/daily/${pastDateKey}/${uid}`));
      }

      for (let i = 0; i < 12; i++) {
        const pastKstDate = new Date(kstMs - i * 30 * 24 * 60 * 60 * 1000);
        const pastGameDate = pastKstDate.getHours() < 5 ?
          new Date(pastKstDate.getTime() - 24 * 60 * 60 * 1000) :
          pastKstDate;

        const pastMonthKey = `${pastGameDate.getFullYear()}-${String(pastGameDate.getMonth() + 1).padStart(2, "0")}`;
        deleteRefs.push(db.doc(`rankings/monthly/${pastMonthKey}/${uid}`));
      }

      console.log(`랭킹 데이터 삭제 준비 완료, 총 삭제 대상: ${deleteRefs.length}건`);

      // 6) 500개 단위로 배치 커밋 (Firestore batch 제한 대응)
      const BATCH_SIZE = 500;
      for (let i = 0; i < deleteRefs.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = deleteRefs.slice(i, i + BATCH_SIZE);
        chunk.forEach((ref) => batch.delete(ref));
        await batch.commit();
        console.log(`배치 커밋 완료: ${i + 1}~${Math.min(i + BATCH_SIZE, deleteRefs.length)}/${deleteRefs.length}`);
      }
      console.log("Firestore 데이터 삭제 완료");

      // 7) Firebase Auth 계정 삭제
      await admin.auth().deleteUser(uid);

      console.log(`회원 탈퇴 완료: uid=${uid}, nickname=${nickname}`);
      res.send("OK");
    } catch (error) {
      console.error("회원 탈퇴 오류:", error);
      res.status(500).send("INTERNAL_ERROR");
    }
  }
);
