import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/addresses/domain/address_models.dart';
import '../features/addresses/presentation/screens/add_edit_address_screen.dart';
import '../features/addresses/presentation/screens/address_list_screen.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/presentation/screens/auth_prompt_screen.dart';
import '../features/auth/presentation/screens/location_access_screen.dart';
import '../features/auth/presentation/screens/onboarding_screen.dart';
import '../features/auth/presentation/screens/otp_verify_screen.dart';
import '../features/auth/presentation/screens/phone_auth_screen.dart';
import '../features/auth/presentation/screens/profile_completion_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/booking/domain/booking_models.dart';
import '../features/booking/presentation/screens/booking_detail_screen.dart';
import '../features/booking/presentation/screens/booking_success_screen.dart';
import '../features/booking/domain/cart_notifier.dart';
import '../features/booking/presentation/screens/checkout_screen.dart';
import '../features/booking/presentation/screens/grocery_cart_screen.dart';
import '../features/booking/presentation/screens/my_bookings_screen.dart';
import '../features/catalog/domain/catalog_models.dart';
import '../features/catalog/presentation/screens/all_services_screen.dart';
import '../features/catalog/presentation/screens/category_detail_screen.dart';
import '../features/catalog/presentation/screens/grocery_product_detail_screen.dart';
import '../features/catalog/presentation/screens/search_screen.dart';
import '../features/catalog/presentation/screens/seller_hub_groceries_screen.dart';
import '../features/catalog/presentation/screens/seller_hub_vegetables_screen.dart';
import '../features/catalog/presentation/screens/service_detail_screen.dart';
import '../features/feedback/presentation/screens/feedback_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/logistics/presentation/screens/drop_location_picker_screen.dart';
import '../features/logistics/presentation/screens/goods_transport_booking_screen.dart';
import '../features/logistics/domain/logistics_models.dart'
    show LogisticsVehicleCategory;
import '../features/logistics/domain/logistics_providers.dart'
    show PickedDropLocation;
import '../features/payment/presentation/screens/payment_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/support/presentation/screens/support_screen.dart';
import '../features/tracking/presentation/screens/live_tracking_screen.dart';
import '../features/work_extension/presentation/screens/work_extension_screen.dart';
import '../shared/theme/app_colors.dart';
import '../shared/widgets/app_shell.dart';

// ── Route path constants ────────────────────────────────────────────────────
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String locationAccess = '/location-access';
  static const String authPrompt = '/auth-prompt';
  static const String home = '/';
  static const String categories = '/categories';
  static const String search = '/search';
  static const String categoryDetail = '/categories/:slug';
  // Added 2026-09-25 — Seller Hub Marketplace grocery department browse
  // (real admin category tree from the vendor's Seller Hub, distinct from
  // categoryDetail's Vegetable Inventory tree and from the flat, no-tree
  // GroceryHubCategoryScreen).
  static const String sellerHubGroceries = '/groceries/seller-hub';
  // Added 2026-09-30 — Fresh Vegetables & Fruits, browsed by the same
  // Seller Hub Marketplace category tree as sellerHubGroceries above (the
  // admin now adds produce as its own main category → sub-category → leaf
  // in that tree, replacing the old, separate Vegetable Inventory module
  // categoryDetail's grocery branch still reads from).
  static const String sellerHubVegetables = '/vegetables/seller-hub';
  static const String serviceDetail = '/services/:slug';
  // Added 2026-09-28 — dedicated product page for groceries/vegetables/
  // fruits, distinct from serviceDetail's scheduled-service layout (see
  // GroceryProductDetailScreen's doc comment for why these can't share a
  // screen).
  static const String groceryProductDetail = '/products/:slug';
  static const String cart = '/cart';
  static const String addresses = '/addresses';
  static const String addAddress = '/addresses/add';
  static const String editAddress = '/addresses/edit';
  static const String login = '/login';
  static const String otpVerify = '/login/verify';
  static const String profileComplete = '/login/profile';
  static const String myBookings = '/bookings';
  static const String bookingDetail = '/bookings/:id';
  static const String bookingSuccess = '/bookings/success/:id';
  static const String payment = '/checkout/payment';
  static const String support = '/support';
  static const String profile = '/profile';
  static const String bookingCheckout = '/checkout';
  // Added 2026-09-19 — see CatalogFlowType.logistics for why this route
  // exists separately from bookingCheckout.
  static const String goodsTransportBooking = '/goods-transport/booking';
  // Added 2026-09-20 — see DropLocationPickerScreen's doc comment: the
  // customer-web-parity fare engine requires real drop coordinates, which a
  // free-text field cannot supply.
  static const String dropLocationPicker = '/goods-transport/drop-location';
  static const String liveTracking = '/track/:identifier';
  static const String feedback = '/feedback/:token';
  static const String workExtension = '/work-extension/:token';
}

