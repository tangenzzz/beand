import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/brew_recipe.dart';
import '../../../models/machine_profile.dart' show profilePlaceholderColor;
import '../../../widgets/machine_badge.dart';
import '../../history/history_logic.dart' show ShotMachine;
import '../../../services/brew_recipe_store.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/header_icon_button.dart';
import '../../../widgets/reorderable_tile_row.dart';
import '../../profile/pourover_profile_detail_screen.dart';
import '../../root_scaffold.dart';
import '../../settings/pourover_profiles_screen.dart';

// Profile row below the brew cards — shaped like the machines' profile row
// (ProfileCarousel): heading on the left, "+" on the right, swipeable cards
// below. Only the profiles checked in Settings → Home → Pour Over →
// Profiles appear here; the "+" leads exactly there.
//
// Tapping opens the profile view as for the machines (read-only, photo,
// delete); the profile is selected in the Pre-Brew card.
class PourOverProfileRow extends StatelessWidget {
  const PourOverProfileRow({super.key});

  static void openSettings(BuildContext context) {
    final nav = RootNavigation.maybeOf(context);
    if (nav?.openSettingsPage != null) {
      nav!.openSettingsPage!((_) => const PourOverProfilesScreen());
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PourOverProfilesScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BrewRecipeStore>();
    final brew = context.watch<PourOverBrewService>();
    final recipes = store.enabledRecipes;
    final selectedId = brew.manual ? null : brew.recipe?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                tooltip: 'Choose profiles',
                onPressed: () => openSettings(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 158,
          child: recipes.isEmpty
              ? Center(
                  child: Text(
                    'No profiles selected. Tap + to choose some.',
                    style: TextStyle(
                      color: context.colors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                )
              // Long-press and drag changes the order (stays in the app,
              // there is no machine behind it).
              : ReorderableTileRow<BrewRecipe>(
                  items: recipes,
                  idOf: (r) => r.id,
                  onReorder: (ordered) =>
                      store.setOrder([for (final r in ordered) r.id]),
                  itemBuilder: (context, r) {
                    return _ProfileTile(
                      recipe: r,
                      selected: r.id == selectedId,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PourOverProfileDetailScreen(recipe: r),
                        ),
                      ),
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
    required this.recipe,
    required this.selected,
    required this.onTap,
  });

  final BrewRecipe recipe;
  final bool selected;
  final VoidCallback onTap;

  // Dimensions like the machines' profile cards.
  static const _width = 130.0;
  static const _imageHeight = 110.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photo = context.watch<BrewRecipeStore>().photoFor(recipe.id);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plain color fill like machine profiles without an image
            // (placeholder color from the profile ID); a custom photo takes
            // precedence. Top left the History's pour-over icon (V60 dripper).
            Container(
              width: _width,
              height: _imageHeight,
              clipBehavior: Clip.antiAlias,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                // The selected profile gets a border in the accent color.
                border: Border.all(
                  color: selected ? colors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              decoration: BoxDecoration(
                color: profilePlaceholderColor(recipe.id),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    Image.file(
                      photo,
                      fit: BoxFit.cover,
                      cacheWidth: (_width * 3).round(),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: MachineBadge(
                      glyph: MachineGlyph.v60,
                      color: ShotMachine.pourOver.color,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recipe.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image of a pour-over profile: custom photo or the placeholder color —
/// the same as on the card, as a circle for pick lists (like the machines'
/// profile circle in the Pre-Shot card).
class PourOverProfileAvatar extends StatelessWidget {
  const PourOverProfileAvatar({
    super.key,
    required this.recipe,
    this.size = 36,
  });

  final BrewRecipe recipe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = context.watch<BrewRecipeStore>().photoFor(recipe.id);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: profilePlaceholderColor(recipe.id),
        shape: BoxShape.circle,
      ),
      child: photo == null
          ? null
          : Image.file(
              photo,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );
  }
}
