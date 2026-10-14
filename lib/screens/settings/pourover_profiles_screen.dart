import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/brew_recipe.dart';
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../live/pourover/recipe_format.dart';

// Settings → Home → Pour Over → Profiles: all profiles to check. Only the
// checked ones appear below the brew cards and in the Pre-Brew picker; the
// "+" there leads here. At the top the check for anything new on GitHub —
// new ones come UNchecked and carry "NEW" until the page is left again.
//
// One card per settings page.
class PourOverProfilesScreen extends StatefulWidget {
  const PourOverProfilesScreen({super.key});

  @override
  State<PourOverProfilesScreen> createState() => _PourOverProfilesScreenState();
}

class _PourOverProfilesScreenState extends State<PourOverProfilesScreen> {
  late final BrewRecipeStore _store = context.read<BrewRecipeStore>();
  String _query = '';

  @override
  void dispose() {
    // Seen is seen: no more "NEW" next time.
    _store.markAllSeen();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    final before = _store.newCount;
    String text;
    try {
      final count = await _store.updateFromGitHub();
      final added = _store.newCount - before;
      text = count == null
          ? 'Profiles are up to date.'
          : added > 0
          ? '$added new ${added == 1 ? 'profile' : 'profiles'} — tick them to use them.'
          : 'Updated, no new profiles.';
    } catch (_) {
      text = 'Could not reach GitHub.';
    }
    messenger.showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BrewRecipeStore>();
    final colors = context.colors;
    final q = _query.trim().toLowerCase();
    final recipes = [
      for (final r in store.recipes)
        if (q.isEmpty ||
            '${r.name} ${r.brewer} ${r.sourceName} ${r.tags.join(' ')}'
                .toLowerCase()
                .contains(q))
          r,
    ];
    // New ones first, otherwise as stored (by brewer, then name).
    final fresh = [
      for (final r in recipes)
        if (store.isNew(r.id)) r,
    ];
    final groups = <String, List<BrewRecipe>>{};
    for (final r in recipes) {
      if (!store.isNew(r.id)) (groups[r.brewer] ??= []).add(r);
    }
    final fetched = store.fetchedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadii.tile),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.dividerInset,
                    16,
                    AppSpacing.dividerInset,
                    4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${store.enabledRecipes.length} of ${store.recipes.length} selected',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            if (fetched != null)
                              Text(
                                'From brew-recipes, ${_date(fetched)}',
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      AppButton(
                        label: store.updating
                            ? 'Checking…'
                            : 'Check for updates',
                        icon: Icons.refresh,
                        variant: AppButtonVariant.secondary,
                        expand: false,
                        height: 40,
                        onPressed: store.updating ? null : _checkForUpdates,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.dividerInset,
                    vertical: 4,
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search,
                        color: colors.textSecondary,
                        size: 20,
                      ),
                      hintText: 'Search',
                      hintStyle: TextStyle(color: colors.textTertiary),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Divider(height: 1, color: colors.divider),
                if (recipes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.dividerInset),
                    child: Text(
                      'No profiles found.',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (fresh.isNotEmpty) ...[
                  _GroupHeader('New'),
                  for (final r in fresh) _ProfileCheck(recipe: r),
                ],
                for (final entry in groups.entries) ...[
                  _GroupHeader(entry.key),
                  for (final r in entry.value) _ProfileCheck(recipe: r),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        14,
        AppSpacing.dividerInset,
        2,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ProfileCheck extends StatelessWidget {
  const _ProfileCheck({required this.recipe});

  final BrewRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BrewRecipeStore>();
    final colors = context.colors;
    final isNew = store.isNew(recipe.id);
    return CheckboxListTile(
      value: store.isEnabled(recipe.id),
      onChanged: (v) => store.setEnabled(recipe.id, v ?? false),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dividerInset,
      ),
      secondary: BrewerAvatar(brewer: recipe.brewer, size: 34),
      title: Row(
        children: [
          Flexible(
            child: Text(
              recipe.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
          ),
          if (isNew) ...[
            const SizedBox(width: 8),
            Text(
              'NEW',
              style: TextStyle(
                color: colors.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        recipeDetail(recipe),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary, fontSize: 12),
      ),
    );
  }
}
