import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../machines/espresso_machine.dart';
import '../../models/machine_profile.dart';
import '../../services/profile_store.dart';
import '../../widgets/header_icon_button.dart';
import '../../widgets/reorderable_tile_row.dart';
import '../profile/profile_detail_screen.dart';
import 'add_profile_dialog.dart';
import '../../theme/app_theme.dart';

// Swipeable profile cards below the Pre-Shot card. Reads the local copy of
// the profiles (ProfileStore), so it works without a connection to the
// machine too.
//
// Runs for both machines: which profiles are meant is decided by the
// ProfileStore of the respective home screen. GaggiMate profiles come
// without an image — there the bean sits on the profile's placeholder color.
class ProfileCarousel extends StatefulWidget {
  const ProfileCarousel({super.key});

  @override
  State<ProfileCarousel> createState() => _ProfileCarouselState();
}

class _ProfileCarouselState extends State<ProfileCarousel> {
  late final ProfileStore _store = context.read<ProfileStore>();
  late final Stream<List<StoredProfile>> _stored = context
      .read<AppDatabase>()
      .watchStoredProfiles(machine: _store.machineKey);

  Future<void> _reorder(
    EspressoMachine machine,
    List<MachineProfile> ordered,
  ) async {
    final result = await reorderMachineProfiles(
      database: context.read<AppDatabase>(),
      machine: machine,
      machineKey: _store.machineKey,
      visible: [for (final p in ordered) p.id],
    );
    if (result.isOk || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not change the order on the ${machine.displayName}',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final machine = context.watch<EspressoMachine>();
    final connected =
        machine.connectionState == MachineConnectionState.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heading on the left, "+" opposite on the right edge: creates a new
        // profile (dialog with the three ways to do so).
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              HeaderIconButton(
                icon: Icon(Icons.add, color: context.colors.textSecondary),
                tooltip: 'Add profile',
                onPressed: () => showAddProfileDialog(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          // Image + two-line name (e.g. "Roasticious Filter Bypass v2");
          // temperature/output are no longer shown below it.
          height: 158,
          child: StreamBuilder<List<StoredProfile>>(
            stream: _stored,
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textTertiary,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load profiles',
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              final profiles = [
                for (final p in snapshot.data ?? const <StoredProfile>[])
                  // Utility profiles (backflush, flush) don't belong in the
                  // shot selection.
                  if (!MachineProfile.isUtility(p))
                    MachineProfile.fromStored(p),
              ];
              if (profiles.isEmpty) {
                return Center(
                  child: Text(
                    connected
                        ? 'No profiles found'
                        : 'Profiles are saved once the machine is connected',
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              // Long press and drag changes the order — on the machine too.
              return ReorderableTileRow<MachineProfile>(
                items: profiles,
                idOf: (p) => p.id,
                itemBuilder: (context, p) =>
                    _ProfileTile(profile: p, machine: machine, store: _store),
                onReorder: (ordered) => _reorder(machine, ordered),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.machine,
    required this.store,
  });

  final MachineProfile profile;
  final EspressoMachine machine;
  final ProfileStore store;

  String get hostname => machine.host;

  static const _width = 130.0;

  static File? _localImage(MachineProfile profile) {
    final path = profile.localImagePath;
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  // Tapping opens the profile view (read-only — loads/heats nothing).
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileDetailScreen(
            summary: profile,
            machine: machine,
            store: store,
          ),
        ),
      ),
      child: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final imagePath = profile.imagePath;
    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: _width,
            height: 110,
            decoration: BoxDecoration(
              // Stays visible as background/fallback while the real profile
              // image loads or if it fails.
              color: profile.accentColor,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: _localImage(profile) != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      _localImage(profile)!,
                      width: _width,
                      height: 110,
                      fit: BoxFit.cover,
                      cacheWidth: (_width * 3).round(),
                    ),
                  )
                : imagePath == null
                ? Icon(
                    Icons.coffee,
                    color: context.colors.textSecondary,
                    size: 32,
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      'http://$hostname$imagePath',
                      width: _width,
                      height: 110,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : Icon(
                              Icons.coffee,
                              color: context.colors.textSecondary,
                              size: 32,
                            ),
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.coffee,
                        color: context.colors.textSecondary,
                        size: 32,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            profile.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
