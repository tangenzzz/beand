// The beans table as it looks from schema v3 on. Since schema v8 the
// migration touches it (type becomes nullable, "Roasted for" is added), so
// every migration test needs it — including those about shots.
const legacyBeansTable = '''
  CREATE TABLE beans (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
    roaster TEXT NULL, roast_date INTEGER NULL,
    is_blend INTEGER NOT NULL DEFAULT 0, country TEXT NULL,
    processing TEXT NULL, variety TEXT NULL, producer TEXT NULL,
    weight_grams REAL NULL, taste TEXT NULL, cost REAL NULL,
    photo_path TEXT NULL, is_frozen INTEGER NOT NULL DEFAULT 0,
    thawed_date INTEGER NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP))
  );
''';

// The shot tables as they exist in every app database since schema v1
// (onCreate created them too). Migration tests that rebuild an old database
// need them, because later migrations extend them.
const legacyShotTables = '''
  CREATE TABLE shots (
    id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL,
    bean_id INTEGER NULL REFERENCES beans (id), profile_name TEXT NULL,
    dose_grams REAL NULL, final_weight REAL NULL, duration_ms INTEGER NULL,
    grind_size TEXT NULL, rating INTEGER NULL, notes TEXT NULL,
    shot_photo_path TEXT NULL, raw_debug_json TEXT NULL,
    created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP))
  );
  CREATE TABLE shot_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT, shot_id INTEGER NOT NULL REFERENCES shots (id),
    time_ms INTEGER NOT NULL, profile_ms INTEGER NULL, pressure REAL NULL, flow REAL NULL,
    weight REAL NULL, gravimetric_flow REAL NULL, external_temp1 REAL NULL,
    external_temp2 REAL NULL, bar_up REAL NULL, bar_mid_up REAL NULL, bar_mid_down REAL NULL,
    bar_down REAL NULL, tube_temp REAL NULL, motor_temp REAL NULL, lam_temp REAL NULL,
    motor_position REAL NULL, motor_speed REAL NULL, motor_power REAL NULL,
    motor_current REAL NULL, bandheater_power REAL NULL, bandheater_current REAL NULL,
    pressure_sensor_raw REAL NULL, water_status INTEGER NULL, weight_prediction REAL NULL
  );
''';

// The additions to the shot tables from schema v4 and v5 — run after
// [legacyShotTables] if the rebuilt database is v5 or newer. From schema 15
// on the migration rebuilds the shot table and reads these columns; a v6
// database without them never existed.
const legacyShotColumnsV5 = '''
  ALTER TABLE shots ADD COLUMN external_id TEXT NULL;
  ALTER TABLE shots ADD COLUMN machine TEXT NOT NULL DEFAULT 'meticulous';
  ALTER TABLE shots ADD COLUMN profile_color TEXT NULL;
  ALTER TABLE shots ADD COLUMN profile_image_path TEXT NULL;
  ALTER TABLE shots ADD COLUMN brew_temp REAL NULL;
  ALTER TABLE shot_readings ADD COLUMN stage TEXT NULL;
  CREATE INDEX shot_readings_shot_id ON shot_readings (shot_id);
  CREATE UNIQUE INDEX shots_external_id ON shots (external_id);
  ALTER TABLE shots ADD COLUMN profile_temp REAL NULL;
  ALTER TABLE shots ADD COLUMN deleted_at INTEGER NULL;
''';
