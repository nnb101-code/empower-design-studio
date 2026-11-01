# GlattTrack — סבב בדיקה 3 (כל שורה) + תיקונים · Review round 3 (every line) + fixes

19.10.2026 · אפליקציה / App **v10.38** · שרת / Server **02 (§47 + round 3)** · 03: **192/192** · מרכז תמיכה / Support center: **29/29**

> ⚠️ **עדיין לא למפעל אמיתי עד שסבבי הבדיקה יסתיימו.** · **Not for a real plant yet, until the review rounds are finished.**

## מה נבדק · What was checked
כל שורה של: האפליקציה (kosher-app-v10.38.html), שרת 02, בדיקות 03, סקריפטי שרת המפעל (plant-server), מרכז התמיכה (support-center).
Every line of: the app, server 02, tests 03, the plant-server scripts, the support center.

## ממצאים ותיקונים · Findings and fixes

| # | חומרה · Severity | מה היה · What it was | תוקן · Fixed |
|---|---|---|---|
| 02-M1 | **בינוני (כשרות) · Medium (kashrut)** | אפשר היה לעקוף את מספרי ההדפסה החד-פעמיים (§47): טאבלט ששונה יכול היה לשלוח מדבקת כשרות שלמה דרך print_job_add, והניקור/הקולר קיבלו חלק בלי מספר. · A changed tablet could send a whole kosher sticker through print_job_add, and the nikur / cooler took a piece with no print number. | print_job_add מסרב ל-kosher (`tickets_required`). מהיום שבו §47 הותקן, ניקור/קולר מקבלים חלק **רק** עם מספר הדפסה שלו. ימים מלפני §47 נשארים כמו קודם. · print_job_add refuses kosher. From the §47 install day on, the nikur / cooler take a piece **only** with its own print number. |
| 02-L2 | נמוך · Low | אחרי תיקון בוושט (נבלה → תקין) שעת השחיטה בברקוד הייתה שעת התיקון. · After an esophagus correction, the barcode showed the correction time as the slaughter time. | עמודה חדשה shochet_time (השעה של השוחט). הברקוד (D/TM) משתמש בה. slaughter_time ממשיך להתקדם בשביל הטאבלטים. · New column shochet_time; the barcode uses it. |
| 02-L3 | נמוך-בינוני · Low/Med | ניסיונות כניסה במקביל מאותה כתובת עקפו את ספירת הניסיונות. · Parallel login tries from one address skipped the count of tries. | נעילה לכל כתובת ב-manager_login וב-worker_login. · A lock per address. |
| 02-L5 | ניקוי · Cleanup | hold_set קיבל 'nikur' תמיד על לוח היום (מספר של יום קודם היה מעכב את הבהמה של היום). · hold_set took 'nikur', always on today's board. | hold_set מסרב לניקור (רק nikur_hold, עם היום של החלק). · hold_set refuses 'nikur'; only nikur_hold. **בדיקה חוזרת · Rechecked:** 'cooler' ב-hold_resolve נשאר. עיכובי קולר קיימים (cooler_hold). · stays: cooler holds exist. |
| 02-L1 / L4 | תיעוד/ניקוי · Doc/cleanup | כותרת ישנה (ימים שמורים, איפוס שמחכה). manager_add מוגדר פעמיים. · Old header text; manager_add defined twice. | כותרת עודכנה (§37). העותק המת הוסר. · Header updated; dead copy removed. |
| — | שיפור · Improvement | גודל ה-QR בשרת: עד גרסה 15. · Server QR size: up to version 15. | עד גרסה 25 (שמות ארוכים). האפליקציה: כל 40 הגרסאות (A-1). · Up to 25; the app: all 40 (A-1). |
| A-1 | נמוך · Low | QR באפליקציה: טבלאות חלקיות. ברקוד ארוך לא נוצר. · App QR: partial tables, so a long barcode was not made. | טבלאות מלאות (40 גרסאות). נבדק בקריאה עם ZXing. · Full tables; checked with a ZXing decode. |
| A-2 | נמוך (XSS) · Low (XSS) | בדיאגרמת העוגה: מפתח עם גרש שבר את ה-onclick. · Pie chart: a key with a quote broke the onclick. | `_jsArg`. נבדק בדפדפן. · Checked in the browser. |
| A-L1 | נמוך · Low | סירוב בוושט (next_station_done / outer_ruled / held) בוטל בשקט. · An esophagus refusal was undone silently. | עכשיו מופיעה הודעה. · A notice is shown now. |
| A-L2 | נמוך · Low | "הצג QR" כבוי גם הוריד את הברקוד ממדבקת הכשרות. · "Show QR" off also removed the barcode from the kosher sticker. | למדבקת כשרות יש תמיד ברקוד. המתג חל רק על רגליים / ראש. · The kosher sticker always has its barcode; the switch is for legs / head only. |
| A-L3 | נמוך · Low | אפשר היה להקליד את מספר מדבקות החלקים, אבל השרת דורס אותו לפי רשימת החלקים. · The parts-sticker count could be typed, but the server overwrote it from the cuts list. | עם רשימת חלקים המספר מוצג ולא מוקלד (✎ פותח את הרשימה). · With a cuts list it is shown, not typed. |
| A-L4 | נמוך · Low | ייצוא ל-Excel: תא שמתחיל ב-= + - @ עלול לרוץ כנוסחה. · Excel export: a cell starting with = + - @ could run as a formula. | נשמר כטקסט. מספר נשאר מספר. · Kept as text; a number stays a number. |
| A-L5 | נמוך · Low | שחזור גיבוי נראה כאילו שינה את השרת. · A backup restore looked as if it changed the server. | כשיש שרת, ההודעה אומרת שהשרת לא שונה, והלוח נטען שוב מהשרת. · With a server: says so and reloads the board. |
| A-L6 | ניקוי · Cleanup | קוד מת (updateNavForConfig, הקוד אחרי return ב-mgrSealChosen, _mgrRenameStatusOld, הבלוק st2). · Dead code. | הוסר. · Removed. |
| A-L7 | נמוך · Low | בהדפסה חוזרת: שורת היומן ו"הודפס כ-" נרשמו לפני ההדפסה. · On a reprint, the log line and "printed as" were written before printing. | נרשמים רק אחרי שהמדפסת קיבלה. · Written only after the printer took them. |
| P-L1 | נמוך · Low | שרת המפעל היה מתקין גם גרסה **ישנה** חתומה. · The plant server would also install an **older** signed release. | מותקנת רק גרסה חדשה יותר. חזרה לגרסה קודמת רק דרך update-app.sh --rollback. · Only a newer version; going back is --rollback. |
| P-L2 | ניקוי · Cleanup | הבדיקה הלילית "איפוס יומי ממתין" כבר לא רלוונטית (§37). · Nightly "reset waits" check is dead since §37. | הוסרה. · Removed. |
| C-L1 | נמוך · Low | שם מפעל עם שורה חדשה נכנס להתראות (מייל / SMS / WhatsApp). · A plant name with a new line went into the alerts. | נדחה (`bad_value`), ונוספה בדיקה. · Refused + test. |
| 03-L1 / L2 | בדיקות · Tests | בדיקה שהשוותה ערך לעצמו. כותרת ישנה. · A check that compared a value with itself; an old title. | תוקן. · Fixed. |

