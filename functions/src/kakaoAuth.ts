import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import axios from "axios";

const db = admin.firestore();

/**
 * 영문 대문자만으로 구성된 초대코드 생성 (8글자)
 * 중복 방지: Firestore에서 기존 초대코드와 중복되지 않을 때까지 생성
 */
async function generateUniqueInviteCode(): Promise<string> {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const maxAttempts = 10; // 최대 시도 횟수 (무한 루프 방지)

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    // 초대코드 생성
    const randomBytes = crypto.randomBytes(8);
    let code = "";
    for (let i = 0; i < 8; i++) {
      code += chars[randomBytes[i] % chars.length];
    }

    // Firestore에서 중복 확인
    const existingCode = await db.collection("users")
      .where("inviteCode", "==", code)
      .limit(1)
      .get();

    // 중복이 없으면 해당 코드 반환
    if (existingCode.empty) {
      console.log(`✅ 고유 초대코드 생성 성공: ${code} (시도 횟수: ${attempt + 1})`);
      return code;
    }

    console.log(`⚠️ 초대코드 중복 감지: ${code}, 재생성 중... (시도 ${attempt + 1}/${maxAttempts})`);
  }

  // 최대 시도 횟수 초과 시 (매우 드문 경우) 타임스탬프 추가
  const fallbackCode = chars[Math.floor(Math.random() * 26)] +
                        Date.now().toString(36).toUpperCase().slice(-7);
  console.log(`⚠️ 최대 시도 횟수 초과, fallback 코드 사용: ${fallbackCode}`);
  return fallbackCode;
}

/**
 * 클라이언트 IP 주소 가져오기
 * @param {object} req - HTTP 요청 객체
 * @return {string} 클라이언트 IP 주소
 */
function getClientIp(req: {headers: Record<string, string | string[] | undefined>; ip?: string; connection?: {remoteAddress?: string}}): string {
  const forwardedFor = req.headers["x-forwarded-for"];
  if (forwardedFor) {
    // x-forwarded-for는 여러 IP가 쉼표로 구분되어 있을 수 있음 (첫 번째가 클라이언트 IP)
    const ip = Array.isArray(forwardedFor) ? forwardedFor[0] : forwardedFor;
    return ip.split(",")[0].trim();
  }
  return req.ip || req.connection?.remoteAddress || "unknown";
}

/**
 * Kakao 로그인 (기존 사용자만)
 */
export const signInKakao = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { kakaoId, accessToken, accountEmail } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!kakaoId || !accessToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "kakaoId와 accessToken이 필요합니다" });
      return;
    }

    try {
      // 1) Kakao 액세스 토큰 검증
      const kakaoUserInfoUrl = "https://kapi.kakao.com/v2/user/me";
      const kakaoResponse = await axios.get(kakaoUserInfoUrl, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      const kakaoUserData = kakaoResponse.data;

      // Kakao ID 검증
      if (kakaoUserData.id.toString() !== kakaoId) {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Kakao 토큰입니다" });
        return;
      }

      // 2) 기존 사용자 확인 (kakaoId로 검색)
      const existingUserQuery = await db.collection("users")
        .where("kakaoId", "==", kakaoId)
        .limit(1)
        .get();

      if (existingUserQuery.empty) {
        // 신규 사용자 - 회원가입 필요
        res.status(404).json({
          error: "USER_NOT_FOUND",
          message: "회원가입이 필요합니다",
          isNewUser: true
        });
        return;
      }

      // 기존 사용자 - 로그인
      const existingUserDoc = existingUserQuery.docs[0];
      const uid = existingUserDoc.id;

      // 프로필 정보 업데이트 (변경된 경우)
      const updates: any = {
        lastAccessTime: admin.firestore.FieldValue.serverTimestamp(),
        ipAddress: clientIp, // IP 주소 업데이트
      };

      if (accountEmail && accountEmail !== existingUserDoc.data().accountEmail) {
        updates.accountEmail = accountEmail;
      }

      await db.doc(`users/${uid}`).update(updates);

      // 3) Firebase Custom Token 생성
      const token = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "kakao",
      });

      res.json({
        token,
        isNewUser: false,
        uid,
      });
    } catch (error: any) {
      console.error("Kakao 로그인 처리 중 오류:", error);

      if (error.response?.status === 401) {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Kakao 액세스 토큰이 만료되었거나 유효하지 않습니다"
        });
      } else {
        res.status(500).json({
          error: "SERVER_ERROR",
          message: "서버 오류가 발생했습니다",
          details: error.message,
        });
      }
    }
  },
);

