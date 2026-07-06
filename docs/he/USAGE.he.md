## איך להתקין

```bash
mkdir -p ~/skills/skill-security-scanner
# העתק את SKILL.md, scan-skill.sh, skill-scan-lib.sh, scan-github-skill.sh, scan-github-remote.sh לתיקייה
chmod +x ~/skills/skill-security-scanner/*.sh
```

שימו לב: `scan-skill.sh` ו-`scan-github-remote.sh` שניהם טוענים (`source`) את `skill-scan-lib.sh` — זה חייב לשבת באותה תיקייה.

## איך להשתמש

*סריקה אוטומטית (CLI):*
```bash
./scan-skill.sh ~/path/to/some-skill/
```

*סריקה דרך Claude Code (AI):*
פשוט תגיד: "scan the skill at ~/path/to/some-skill/ for security issues" — וה-AI ישתמש ב-SKILL.md כמדריך לסריקה מעמיקה (כולל דברים ש-regex לא תופס, כמו הנחיות מתוחכמות להנדסה חברתית).

---

*אזהרה חשובה:* זה כלי עזר, לא חומת מגן. סקיל מתוחכם יכול לעקוף בדיקות regex. תמיד תשלב את זה עם:
1. בדיקה ידנית של ה-SKILL.md
2. חיפוש על הכותב/מקור
3. הרצה ראשונית בסביבת sandbox

## לסרוק סקיל מ-GitHub, בלי הורדה

יש שתי אופציות לסריקת מקור מרוחק — תלוי אם אתם רוצים clone מקומי זמני או לא רוצים לגעת בדיסק בכלל.

### אופציה 1 — clone זמני ל-temp (עם git, מנקה אוטומטית)

```bash
./scan-github-skill.sh https://github.com/some-user/some-skill

# סקיל בתוך מונו-רפו, branch ספציפי
./scan-github-skill.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```

זה עושה clone רדוד ל-temp → סורק → מנקה אוטומטית (`trap ... EXIT`). כל מקור נסרק באותה צורה, ללא קיצורי דרך לפי שם ה-repo/org. במהלך הסריקה עצמה תוכן ה-repo יושב בדיסק (בתיקיית temp), גם אם רק לזמן קצר.

### אופציה 2 — סריקה מרוחקת אמיתית, בלי לגעת בדיסק בכלל

```bash
./scan-github-remote.sh https://github.com/some-user/some-skill

# סקיל בתוך מונו-רפו, branch ספציפי
./scan-github-remote.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```

זה לא עושה `git clone` בכלל. במקום זה:
1. קורא ל-GitHub API בשביל רשימת הקבצים (`git/trees?recursive=1`) — קריאה אחת, בלי להוריד תוכן.
2. מסנן לפי סיומות רלוונטיות (`.md .sh .py .js .ts .json .txt .yaml .yml .toml`) ולפי subpath אם צוין.
3. לכל קובץ תואם — מושך את התוכן ישירות לזיכרון דרך `raw.githubusercontent.com`, בלי `-o`/כתיבה לקובץ.
4. סורק את התוכן מהזיכרון ומשליך אותו — שום קובץ מה-repo לא נכתב לדיסק בשום שלב.

דורש `curl` ו-python3 (בשביל parsing נכון של JSON מה-API, בלי regex שביר). ל-repos פרטיים או בשביל rate limit גבוה יותר (5000/שעה במקום 60/שעה) — הגדירו `export GITHUB_TOKEN=<token>` לפני ההרצה.

הגבלה: אם ה-repo ענק וה-API חותך את רשימת הקבצים (`truncated: true`), הסקריפט מדפיס אזהרה — במקרה כזה עדיף אופציה 1 (clone), שרואה את כל ה-repo.