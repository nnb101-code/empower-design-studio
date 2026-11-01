# GlattTrack — הסבר מלא על התוכנה · A full explanation of the software

גרסה / Version: **v10.38** · שרת / Server: **step 46 (02, up to §49)** · בדיקות / Tests: שרת המפעל **197/197**, מרכז היצרן **35/35** · 01.11.2026

> ⚠️ **עדיין לא למפעל אמיתי עד שסבבי הבדיקה יסתיימו.** · **Not for a real plant yet, until the review rounds are finished.**
> מדפסות וסורקים אמיתיים עוד לא נבדקו במפעל. · Real printers and scanners have not been tested in a plant yet.

---

## 1. מה זה · What it is

**עברית:** GlattTrack עוקבת אחרי הכשרות של כל בהמה בבית שחיטה, מהשחיטה ועד החתמת הבשר והניקור. כל בהמה מקבלת מספר אחד ליום. כל תחנה בקו רואה את אותו מספר ומוסיפה את מה שהיא עושה: שחיטה, בדיקת וושט, מדבקות, בדיקת פנים, פסיקת חוץ, חלקים, חותמות, ניקור. השרת לא מאפשר לדלג על תחנה, ומדבקת כשרות יוצאת רק לבהמה שנפסקה כשרה. הברקוד על המדבקה נושא את כל התהליך: מי שחט ומתי, מי בדק בפנים ובחוץ ומתי, איזה חלק, ואיזו כשרות.

**English:** GlattTrack tracks the kashrut of every animal in a slaughterhouse, from slaughter to the stamped meat and the nikur (deveining). Each animal gets one number per day. Every station on the line sees that number and adds what it does: slaughter, esophagus check, stickers, inner check, outer ruling, parts, stamps, nikur. The server never lets a station be skipped, and a kosher sticker is printed only for an animal ruled kosher. The barcode on the sticker carries the whole process: who slaughtered and when, who checked inside and outside and when, which part, and which kashrut.

---

## 2. מי משתמש · Who uses it

