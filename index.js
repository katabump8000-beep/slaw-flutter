// إشعارات فورية (FCM) لتطبيق FIR — تصل والتطبيق مغلق، مع عدّاد على أيقونة التطبيق
const { onValueCreated } = require('firebase-functions/v2/database');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.database();

const OPT = { instance: 'slaw-3a991-default-rtdb', region: 'europe-west1' };
const val = async (p) => (await db.ref(p).get()).val();

async function nameOf(uid) {
  try { return (await val(`profiles/${uid}/name`)) || 'عضو'; } catch (_) { return 'عضو'; }
}

// يرسل إشعاراً لمستخدم + يزيد عدّاد الأيقونة
async function push(uid, { title, body, tag, gid, mid }) {
  const tk = await val(`fcmTokens/${uid}`);
  if (!tk) return;
  const tokens = Object.keys(tk);
  if (!tokens.length) return;
  const r = await db.ref(`badge/${uid}`).transaction((n) => (typeof n === 'number' ? n : 0) + 1);
  const count = (r.snapshot && r.snapshot.val()) || 1;
  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { gid: gid || '', mid: mid || '' },
    android: {
      priority: 'high',
      ttl: 3600 * 1000,
      notification: {
        channelId: 'fir_main',
        tag: tag || undefined,
        notificationCount: count,
        defaultSound: true,
        defaultVibrateTimings: true,
        visibility: 'public',
        notificationPriority: 'PRIORITY_MAX',
      },
    },
  });
  const bad = [];
  res.responses.forEach((x, i) => {
    const c = x.error && x.error.code;
    if (c === 'messaging/registration-token-not-registered' || c === 'messaging/invalid-registration-token') bad.push(tokens[i]);
  });
  await Promise.all(bad.map((t) => db.ref(`fcmTokens/${uid}/${t}`).remove()));
}

const clip = (s, n = 110) => (s || '').toString().replace(/\s+/g, ' ').slice(0, n);

// 1) إشعارات الجرس: منشن، @الكل، صداقة، تحويل، دعم ...
exports.onNotif = onValueCreated({ ...OPT, ref: '/notifs/{uid}/{nid}' }, async (e) => {
  const n = e.data.val();
  if (!n) return;
  const who = await nameOf(n.from);
  const g = n.m || '';
  const T = {
    men: ['📣 هناك من ذكر اسمك', `${who} ذكرك في «${g}»: ${clip(n.tx, 70)}`],
    all: ['📢 نداء للجميع', `${who} في «${g}»: ${clip(n.tx, 70)}`],
    frq: ['👥 طلب صداقة جديد', `${who} أرسل لك طلب صداقة — افتح التطبيق للقبول`],
    fok: ['✅ تم قبول صداقتك', `${who} قبل طلب صداقتك`],
    tr: ['💰 وصلك رصيد', `${who} حوّل لك رصيداً`],
    sup: ['🛟 رسالة ابلاغ', clip(n.tx) || 'رسالة ابلاغ من أحد الأعضاء'],
    add: ['➕ تمت إضافتك', `تمت إضافتك إلى «${g}»`],
    kick: ['⛔ تم طردك', `تم طردك من «${g}»`],
    mute: ['🔇 تم كتمك', `تم كتمك في «${g}»`],
    role: ['🎖 تغيّرت رتبتك', `تغيّرت رتبتك في «${g}»`],
  };
  const t = T[n.t] || ['FIR', clip(n.tx) || 'لديك إشعار جديد'];
  const tag = n.mid ? n.mid : n.t === 'frq' ? `frq_${n.from}` : undefined;
  await push(e.params.uid, { title: t[0], body: t[1], tag, gid: n.g, mid: n.mid });
});

// 2) طلب صداقة (حتى لو لم يجمعهما قروب)
exports.onFriendReq = onValueCreated({ ...OPT, ref: '/friendReq/{to}/{from}' }, async (e) => {
  const who = await nameOf(e.params.from);
  await push(e.params.to, { title: '👥 طلب صداقة جديد', body: `${who} أرسل لك طلب صداقة — افتح التطبيق للقبول`, tag: `frq_${e.params.from}` });
});

// 3) رسائل القروبات: إشعار لكل عضو (مثل واتساب)
exports.onMessage = onValueCreated({ ...OPT, ref: '/messages/{gid}/{mid}' }, async (e) => {
  const m = e.data.val();
  if (!m || m.type === 'sys') return;
  const gid = e.params.gid;
  const g = await val(`groups/${gid}`);
  if (!g || g.kind !== 'main') return;
  const text = m.type === 'text' ? m.text || '' : '';
  if (/@(الكل|all)/i.test(text)) return; // له إشعاره الخاص
  const who = await nameOf(m.from);
  const body = {
    text: clip(text),
    image: '📷 صورة',
    sticker: '🏷 ملصق',
    audio: '🎤 رسالة صوتية',
  }[m.type] || 'رسالة جديدة';
  const mem = (await val(`members/${gid}`)) || {};
  const ids = Object.keys(mem).filter((u) => mem[u] === true && u !== m.from).slice(0, 400);
  const banned = (await val('banned')) || {};
  await Promise.all(
    ids.filter((u) => !banned[u]).map((u) =>
      push(u, { title: g.name || 'FIR', body: `${who}: ${body}`, tag: e.params.mid, gid, mid: e.params.mid }).catch(() => {})
    )
  );
});