/**
 * Kakao 회원가입 (닉네임 + 추천인 코드)
 */
export const signUpKakao = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { kakaoId, accessToken, accountEmail, nickname, usedInviteCode, adId, deviceId } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!kakaoId || !accessToken || !nickname) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "kakaoId, accessToken, nickname이 필요합니다" });
      return;
    }

    try {
      // 1) Kakao 액세스 토큰 검증
      const kakaoUserInfoUrl = "https://kapi.kakao.com/v2/user/me";
      const kakaoResponse = await axios.get(kakaoUserInfoUrl, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      const kakaoUserData = kakaoResponse.data;

      // Kakao ID 검증
      if (kakaoUserData.id.toString() !== kakaoId) {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Kakao 토큰입니다" });
        return;
      }

      // 2) deviceId 검증 - 필수값 체크
      if (!deviceId || deviceId === "" || deviceId === "unknown" || deviceId === "00000000-0000-0000-0000-000000000000") {
        res.status(400).json({
          error: "INVALID_DEVICE_ID",
          message: "유효하지 않은 기기 ID입니다"
        });
        return;
      }

      // deviceId 중복 체크 - 전체 users 컬렉션에서 검색
      const existingDeviceIdQuery = await db.collection("users")
        .where("deviceId", "==", deviceId)
        .limit(1)
        .get();

      if (!existingDeviceIdQuery.empty) {
        res.status(409).json({
          error: "DEVICE_ALREADY_REGISTERED",
          message: "이미 가입된 기기입니다"
        });
        return;
      }

      // deviceIdList 중복 체크 (초대코드 사용 시에만)
      if (usedInviteCode && deviceId) {
        const deviceIdDoc = await db.collection("deviceIdList").doc(deviceId).get();
        if (deviceIdDoc.exists) {
          res.status(409).json({
            error: "SAME_DEVICE_ERROR",
            message: "기기당 초대코드는 한 번만 입력 가능합니다"
          });
          return;
        }
      }

      // 2-1) deviceId 다중 계정 감지 - users 컬렉션에서 동일 deviceId 검색
      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        const multiAccountQuery = await db.collection("users")
          .where("deviceId", "==", deviceId)
          .get();

        // 동일 deviceId가 2개 이상이면 blockDeviceIdList에 추가 (history 방식)
        if (multiAccountQuery.size >= 2) {
          console.log(`⚠️ 동일 deviceId ${multiAccountQuery.size}개 감지: ${deviceId}`);

          // blockDeviceIdList에 추가 (history 배열 방식)
          const historyEntry = {
            uid: "", // 아직 생성 전이므로 빈 값
            nickname: nickname,
            reason: "duplicate",
            createdAt: admin.firestore.Timestamp.now()
          };

          const blockDoc = await db.collection("blockDeviceIdList").doc(deviceId).get();
          if (blockDoc.exists) {
            // 기존 문서에 history 추가
            await db.collection("blockDeviceIdList").doc(deviceId).update({
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              history: admin.firestore.FieldValue.arrayUnion(historyEntry)
            });
          } else {
            // 새 문서 생성
            await db.collection("blockDeviceIdList").doc(deviceId).set({
              deviceId: deviceId,
              adId: adId || "",
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              history: [historyEntry]
            });
          }
          console.log(`✅ blockDeviceIdList에 ${deviceId} 추가/업데이트 완료 (reason: duplicate, nickname: ${nickname})`);
        }
      }

      // 3) 이미 가입된 사용자인지 확인 (kakaoId로)
      const existingKakaoQuery = await db.collection("users")
        .where("kakaoId", "==", kakaoId)
        .limit(1)
        .get();

      if (!existingKakaoQuery.empty) {
        res.status(409).json({ error: "USER_ALREADY_EXISTS", message: "이미 가입된 사용자입니다" });
        return;
      }

      // 3-1) accountEmail 중복 체크 (다른 로그인 방법과의 중복 방지)
      if (accountEmail) {
        const existingEmailQuery = await db.collection("users")
          .where("accountEmail", "==", accountEmail)
          .limit(1)
          .get();

        if (!existingEmailQuery.empty) {
          res.status(409).json({
            error: "EMAIL_ALREADY_EXISTS",
            message: "이미 가입된 이메일입니다."
          });
          return;
        }
      }

      // 4) 닉네임 중복 확인
      const nickSnap = await db.doc(`nicknames/${nickname}`).get();
      if (nickSnap.exists) {
        res.status(409).json({ error: "NICKNAME_TAKEN", message: "이미 사용 중인 닉네임입니다" });
        return;
      }

      // 5) 초대코드 검증 및 처리
      let inviterUid: string | null = null;
      let shouldAddToInviteList = false;  // 초대 리스트에 추가할지 여부
      let initialMoney = 0;  // 기본 0머니

      if (usedInviteCode) {
        // 초대코드로 초대자 찾기
        const inviterQuery = await db.collection("users")
          .where("inviteCode", "==", usedInviteCode)
          .limit(1)
          .get();

        if (!inviterQuery.empty) {
          const inviterDoc = inviterQuery.docs[0];
          inviterUid = inviterDoc.id;
          initialMoney = 300000;  // 초대코드 사용 시 30만 머니 지급 (무제한)

          // 무제한 친구 초대 - 항상 초대 리스트에 추가
          shouldAddToInviteList = true;
        }
      }

      // 6) Firebase Auth 사용자 생성
      let uid: string;
      try {
        const authUser = await admin.auth().createUser({
          uid: `kakao_${kakaoId}`, // Kakao ID를 UID로 사용 (prefix 추가)
          email: accountEmail,
        });
        uid = authUser.uid;
      } catch (error: any) {
        if (error.code === "auth/uid-already-exists") {
          uid = `kakao_${kakaoId}`;
        } else if (error.code === "auth/email-already-exists") {
          // 이메일이 이미 다른 계정(구글 등)에 사용 중
          res.status(409).json({
            error: "EMAIL_ALREADY_EXISTS",
            message: "이미 가입된 이메일입니다."
          });
          return;
        } else {
          throw error;
        }
      }

      // 7) 초대코드 생성 (영문 대문자만, 중복 방지)
      const inviteCode = await generateUniqueInviteCode();

      // ─── 오늘 날짜(KST)로 슬롯 생성 ───
      const nowKst = new Date(Date.now() + 1000 * 60 * 60 * 9);   // UTC→KST 보정
      const gameDate = nowKst.getHours() < 5 ?
        new Date(nowKst.getTime() - 24 * 60 * 60 * 1000) :
        nowKst;

      const year = gameDate.getFullYear();
      const month = String(gameDate.getMonth() + 1).padStart(2, "0");
      const day = String(gameDate.getDate()).padStart(2, "0");
      const dateLabel = `${year}-${month}-${day}`;

      const defaultSlots = [
        { id: `morning-${dateLabel}`, timeName: "아침",  timeRangeLabel: "07-10시",  startHour: 7,  endHour:  10, status: 0, coinType: 0, reward: 0 },
        { id: `dinner-${dateLabel}`,  timeName: "저녁",  timeRangeLabel: "19-22시", startHour: 19, endHour: 22, status: 0, coinType: 0, reward: 0 },
        { id: `all-${dateLabel}`,     timeName: "완벽출석", timeRangeLabel:"한번더!",   startHour: 0,  endHour:  0, status: 0, coinType: 0, reward: 0 },
      ];

      // 8) Firestore에 사용자 문서 생성
      const batch = db.batch();
      batch.set(db.doc(`users/${uid}`), {
        uid,
        kakaoId,
        accountEmail: accountEmail || "",
        nickname,
        inviteCode,
        adId: adId || "",
        deviceId: deviceId || "",
        passwordHash: "", // Kakao 로그인은 비밀번호 없음
        money: initialMoney,
        bonusMoney: 0,
        totalEarnings: 0,
        pincruxMoney: 0,
        autoEarnPigLevel: 1,
        luckyBagCount: 200,
        rewardRefillCount: 50,
        joinDate: admin.firestore.FieldValue.serverTimestamp(),
        lastAccessTime: admin.firestore.FieldValue.serverTimestamp(),
        resetVersion: dateLabel,
        attendanceData: {
          lastResetDate: admin.firestore.FieldValue.serverTimestamp(),
          showAllClearCelebration: false,
          slots: defaultSlots
        },
        inviteFriendList: [],
        isKakao: true, // 카카오 로그인 사용자 표시
        purchaseValid: 0, // 구매 검증 상태: 0=승인(기본값)
        deviceChangeCount: 0, // 기기 변경 횟수: 0=변경없음
        ipAddress: clientIp, // 회원가입 시 IP 주소 저장
      });
      batch.set(db.doc(`nicknames/${nickname}`), { uid });
      await batch.commit();

      // 9) 초대자의 inviteFriendList에 추가 (무제한)
      if (inviterUid && shouldAddToInviteList) {
        const inviteFriend = {
          ipAddress: clientIp,
          nickname: nickname,
          isCollected: false,
          invitedAt: admin.firestore.Timestamp.now()
        };

        await db.doc(`users/${inviterUid}`).set({
          inviteFriendList: admin.firestore.FieldValue.arrayUnion(inviteFriend)
        }, { merge: true });
      }

      // 10) 기기 ID를 deviceIdList 컬렉션에 추가 (초대코드를 사용한 경우)
      if (usedInviteCode && deviceId) {
        await db.collection("deviceIdList").doc(deviceId).set({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          nickname: nickname,
          adId: adId || ""
        });
      }

      // 11) Firebase Custom Token 생성
      const token = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "kakao",
      });

      res.json({
        token,
        uid,
        isNewUser: true,
      });
    } catch (error: any) {
      console.error("Kakao 회원가입 처리 중 오류:", error);

      if (error.response?.status === 401) {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Kakao 액세스 토큰이 만료되었거나 유효하지 않습니다"
        });
      } else {
        res.status(500).json({
          error: "SERVER_ERROR",
          message: "서버 오류가 발생했습니다",
          details: error.message,
        });
      }
    }
  },
);

