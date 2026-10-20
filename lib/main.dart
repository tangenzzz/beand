import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'database/database.dart';
import 'machines/gaggimate/gaggimate_live_shot_service.dart';
import 'machines/gaggimate/gaggimate_service.dart';
import 'machines/gaggimate/gaggimate_profile_sync_service.dart';
import 'machines/gaggimate/gaggimate_shot_sync_service.dart';
import 'scale/acaia_scale.dart';
import 'scale/brew_scale.dart';
import 'scale/simulated_scale.dart';
import 'screens/root_scaffold.dart';
import 'screens/settings/gaggimate_settings_screen.dart';
import 'screens/settings/meticulous_settings_screen.dart';
import 'services/ai/ai_service.dart';
import 'services/ai/ai_settings.dart';
import 'services/app_settings.dart';
import 'services/auto_backup.dart';
import 'services/bundled_licenses.dart';
import 'services/gear_store.dart';
import 'services/grinder_store.dart';
import 'services/water_store.dart';
import 'services/brew_recipe_store.dart';
import 'services/live_shot_service.dart';
import 'services/machine_address_fallback.dart';
import 'services/machine_discovery.dart';
import 'services/meticulous_socket_service.dart';
import 'services/pourover_brew_service.dart';
import 'services/profile_images.dart';
import 'services/profile_sync_service.dart';
import 'services/shot_setup.dart';
import 'services/shot_sync_service.dart';
import 'sync/engine/sync_engine.dart';
import 'sync/records/setting_codec.dart';
import 'sync/engine/sync_state_store.dart';
import 'sync/identity/key_store.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';

// First attempt on first launch only. Real machines announce names like
// meticulous<Words>-<id>.local; if this one is dead the app quietly finds
// the machine via mDNS discovery (Settings → Connections).
const _defaultHostname = 'meticulous.local';

// GaggiMate announces itself via mDNS under this name (firmware mDNSPlugin).
const _defaultGaggimateHost = 'gaggimate.local';

