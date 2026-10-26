#!/bin/bash
# makedemo.sh — genera dos bases SQLite inventadas (Things + Calendario) para poder
# mostrar la app sin tocar los datos reales de nadie.
#
#   zsh Tools/demo.sh          # construye las bases y abre la app en modo demo
#   ./Tools/makedemo.sh        # solo construye las bases en build/demo/
#
# Las fechas se calculan contra el lunes de la semana en curso, así el tablero siempre
# sale poblado sin importar cuándo se ejecute. Los únicos datos que hay aquí son los de
# este archivo.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HERE/build/demo"
mkdir -p "$OUT"

THINGS="$OUT/things.sqlite"
CAL="$OUT/calendar.sqlite"
[ -f "$THINGS" ] && mv "$THINGS" "$THINGS.anterior"
[ -f "$CAL" ] && mv "$CAL" "$CAL.anterior"

# ---- fechas ---------------------------------------------------------------
dow=$(date +%u)                                  # 1 = lunes … 7 = domingo
monday=$(date -j -v-$((dow - 1))d +%Y-%m-%d)

# coso: imprime "año mes día" de i días después del lunes de esta semana.
coso() { date -j -v+$1d -f "%Y-%m-%d" "$monday" +%Y-%m-%d; }
# thingsDate: empaqueta una fecha como Things (YYYYYYYYYYYMMMMDDDDD0000000).
td() {
  IFS='-' read -r y m d <<< "$(coso "$1")"
  echo $(( (10#$y << 16) | (10#$m << 12) | (10#$d << 7) ))
}
# cf: CFAbsoluteTime de "día de la semana + hora", que es como Calendar guarda las fechas.
cf() {
  printf '%s' "$(echo "$(date -j -f '%Y-%m-%d %H:%M:%S' "$(coso "$1") $2:00" +%s) - 978307200" | bc)"
}
oy=$(date -j -v-$((dow + 2))d +%Y); om=$(date -j -v-$((dow + 2))d +%m); od=$(date -j -v-$((dow + 2))d +%d)
OVERDUE=$(( (10#$oy << 16) | (10#$om << 12) | (10#$od << 7) ))

# ---- base de Things -------------------------------------------------------
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

INSERT INTO TMArea VALUES ('ar-prod','Producto'), ('ar-oper','Operaciones'), ('ar-form','Formación');
INSERT INTO TMTag  VALUES ('tg-i','Important'), ('tg-u','Urgent'), ('tg-h','High'),
                          ('tg-m','Medium'), ('tg-l','Low'), ('tg-d','Deep work');

-- Proyectos (type 1)
INSERT INTO TMTask (uuid,type,title,notes,"index",start,startDate,deadline,deadlineSuppressionDate,
                    rt1_instanceCreationPaused,openChecklistItemsCount,checklistItemsCount,area,status,trashed,creationDate) VALUES
 ('p-web',1,'Lanzar la web nueva','Rediseño completo, tres secciones.',10,1,$(td 0),NULL,0,0,3,5,'ar-prod',0,0,1700000000),
 ('p-q4', 1,'Plan de pruebas del trimestre','Cobertura de casos límite.',20,1,$(td 2),NULL,0,0,2,4,'ar-oper',0,0,1700000000),
 ('p-cur',1,'Curso de análisis de datos','Semana 4 de 9.',30,1,$(td 1),NULL,0,0,1,6,'ar-form',0,0,1700000000);

-- Tareas con fecha, lunes a domingo
INSERT INTO TMTask (uuid,type,title,notes,"index",start,startDate,deadline,deadlineSuppressionDate,
                    rt1_instanceCreationPaused,openChecklistItemsCount,checklistItemsCount,
                    project,area,heading,status,trashed,creationDate) VALUES
 ('t1',0,'Revisar el borrador del informe','45 min',100,1,$(td 0),$(td 0),0,0,0,0,'p-web','ar-prod',NULL,0,0,1700000000),
 ('t2',0,'Responder la cotización de la obra','','110',1,$(td 0),$(td 0),0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t3',0,'Cerrar el presupuesto del proyecto','90 min',120,1,$(td 1),$(td 1),0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t4',0,'Preparar la presentación del martes','60 min',130,1,$(td 1),$(td 1),0,0,0,0,'p-web','ar-prod',NULL,0,0,1700000000),
 ('t5',0,'Clase de estadística descriptiva','','140',1,$(td 2),NULL,0,0,0,0,'p-cur','ar-form',NULL,0,0,1700000000),
 ('t6',0,'Simulación del escenario de demanda','120 min',150,1,$(td 2),$(td 3),0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t7',0,'Actualizar el manual de procedimientos','','160',1,$(td 3),NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t8',0,'Entrevista con la proveedora','30 min',170,1,$(td 3),$(td 3),0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t9',0,'Pasar la revisión de calidad','45 min',180,1,$(td 4),NULL,0,0,0,0,'p-q4','ar-oper',NULL,0,0,1700000000),
 ('t10',0,'Escribir el resumen de la semana','','190',1,$(td 4),$(td 4),0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t11',0,'Ordenar el archivo de planos','','200',1,$(td 5),NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t12',0,'Practicar con el set de ejercicios','','210',1,$(td 6),NULL,0,0,0,0,'p-cur','ar-form',NULL,0,0,1700000000),
 -- Vencida: plazo el viernes de la semana pasada
 ('t13',0,'Reclamar la factura impaga','20 min',220,1,$(td 0),$OVERDUE,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 -- Sin fecha: bandeja, en cualquier momento y algún día
 ('t14',0,'Leer el artículo sobre tarifas horarias','30 min',230,0,NULL,NULL,0,0,0,0,NULL,'ar-form',NULL,0,0,1700000000),
 ('t15',0,'Pedir presupuesto para el servidor','',240,1,NULL,NULL,0,0,0,0,NULL,'ar-oper',NULL,0,0,1700000000),
 ('t16',0,'Explorar la herramienta de mapas de calor','','250',2,NULL,NULL,0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t17',0,'Renovar la suscripción del editor','','260',1,NULL,NULL,0,0,0,0,NULL,'ar-prod',NULL,0,0,1700000000),
 ('t18',0,'Clasificar las capturas del tablero','','270',0,NULL,NULL,0,0,0,0,NULL,'ar-form',NULL,0,0,1700000000);

-- Etiquetas de prioridad (escalera Important > Urgent > High > Medium > Low)
INSERT INTO TMTaskTag VALUES ('t1','tg-i'),('t1','tg-u'),('t2','tg-u'),('t3','tg-i'),
 ('t4','tg-h'),('t6','tg-h'),('t5','tg-m'),('t7','tg-m'),('t9','tg-h'),('t10','tg-m'),
 ('t11','tg-l'),('t12','tg-l'),('t13','tg-u'),('t14','tg-d'),('t16','tg-l'),('t18','tg-d');
SQL

# ---- base de Calendario ---------------------------------------------------
sqlite3 "$CAL" <<SQL
CREATE TABLE Store     (ROWID INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE Calendar  (ROWID INTEGER PRIMARY KEY, title TEXT, color INTEGER, flags INTEGER, store_id INTEGER);
CREATE TABLE CalendarItem (ROWID INTEGER PRIMARY KEY, summary TEXT, all_day INTEGER,
                           start_date REAL, end_date REAL, hidden INTEGER, status INTEGER, calendar_id INTEGER);
CREATE TABLE OccurrenceCache (event_id INTEGER, day REAL, occurrence_date REAL, calendar_id INTEGER);

INSERT INTO Store VALUES (1,'iCloud'), (2,'Google'), (3,'Other');
INSERT INTO Calendar VALUES (10,'Agenda',1,0,1), (11,'Equipo',2,0,2), (12,'Personal',3,0,3);
SQL

# Eventos: (calendario, resumen, día 0-6, inicio, fin, ¿todo el día?)
add_event() {
  local cid="$1" title="$2" day="$3" t0="$4" t1="$5" allday="$6" rid
  rid=$(( RANDOM % 1000000 + 100 ))
  local s e
  if [ "$allday" = "1" ]; then s=$(cf "$day" "00:00"); e=$(cf "$day" "23:59")
  else s=$(cf "$day" "$t0"); e=$(cf "$day" "$t1"); fi
  sqlite3 "$CAL" "INSERT INTO CalendarItem VALUES ($rid,'$title',$allday,$s,$e,0,0,$cid);
                  INSERT INTO OccurrenceCache VALUES ($rid,$s,$s,$cid);"
}

add_event 10 "Sincronización del equipo" 0 "09:00" "09:30" 0
add_event 11 "Revisión de diseño"        0 "11:00" "12:00" 0
add_event 12 "Almuerzo con la vecina"    0 "13:30" "14:30" 0
add_event 10 "Clase de estadística"      1 "18:00" "20:00" 0
add_event 11 "Comité de avance"          2 "10:00" "11:00" 0
add_event 10 "Mantención del servidor"   2 "00:00" "00:00" 1
add_event 12 "Cumple del socio"          3 "00:00" "00:00" 1
add_event 11 "Demo con la clienta"       3 "15:00" "16:00" 0
add_event 10 "Planificación mensual"     4 "09:30" "11:30" 0
add_event 12 "Feria de productos locales" 5 "11:00" "14:00" 0
add_event 10 "Jornada de puertas abiertas" 6 "10:00" "13:00" 0

echo "→ $THINGS"
echo "→ $CAL"
echo "  lunes de referencia: $monday · tareas: $(sqlite3 "$THINGS" 'select count(*) from TMTask') · eventos: $(sqlite3 "$CAL" 'select count(*) from CalendarItem')"