// Added 2026-09-19 so code outside the widget tree — specifically a local
// notification's tap callback in notification_service.dart, which fires
// from the OS with no BuildContext of its own — can still navigate (e.g.
// to a booking's detail screen). Not used for anything else; every normal
// in-app navigation keeps using its own local `context`.
final rootNavigatorKey = GlobalKey<NavigatorState>();

// ── Router provider ─────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // The splash route (SplashScreen) renders the SEVO brand image first on
    // every cold start, then hands off to Home itself after a fixed delay —
    // see splash_screen.dart.
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    routes: [
      // ── Onboarding / Welcome routes (no bottom nav — pre-shell) ───────────
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.locationAccess,
        name: 'location-access',
        builder: (context, state) => const LocationAccessScreen(),
      ),
      GoRoute(
        path: AppRoutes.authPrompt,
        name: 'auth-prompt',
        builder: (context, state) => const AuthPromptScreen(),
      ),

      // ── App shell (persistent bottom nav) ─────────────────────────────────
      // Every screen the customer browses day-to-day — catalog, checkout,
      // addresses, booking detail — lives under this single ShellRoute so
      // the bottom tab bar (Home/Bookings/Cart/Support/Profile) never
      // disappears while navigating deeper than one level. Only the
      // pre-auth flow (splash/onboarding/login) and tokenized deep links
      // that can be opened without ever seeing app chrome stay outside it.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.myBookings,
            name: 'my-bookings',
            builder: (context, state) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.cart,
            name: 'cart',
            builder: (context, state) => const _CartRouteScreen(),
          ),
          GoRoute(
            path: AppRoutes.support,
            name: 'support',
            builder: (context, state) => const SupportScreen(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),

          // ── Catalog routes ────────────────────────────────────────────────
          GoRoute(
            path: AppRoutes.search,
            name: 'search',
            builder: (context, state) => const SearchScreen(),
          ),
          GoRoute(
            path: AppRoutes.categories,
            name: 'all-services',
            builder: (context, state) => const AllServicesScreen(),
          ),
          GoRoute(
            path: AppRoutes.categoryDetail,
            name: 'category-detail',
            builder: (context, state) {
              final slug = state.pathParameters['slug'] ?? '';
              final extra = state.extra;
              return CategoryDetailScreen(
                categorySlug: slug,
                initialCategory: extra is Category ? extra : null,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.sellerHubGroceries,
            name: 'seller-hub-groceries',
            // Fixed 2026-09-28: accepts an optional `?category=<slug>` so an
            // admin marketplace click-through link (e.g. Home's Bestsellers
            // tiles, via _handleAdminLinkTap in home_screen.dart) can open
            // straight into the right department instead of always
            // defaulting to the first one.
            builder: (context, state) => SellerHubGroceriesScreen(
              initialCategorySlug: state.uri.queryParameters['category'],
            ),
          ),
          GoRoute(
            path: AppRoutes.sellerHubVegetables,
            name: 'seller-hub-vegetables',
            // Same `?category=<slug>` deep-link support as
            // seller-hub-groceries above.
            builder: (context, state) => SellerHubVegetablesScreen(
              initialCategorySlug: state.uri.queryParameters['category'],
            ),
          ),
          GoRoute(
            path: AppRoutes.serviceDetail,
            name: 'service-detail',
            builder: (context, state) {
              final slug = state.pathParameters['slug'] ?? '';
              final extra = state.extra;
              debugPrint(
                  '[AppRouter] Navigating to serviceDetail with slug: "$slug", extra: ${extra.runtimeType}');
              return ServiceDetailScreen(
                serviceSlug: slug,
                initialService: extra is ServiceItem ? extra : null,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.groceryProductDetail,
            name: 'grocery-product-detail',
            builder: (context, state) {
              final slug = state.pathParameters['slug'] ?? '';
              final extra = state.extra;
              return GroceryProductDetailScreen(
                productSlug: slug,
                initialProduct: extra is ServiceItem ? extra : null,
              );
            },
          ),

          // ── Address routes ────────────────────────────────────────────────
          GoRoute(
            path: AppRoutes.addresses,
            name: 'addresses',
            builder: (context, state) {
              final selectMode = state.uri.queryParameters['select'] == 'true';
              return AddressListScreen(isSelectionMode: selectMode);
            },
          ),
          GoRoute(
            path: AppRoutes.addAddress,
            name: 'add-address',
            builder: (context, state) => const AddEditAddressScreen(),
          ),
          GoRoute(
            path: AppRoutes.editAddress,
            name: 'edit-address',
            builder: (context, state) {
              final extra = state.extra;
              return AddEditAddressScreen(
                initialAddress: extra is Address ? extra : null,
              );
            },
          ),

          // ── Checkout ──────────────────────────────────────────────────────
          GoRoute(
            path: AppRoutes.bookingCheckout,
            name: 'checkout',
            builder: (context, state) {
              final serviceSlug = state.uri.queryParameters['service'];
              final extra = state.extra;
              return CheckoutScreen(
                initialServiceSlug: serviceSlug,
                initialService: extra is ServiceItem ? extra : null,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.goodsTransportBooking,
            name: 'goods-transport-booking',
            builder: (context, state) {
              // Updated 2026-09-20: this screen no longer books a single
              // tapped ServiceItem/package — it's the consolidated Goods &
              // Transport flow (pickup, drop-on-map, date/slot, vehicle
              // category + tier, live fare) — so no extra is required at
              // all. An optional Category is still accepted (from
              // CategoryDetailScreen's redirect) purely for page branding.
              final extra = state.extra;
              final catParam = state.uri.queryParameters['category'];
              final initialVehicleCat = switch (catParam) {
                'truck' => LogisticsVehicleCategory.truck,
                'two_wheeler' || 'two-wheeler' => LogisticsVehicleCategory.twoWheeler,
                'packers_movers' || 'packers-movers' => LogisticsVehicleCategory.packersMovers,
                _ => null,
              };
              return GoodsTransportBookingScreen(
                category: extra is Category ? extra : null,
                initialVehicleCategory: initialVehicleCat,
              );
            },
          ),

          GoRoute(
            path: AppRoutes.bookingSuccess,
            name: 'booking-success',
            builder: (context, state) {
              final idString = state.pathParameters['id'] ?? '0';
              final id = int.tryParse(idString) ?? 0;
              final extra = state.extra;
              return BookingSuccessScreen(
                bookingId: id,
                initialBooking: extra is Booking ? extra : null,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.bookingDetail,
            name: 'booking-detail',
            builder: (context, state) {
              final idString = state.pathParameters['id'] ?? '0';
              final id = int.tryParse(idString) ?? 0;
              final extra = state.extra;
              return BookingDetailScreen(
                bookingId: id,
                initialBooking: extra is Booking ? extra : null,
              );
            },
          ),
          GoRoute(
            path: AppRoutes.payment,
            name: 'payment',
            builder: (context, state) {
              final bookingIdString = state.uri.queryParameters['booking'] ?? '0';
              final bookingId = int.tryParse(bookingIdString) ?? 0;
              final type = state.uri.queryParameters['type'] ?? 'advance';
              return PaymentScreen(
                bookingId: bookingId,
                paymentType: type,
              );
            },
          ),
        ],
      ),

      // ── Auth flow (no bottom nav — pre-authentication) ────────────────────
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const PhoneAuthScreen(),
        routes: [
          GoRoute(
            path: 'verify',
            name: 'otp-verify',
            builder: (context, state) {
              final extra = state.extra;
              if (extra is OtpVerifyArgs) {
                return OtpVerifyScreen(
                  identifier: extra.identifier,
                  channel: extra.channel,
                  resendAfterSeconds: extra.resendAfterSeconds,
                );
              }
              final identifier =
                  state.uri.queryParameters['identifier'] ?? '';
              final channel =
                  state.uri.queryParameters['channel'] ?? 'sms';
              final resendAfter =
                  int.tryParse(state.uri.queryParameters['resend_after'] ?? '') ?? 60;
              return OtpVerifyScreen(
                identifier: identifier,
                channel: channel,
                resendAfterSeconds: resendAfter,
              );
            },
          ),
          GoRoute(
            path: 'profile',
            name: 'profile-complete',
            builder: (context, state) => const ProfileCompletionScreen(),
          ),
        ],
      ),

      // ── Fullscreen map picker (no bottom nav) ────────────────────────────
      GoRoute(
        path: AppRoutes.dropLocationPicker,
        name: 'goods-transport-drop-location',
        builder: (context, state) {
          final extra = state.extra;
          return DropLocationPickerScreen(
            initial: extra is PickedDropLocation ? extra : null,
          );
        },
      ),

      // ── Deep links (tokenized, no auth wall, no bottom nav) ───────────────
      GoRoute(
        path: AppRoutes.liveTracking,
        name: 'live-tracking',
        builder: (context, state) => LiveTrackingScreen(
          identifier: state.pathParameters['identifier'] ?? '',
          // Present when navigated from booking detail / my bookings — lets
          // the tracking screen show the real assigned technician and
          // service address instead of relying only on the live-location
          // feed for that data (see live_tracking_screen.dart).
          booking: state.extra is Booking ? state.extra as Booking : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.feedback,
        name: 'feedback',
        builder: (context, state) => FeedbackScreen(
          token: state.pathParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.workExtension,
        name: 'work-extension',
        builder: (context, state) => WorkExtensionScreen(
          token: state.pathParameters['token'] ?? '',
        ),
      ),
    ],

    // ── Error route ──────────────────────────────────────────────────────────
    errorBuilder: (context, state) => _NotFoundScreen(error: state.error),
  );
});


// Rebranded 2026-10-01 — this used to be the raw go_router/Material default
// look (a bare 🔍 emoji, default AppBar, no brand color anywhere), which
// stood out as visibly off-brand against every other screen in the app the
// moment a customer hit a bad/stale deep link. Matches the same AppColors
// tokens and rounded-pill button shape used everywhere else (see
// NoInternetScreen for the sibling "something's wrong" state).
class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({this.error});
  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.search_off_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Page Not Found",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "The page you're looking for doesn't exist or may\nhave moved. Let's get you back on track.",
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Go Home'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Added 2026-10-07 ("The cart section is only working for groceries and
/// vegetables not for the services block"): the bottom-nav Cart tab used to
/// unconditionally build [GroceryCartScreen], which only ever reads/renders
/// grocery items and shows its grocery-flavored empty state for anyone else
/// — so a customer who had added a *service* to the shared [cartProvider]
/// (see the new Add-to-Cart button on the service detail screen) could never
/// actually see or check out that item from the Cart tab. [CheckoutScreen]
/// already falls back to reading the full shared cart whenever it's opened
/// without a single pinned `initialService` (see its `_handlePlaceOrder`/
/// `build`), so it's the correct destination for a cart that contains any
/// non-grocery item. A cart that's empty, or contains only grocery/vegetable
/// items, keeps going to [GroceryCartScreen] exactly as before.
class _CartRouteScreen extends ConsumerWidget {
  const _CartRouteScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final hasServiceItem = items.any((i) => !i.service.isGroceryFlow);
    if (hasServiceItem) {
      return const CheckoutScreen();
    }
    return const GroceryCartScreen();
  }
}
