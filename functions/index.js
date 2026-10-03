/**
 * Cloud Functions for Portfolio Services Dashboard (PSD).
 *
 * Everything that must not be trusted to the browser happens here:
 *   claimAdmin             one-time — first allowed Google sign-in becomes the only admin
 *   syncCampusStay         admin  — import/refresh providers from Campus Stay (also every 30 min)
 *   createProviderAccount  admin  — create the provider's dashboard login
 *   campusStayProfile      student — prefill the request form from their Campus Stay account
 *   submitRequest          student (anonymous) — validate + store a service request
 *   updateRequestStatus    provider/admin — move a request through its lifecycle
 */
const { setGlobalOptions } = require("firebase-functions/v2");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");

// Keep in sync with kFunctionsRegion in lib/config.dart.
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

// The only Google account allowed to claim admin. Asked for on first
// `firebase deploy` and saved in functions/.env.<project> (kept out of git).
const ADMIN_EMAIL = defineString("ADMIN_EMAIL", {
  description: "Google email of the PSD admin (the only account that can claim admin)",
});

initializeApp();
const db = getFirestore();

// Campus Stay Ghana's Firebase project is the source of truth for service
// providers. These functions read it with their own service account, which
// needs the "Cloud Datastore Viewer" role on that project (read-only).
const CAMPUS_STAY_PROJECT = "campus-stay-gh";
const campusStayDb = getFirestore(initializeApp({ projectId: CAMPUS_STAY_PROJECT }, "campusStay"));

const NEXT_STATUSES = {
  pending: ["accepted", "rejected"],
  accepted: ["scheduled", "in_progress", "cancelled"],
  scheduled: ["in_progress", "cancelled"],
  in_progress: ["completed", "cancelled"],
  completed: [],
  rejected: [],
  cancelled: [],
};
const SOURCES = ["campus_stay", "direct"];
const MAX_PHOTOS = 3;
const MAX_REQUESTS_PER_HOUR = 5;

// ------------------------------------------------------------------ helpers

function str(value, field, { min = 0, max = 500 } = {}) {
  const s = typeof value === "string" ? value.trim() : "";
  if (s.length < min) throw new HttpsError("invalid-argument", `${field} is required.`);
  if (s.length > max) throw new HttpsError("invalid-argument", `${field} is too long.`);
  return s;
}

function slugify(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/** "Plug Doctor" -> "PD", used for request numbers like PD-0001. */
function refPrefix(name) {
  const letters = String(name)
    .split(/\s+/)
    .map((w) => w.replace(/[^A-Za-z0-9]/g, "")[0])
    .filter(Boolean)
    .join("")
    .toUpperCase()
    .slice(0, 3);
  return letters.length >= 2 ? letters : String(name).replace(/[^A-Za-z]/g, "").slice(0, 3).toUpperCase() || "REQ";
}

async function profileOf(uid) {
  const snap = await db.doc(`users/${uid}`).get();
  return snap.exists ? snap.data() : null;
}

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Please sign in.");
  return request.auth.uid;
}

async function requireAdmin(request) {
  const uid = requireAuth(request);
  const profile = await profileOf(uid);
  if (profile?.role !== "admin") throw new HttpsError("permission-denied", "Admins only.");
  return uid;
}

// ---------------------------------------------------------------- claimAdmin

/**
 * One-time admin setup. The first Google sign-in whose email matches
 * ADMIN_EMAIL becomes admin; config/admin then locks the role to that uid
 * forever, so no one else can ever claim it.
 */
