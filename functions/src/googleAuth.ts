import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

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
 * Google 로그인 (기존 사용자만)
 */
export const signInGoogle = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { googleId, idToken, accountEmail } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!googleId || !idToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "googleId와 idToken이 필요합니다" });
      return;
    }

    try {
      // 1) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      // Google ID 검증 (Firebase uid와 googleId 비교)
      if (decodedToken.uid !== `google_${googleId}` && decodedToken.firebase.sign_in_provider !== "google.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Google 토큰입니다" });
        return;
      }

      // 2) 기존 사용자 확인 (googleId로 검색)
      console.log(`🔍 Firestore 검색 시작: googleId=${googleId}`);

      const existingUserQuery = await db.collection("users")
        .where("googleId", "==", googleId)
        .limit(1)
        .get();

      console.log(`📊 검색 결과: ${existingUserQuery.empty ? "못 찾음 (신규)" : "찾음 (기존)"}, 검색한 googleId=${googleId}`);

      if (existingUserQuery.empty) {
        // 신규 사용자 - 회원가입 필요
        // ✅ Firebase Auth 계정은 유지 (signUpGoogle에서 재사용)
        console.log(`❌ 사용자 못 찾음 - googleId=${googleId}`);
        res.status(404).json({
          error: "USER_NOT_FOUND",
          message: "회원가입이 필요합니다",
          isNewUser: true
        });
        return;
      }

      console.log(`✅ 사용자 찾음 - UID=${existingUserQuery.docs[0].id}, googleId=${googleId}`);

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
        provider: "google",
      });

      res.json({
        token,
        isNewUser: false,
        uid,
      });
    } catch (error: any) {
      console.error("Google 로그인 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Google ID 토큰이 만료되었거나 유효하지 않습니다"
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
 * Google 회원가입 (닉네임 + 구글 계정)
 */
export const signUpGoogle = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { googleId, idToken, accountEmail, nickname, usedInviteCode, adId, deviceId } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!googleId || !idToken || !nickname) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "googleId, idToken, nickname이 필요합니다" });
      return;
    }

    try {
      // 1) deviceId 검증 - 필수값 체크
      if (!deviceId || deviceId === "" || deviceId === "unknown" || deviceId === "00000000-0000-0000-0000-000000000000") {
        res.status(400).json({
          error: "INVALID_DEVICE_ID",
          message: "유효하지 않은 기기 ID입니다"
        });
        return;
      }

      // 2) deviceId 중복 체크 - 전체 users 컬렉션에서 검색
      const existingDeviceIdQuery = await db.collection("users")
        .where("deviceId", "==", deviceId)
        .limit(1)
        .get();

      if (!existingDeviceIdQuery.empty) {
        const existingDoc = existingDeviceIdQuery.docs[0];
        const existingData = existingDoc.data();
        const existingUid = existingDoc.id;

        // ⚠️ Orphan 데이터 감지: 회원가입 실패로 불완전한 데이터가 남은 경우
        // 모든 로그인 수단(googleId, kakaoId, passwordHash)이 없으면 orphan으로 간주
        const isOrphan = !existingData.googleId && !existingData.kakaoId && !existingData.appleId && !existingData.passwordHash;

        if (isOrphan) {
          console.log(`🧹 Orphan user 데이터 감지 (deviceId: ${deviceId}), 정리 후 진행: ${existingUid}`);

          try {
            // Orphan 데이터 정리
            const batch = db.batch();

            // User 문서 삭제
            batch.delete(db.doc(`users/${existingUid}`));

            // Nickname 문서 삭제 (있는 경우)
            if (existingData.nickname) {
              batch.delete(db.doc(`nicknames/${existingData.nickname}`));
            }

            await batch.commit();

            // Firebase Auth 계정 삭제 시도
            try {
              await admin.auth().deleteUser(existingUid);
              console.log(`✅ Orphan Firebase Auth 계정 삭제: ${existingUid}`);
            } catch (authError: any) {
              console.log(`ℹ️ Orphan Firebase Auth 삭제 스킵: ${authError.message}`);
            }

            console.log("✅ Orphan user 데이터 정리 완료, 회원가입 진행");
          } catch (cleanupError: any) {
            console.error(`❌ Orphan 데이터 정리 실패: ${cleanupError.message}`);
            // 정리 실패 시 일반 중복 에러로 처리
            res.status(409).json({
              error: "DEVICE_ALREADY_REGISTERED",
              message: "이미 가입된 기기입니다"
            });
            return;
          }
        } else {
          // 완전한 데이터가 있으면 정상적인 중복 에러
          res.status(409).json({
            error: "DEVICE_ALREADY_REGISTERED",
            message: "이미 가입된 기기입니다"
          });
          return;
        }
      }

      // 3) deviceIdList 중복 체크 (초대코드 사용 시에만)
      if (usedInviteCode && deviceId) {
        const deviceIdDoc = await db.collection("deviceIdList").doc(deviceId).get();
        if (deviceIdDoc.exists) {
          // deviceIdList에 이미 존재하면 중복 에러
          res.status(409).json({
            error: "SAME_DEVICE_ERROR",
            message: "기기당 초대코드는 한 번만 입력 가능합니다"
          });
          return;
        }
      }

      // 3-1) deviceId 다중 계정 감지 - users 컬렉션에서 동일 deviceId 검색
      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        const multiAccountQuery = await db.collection("users")
          .where("deviceId", "==", deviceId)
          .get();

        // 동일 deviceId가 2개 이상이면 blockDeviceIdList에 추가 (history 방식)
        if (multiAccountQuery.size >= 2) {
          console.log(`⚠️ 동일 deviceId ${multiAccountQuery.size}개 감지: ${deviceId}`);

          // blockDeviceIdList에 추가 (history 배열 방식)
          const historyEntry = {
            uid: "", // 아직 생성 전이므로 빈 값, 나중에 업데이트 필요
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

      // 4) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      // Google ID 검증
      if (decodedToken.firebase.sign_in_provider !== "google.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Google 토큰입니다" });
        return;
      }

      // 5) 이미 가입된 사용자인지 확인 (googleId로)
      console.log(`🔍 [signUpGoogle] 중복 체크 시작: googleId=${googleId}`);

      const existingGoogleQuery = await db.collection("users")
        .where("googleId", "==", googleId)
        .limit(1)
        .get();

      if (!existingGoogleQuery.empty) {
        console.log(`❌ [signUpGoogle] 이미 가입됨 - UID=${existingGoogleQuery.docs[0].id}, googleId=${googleId}`);
        res.status(409).json({ error: "USER_ALREADY_EXISTS", message: "이미 가입된 사용자입니다" });
        return;
      }

      console.log(`✅ [signUpGoogle] 중복 없음 - 회원가입 진행, googleId=${googleId}`);

      // 5-1) accountEmail 중복 체크 (다른 로그인 방법과의 중복 방지)
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

      // 6) 닉네임 중복 확인
      const nickSnap = await db.doc(`nicknames/${nickname}`).get();
      if (nickSnap.exists) {
        res.status(409).json({ error: "NICKNAME_TAKEN", message: "이미 사용 중인 닉네임입니다" });
        return;
      }

      // 7) 초대코드 검증 및 처리
      let inviterUid: string | null = null;
      let shouldAddToInviteList = false;
      let initialMoney = 0;

      if (usedInviteCode) {
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

      // 8) Firebase Auth 계정 확인 및 사용 (Plan A: 기존 계정 재사용)
      let uid: string = decodedToken.uid;

      try {
        // 8-1) decodedToken의 uid로 계정이 존재하는지 확인
        const existingAuthUser = await admin.auth().getUser(uid);
        console.log(`✅ 기존 Firebase Auth 계정 재사용: ${uid}`);

        // 계정은 존재하지만 이메일이 다른 경우 업데이트
        if (existingAuthUser.email !== accountEmail && accountEmail) {
          await admin.auth().updateUser(uid, { email: accountEmail });
          console.log(`📧 이메일 업데이트: ${accountEmail}`);
        }
      } catch (error: any) {
        if (error.code === "auth/user-not-found") {
          // 8-2) 계정이 없으면 새로 생성
          console.log(`🆕 Firebase Auth 계정 생성 시도: ${uid}`);
          try {
            await admin.auth().createUser({
              uid: uid,
              email: accountEmail,
            });
            console.log(`✅ Firebase Auth 계정 생성 완료: ${uid}`);
          } catch (createError: any) {
            if (createError.code === "auth/email-already-exists") {
              // 이메일이 이미 다른 계정에 사용 중 → 해당 계정이 구글 계정인지 확인
              try {
                const existingUser = await admin.auth().getUserByEmail(accountEmail);
                if (existingUser.providerData.some((p) => p.providerId === "google.com")) {
                  // 구글 계정이면 그대로 사용
                  uid = existingUser.uid;
                  console.log(`✅ 기존 구글 계정 발견, 재사용: ${uid}`);
                } else {
                  // 다른 로그인 방법(카카오 등)에 사용 중
                  res.status(409).json({
                    error: "EMAIL_ALREADY_EXISTS",
                    message: "이미 가입된 이메일입니다."
                  });
                  return;
                }
              } catch (getUserError) {
                console.error("getUserByEmail 실패:", getUserError);
                throw createError;
              }
            } else {
              throw createError;
            }
          }
        } else {
          // 다른 에러는 그대로 throw
          throw error;
        }
      }

      // 9) 초대코드 생성 (영문 대문자만, 중복 방지)
      const inviteCode = await generateUniqueInviteCode();

      // 오늘 날짜(KST)로 슬롯 생성
      const nowKst = new Date(Date.now() + 1000 * 60 * 60 * 9);
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

      // 10) Firestore에 사용자 문서 생성
      const batch = db.batch();
      batch.set(db.doc(`users/${uid}`), {
        uid,
        googleId,
        accountEmail: accountEmail || "",
        nickname,
        inviteCode,
        adId: adId || "",
        deviceId: deviceId || "",
        passwordHash: "", // Google 로그인은 비밀번호 없음
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
        isGoogle: true,
        isKakao: false,
        purchaseValid: 0, // 구매 검증 상태: 0=승인(기본값)
        deviceChangeCount: 0, // 기기 변경 횟수: 0=변경없음
        ipAddress: clientIp, // 회원가입 시 IP 주소 저장
      });
      batch.set(db.doc(`nicknames/${nickname}`), { uid });
      await batch.commit();

      // 11) 초대자의 inviteFriendList에 추가 (무제한)
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

      // 12) 기기 ID를 deviceIdList 컬렉션에 추가 (초대코드를 사용한 경우)
      if (usedInviteCode && deviceId) {
        await db.collection("deviceIdList").doc(deviceId).set({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          nickname: nickname,
          adId: adId || ""
        });
      }

      // 13) Firebase Custom Token 생성
      const token = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "google",
      });

      res.json({
        token,
        uid,
        isNewUser: true,
      });
    } catch (error: any) {
      console.error("Google 회원가입 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Google ID 토큰이 만료되었거나 유효하지 않습니다"
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
 * 기존 사용자 구글 계정 연동
 */
export const linkGoogleAccount = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, googleId, idToken, accountEmail, cleanupOrphanUid } = req.body ?? {};

    if (!uid || !googleId || !idToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "uid, googleId, idToken이 필요합니다" });
      return;
    }

    try {
      // 1) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      // Google ID 검증
      if (decodedToken.firebase.sign_in_provider !== "google.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Google 토큰입니다" });
        return;
      }

      // 2) ⚠️ CRITICAL: Orphan 데이터 정리를 validation BEFORE에 수행
      // 회원가입 실패로 남은 orphan 데이터를 모두 정리
      if (cleanupOrphanUid && cleanupOrphanUid !== uid) {
        console.log(`🧹 Orphan 데이터 정리 시작: ${cleanupOrphanUid}`);

        try {
          // 2-1) Orphan Firestore 문서 삭제
          const orphanUserDoc = await db.doc(`users/${cleanupOrphanUid}`).get();
          if (orphanUserDoc.exists) {
            const orphanData = orphanUserDoc.data();
            console.log(`📄 Orphan Firestore 문서 발견: ${cleanupOrphanUid}`, orphanData);

            // Batch 작업으로 관련 데이터 정리
            const batch = db.batch();

            // Orphan user 문서 삭제
            batch.delete(db.doc(`users/${cleanupOrphanUid}`));

            // Orphan nickname 문서 삭제 (있는 경우)
            if (orphanData?.nickname) {
              const nicknameRef = db.doc(`nicknames/${orphanData.nickname}`);
              batch.delete(nicknameRef);
              console.log(`🔤 Orphan nickname 삭제 예정: ${orphanData.nickname}`);
            }

            await batch.commit();
            console.log(`✅ Orphan Firestore 문서 삭제 완료: ${cleanupOrphanUid}`);
          }

          // 2-2) Orphan Firebase Auth 계정 삭제
          try {
            await admin.auth().deleteUser(cleanupOrphanUid);
            console.log(`✅ Orphan Firebase Auth 계정 삭제 완료: ${cleanupOrphanUid}`);
          } catch (authError: any) {
            // 이미 삭제되었거나 존재하지 않을 수 있음 (정상)
            console.log(`ℹ️ Orphan Firebase Auth 삭제 스킵: ${authError.message}`);
          }

          // 2-3) Orphan deviceIdList 항목 정리 (uid로 검색)
          const orphanDeviceIdQuery = await db.collection("deviceIdList")
            .where("uid", "==", cleanupOrphanUid)
            .get();

          if (!orphanDeviceIdQuery.empty) {
            const deleteBatch = db.batch();
            orphanDeviceIdQuery.docs.forEach((doc) => {
              deleteBatch.delete(doc.ref);
              console.log(`🗑️ Orphan deviceIdList 삭제 예정: ${doc.id}`);
            });
            await deleteBatch.commit();
            console.log("✅ Orphan deviceIdList 항목 삭제 완료");
          }
        } catch (cleanupError: any) {
          // 정리 실패는 경고만 출력하고 계속 진행
          console.warn(`⚠️ Orphan 데이터 정리 중 오류 (계속 진행): ${cleanupError.message}`);
        }
      }

      // 3) Firestore에서 원래 사용자 확인
      const userDoc = await db.doc(`users/${uid}`).get();
      if (!userDoc.exists) {
        res.status(404).json({ error: "USER_NOT_FOUND", message: "사용자를 찾을 수 없습니다" });
        return;
      }

      const userData = userDoc.data();

      // 4) 이미 구글 계정이 연동되어 있는지 확인
      if (userData?.googleId) {
        res.status(409).json({ error: "ALREADY_LINKED", message: "이미 구글 계정이 연동되어 있습니다" });
        return;
      }

      // 5) 해당 구글 계정이 다른 사용자에게 사용되고 있는지 확인
      // ⚠️ orphan 정리 후 검사하므로 orphan 데이터는 더 이상 발견되지 않음
      const existingGoogleQuery = await db.collection("users")
        .where("googleId", "==", googleId)
        .limit(1)
        .get();

      if (!existingGoogleQuery.empty) {
        const existingDoc = existingGoogleQuery.docs[0];
        const existingUid = existingDoc.id;

        // 만약 발견된 계정이 원래 연동하려는 계정과 동일하면 정상 진행
        if (existingUid === uid) {
          console.log(`ℹ️ 동일 계정 감지 (정상): ${uid}`);
        } else {
          res.status(409).json({ error: "GOOGLE_ALREADY_USED", message: "이미 다른 계정에 연동된 구글 계정입니다" });
          return;
        }
      }

      // 6) Firestore 사용자 정보 업데이트
      console.log(`📝 Firestore 업데이트 시도: uid=${uid}, googleId=${googleId}, accountEmail=${accountEmail}`);

      await db.doc(`users/${uid}`).update({
        googleId: googleId,
        accountEmail: accountEmail || "",
        isGoogle: true,
      });

      console.log(`✅ 구글 계정 연동 완료: ${uid} → ${googleId}`);

      // 6) 원래 계정의 커스텀 토큰 생성 (클라이언트가 원래 계정으로 복원할 수 있도록)
      const customToken = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "password+google",
      });

      res.json({
        success: true,
        message: "구글 계정 연동이 완료되었습니다",
        customToken: customToken, // 원래 계정 복원용 커스텀 토큰
      });
    } catch (error: any) {
      console.error("구글 계정 연동 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Google ID 토큰이 만료되었거나 유효하지 않습니다"
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