/**
 * 기존 사용자 카카오 계정 연동
 */
export const linkKakaoAccount = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, kakaoId, accessToken, accountEmail } = req.body ?? {};

    if (!uid || !kakaoId || !accessToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "uid, kakaoId, accessToken이 필요합니다" });
      return;
    }

    try {
      // 1) Kakao 액세스 토큰 검증
      const kakaoUserInfoUrl = "https://kapi.kakao.com/v2/user/me";
      const kakaoResponse = await axios.get(kakaoUserInfoUrl, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      const kakaoUserData = kakaoResponse.data;

      // Kakao ID 검증
      if (kakaoUserData.id.toString() !== kakaoId) {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Kakao 토큰입니다" });
        return;
      }

      // 2) 이미 다른 계정에 연동된 카카오 ID인지 확인
      const existingKakaoQuery = await db.collection("users")
        .where("kakaoId", "==", kakaoId)
        .limit(1)
        .get();

      if (!existingKakaoQuery.empty) {
        res.status(409).json({
          error: "KAKAO_ALREADY_LINKED",
          message: "이미 다른 계정에 연동된 카카오 계정입니다"
        });
        return;
      }

      // 3) 사용자 문서 확인
      const userDoc = await db.doc(`users/${uid}`).get();
      if (!userDoc.exists) {
        res.status(404).json({ error: "USER_NOT_FOUND", message: "사용자를 찾을 수 없습니다" });
        return;
      }

      // 4) 카카오 정보 연동
      await db.doc(`users/${uid}`).update({
        kakaoId,
        accountEmail: accountEmail || "",
        isKakao: true,
        lastAccessTime: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.json({
        success: true,
        message: "카카오 계정 연동이 완료되었습니다",
      });
    } catch (error: any) {
      console.error("카카오 계정 연동 중 오류:", error);

      if (error.response?.status === 401) {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Kakao 액세스 토큰이 만료되었거나 유효하지 않습니다"
        });
      } else {
        res.status(500).json({
          error: "SERVER_ERROR",
          message: "서버 오류가 발생했습니다",
          details: error.message,
        });
      }
    }
  },
);