exports.claimAdmin = onCall(async (request) => {
  const uid = requireAuth(request);
  const token = request.auth.token;
  if (token.firebase?.sign_in_provider !== "google.com" || !token.email_verified) {
    throw new HttpsError("permission-denied", "Admin setup requires signing in with Google.");
  }
  const email = String(token.email || "").toLowerCase();
  const allowed = ADMIN_EMAIL.value().trim().toLowerCase();

  const lockRef = db.doc("config/admin");
  await db.runTransaction(async (tx) => {
    const lock = await tx.get(lockRef);
    if (lock.exists) {
      if (lock.data().uid === uid) return; // already the admin — nothing to do
      throw new HttpsError("permission-denied", "This Google account is not the PSD admin.");
    }
    if (!allowed || email !== allowed) {
      throw new HttpsError("permission-denied", "This Google account is not the PSD admin.");
    }
    tx.set(lockRef, { uid, email, claimedAt: FieldValue.serverTimestamp() });
    tx.set(db.doc(`users/${uid}`), {
      role: "admin",
      email,
      displayName: token.name || "",
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

// ------------------------------------------------------------ syncCampusStay

/**
 * Mirrors Campus Stay's `service_providers` into PSD `providers`, using the
 * same document id. Campus Stay owns the business details (name, description,
 * category, services, location, photos, phone, status); PSD only adds its own
 * fields (slug/link, login, request counter, logo, tagline, hours, prices).
 * A provider's link (slug) is fixed the first time it is imported.
 */
async function syncCampusStay() {
  const [csSnap, psdSnap, slugSnap] = await Promise.all([
    campusStayDb.collection("service_providers").get(),
    db.collection("providers").get(),
    db.collection("slugs").get(),
  ]);
  const existing = new Map(psdSnap.docs.map((d) => [d.id, d.data()]));
  const takenSlugs = new Set(slugSnap.docs.map((d) => d.id));
  const seen = new Set();
  const writes = [];
  let created = 0;
  let updated = 0;
  let removed = 0;

  for (const doc of csSnap.docs) {
    const d = doc.data();
    const id = doc.id;
    const name = String(d.businessName || "").trim();
    if (!name) continue;
    seen.add(id);
    const cur = existing.get(id);

    // Keep prices/descriptions the provider added in PSD, matched by service name.
    const previous = new Map((cur?.services || []).map((s) => [String(s.name).toLowerCase(), s]));
    const usedIds = new Set();
    const services = (Array.isArray(d.services) ? d.services : [])
      .map((n) => String(n).trim())
      .filter(Boolean)
      .map((n) => {
        const prev = previous.get(n.toLowerCase());
        let sid = prev?.id || slugify(n) || "service";
        while (usedIds.has(sid)) sid += "-x";
        usedIds.add(sid);
        return { id: sid, name: n, description: prev?.description || "", priceFrom: prev?.priceFrom ?? null };
      });

    const fields = {
      campusStayId: id,
      name,
      description: String(d.description || ""),
      category: [d.categoryName, d.subcategoryName].filter(Boolean).join(" · "),
      location: [d.area, d.campusName].filter(Boolean).join(", "),
      phone: String(d.phone || ""),
      whatsapp: String(d.whatsapp || ""),
      csPhotos: (Array.isArray(d.photos) ? d.photos : []).map(String),
      isVerified: d.isVerified === true,
      services,
      status: d.status === "hidden" ? "suspended" : "active",
      syncedAt: FieldValue.serverTimestamp(),
    };

    if (!cur) {
      const base = slugify(name) || "service";
      let slug = base;
      for (let n = 2; takenSlugs.has(slug); n++) slug = `${base}-${n}`;
      takenSlugs.add(slug);
      writes.push((b) => b.set(db.doc(`slugs/${slug}`), { providerId: id, createdAt: FieldValue.serverTimestamp() }));
      Object.assign(fields, {
        slug,
        tagline: "",
        hours: "",
        email: "",
        logoUrl: null,
        coverUrl: null,
        gallery: [],
        ownerUid: null,
        refPrefix: refPrefix(name),
        requestCounter: 0,
        createdAt: FieldValue.serverTimestamp(),
      });
      created++;
    } else {
      updated++;
    }
    writes.push((b) => b.set(db.doc(`providers/${id}`), fields, { merge: true }));
  }

  // Deleted from Campus Stay → hide the portfolio (requests and link are kept).
  for (const [id, p] of existing) {
    if (p.campusStayId && !seen.has(id) && p.status !== "removed") {
      writes.push((b) => b.update(db.doc(`providers/${id}`), { status: "removed", syncedAt: FieldValue.serverTimestamp() }));
      removed++;
    }
  }

  for (let i = 0; i < writes.length; i += 400) {
    const batch = db.batch();
    writes.slice(i, i + 400).forEach((w) => w(batch));
    await batch.commit();
  }
  await db.doc("config/sync").set({ lastSyncedAt: FieldValue.serverTimestamp(), created, updated, removed });
  return { created, updated, removed, total: seen.size };
}

function explainSyncError(e) {
  if (e.code === 7 || /PERMISSION_DENIED/i.test(e.message)) {
    return new HttpsError(
      "failed-precondition",
      "PSD can't read Campus Stay yet. Grant this project's service account the " +
        "\"Cloud Datastore Viewer\" role on campus-stay-gh (see README).",
    );
  }
  return e;
}

exports.syncCampusStay = onCall({ timeoutSeconds: 300 }, async (request) => {
  await requireAdmin(request);
  try {
    return await syncCampusStay();
  } catch (e) {
    throw explainSyncError(e);
  }
});

exports.scheduledCampusStaySync = onSchedule({ schedule: "every 30 minutes", timeoutSeconds: 300 }, async () => {
  await syncCampusStay();
});

// ----------------------------------------------------- createProviderAccount

exports.createProviderAccount = onCall(async (request) => {
  await requireAdmin(request);
  const d = request.data || {};
  const providerId = str(d.providerId, "providerId", { min: 1, max: 100 });
  const email = str(d.email, "Email", { min: 3, max: 200 }).toLowerCase();
  const password = typeof d.password === "string" ? d.password : "";
  const displayName = str(d.displayName, "Name", { max: 100 });
  if (!email.includes("@")) throw new HttpsError("invalid-argument", "Enter a valid email.");
  if (password.length < 8) throw new HttpsError("invalid-argument", "Password must be at least 8 characters.");

  const providerRef = db.doc(`providers/${providerId}`);
  if (!(await providerRef.get()).exists) throw new HttpsError("not-found", "Provider not found.");

  const auth = getAuth();
  let user;
  let existed = false;
  try {
    user = await auth.getUserByEmail(email);
    existed = true;
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    user = await auth.createUser({ email, password, displayName });
  }

  const existing = await profileOf(user.uid);
  if (existing?.role === "admin") {
    throw new HttpsError("failed-precondition", "That email belongs to an admin account.");
  }
  if (existing?.providerId && existing.providerId !== providerId) {
    throw new HttpsError("failed-precondition", "That email is already linked to another provider.");
  }

  await db.doc(`users/${user.uid}`).set(
    { role: "provider", providerId, email, displayName, createdAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await db.runTransaction(async (tx) => {
    const p = await tx.get(providerRef);
    if (!p.data().ownerUid) tx.update(providerRef, { ownerUid: user.uid });
  });

  return { uid: user.uid, existed };
});

// --------------------------------------------------------- campusStayProfile

/**
 * Finds the Campus Stay student behind a PSD sign-in. Only a Google sign-in
 * with a verified email counts as proof of owning that Campus Stay account.
 * Returns just what a request needs — never ID documents or other private data.
 */
async function campusStayStudentFor(auth) {
  const t = auth?.token;
  if (!t || t.firebase?.sign_in_provider !== "google.com" || !t.email_verified || !t.email) return null;
  const emails = [...new Set([t.email, t.email.toLowerCase()])];
  const q = await campusStayDb.collection("users").where("email", "in", emails).limit(5).get();
  const doc = q.docs.find((d) => d.data().role === "student" && d.data().isSuspended !== true);
  if (!doc) return null;
  const u = doc.data();

  let hostel = "";
  if (u.activePropertyId) {
    const h = await campusStayDb.doc(`hostels/${u.activePropertyId}`).get();
    if (h.exists) hostel = [h.data().name, h.data().area].filter(Boolean).join(", ");
  }
  return {
    uid: doc.id,
    name: String(u.name || ""),
    phone: String(u.phoneNumber || ""),
    email: String(u.email || ""),
    school: String(u.schoolName || u.school || ""),
    hostel,
  };
}

exports.campusStayProfile = onCall(async (request) => {
  requireAuth(request);
  let student;
  try {
    student = await campusStayStudentFor(request.auth);
  } catch (e) {
    throw explainSyncError(e);
  }
  if (!student) {
    throw new HttpsError("not-found", "No Campus Stay student account uses this Google email. Fill in your details below.");
  }
  const { uid: _uid, ...profile } = student;
  return profile;
});

// ------------------------------------------------------------- submitRequest

exports.submitRequest = onCall(async (request) => {
  const uid = requireAuth(request); // anonymous auth is fine
  const d = request.data || {};

  const providerId = str(d.providerId, "providerId", { min: 1, max: 100 });
  const serviceId = str(d.serviceId, "Service", { max: 120 });
  const studentName = str(d.studentName, "Your name", { min: 2, max: 80 });
  const studentPhone = str(d.studentPhone, "Phone number", { min: 9, max: 30 });
  if (studentPhone.replace(/\D/g, "").length < 9) {
    throw new HttpsError("invalid-argument", "Enter a valid phone number.");
  }
  const studentEmail = str(d.studentEmail, "Email", { max: 200 });
  const location = str(d.location, "Location", { min: 1, max: 160 });
  const preferredDate = str(d.preferredDate, "Preferred date", { max: 20 });
  const preferredTime = str(d.preferredTime, "Preferred time", { max: 20 });
  const description = str(d.description, "Description", { min: 5, max: 1000 });
  const sourcePlatform = SOURCES.includes(d.source) ? d.source : "direct";
  const uploads = (Array.isArray(d.uploads) ? d.uploads : [])
    .filter((p) => typeof p === "string" && new RegExp(`^uploads/${uid}/[^/]+$`).test(p))
    .slice(0, MAX_PHOTOS);

  // Basic spam protection: a browser session can't flood a provider.
  const hourAgo = Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
  const recent = await db
    .collection("serviceRequests")
    .where("submittedBy", "==", uid)
    .where("createdAt", ">", hourAgo)
    .count()
    .get();
  if (recent.data().count >= MAX_REQUESTS_PER_HOUR) {
    throw new HttpsError("resource-exhausted", "You've sent several requests recently. Please try again later.");
  }

  // Signed in with Google as a Campus Stay student? Link the request to them.
  // A lookup failure must never block the request itself.
  const csStudent = await campusStayStudentFor(request.auth).catch((e) => {
    console.warn("Campus Stay student lookup failed", e.message);
    return null;
  });

  const providerRef = db.doc(`providers/${providerId}`);
  const requestRef = db.collection("serviceRequests").doc();
  let ref;

  await db.runTransaction(async (tx) => {
    const provider = await tx.get(providerRef);
    if (!provider.exists || provider.data().status !== "active") {
      throw new HttpsError("not-found", "This service is not available right now.");
    }
    const p = provider.data();
    const service = (p.services || []).find((s) => s.id === serviceId);
    const counter = (p.requestCounter || 0) + 1;
    ref = `${p.refPrefix || "REQ"}-${String(counter).padStart(4, "0")}`;
    const now = Timestamp.now();

    tx.update(providerRef, { requestCounter: counter });
    tx.set(requestRef, {
      ref,
      providerId,
      providerName: p.name,
      serviceId: service ? service.id : "other",
      serviceName: service ? service.name : "Other request",
      studentName,
      studentPhone,
      studentEmail,
      studentVerified: csStudent != null,
      campusStayStudentId: csStudent?.uid ?? null,
      studentSchool: csStudent?.school ?? "",
      location,
      preferredDate,
      preferredTime,
      description,
      attachments: [],
      sourcePlatform,
      status: "pending",
      statusHistory: [{ status: "pending", at: now, by: "student", note: "" }],
      submittedBy: uid,
      createdAt: now,
      updatedAt: now,
    });
  });

  // Move photos out of the student's upload folder into the private request folder.
  if (uploads.length) {
    const bucket = getStorage().bucket();
    const attachments = [];
    for (const path of uploads) {
      const dest = `requests/${requestRef.id}/${path.split("/").pop()}`;
      try {
        await bucket.file(path).move(dest);
        attachments.push(dest);
      } catch (e) {
        console.warn(`Could not move ${path}`, e.message);
      }
    }
    if (attachments.length) await requestRef.update({ attachments });
  }

  return { requestId: requestRef.id, ref };
});

// ------------------------------------------------------- updateRequestStatus

exports.updateRequestStatus = onCall(async (request) => {
  const uid = requireAuth(request);
  const d = request.data || {};
  const requestId = str(d.requestId, "requestId", { min: 1, max: 100 });
  const status = str(d.status, "status", { min: 1, max: 30 });
  const note = str(d.note, "Note", { max: 500 });

  const profile = await profileOf(uid);
  if (!profile || !["admin", "provider"].includes(profile.role)) {
    throw new HttpsError("permission-denied", "Not allowed.");
  }

  const requestRef = db.doc(`serviceRequests/${requestId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(requestRef);
    if (!snap.exists) throw new HttpsError("not-found", "Request not found.");
    const r = snap.data();
    if (profile.role === "provider" && profile.providerId !== r.providerId) {
      throw new HttpsError("permission-denied", "This request belongs to another provider.");
    }
    if (!(NEXT_STATUSES[r.status] || []).includes(status)) {
      throw new HttpsError("failed-precondition", `Can't change a ${r.status} request to ${status}.`);
    }
    const now = Timestamp.now();
    tx.update(requestRef, {
      status,
      updatedAt: now,
      statusHistory: FieldValue.arrayUnion({ status, at: now, by: uid, note }),
    });
  });

  return { ok: true };
});
