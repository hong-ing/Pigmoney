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
  const maxAttempts = 10;

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const randomBytes = crypto.randomBytes(8);
    let code = "";
    for (let i = 0; i < 8; i++) {
      code += chars[randomBytes[i] % chars.length];
    }

    const existingCode = await db.collection("users")
      .where("inviteCode", "==", code)
      .limit(1)
      .get();

    if (existingCode.empty) {
      console.log(`✅ 고유 초대코드 생성 성공: ${code} (시도 횟수: ${attempt + 1})`);
      return code;
    }

    console.log(`⚠️ 초대코드 중복 감지: ${code}, 재생성 중... (시도 ${attempt + 1}/${maxAttempts})`);
  }

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
    const ip = Array.isArray(forwardedFor) ? forwardedFor[0] : forwardedFor;
    return ip.split(",")[0].trim();
  }
  return req.ip || req.connection?.remoteAddress || "unknown";
}

/**
 * Apple 로그인 (기존 사용자만)
 */
export const signInApple = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { appleId, idToken, accountEmail } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!appleId || !idToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "appleId와 idToken이 필요합니다" });
      return;
    }

    try {
      // 1) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      // Apple ID 검증
      if (decodedToken.firebase.sign_in_provider !== "apple.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Apple 토큰입니다" });
        return;
      }

      // 2) 기존 사용자 확인 (appleId로 검색)
      console.log(`🔍 Firestore 검색 시작: appleId=${appleId}`);

      const existingUserQuery = await db.collection("users")
        .where("appleId", "==", appleId)
        .limit(1)
        .get();

      console.log(`📊 검색 결과: ${existingUserQuery.empty ? "못 찾음 (신규)" : "찾음 (기존)"}, 검색한 appleId=${appleId}`);

      if (existingUserQuery.empty) {
        // 신규 사용자 - 회원가입 필요
        console.log(`❌ 사용자 못 찾음 - appleId=${appleId}`);
        res.status(404).json({
          error: "USER_NOT_FOUND",
          message: "회원가입이 필요합니다",
          isNewUser: true,
        });
        return;
      }

      console.log(`✅ 사용자 찾음 - UID=${existingUserQuery.docs[0].id}, appleId=${appleId}`);

      const existingUserDoc = existingUserQuery.docs[0];
      const uid = existingUserDoc.id;

      // 프로필 업데이트
      const updates: any = {
        lastAccessTime: admin.firestore.FieldValue.serverTimestamp(),
        ipAddress: clientIp,
      };

      // Apple은 첫 로그인 시에만 email을 반환하므로, 비어있지 않을 때만 업데이트
      if (accountEmail && accountEmail !== existingUserDoc.data().accountEmail) {
        updates.accountEmail = accountEmail;
      }

      await db.doc(`users/${uid}`).update(updates);

      // 3) Firebase Custom Token 생성
      const token = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "apple",
      });

      res.json({
        token,
        isNewUser: false,
        uid,
      });
    } catch (error: any) {
      console.error("Apple 로그인 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Apple ID 토큰이 만료되었거나 유효하지 않습니다",
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
 * Apple 회원가입 (닉네임 + 애플 계정)
 */
export const signUpApple = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { appleId, idToken, accountEmail, nickname, usedInviteCode, adId, deviceId } = req.body ?? {};
    const clientIp = getClientIp(req);

    if (!appleId || !idToken || !nickname) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "appleId, idToken, nickname이 필요합니다" });
      return;
    }

    try {
      // 1) deviceId 검증
      if (!deviceId || deviceId === "" || deviceId === "unknown" || deviceId === "00000000-0000-0000-0000-000000000000") {
        res.status(400).json({
          error: "INVALID_DEVICE_ID",
          message: "유효하지 않은 기기 ID입니다",
        });
        return;
      }

      // 2) deviceId 중복 체크 (orphan 정리 포함)
      const existingDeviceIdQuery = await db.collection("users")
        .where("deviceId", "==", deviceId)
        .limit(1)
        .get();

      if (!existingDeviceIdQuery.empty) {
        const existingDoc = existingDeviceIdQuery.docs[0];
        const existingData = existingDoc.data();
        const existingUid = existingDoc.id;

        const isOrphan = !existingData.googleId && !existingData.kakaoId && !existingData.appleId && !existingData.passwordHash;

        if (isOrphan) {
          console.log(`🧹 Orphan user 데이터 감지 (deviceId: ${deviceId}), 정리 후 진행: ${existingUid}`);

          try {
            const batch = db.batch();
            batch.delete(db.doc(`users/${existingUid}`));
            if (existingData.nickname) {
              batch.delete(db.doc(`nicknames/${existingData.nickname}`));
            }
            await batch.commit();

            try {
              await admin.auth().deleteUser(existingUid);
              console.log(`✅ Orphan Firebase Auth 계정 삭제: ${existingUid}`);
            } catch (authError: any) {
              console.log(`ℹ️ Orphan Firebase Auth 삭제 스킵: ${authError.message}`);
            }
            console.log("✅ Orphan user 데이터 정리 완료, 회원가입 진행");
          } catch (cleanupError: any) {
            console.error(`❌ Orphan 데이터 정리 실패: ${cleanupError.message}`);
            res.status(409).json({
              error: "DEVICE_ALREADY_REGISTERED",
              message: "이미 가입된 기기입니다",
            });
            return;
          }
        } else {
          res.status(409).json({
            error: "DEVICE_ALREADY_REGISTERED",
            message: "이미 가입된 기기입니다",
          });
          return;
        }
      }

      // 3) deviceIdList 중복 체크 (초대코드 사용 시)
      if (usedInviteCode && deviceId) {
        const deviceIdDoc = await db.collection("deviceIdList").doc(deviceId).get();
        if (deviceIdDoc.exists) {
          res.status(409).json({
            error: "SAME_DEVICE_ERROR",
            message: "기기당 초대코드는 한 번만 입력 가능합니다",
          });
          return;
        }
      }

      // 3-1) deviceId 다중 계정 감지
      if (deviceId && deviceId !== "" && deviceId !== "unknown") {
        const multiAccountQuery = await db.collection("users")
          .where("deviceId", "==", deviceId)
          .get();

        if (multiAccountQuery.size >= 2) {
          console.log(`⚠️ 동일 deviceId ${multiAccountQuery.size}개 감지: ${deviceId}`);

          const historyEntry = {
            uid: "",
            nickname: nickname,
            reason: "duplicate",
            createdAt: admin.firestore.Timestamp.now(),
          };

          const blockDoc = await db.collection("blockDeviceIdList").doc(deviceId).get();
          if (blockDoc.exists) {
            await db.collection("blockDeviceIdList").doc(deviceId).update({
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              history: admin.firestore.FieldValue.arrayUnion(historyEntry),
            });
          } else {
            await db.collection("blockDeviceIdList").doc(deviceId).set({
              deviceId: deviceId,
              adId: adId || "",
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              history: [historyEntry],
            });
          }
          console.log(`✅ blockDeviceIdList에 ${deviceId} 추가/업데이트 완료`);
        }
      }

      // 4) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      if (decodedToken.firebase.sign_in_provider !== "apple.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Apple 토큰입니다" });
        return;
      }

      // 5) 이미 가입된 사용자인지 확인 (appleId로)
      console.log(`🔍 [signUpApple] 중복 체크 시작: appleId=${appleId}`);

      const existingAppleQuery = await db.collection("users")
        .where("appleId", "==", appleId)
        .limit(1)
        .get();

      if (!existingAppleQuery.empty) {
        console.log(`❌ [signUpApple] 이미 가입됨 - UID=${existingAppleQuery.docs[0].id}, appleId=${appleId}`);
        res.status(409).json({ error: "USER_ALREADY_EXISTS", message: "이미 가입된 사용자입니다" });
        return;
      }

      console.log(`✅ [signUpApple] 중복 없음 - 회원가입 진행, appleId=${appleId}`);

      // 5-1) accountEmail 중복 체크 (Apple은 첫 로그인 시에만 email 제공이므로 빈 값일 수 있음)
      if (accountEmail) {
        const existingEmailQuery = await db.collection("users")
          .where("accountEmail", "==", accountEmail)
          .limit(1)
          .get();

        if (!existingEmailQuery.empty) {
          res.status(409).json({
            error: "EMAIL_ALREADY_EXISTS",
            message: "이미 가입된 이메일입니다.",
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
          initialMoney = 300000;
          shouldAddToInviteList = true;
        }
      }

      // 8) Firebase Auth 계정 확인 및 사용
      let uid: string = decodedToken.uid;

      try {
        const existingAuthUser = await admin.auth().getUser(uid);
        console.log(`✅ 기존 Firebase Auth 계정 재사용: ${uid}`);

        if (accountEmail && existingAuthUser.email !== accountEmail) {
          try {
            await admin.auth().updateUser(uid, { email: accountEmail });
            console.log(`📧 이메일 업데이트: ${accountEmail}`);
          } catch (updateError: any) {
            // 이메일 업데이트 실패는 무시 (Apple은 private relay 이메일을 사용할 수 있음)
            console.log(`ℹ️ 이메일 업데이트 스킵: ${updateError.message}`);
          }
        }
      } catch (error: any) {
        if (error.code === "auth/user-not-found") {
          console.log(`🆕 Firebase Auth 계정 생성 시도: ${uid}`);
          try {
            await admin.auth().createUser({
              uid: uid,
              email: accountEmail || undefined,
            });
            console.log(`✅ Firebase Auth 계정 생성 완료: ${uid}`);
          } catch (createError: any) {
            if (createError.code === "auth/email-already-exists" && accountEmail) {
              try {
                const existingUser = await admin.auth().getUserByEmail(accountEmail);
                if (existingUser.providerData.some((p) => p.providerId === "apple.com")) {
                  uid = existingUser.uid;
                  console.log(`✅ 기존 애플 계정 발견, 재사용: ${uid}`);
                } else {
                  res.status(409).json({
                    error: "EMAIL_ALREADY_EXISTS",
                    message: "이미 가입된 이메일입니다.",
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
          throw error;
        }
      }

      // 9) 초대코드 생성
      const inviteCode = await generateUniqueInviteCode();

      const nowKst = new Date(Date.now() + 1000 * 60 * 60 * 9);
      const gameDate = nowKst.getHours() < 5 ?
        new Date(nowKst.getTime() - 24 * 60 * 60 * 1000) :
        nowKst;

      const year = gameDate.getFullYear();
      const month = String(gameDate.getMonth() + 1).padStart(2, "0");
      const day = String(gameDate.getDate()).padStart(2, "0");
      const dateLabel = `${year}-${month}-${day}`;

      const defaultSlots = [
        { id: `morning-${dateLabel}`, timeName: "아침", timeRangeLabel: "07-10시", startHour: 7, endHour: 10, status: 0, coinType: 0, reward: 0 },
        { id: `dinner-${dateLabel}`, timeName: "저녁", timeRangeLabel: "19-22시", startHour: 19, endHour: 22, status: 0, coinType: 0, reward: 0 },
        { id: `all-${dateLabel}`, timeName: "완벽출석", timeRangeLabel: "한번더!", startHour: 0, endHour: 0, status: 0, coinType: 0, reward: 0 },
      ];

      // 10) Firestore에 사용자 문서 생성
      const batch = db.batch();
      batch.set(db.doc(`users/${uid}`), {
        uid,
        appleId,
        accountEmail: accountEmail || "",
        nickname,
        inviteCode,
        adId: adId || "",
        deviceId: deviceId || "",
        passwordHash: "",
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
          slots: defaultSlots,
        },
        inviteFriendList: [],
        isApple: true,
        isGoogle: false,
        isKakao: false,
        purchaseValid: 0,
        deviceChangeCount: 0,
        ipAddress: clientIp,
      });
      batch.set(db.doc(`nicknames/${nickname}`), { uid });
      await batch.commit();

      // 11) 초대자의 inviteFriendList에 추가
      if (inviterUid && shouldAddToInviteList) {
        const inviteFriend = {
          ipAddress: clientIp,
          nickname: nickname,
          isCollected: false,
          invitedAt: admin.firestore.Timestamp.now(),
        };

        await db.doc(`users/${inviterUid}`).set({
          inviteFriendList: admin.firestore.FieldValue.arrayUnion(inviteFriend),
        }, { merge: true });
      }

      // 12) deviceIdList 추가
      if (usedInviteCode && deviceId) {
        await db.collection("deviceIdList").doc(deviceId).set({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          nickname: nickname,
          adId: adId || "",
        });
      }

      // 13) Firebase Custom Token 생성
      const token = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "apple",
      });

      res.json({
        token,
        uid,
        isNewUser: true,
      });
    } catch (error: any) {
      console.error("Apple 회원가입 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Apple ID 토큰이 만료되었거나 유효하지 않습니다",
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
 * 기존 사용자 애플 계정 연동
 */
export const linkAppleAccount = onRequest(
  { region: "asia-northeast3" },
  async (req, res) => {
    const { uid, appleId, idToken, accountEmail, cleanupOrphanUid } = req.body ?? {};

    if (!uid || !appleId || !idToken) {
      res.status(400).json({ error: "MISSING_PARAMS", message: "uid, appleId, idToken이 필요합니다" });
      return;
    }

    try {
      // 1) Firebase ID 토큰 검증
      const decodedToken = await admin.auth().verifyIdToken(idToken);

      if (decodedToken.firebase.sign_in_provider !== "apple.com") {
        res.status(401).json({ error: "INVALID_TOKEN", message: "유효하지 않은 Apple 토큰입니다" });
        return;
      }

      // 2) Orphan 데이터 정리
      if (cleanupOrphanUid && cleanupOrphanUid !== uid) {
        console.log(`🧹 Orphan 데이터 정리 시작: ${cleanupOrphanUid}`);

        try {
          const orphanUserDoc = await db.doc(`users/${cleanupOrphanUid}`).get();
          if (orphanUserDoc.exists) {
            const orphanData = orphanUserDoc.data();
            const batch = db.batch();
            batch.delete(db.doc(`users/${cleanupOrphanUid}`));
            if (orphanData?.nickname) {
              batch.delete(db.doc(`nicknames/${orphanData.nickname}`));
            }
            await batch.commit();
            console.log(`✅ Orphan Firestore 문서 삭제 완료: ${cleanupOrphanUid}`);
          }

          try {
            await admin.auth().deleteUser(cleanupOrphanUid);
            console.log(`✅ Orphan Firebase Auth 계정 삭제 완료: ${cleanupOrphanUid}`);
          } catch (authError: any) {
            console.log(`ℹ️ Orphan Firebase Auth 삭제 스킵: ${authError.message}`);
          }

          const orphanDeviceIdQuery = await db.collection("deviceIdList")
            .where("uid", "==", cleanupOrphanUid)
            .get();

          if (!orphanDeviceIdQuery.empty) {
            const deleteBatch = db.batch();
            orphanDeviceIdQuery.docs.forEach((doc) => {
              deleteBatch.delete(doc.ref);
            });
            await deleteBatch.commit();
            console.log("✅ Orphan deviceIdList 항목 삭제 완료");
          }
        } catch (cleanupError: any) {
          console.warn(`⚠️ Orphan 데이터 정리 중 오류 (계속 진행): ${cleanupError.message}`);
        }
      }

      // 3) 원래 사용자 확인
      const userDoc = await db.doc(`users/${uid}`).get();
      if (!userDoc.exists) {
        res.status(404).json({ error: "USER_NOT_FOUND", message: "사용자를 찾을 수 없습니다" });
        return;
      }

      const userData = userDoc.data();

      // 4) 이미 애플 계정이 연동되어 있는지 확인
      if (userData?.appleId) {
        res.status(409).json({ error: "ALREADY_LINKED", message: "이미 애플 계정이 연동되어 있습니다" });
        return;
      }

      // 5) 해당 애플 계정이 다른 사용자에게 연결되어 있는지 확인
      const existingAppleQuery = await db.collection("users")
        .where("appleId", "==", appleId)
        .limit(1)
        .get();

      if (!existingAppleQuery.empty) {
        const existingDoc = existingAppleQuery.docs[0];
        const existingUid = existingDoc.id;

        if (existingUid === uid) {
          console.log(`ℹ️ 동일 계정 감지 (정상): ${uid}`);
        } else {
          res.status(409).json({ error: "APPLE_ALREADY_USED", message: "이미 다른 계정에 연동된 애플 계정입니다" });
          return;
        }
      }

      // 6) Firestore 사용자 정보 업데이트
      console.log(`📝 Firestore 업데이트 시도: uid=${uid}, appleId=${appleId}, accountEmail=${accountEmail}`);

      const updateData: any = {
        appleId: appleId,
        isApple: true,
      };

      // accountEmail이 있을 때만 업데이트 (Apple은 첫 로그인 시에만 제공)
      if (accountEmail) {
        updateData.accountEmail = accountEmail;
      }

      await db.doc(`users/${uid}`).update(updateData);

      console.log(`✅ 애플 계정 연동 완료: ${uid} → ${appleId}`);

      // 7) 원래 계정의 커스텀 토큰 생성
      const customToken = await admin.auth().createCustomToken(uid, {
        role: "user",
        provider: "password+apple",
      });

      res.json({
        success: true,
        message: "애플 계정 연동이 완료되었습니다",
        customToken: customToken,
      });
    } catch (error: any) {
      console.error("애플 계정 연동 처리 중 오류:", error);

      if (error.code === "auth/id-token-expired" || error.code === "auth/argument-error") {
        res.status(401).json({
          error: "INVALID_TOKEN",
          message: "Apple ID 토큰이 만료되었거나 유효하지 않습니다",
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
