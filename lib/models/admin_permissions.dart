import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Admin page permissions
//
//  Every admin account is either:
//    • a full-access admin (is_super = true)  → sees and edits every page, or
//    • a limited admin                        → gets an explicit map of
//      { page key : 'view' | 'edit' }.
//
//  A page that isn't in the map at all is completely hidden — the tab is not
//  rendered and its screen is never built.
//
//  The map lives in public.admin_accounts.permissions (jsonb) and is returned
//  by the admin_panel_login() RPC at login time.
// ─────────────────────────────────────────────────────────────────────────────

/// Access levels stored in the permissions map.
class AdminAccess {
  static const String none = 'none';
  static const String view = 'view';
  static const String edit = 'edit';
}

/// One selectable page in the "Create Admin" permissions dropdown.
class AdminPage {
  final String key;
  final String label;
  final IconData icon;
  const AdminPage(this.key, this.label, this.icon);
}

/// Page keys — these must match the tab order in AdminDashboardScreen.
class AdminPageKeys {
  static const String dashboard    = 'dashboard';
  static const String orders       = 'orders';
  static const String users        = 'users';
  static const String pricing      = 'pricing';
  static const String affiliate    = 'affiliate';
  static const String content      = 'content';
  static const String ads          = 'ads';
  static const String verification = 'verification';
  static const String tracking     = 'tracking';
  static const String marketing    = 'marketing';
  static const String settings     = 'settings';
}

/// Nav tabs, in the same order as the dashboard's IndexedStack children.
const List<AdminPage> kAdminTabPages = [
  AdminPage(AdminPageKeys.dashboard,    'Dashboard',    Icons.dashboard_rounded),
  AdminPage(AdminPageKeys.orders,       'Orders',       Icons.shopping_cart_rounded),
  AdminPage(AdminPageKeys.users,        'Users',        Icons.people_rounded),
  AdminPage(AdminPageKeys.pricing,      'Pricing',      Icons.attach_money_rounded),
  AdminPage(AdminPageKeys.affiliate,    'Affiliate',    Icons.handshake_outlined),
  AdminPage(AdminPageKeys.content,      'Content',      Icons.format_quote_rounded),
  AdminPage(AdminPageKeys.ads,          'Ads',          Icons.campaign_rounded),
  AdminPage(AdminPageKeys.verification, 'Verification', Icons.admin_panel_settings_rounded),
  AdminPage(AdminPageKeys.tracking,     'Tracking',     Icons.search_rounded),
  AdminPage(AdminPageKeys.marketing,    'Marketing',    Icons.campaign_rounded),
];

/// Everything that can be granted — the nav tabs plus Settings
/// (Settings covers WhatsApp number, Usage & Monitoring, and the ability to
/// create/edit other admin accounts).
const List<AdminPage> kAdminPages = [
  ...kAdminTabPages,
  AdminPage(AdminPageKeys.settings, 'Settings & Admins', Icons.settings_rounded),
];

/// Short labels used on bottom nav (kept identical to the old hard-coded list).
const Map<String, String> kAdminTabShortLabels = {
  AdminPageKeys.verification: 'Verify',
  AdminPageKeys.tracking: 'Track',
};

// ─────────────────────────────────────────────────────────────────────────────
//  AdminPerms — global, read anywhere in the app.
// ─────────────────────────────────────────────────────────────────────────────
class AdminPerms extends ChangeNotifier {
  AdminPerms._();
  static final AdminPerms i = AdminPerms._();

  /// Used so a "no permission" message can be shown from anywhere,
  /// even outside a Scaffold context. Wired in main.dart.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  String? accountId;
  String accountName = '';
  String accountCnic = '';
  bool isSuper = false;
  Map<String, String> _map = {};

  Map<String, String> get map => Map.unmodifiable(_map);

  void apply({
    required String? id,
    required String name,
    required String cnic,
    required bool isSuper,
    required Map<String, String> permissions,
  }) {
    accountId = id;
    accountName = name;
    accountCnic = cnic;
    this.isSuper = isSuper;
    _map = Map<String, String>.from(permissions);
    notifyListeners();
  }

  void clear() {
    accountId = null;
    accountName = '';
    accountCnic = '';
    isSuper = false;
    _map = {};
    notifyListeners();
  }

  String levelOf(String pageKey) {
    if (isSuper) return AdminAccess.edit;
    final v = _map[pageKey];
    if (v == AdminAccess.edit || v == AdminAccess.view) return v!;
    return AdminAccess.none;
  }

  bool canView(String pageKey) => levelOf(pageKey) != AdminAccess.none;
  bool canEdit(String pageKey) => levelOf(pageKey) == AdminAccess.edit;

  /// True when the page is visible but the admin may not change anything.
  bool isViewOnly(String pageKey) => levelOf(pageKey) == AdminAccess.view;

  /// Tabs this admin is allowed to open, in dashboard order.
  List<AdminPage> get visibleTabs =>
      kAdminTabPages.where((p) => canView(p.key)).toList();

  /// Index (in the dashboard's fixed 0..9 tab order) of the first tab
  /// this admin may open. Falls back to 0.
  int get firstVisibleTabIndex {
    for (int i = 0; i < kAdminTabPages.length; i++) {
      if (canView(kAdminTabPages[i].key)) return i;
    }
    return 0;
  }

  /// Returns true if the action may proceed. Otherwise shows a message
  /// and returns false — call this at the top of every save/delete handler.
  bool guardEdit(String pageKey, {String? what}) {
    if (canEdit(pageKey)) return true;
    denied(what: what);
    return false;
  }

  void denied({String? what}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF3A1730),
        content: Row(children: [
          const Icon(Icons.lock_outline_rounded, color: Color(0xFFFF6B8A), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              what == null
                  ? 'You have view-only access here.'
                  : 'You have view-only access — $what is not allowed.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small "View only" chip shown at the top of read-only pages.
// ─────────────────────────────────────────────────────────────────────────────
class ViewOnlyBanner extends StatelessWidget {
  final String pageKey;
  const ViewOnlyBanner({super.key, required this.pageKey});

  @override
  Widget build(BuildContext context) {
    if (!AdminPerms.i.isViewOnly(pageKey)) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: const Color(0xFF2A1F3D),
      child: Row(children: [
        Icon(Icons.visibility_outlined, size: 15, color: Colors.white.withOpacity(0.55)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'View only — you can read this page but not make changes.',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.55)),
          ),
        ),
      ]),
    );
  }
}