## בדיקות שרצו · Tests run
- 03 על מסד מקומי + התקנה נקייה: **192/192** (נוספו: מספרי הדפסה בלבד, shochet_time, נעילת כניסה, hold_set בלי ניקור).
  03 on a local DB and on a fresh install: **192/192** (added: print numbers only, shochet_time, login lock, hold_set without nikur).
- מרכז תמיכה: **29/29**. · Support center: **29/29**.
- דפדפן: t31, t32, t33, t34, A-2, A-L2/L3/L4 עברו. ב-t22 סורקים בניקור מדבקה שהוכנה ביד בלי מספר הדפסה, ועכשיו היא נדחית ("מדבקה לא מוכרת — לא להכניס"). זה מה שצריך לקרות. התהליך האמיתי עם מספרי הדפסה נבדק ב-t33.
  Browser: t31–t34, A-2 and A-L2/L3/L4 passed. In t22 the nikur scans a hand-made sticker with no print number, and it is now refused. That is the intended behaviour; the real flow with print numbers is covered by t33.
- תחביר: כל 16 קטעי הקוד באפליקציה, וגם report-to-center.sh ו-nightly-check.sh. · Syntax: all 16 app script blocks and both shell scripts.

## חשוב בהתקנה · Important when installing
אחרי התקנת 02 החדש, חלק כשר שהודפס **היום** עם אפליקציה ישנה (בלי מספרי הדפסה) לא ייכנס לניקור. צריך לעדכן את כל הטאבלטים לפני העבודה.
After installing the new 02, a kosher piece printed **today** by an old app (with no print numbers) will not go into the nikur. Update all tablets before work.

## שאלות לבעלים · Questions for the owner
1. **A-Q4:** בהגדרות אפשר לשנות שם, להוסיף ולמחוק סטטוסים. הכלל ב-STATUS.md הוא "בלי שינוי שמות / בלי הוספות". להשאיר או לחסום? (לא שיניתי.)
   Settings allow renaming / adding / deleting statuses, while the rule says "no renaming / no additions". Keep it or block it? (Not changed.)
2. **A-L8:** בדפים המשפטיים (תנאים / פרטיות) עדיין יש מקומות ריקים. צריך: שם החברה, כתובת, מייל ליצירת קשר, ומדינת החוק.
   The legal pages still have placeholders. Needed: company name, address, contact e-mail, governing law.
