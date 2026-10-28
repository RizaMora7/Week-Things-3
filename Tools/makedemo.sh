#!/bin/bash
# makedemo.sh — generates two made-up SQLite databases (Things + Calendar) so the
# app can be shown without touching anyone's real data.
#
#   zsh Tools/demo.sh          # builds the databases and opens the app in demo mode
#   ./Tools/makedemo.sh        # only builds the databases in build/demo/
#
# Dates are computed against the Monday of the current week, so the board always
# comes out populated no matter when it runs. The only data here is what's in
# this file.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/build/demo"
mkdir -p "$OUT"

THINGS="$OUT/things.sqlite"
CAL="$OUT/calendar.sqlite"
[ -f "$THINGS" ] && mv "$THINGS" "$THINGS.anterior"
[ -f "$CAL" ] && mv "$CAL" "$CAL.anterior"

# ---- dates ---------------------------------------------------------------
dow=$(date +%u)                                  # 1 = Monday … 7 = Sunday
monday=$(date -j -v-$((dow - 1))d +%Y-%m-%d)

# coso: prints "year month day" for i days after this week's Monday.
coso() { date -j -v+$1d -f "%Y-%m-%d" "$monday" +%Y-%m-%d; }
# thingsDate: packs a date the way Things does (YYYYYYYYYYYMMMMDDDDD0000000).
td() {
  IFS='-' read -r y m d <<< "$(coso "$1")"
  echo $(( (10#$y << 16) | (10#$m << 12) | (10#$d << 7) ))
}
# cf: CFAbsoluteTime for "weekday + time", which is how Calendar stores dates.
cf() {
  printf '%s' "$(echo "$(date -j -f '%Y-%m-%d %H:%M:%S' "$(coso "$1") $2:00" +%s) - 978307200" | bc)"
}
oy=$(date -j -v-$((dow + 2))d +%Y); om=$(date -j -v-$((dow + 2))d +%m); od=$(date -j -v-$((dow + 2))d +%d)
OVERDUE=$(( (10#$oy << 16) | (10#$om << 12) | (10#$od << 7) ))

# ---- Things database -----------------------------------------------------
sqlite3 "$THINGS" <<SQL
PRAGMA journal_mode=WAL;
CREATE TABLE TMArea  (uuid TEXT PRIMARY KEY, title TEXT);
CREATE TABLE TMTag   (uuid TEXT PRIMARY KEY, title TEXT);
CREATE TABLE TMTaskTag (tasks TEXT, tags TEXT);
CREATE TABLE TMTask (
  uuid TEXT PRIMARY KEY, type INTEGER, title TEXT, notes TEXT, "index" INTEGER,
  start INTEGER, startDate INTEGER, deadline INTEGER, deadlineSuppressionDate INTEGER,
  rt1_recurrenceRule TEXT, rt1_instanceCreationPaused INTEGER, rt1_nextInstanceStartDate INTEGER,
  openChecklistItemsCount INTEGER, checklistItemsCount INTEGER,
  project TEXT, area TEXT, heading TEXT, status INTEGER, trashed INTEGER, creationDate REAL);

INSERT INTO TMArea VALUES ('ar-prod','Product'), ('ar-oper','Operations'), ('ar-form','Learning');
INSERT INTO TMTag  VALUES ('tg-i','Important'), ('tg-u','Urgent'), ('tg-h','High'),
                          ('tg-m','Medium'), ('tg-l','Low'), ('tg-d','Deep work');

-- Projects (type 1)
INSERT INTO TMTask (uuid,type,title,notes,"index",start,startDate,deadline,deadlineSuppressionDate,
                    rt1_instanceCreationPaused,openChecklistItemsCount,checklistItemsCount,area,status,trashed,creationDate) VALUES
 ('p-web',1,'Launch the new website','Full redesign, three sections.',10,1,$(td 0),NULL,0,0,3,5,'ar-prod',0,0,1700000000),
 ('p-q4', 1,'Quarterly test plan','Edge-case coverage.',20,1,$(td 2),NULL,0,0,2,4,'ar-oper',0,0,1700000000),
 ('p-cur',1,'Data analysis course','Week 4 of 9.',30,1,$(td 1),NULL,0,0,1,6,'ar-form',0,0,1700000000);

-- Dated to-dos, Monday to Sunday
INSERT INTO TMTask (uuid,type,title,notes,"index",start,startDate,deadline,deadlineSuppressionDate,
                    rt1_instanceCreationPaused,openChecklistItemsCount,checklistItemsCount,
                    project,area,heading,status,trashed,creationDate) VALUES
 ('t1',0,'Review the report draft','45 min',100,1,$(td 0),$(td 0),0,0,0,0,'p-web','ar-prod',NULL,0,0,1700000000),
 ('t2',0,'Reply to the site quote','','110',1,$(td 0),$(td 0),0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t3',0,'Close the project budget','90 min',120,1,$(td 1),$(td 1),0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t4',0,'Prepare the Tuesday presentation','60 min',130,1,$(td 1),$(td 1),0,0,0,0,'p-web','ar-prod',NULL,0,0,1700000000),
 ('t5',0,'Descriptive statistics class','','140',1,$(td 2),NULL,0,0,0,0,'p-cur','ar-form',NULL,0,0,1700000000),
 ('t6',0,'Demand scenario simulation','120 min',150,1,$(td 2),$(td 3),0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t7',0,'Update the procedures manual','','160',1,$(td 3),NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t8',0,'Interview with the supplier','30 min',170,1,$(td 3),$(td 3),0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t9',0,'Pass the quality review','45 min',180,1,$(td 4),NULL,0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t10',0,'Write the weekly summary','','190',1,$(td 4),$(td 4),0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t11',0,'Sort the drawings archive','','200',1,$(td 5),NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t12',0,'Practise with the exercise set','','210',1,$(td 6),NULL,0,0,0,0,'p-cur','ar-form',NULL,0,0,1700000000),
 -- Overdue: deadline last Friday
 ('t13',0,'Chase the unpaid invoice','20 min',220,1,$(td 0),$OVERDUE,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 -- Undated: inbox, anytime and someday
 ('t14',0,'Read the article on time-of-use tariffs','30 min',230,0,NULL,NULL,0,0,0,0,NULL,'ar-form',NULL,0,0,1700000000),
 ('t15',0,'Get a quote for the server','',240,1,NULL,NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t16',0,'Explore the heat-map tool','','250',2,NULL,NULL,0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t17',0,'Renew the editor subscription','','260',1,NULL,NULL,0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t18',0,'Sort the board screenshots','','270',0,NULL,NULL,0,0,0,0,NULL,'ar-form',NULL,0,0,1700000000);

-- Priority tags (ladder Important > Urgent > High > Medium > Low)
INSERT INTO TMTaskTag VALUES ('t1','tg-i'),('t1','tg-u'),('t2','tg-u'),('t3','tg-i'),
 ('t4','tg-h'),('t6','tg-h'),('t5','tg-m'),('t7','tg-m'),('t9','tg-h'),('t10','tg-m'),
 ('t11','tg-l'),('t12','tg-l'),('t13','tg-u'),('t14','tg-d'),('t16','tg-l'),('t18','tg-d');
SQL

# ---- Calendar database ---------------------------------------------------
sqlite3 "$CAL" <<SQL
CREATE TABLE Store     (ROWID INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE Calendar  (ROWID INTEGER PRIMARY KEY, title TEXT, color INTEGER, flags INTEGER, store_id INTEGER);
CREATE TABLE CalendarItem (ROWID INTEGER PRIMARY KEY, summary TEXT, all_day INTEGER,
                           start_date REAL, end_date REAL, hidden INTEGER, status INTEGER, calendar_id INTEGER);
CREATE TABLE OccurrenceCache (event_id INTEGER, day REAL, occurrence_date REAL, calendar_id INTEGER);

INSERT INTO Store VALUES (1,'iCloud'), (2,'Google'), (3,'Other');
INSERT INTO Calendar VALUES (10,'Agenda',1,0,1), (11,'Team',2,0,2), (12,'Personal',3,0,3);
SQL

# Events: (calendar, summary, day 0-6, start, end, all-day?)
add_event() {
  local cid="$1" title="$2" day="$3" t0="$4" t1="$5" allday="$6" rid
  rid=$(( RANDOM % 1000000 + 100 ))
  local s e
  if [ "$allday" = "1" ]; then s=$(cf "$day" "00:00"); e=$(cf "$day" "23:59")
  else s=$(cf "$day" "$t0"); e=$(cf "$day" "$t1"); fi
  sqlite3 "$CAL" "INSERT INTO CalendarItem VALUES ($rid,'$title',$allday,$s,$e,0,0,$cid);
                  INSERT INTO OccurrenceCache VALUES ($rid,$s,$s,$cid);"
}

add_event 10 "Team sync"                 0 "09:00" "09:30" 0
add_event 11 "Design review"             0 "11:00" "12:00" 0
add_event 12 "Lunch with the neighbour"  0 "13:30" "14:30" 0
add_event 10 "Statistics class"          1 "18:00" "20:00" 0
add_event 11 "Progress committee"        2 "10:00" "11:00" 0
add_event 10 "Server maintenance"        2 "00:00" "00:00" 1
add_event 12 "Partner birthday"          3 "00:00" "00:00" 1
add_event 11 "Client demo"               3 "15:00" "16:00" 0
add_event 10 "Monthly planning"          4 "09:30" "11:30" 0
add_event 12 "Local produce market"     5 "11:00" "14:00" 0
add_event 10 "Open day"                   6 "10:00" "13:00" 0

echo "→ $THINGS"
echo "→ $CAL"
echo "  reference Monday: $monday · to-dos: $(sqlite3 "$THINGS" 'select count(*) from TMTask') · events: $(sqlite3 "$CAL" 'select count(*) from CalendarItem')"