// First pour-over recipe, as long as none has been chosen.
const _defaultRecipeId = 'tetsu-kasuya-4-6-method';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();

  final prefs = await SharedPreferences.getInstance();
  final hostname = prefs.getString(hostnamePrefKey) ?? _defaultHostname;

  final appSettings = await AppSettings.load();
  // All gear of My Coffee Desk; grinders and waters are views on it.
  final gear = await GearStore.load();
  final grinders = GrinderStore(gear);
  final waters = WaterStore(gear);
  // AI settings (Settings → AI). Loaded before runApp so no AI button
  // briefly appears and disappears; the keys themselves stay in the
  // keystore and are fetched per call.
  final aiSettings = await AiSettings.load();
  final database = AppDatabase();
  // Device id for sync (which device changed something last). Lives in the
  // keystore, not in the prefs, so a backup never carries it to another
  // device. If the keystore does not answer, the column stays empty —
  // writing still works.
  try {
    database.deviceId = await SecureSyncKeyStore().deviceId();
  } catch (e) {
    debugPrint('Sync device id unavailable: $e');
  }
  // One discovery for both machines (each queries its own service type).
  final discovery = BonsoirMachineDiscovery();
  final socketService = MeticulousSocketService(hostname: hostname);
  // If the stored address does not answer, the service quietly tries the
  // last seen IP and then searches the network (see
  // MachineAddressFallback); whatever it finds is saved right away so the
  // next launch gets it right directly.
  socketService.addressFallback = MachineAddressFallback(
    serviceType: meticulousServiceType,
    discovery: discovery,
    lastIp: prefs.getString(lastIpPrefKey),
  );
  // The fallback search must NOT replace the configured name with an IP
  // (see MachineAddressStore) — that happened before.
  socketService.onAddressChanged = (host, ip) =>
      meticulousAddressStore.remember(address: host, ip: ip);
  socketService.connect();
  // Each machine has its own setup store — otherwise the GaggiMate home
  // would show the Meticulous profile.
  final shotSetup = await ShotSetup.load();
  shotSetup.gear = gear;
  final gaggimateSetup = await ShotSetup.load(machineKey: 'gaggimate');
  gaggimateSetup.gear = gear;
  final shotSetups = ShotSetups(
    meticulous: shotSetup,
    gaggimate: gaggimateSetup,
  );
  // Pull profile/bean/dose/grind size of the respective last shot into the
  // pre-shot card (see ShotSetup.restoreFromLastShot).
  await shotSetup.restoreFromLastShot(database);
  await gaggimateSetup.restoreFromLastShot(database);
  final docs = await getApplicationDocumentsDirectory();
  // Keeps the local DB complete: imports all shots from the machine (on
  // connect and after every shot), see shot_sync_service.dart.
  final imageDir = Directory(p.join(docs.path, 'profile_images'));
  final syncService = ShotSyncService(
    database: database,
    socket: socketService,
    setup: shotSetup,
    imageDir: imageDir,
  )..start();
  // Keep profiles locally too (available offline).
  final profileSync = ProfileSyncService(
    database: database,
    socket: socketService,
    imageDir: imageDir,
  )..start();
  // Drives the pre-shot/shot/post-shot card purely from the machine's live
  // status (see live_shot_service.dart).
  final liveShotService = MeticulousLiveShotService(socketService)..start();

  // GaggiMate: only connect if the pill is shown at all — otherwise
  // everyone without a GaggiMate would get a reconnect loop into nowhere.
  // Turning it on in Settings → Home connects afterwards (see
  // HomeSettingsScreen).
  final gaggimate = GaggiMateService(
    host: prefs.getString(gaggimateHostPrefKey) ?? _defaultGaggimateHost,
  );
  gaggimate.addressFallback = MachineAddressFallback(
    serviceType: gaggimateServiceType,
    discovery: discovery,
    lastIp: prefs.getString(gaggimateLastIpPrefKey),
  );
  gaggimate.onAddressChanged = (host, ip) =>
      gaggimateAddressStore.remember(address: host, ip: ip);
  if (appSettings.isHomeModeEnabled(HomeMode.gaggimate)) gaggimate.connect();
  final gaggimateLiveShot = GaggiMateLiveShotService(gaggimate)..start();
  // Pulls GaggiMate brews into the same table as the Meticulous ones
  // (see gaggimate_shot_sync_service.dart). Runs even without an existing
  // connection: it hooks onto the service and starts once that connects.
  final gaggimateSync = GaggiMateShotSyncService(
    database: database,
    machine: gaggimate,
    setup: gaggimateSetup,
  )..start();
  // Local copy of the GaggiMate profiles — counterpart to the Meticulous
  // ProfileSyncService, so the profile row and profile view work without a
  // connection.
  final gaggimateProfiles = GaggiMateProfileSyncService(
    database: database,
    machine: gaggimate,
  )..start();

  // Pour Over: recipes (bundled or last fetched from GitHub), its own setup
  // store and the Bluetooth scale. With
  // --dart-define=BEAND_SIM_SCALE=true a simulated scale runs instead of the
  // Acaia and "pours" the recipe itself when a brew starts — for
  // development only; for users Pour Over only works with a real scale.
  final recipeStore = BrewRecipeStore(
    cacheFile: File(p.join(docs.path, 'brew_recipes_cache.json')),
  );
  await recipeStore.load();
  final pourOverSetup = await ShotSetup.load(machineKey: 'pourover');
  pourOverSetup.gear = gear;
  // The brew chain last used for pour over (as for both machines above).
  await pourOverSetup.restoreChainFromLastShot(database);
  shotSetups.pourOver = pourOverSetup;
  if (pourOverSetup.profileId == null ||
      recipeStore.byId(pourOverSetup.profileId!) == null) {
    final first =
        recipeStore.byId(_defaultRecipeId) ??
        (recipeStore.recipes.isEmpty ? null : recipeStore.recipes.first);
    if (first != null) {
      pourOverSetup.setProfile(first.id, first.name);
      pourOverSetup.setDose(first.doseG);
    }
  }
  late final PourOverBrewService pourOver;
  final BrewScale scale = const bool.fromEnvironment('BEAND_SIM_SCALE')
      ? SimulatedScale(speed: 3, autoPour: () => pourOver.plan)
      : AcaiaScale();
  pourOver = PourOverBrewService(
    scale: scale,
    recipes: recipeStore,
    setup: pourOverSetup,
    database: database,
  )..start();

  final profileImages = ProfileImages(database.watchStoredProfiles());

  // Sync between your own devices (Settings → Sync). If enabled, it syncs
  // right away in the background; the UI does not wait for it.
  final deviceSync = SyncService(
    db: database,
    keyStore: SecureSyncKeyStore(),
    stateStore: FileSyncStateStore(),
    // Settings that travel between devices (whitelist in
    // lib/sync/records/setting_codec.dart).
    settings: SettingsBridge(
      prefs: () async =>
          SharedPreferencesSettingsStore(await SharedPreferences.getInstance()),
      // Gear photos live in a setting; they travel via the photo servers.
      photos: gear,
      reload: () async {
        await appSettings.reload();
        await aiSettings.reload();
        await gear.reload();
      },
    ),
    settingsSources: [appSettings, aiSettings, gear],
    docsDir: getApplicationDocumentsDirectory,
  );
  await deviceSync.init();

  // Auto backup (Settings → Backup): WorkManager runs it at the set times,
  // in this engine while the app is open — then with this database.
  AutoBackup.appDatabase = database;
  unawaited(_startAutoBackup());

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        ChangeNotifierProvider<AppSettings>.value(value: appSettings),
        ChangeNotifierProvider<GearStore>.value(value: gear),
        ChangeNotifierProvider<GrinderStore>.value(value: grinders),
        ChangeNotifierProvider<WaterStore>.value(value: waters),
        ChangeNotifierProvider<AiSettings>.value(value: aiSettings),
        // The service depends on the settings and holds no state itself —
        // building it once is enough, and screens can swap it in tests for
        // one with a fixed HTTP client.
        Provider<AiService>.value(value: AiService(aiSettings)),
        ChangeNotifierProvider<MeticulousSocketService>.value(
          value: socketService,
        ),
        Provider<ShotSetups>.value(value: shotSetups),
        ChangeNotifierProvider<LiveShotService>.value(value: liveShotService),
        ChangeNotifierProvider<GaggiMateService>.value(value: gaggimate),
        ChangeNotifierProvider<GaggiMateLiveShotService>.value(
          value: gaggimateLiveShot,
        ),
        // Profile images for history: used where a shot carries none
        // itself (see profile_images.dart).
        ChangeNotifierProvider<ProfileImages>.value(value: profileImages),
        Provider<ShotSyncService>.value(value: syncService),
        Provider<GaggiMateShotSyncService>.value(value: gaggimateSync),
        Provider<GaggiMateProfileSyncService>.value(value: gaggimateProfiles),
        Provider<ProfileSyncService>.value(value: profileSync),
        ChangeNotifierProvider<BrewScale>.value(value: scale),
        ChangeNotifierProvider<BrewRecipeStore>.value(value: recipeStore),
        ChangeNotifierProvider<PourOverBrewService>.value(value: pourOver),
        ChangeNotifierProvider<SyncService>.value(value: deviceSync),
      ],
      child: const BeandApp(),
    ),
  );
}

class BeandApp extends StatelessWidget {
  const BeandApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Appearance and accent come from the settings; they are loaded before
    // runApp, so the right theme is there in the FIRST frame — nothing
    // jumps. "System" follows the device brightness, provided by the
    // MediaQuery above the MaterialApp (set by runApp).
    final settings = context.watch<AppSettings>();
    final variant = settings.themeMode.resolve(
      MediaQuery.platformBrightnessOf(context),
    );
    return MaterialApp(
      title: "bean'd",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(variant: variant, accent: settings.accent),
      home: const RootScaffold(),
    );
  }
}

// Registers the background entry point, then catches up on a slot that was
// missed (phone off, Doze) and queues the next one. A little after the
// start, so it does not compete with the first frames.
Future<void> _startAutoBackup() async {
  try {
    await Workmanager().initialize(autoBackupDispatcher);
    await Future<void>.delayed(const Duration(seconds: 10));
    final backup = await AutoBackup.platform();
    await backup.run();
  } catch (e) {
    debugPrint('Auto backup check failed: $e');
  }
}