// 4) إعلان حرب: لأعضاء النقابة المُهاجَمة
exports.onWar = onValueCreated({ ...OPT, ref: '/warFeed/{wid}' }, async (e) => {
  const w = e.data.val();
  if (!w) return;
  const mem = (await val(`members/${w.dg}`)) || {};
  const ids = Object.keys(mem).filter((u) => mem[u] === true).slice(0, 400);
  await Promise.all(
    ids.map((u) =>
      push(u, { title: '⚔️ إعلان حرب!', body: `نقابة ${w.an} تعلن الحرب على نقابة ${w.dn}`, tag: `war_${e.params.wid}` }).catch(() => {})
    )
  );
});

// 5) رسائل الأصدقاء الخاصة
exports.onFriendDm = onValueCreated({ ...OPT, ref: '/fdm/{a}/{b}/{mid}' }, async (e) => {
  const m = e.data.val();
  if (!m) return;
  const to = m.from === e.params.a ? e.params.b : e.params.a;
  const who = await nameOf(m.from);
  await push(to, { title: `💬 ${who}`, body: clip(m.text), tag: `dm_${m.from}` });
});

// 6) مراسلة الإمبراطور
exports.onEmpMsg = onValueCreated({ ...OPT, ref: '/emp/msg/{uid}/{mid}' }, async (e) => {
  const m = e.data.val();
  if (!m) return;
  const emp = await val('config/emperorUid');
  const to = m.from === e.params.uid ? emp : e.params.uid;
  if (!to) return;
  await push(to, { title: '👑 رسالة من الإمبراطور', body: clip(m.text), tag: `emp_${e.params.uid}` });
});

// 7) بلاغات الأعضاء على الدردشات: إشعار فوري لكل المطورين والإمبراطور
exports.onReport = onValueCreated({ ...OPT, ref: '/reports/{rid}' }, async (e) => {
  const r = e.data.val();
  if (!r) return;
  const who = await nameOf(r.u);
  const roles = (await val('roles')) || {};
  const emp = await val('config/emperorUid');
  const ids = new Set(Object.keys(roles).filter((u) => roles[u] === 'dev'));
  if (emp) ids.add(emp);
  ids.delete(r.u);
  await Promise.all(
    [...ids].map((u) =>
      push(u, { title: '🚩 بلاغ جديد على دردشة', body: `${who}: ${clip(r.r, 90)}`, tag: `rep_${e.params.rid}` }).catch(() => {})
    )
  );
});

// 8) حذف عضو نهائياً (من شاشة «حظر / حذف عضو»): يمسح الحساب وكل أثره
exports.onDelMember = onValueCreated({ ...OPT, ref: '/delQueue/{uid}' }, async (e) => {
  const uid = e.params.uid;
  const q = db.ref(`delQueue/${uid}`);
  try {
    const by = (e.data.val() || {}).by;
    const emp = await val('config/emperorUid');
    const byRole = by ? await val(`roles/${by}`) : null;
    const allowed = by && (by === emp || byRole === 'dev') && uid !== emp;
    const targetDev = (await val(`roles/${uid}`)) === 'dev';
    if (!allowed || (targetDev && by !== emp)) { await q.remove(); return; }

    const up = {};
    const own = ['profiles', 'wallets', 'pw', 'pdata', 'avatars', 'seen', 'flags', 'presence', 'tamper', 'pride', 'prideTs',
      'likeCount', 'wins', 'msgTotal', 'fcmTokens', 'badge', 'notifs', 'friends', 'supportOpen', 'restricted', 'joinLog',
      'refClaims', 'refPaid', 'pubCount', 'pwSwap', 'spin', 'gift', 'roles', 'devs', 'banned', 'mod', 'myStickers', 'welcomed'];
    for (const k of own) up[`${k}/${uid}`] = null;
    const pid = await val(`pdata/${uid}/pid`);
    if (pid) up[`pids/${pid}`] = null;
    const dev = await val(`deviceOf/${uid}`);
    if (dev) up[`devices/${dev}`] = null;
    up[`deviceOf/${uid}`] = null;

    const members = (await val('members')) || {};
    for (const g of Object.keys(members)) {
      if (members[g] && members[g][uid] !== undefined) up[`members/${g}/${uid}`] = null;
      up[`stats/${g}/${uid}`] = null;
      up[`groupAdmins/${g}/${uid}`] = null;
    }
    const idx = (await val('nameIdx')) || {};
    for (const g of Object.keys(idx)) for (const k of Object.keys(idx[g] || {})) if (idx[g][k] === uid) up[`nameIdx/${g}/${k}`] = null;
    const al = (await val('pwAlias')) || {};
    for (const k of Object.keys(al)) if (al[k] && al[k].u === uid) up[`pwAlias/${k}`] = null;
    const fr = (await val(`friends/${uid}`)) || {};
    for (const f of Object.keys(fr)) up[`friends/${f}/${uid}`] = null;

    await db.ref().update(up);
    try { await admin.auth().deleteUser(uid); } catch (_) {}
  } catch (err) {
    console.error('onDelMember', err);
  } finally {
    try { await q.remove(); } catch (_) {}
  }
});