| מי · Who | מה עושה · What they do |
|---|---|
| **עובדי התחנות** (שוחט, בודק וושט, בודק פנים, בודק חוץ, עובדי מדבקות / חלקים / חותמות / ניקור) · **Station workers** | כל אחד בטאבלט של התחנה שלו. במסכים שדורשים זאת נכנסים עם קוד אישי. · Each on their station's tablet; on screens that require it, they log in with a personal code. |
| **ראש הצוות** · **Team leader** | מגדיר את המפעל (מסכים, עובדים, סטטוסים, מדפסות, רשימת החלקים), רואה את היום, מחפש, מסכם, מטפל בתקלות. עובד רק ממכשיר ראש צוות מצומד. **לעולם לא פוסק.** · Sets up the plant (screens, workers, statuses, printers, parts list), watches the day, searches, summarizes, handles issues. Works only from a paired team-leader device. **Never rules.** |
| **בעל המפעל** · **Owner** | צופה בלבד (היום, סיכומים, חיפוש). לא משנה הגדרות. · Watches only (today, summaries, search). Changes no settings. |
| **היצרן** (Maker) · **The manufacturer** | בתוך מפעל: רק הגדרות טכניות (מדפסות, סורקים וכו'), כשהמפעל פתח גישת תמיכה. **לא נוגע בפסיקות או בכשרות.** · Inside a plant: technical settings only (printers, scanners…), when the plant opened support access. **Never touches rulings or kashrut.** |
| **צוות מרכז היצרן** · **Manufacturer-center staff** | מנהל (הכל), תמיכה טכנית (מפעלים, תקלות, פקודות, עדכונים), כספים (חיובים בלבד), רישיונות ומכירות (רישיונות בלבד), צפייה בלבד. לכל אחד קוד משלו. · Admin (all), technical support (plants, issues, commands, updates), finance (billing only), licenses & sales (licenses only), view only. Each has their own code. |

---

## 3. הקו והמסכים · The line and the screens

**סדר הקו · Line order:** שחיטה ← וושט (אם מופעל) ← רגליים ← ראש (אם מפוצל) ← בודק פנים ← בודק חוץ ← מיון רגליים / חלקים קטנים / חותמות ושקילה ← קולר ← ניקור.
Slaughter → esophagus (if on) → legs → head (if split) → inner inspector → outer inspector → legs sorting / small parts / stamps & weighing → cooler → nikur.

| מסך · Screen | מה קורה בו · What happens there |
|---|---|
| **שחיטה** · Slaughter | השוחט מסמן כל מספר: נשחט / לא חלק / נבלה / ירוי, וגם "?" (שאלה). צפצוף כשאין פעולה זמן מוגדר. כפתורים חיצוניים, צלילים, מנורה וצופר דרך ממסר. · The shochet marks each number: slaughtered / not chalak / nevela / shot, plus "?" (question). A beep after inactivity. External buttons, sounds, light and siren via a relay. |
| **וושט** · Esophagus | תקין / נבלה. תיקון מותר (עם אזהרה). שעת השוחט נשמרת גם אחרי תיקון. · OK / nevela. A correction is allowed (with a warning). The shochet's time is kept even after a correction. |
| **רגליים / ראש** · Legs / head | הדפסת מדבקות מספר לרגליים ולראש (כמות לפי רשימת החלקים). אפשר לפצל לשני טאבלטים. · Prints number stickers for legs and head (count from the parts list). Can be split into two tablets. |
| **בודק פנים** · Inner inspector | פסיקת פנים (תקין / טרף + סוג: בית הכוסות / כרסים / ריאות), ציור ריאה, "?" על חלק. עד 2 מסכים. · Inner ruling (OK / treif + kind: maw / rumen / lungs), lung drawing, "?" on a part. Up to 2 screens. |
| **בודק חוץ** · Outer inspector | הפסיקה הסופית: גלאט / בית יוסף / כשר / סטטוסים של המפעל / טרף. "לא חלק" הוא סימון עד הפסיקה. אפשר מסך B ל"לא חלק". · The final ruling: glatt / Beit Yosef / kosher / the plant's own statuses / treif. "Not chalak" is a mark until the ruling. Optional screen B for "not chalak". |
| **חלקים קטנים** · Small parts | מדבקות כשרות לחלקים (לשון, לחיים, כבד…) לפי הרשימה. חלק מעוכב לא מודפס. · Kosher stickers for parts (tongue, cheeks, liver…) per the list. A held part is not printed. |
| **חותמות ושקילה** · Stamps & weighing | מדבקות כשרות לחצאים / רבעים / צדדים, שקילה (גם במצלמה), מדבקות משקל GS1, ק"ג / lb. · Kosher stickers for halves / quarters / sides, weighing (also by camera), GS1 weight labels, kg / lb. |
| **קולר** · Cooler | סורק את החלקים הגדולים שנכנסים לקירור. "?" ו-USDA. · Scans the large parts entering the cooler. "?" and USDA. |
| **ניקור** (רגיל / חלקים קטנים) · Nikur (regular / small parts) | סורק כל חתיכה. כשרה נכנסת. טרף, נבלה, מעוכבת, בלי פסיקה או **בלי מספר הדפסה** — נדחית. עובד גם על יום קודם (אחרי הקולר). · Scans every piece. Kosher goes in; treif, nevela, held, unruled or **without a print number** is refused. Works on an earlier day too (after the cooler). |
| **משגיחים** (מליחה, שיפינג) · Supervisors (salting, shipping) | התשתית קיימת (צימוד, עובדים, כניסה). התוכן עוד לא נבנה. · Infrastructure only (pairing, workers, login). The content isn't built yet. |
| **מונה / תצוגה** · Counter display | מסך גדול עם המספרים. · A big screen with the numbers. |
| **ראש הצוות** · Team leader | לשוניות: **היום** (מצב הקו, בריאות), **חיפוש** (בהמה, כרטיס בהמה), **סיכומים** (4 קבוצות: כשרות, משקים וזנים, אנשים, משקל וזמנים; ייצוא ל-Excel; השוואה לתקופה קודמת / אשתקד), **הגדרות** (מסכים וצימוד, פונקציות, משתמשים, מכשירים, מערכת), **תקלות** (דיווחים, פניות ליצרן, מה היצרן שינה, הדפסות חוזרות). · Tabs: **Today**, **Search** (animal card), **Summaries** (4 groups; Excel export; compare), **Settings**, **Issues**. |

**"?" ו-USDA:** בכל מסך אפשר לשים "?" (שאלה) או USDA (עיכוב) על בהמה או על חלק. המעוכב לא ממשיך הלאה עד שהתחנה ששמה אותו משחררת או פוסלת. · On every screen a "?" (question) or a USDA hold can be put on an animal or a part. The held item goes no further until the station that put it releases or condemns it.

**שלוש שפות:** עברית, אנגלית, ספרדית, לכל מסך בנפרד. · **Three languages:** Hebrew, English, Spanish, per screen.

---

## 4. כללי הכשרות במערכת · The kashrut rules in the system

- **סדר נאכף בשרת:** תחנה לא יכולה לסמן לפני שהתחנה הקודמת סיימה. · **Order enforced on the server.**
- **סטטוסים:** כל מפעל מגדיר את הסטטוסים שלו; כל סטטוס הוא "חלק" או "לא חלק"; טרף תמיד קיים. סטטוס שנמצא בשימוש היום לא משנה משמעות. · **Statuses:** each plant defines its own; each is "chalak" or "not chalak"; treif always exists; a status in use today keeps its meaning.
- **שינוי עם אזהרה:** אפשר לתקן פסיקה, עם אזהרה, ובכפוף לכך שהתחנה הבאה עוד לא התקדמה. · **Change with a warning.**
- **כלל סגירה:** סוגרים מסך או חלק באמצע יום — מה שכבר נעשה ממשיך עד הסוף, ומעכשיו לא לוקחים עוד. · **Closing rule.**
- **סימן כשרות:** כל חלק מבהמה שנפסקה כשרה חייב לקבל סימן כשרות. · **Kashrut mark** on every part of a kosher animal.
- **ניקור:** במפעל קבוע — באותו יום, או למחרת אחרי הקולר. חתיכה נסרקת לפי היום שעל המדבקה. · **Nikur** is fixed per plant (same day or next day after the cooler).
- **איפוס יומי (§37):** היום תמיד מתאפס בשעה שלו. לפני האיפוס הלוח נשמר בארכיון. ראש הצוות יכול לאפס ידנית (חירום). · **Daily reset (§37):** the day always resets at its hour; the board is archived first.
- **בלי שרת אין עבודה:** 15 שניות בלי תשובה מהשרת והמסך ננעל, ונפתח לבד כשהשרת חוזר. · **No server, no work** (15-second lock).
- **מצב בדיקה:** בעל המפעל יכול להדליק מצב בדיקה (נכבה לבד אחרי 8 שעות): מסך בלי מדפסת "מדפיס" וירטואלית. **יוסר לפני מכירה.** · **Test mode** (auto-off after 8 h): virtual printing. **Removed before sale.**

---

## 5. מדבקות וברקוד · Stickers and barcode

- **מדבקת רגליים / ראש:** `BH|N:<מספר>|D:<תאריך>|HD:<תאריך עברי>|W:<יום>|TM:<שעה>|SH:<שוחט>|S:<סטטוס>`.
- **מדבקת כשרות (§47):** הברקוד **נבנה בשרת**, לא בטאבלט: `BH|N|D|TM|SH|IN|IT|OUT|OT|P|I|B|K|S|T` — מספר, תאריך ושעת שחיטה (של השוחט), שוחט, בודק פנים ושעה, בודק חוץ ושעה, חלק, מספר חתיכה, יום, כשרות במילים, סטטוס, ו-**T = מספר הדפסה חד-פעמי**. · **Kosher sticker (§47):** the barcode is **built on the server**; **T = a one-time print number**.
- **מספרי הדפסה חד-פעמיים:** כל מדבקת כשרות מקבלת מספר מהשרת. ניקור וקולר מקבלים חתיכה **רק** עם מספר שלה (מהיום שבו §47 הותקן). טאבלט ששונה לא יכול להדפיס מדבקת כשרות משלו. · **One-time print numbers:** nikur and cooler take a piece **only** with its own number.
- **סימן הכשרות** (תמונה שראש הצוות מעלה) מודפס על כל מדבקת כשרות. · The **kashrut mark** (uploaded by the team leader) is printed on every kosher sticker.
- **הדפסה:** מדפסת רשת דרך שרת המפעל (ZPL, יציאה 9100, רק מדפסות מהרשימה), Bluetooth ישר מהטאבלט, או מסך ההדפסה של אנדרואיד. **קודם מדפיסים, אחר כך מסמנים:** אם ההדפסה נכשלה, הבהמה לא מסומנת. · **Printing:** network via the plant server, Bluetooth, or Android print. **Print first, then mark.**
- **סורקים:** USB / Bluetooth, סורק Wi-Fi דרך שרת המפעל, או טלפון כסורק. · **Scanners:** USB / Bluetooth, Wi-Fi via the plant server, or a phone as a scanner.

---

## 6. מבנה טכני · Technical structure

```
 טאבלטים (קובץ HTML אחד)  ──https──▶  שרת המפעל (Postgres + PostgREST / Supabase)
   tablets (one HTML file)              plant server: 02 (all rules) + 03 (self-test)
          │                                       │
          │                          מחשב Linux במפעל (ראשי + גיבוי): גיבוי לילי, בדיקת לילה,
          │                          ממסר מדפסות / סורקים, UPS, דיווח למרכז, עדכונים חתומים
          │                          plant Linux (primary + standby): backup, nightly check,
          │                          print / scanner relay, UPS, report to the center, signed updates
          │                                       │ (every 5 min)
          └───────────────────────────────────────▼
                         מרכז היצרן: Supabase נפרד + דף אחד + notify.sh
                         manufacturer center: separate Supabase + one page + notify.sh
```

- **האפליקציה:** `kosher-app-v10.38.html`, קובץ אחד (~2MB). עובדת גם בלי רשת לזמן קצר (תור שליחה), שולחת הכל לשרת. גרסת מפעל: `make-plant-build.py` (בלי כתובת ענן). · **The app:** one file; a send queue for short outages; a plant build without any cloud address.
- **השרת (02):** כל הכללים בשרת, בפונקציות (RPC). האפליקציה לא כותבת לטבלאות ישירות. RLS על כל טבלה. כל פונקציה מוגנת עם `search_path` קבוע. · **The server (02):** all rules in server functions; no direct table writes; RLS on every table.
- **03:** בדיקת אבטחה אחת ארוכה (197 בדיקות), שרצה ואז מבטלת את כל מה שעשתה. · **03:** one long self-test (197 checks) that undoes everything.
- **שרת המפעל (Linux):** `plant-server/`. ראשי + גיבוי (streaming replication, keepalived), גיבוי לילי שנבדק, בדיקת לילה, ממסר מדפסות וסורקים, UPS (nut), דיווח למרכז, עדכון חתום. · **Plant server (Linux):** primary + standby, verified nightly backup, nightly check, relays, UPS, report to the center, signed update.
- **מרכז היצרן:** `support-center/`. Supabase נפרד, דף אחד (`index.html` + `sc-config.js`, או `glatttrack-center.html` בקובץ אחד), `notify.sh` להתראות. · **Manufacturer center:** a separate Supabase, one page, `notify.sh` for alerts.

---

## 7. אבטחה · Security

- **מכשירים:** כל טאבלט מצומד בקוד חד-פעמי ומקבל מפתח. בלי מפתח — אין גישה. ראש הצוות מסיר מכשיר, והמפתח נעצר מיד. טאבלט מתנתק רק כשהשרת אומר זאת עם המפתח שלו. · **Devices:** paired with a one-time code; a key per tablet; removal stops it at once.
- **עובדים:** במסך שעובד עם קוד, השרת מקבל פסיקה רק מעובד שנכנס עם הקוד שלו. · **Workers:** rulings only from a logged-in worker where required.
- **ראש צוות:** רק ממכשיר ראש צוות. קוד שחזור. נעילה אחרי קודים שגויים (לפי כתובת ומכשיר). · **Team leader:** only from a team-leader device; recovery code; lockout per address + device.
- **קודים:** נשמרים מוצפנים (bcrypt). שדות קוד משמאל לימין, 👁 להצגה, אזהרה כשהמקלדת בעברית. · **Codes:** bcrypt; code fields LTR with 👁 and a Hebrew-keyboard warning.
- **עדכונים:** רק עדכון **חתום** במפתח של היצרן (Ed25519) מותקן; ה-sha256 של כל קובץ נבדק; 02 + 03 רצים לפני שהאפליקציה מוחלפת; רק גרסה חדשה יותר. · **Updates:** only **signed** releases; sha256 checked; only newer versions.
- **קוד יצרן חדש למפעל:** נוצר במרכז (bcrypt בדפדפן — הקוד לא יוצא מהדף), נחתם במחשב של היצרן (`maker-code-sign.sh`), המפעל בודק חתימה, מספר מפעל וזמן. · **New maker code:** hash made in the browser, signed by the manufacturer, checked by the plant.
- **מרכז היצרן:** מחלקות נפרדות (השרת חוסם, לא רק המסך), קוד שחזור למנהל, יומן "מי עשה מה". · **Center:** separate departments enforced by the server; admin recovery code; audit log.
- **סודות:** המפתח הפרטי של היצרן (`gt-release-private.pem`) לעולם לא בקבצים ששולחים. בדפים רק ערכים ציבוריים (כתובת ומפתח anon). · **Secrets:** the private key never leaves the manufacturer's computer; pages hold public values only.

---

## 8. רישיונות (§49) · Licenses (§49)

- **במרכז:** לשונית 🔑 רישיונות. דמו 14 או 30 יום, חודש, חודשיים, חצי שנה, שנה, או עד תאריך; מספר טאבלטים; היסטוריה; התראות 14, 7 ויום לפני הסוף ובסוף. · **In the center:** periods, tablet limit, history, alerts.
- **קוד רישיון:** `GT-<מפעל>-<יום אחרון>-<טאבלטים>-<מספר>-<12 סימנים>`, נחתם במפתח הרישיון של המפעל (HMAC). מגיע לבד דרך שרת המפעל, או שראש הצוות מקליד אותו. · **License code:** signed with the plant's license key; arrives by itself or is typed by the team leader.
- **כשנגמר:** אזהרה במסכים 14 יום לפני; אחרי הסוף **2 ימי חסד**; אחר כך יום שחיטה **חדש** לא מקבל בהמות — **אף פעם לא באמצע יום**; הנתונים והסיכומים נשארים פתוחים. · **When it ends:** warning, **2 grace days**, then a **new** slaughter day takes no animals — **never mid-day**.
- **בלי רישיון:** דמו של 30 יום מההתקנה. · **Without a license:** a 30-day demo.
- **בכנות:** מי ששולט במסד של המפעל יכול טכנית לשנות הכל; הרישיון שומר על המשתמש הישר ומונע מראש הצוות לעקוף. · **Honestly:** whoever controls the plant's database could change anything.

---

## 9. מה יש בזיפ · What is in the zip

| תיקייה · Folder | תוכן · Contents |
|---|---|
| `0-SOFTWARE-OVERVIEW.md` | המסמך הזה · this document |
| `1-app/` | האפליקציה + `make-plant-build.py` · the app |
| `2-server-update/` | עדכון שרת קיים: 00 → 01 → 02 → 03 + `INSTALL-HE.md` + מצב בדיקה · update an existing server |
| `3-server-new-from-zero/` | שרת חדש: כל השרת בקובץ אחד + 03 + בדיקת משטח האבטחה · a new server from zero |
| `4-plant-server/` | כל הסקריפטים של שרת המפעל + `PLANT-RESILIENCE-HE.md` · plant server scripts |
| `5-support-center/` | מרכז היצרן: SQL, בדיקה, דף, `notify.sh`, סקריפטי חתימה, מדריך · the manufacturer center |
| `6-kashrut-marks-and-stickers/` | סימני כשרות ומדבקות לדוגמה · marks and sample stickers |
| `7-docs/` | מצב הפרויקט, דוחות הבדיקה, כל השינויים · status, review reports, changes |
| `8-tests/` | תוצאות הבדיקות ובדיקות הדפדפן · test results and browser tests |

**לא בזיפ (בכוונה):** מפתחות פרטיים וסודות, הסרטונים (155MB), גרסאות ישנות. · **Not in the zip (on purpose):** private keys and secrets, the videos, old versions.

---

## 10. התקנה בקצרה · Installation in short

1. **שרת מפעל (Supabase):** קיים — `02` ואז `03` (197/197). חדש — `1-glatttrack-schema-full.sql` ואז `03`. · **Plant server:** 02 then 03; or the full schema then 03.
2. **האפליקציה:** מחליפים את קובץ האפליקציה; הטאבלטים מתעדכנים בפתיחה הבאה. · **App:** replace the file.
3. **מרכז היצרן:** Supabase נפרד — `central-setup.sql` ואז `central-selftest.sql` (35/35); מנהל ראשון ב-SQL; פותחים את `glatttrack-center.html`. · **Center:** setup, self-test, first admin, open the page.
4. **רישיון:** במרכז ← 🔑 מפתח למפעל (שורה אחת ב-SQL של המפעל) ← רישיון חדש ← ראש הצוות מקליד את הקוד. · **License:** plant key once, then a license code.
5. **שרת מפעל Linux** (כשיהיה): `4-plant-server/` + `PLANT-RESILIENCE-HE.md`. · **Plant Linux server** (when there is one).

---

## 11. בדיקות שעברו · Tests that passed

- **03 (שרת המפעל):** 197/197, גם בהתקנה נקייה. כולל: סדר הקו, הרשאות, מכשירים, עובדים, עיכובים, מדבקות ומספרי הדפסה, ניקור וקולר, איפוס, קוד יצרן, רישיונות. · **03:** 197/197, also on a fresh install.
- **מרכז היצרן:** 35/35 (כולל מחלקות, שחזור קוד, קוד יצרן חתום, רישיונות והתראות). · **Center:** 35/35.
- **דפדפן:** הדפסה וירטואלית, טקסט עוין לא רץ (XSS), מדבקות כשרות מהשרת, ברקודים קריאים, שדות קוד, סיכומים בקבוצות, צימוד, דף המרכז, קובץ אחד בטלפון, קוד יצרן, רישיונות. · **Browser:** virtual printing, no XSS, server-built stickers, readable barcodes, code fields, summaries, pairing, center page, one-file page, maker code, licenses.
- **ביצועים:** טעינה 2.2 שניות בטאבלט איטי, פסיקה 27ms בממוצע. · **Performance:** 2.2 s load on a slow tablet, 27 ms per ruling.

## 12. סבבי בדיקת קוד · Code review rounds

- **סבבים 1–3:** כל שורה בכל הקבצים; כל הממצאים תוקנו (`REVIEW-FULL-FINDINGS.md`, `REVIEW-ROUND3-REPORT.md`). · **Rounds 1–3:** every line; all findings fixed.
- **סבב 4:** הקוד החדש אחרי סבב 3 + סריקות אוטומטיות; 3 ממצאים תוקנו. · **Round 4:** new code + automatic sweeps; 3 findings fixed.
- **חיצוני:** ChatGPT (עד סבב 21), Gemini (סבב אחרון בלי ממצאים). · **External:** ChatGPT, Gemini.

## 13. מה עוד לא גמור · What is not finished yet

- מדפסות וסורקים אמיתיים — עוד לא נבדקו במפעל. · Real printers / scanners — not tested in a plant.
- נוהל חירום על נייר + מסך הזנה מאוחרת. · Paper emergency procedure + late-entry screen.
- תוכן מסכי המשגיח (מליחה, שיפינג), מסכי הכשרה, פירוק ואריזה. · Supervisor screens content, kashering, cutting, packing.
- סריקה בניקור בלי חיבור לשרת לא נשמרת לשליחה מאוחרת. · Nikur scans offline are not queued.
- משקל משוער בסיכומים ובחיוב. · Estimated weight in summaries and billing.
- **לפני מכירה:** להסיר את מצב הבדיקה. · **Before sale:** remove test mode.
- **שאלות פתוחות לבעלים:** שינוי שמות / הוספה / מחיקה של סטטוסים (A-Q4); פרטים לדפים המשפטיים (A-L8); מה זה "inside in". · **Open questions:** A-Q4, A-L8, "inside in".

## 14. מילון · Glossary

| עברית | English |
|---|---|
| שחיטה / שוחט | slaughter / shochet |
| וושט | esophagus |
| בודק פנים / בודק חוץ | inner / outer inspector |
| גלאט / חלק · לא חלק | glatt / chalak (smooth) · not chalak |
| בית יוסף | Beit Yosef (a stricter standard) |
| טרף · בית הכוסות · כרסים · ריאות | treif · maw · rumen · lungs |
| נבלה · ירוי | nevela (improper slaughter) · shot |
| ניקור | nikur (removing forbidden veins and fat) |
| קולר | cooler (cold room) |
| משגיח | mashgiach (kashrut supervisor) |
| ראש צוות | team leader |
| מעוכב · "?" | held · question |

---

## 15. לבודק בצ'אט האחר · For the reviewer in the other chat

**מה לבדוק, לפי סדר חשיבות · What to check, by importance:**
1. **כשרות:** האם אפשר להוציא מדבקת כשרות, או להכניס חתיכה לניקור או לקולר, לבהמה שאינה כשרה, מעוכבת, או בלי מספר הדפסה? (`02`: `print_tickets_take`, `print_kosher_add`, `nikur_scan`, `cooler_scan`, `_ticket_refusal`). · **Kashrut:** can a kosher sticker or a nikur / cooler entry happen for a non-kosher, held, or unticketed piece?
2. **סדר הקו והרשאות:** האם תחנה יכולה לדלג, לכתוב בשם תחנה אחרת, או לשנות פסיקה שלא שלה? (`claim_animal_stage`, `animal_push`, הטריגרים על `animals_pilot`). · **Order and permissions.**
3. **אבטחה:** מכשירים, עובדים, ראש צוות, יצרן, עדכונים חתומים, קוד יצרן, רישיונות, מרכז היצרן. · **Security.**
4. **אמינות:** איפוס יומי, בלי רשת, שני טאבלטים באותו רגע, שחזור, שרת גיבוי. · **Reliability.**
5. **האפליקציה:** XSS, תור שליחה, שפות, ממשק. · **The app.**

**כללים לבודק · Rules for the reviewer:** לדווח כל ממצא עם קובץ, שורה ותרחיש מדויק; להבדיל בין באג מוכח לבין השערה; לא להציע תוספות שלא ביקשו (כלל הבעלים: בלי המצאות ובלי אפשרויות נוספות). · Report each finding with file, line and an exact scenario; separate proven bugs from guesses; don't propose additions nobody asked for.
