import '../../../../shared/widgets/login_required_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/image_url_helper.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';
import 'booking_detail_screen.dart' show bookingItemImageProvider;
import '../../../../shared/utils/date_utils.dart';
import '../../../../shared/widgets/motion.dart';

const Color _mbBg = Color(0xFFF8F4EF);

/// Screen listing customer bookings separated into Upcoming and History tabs.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

/// Which booking category the user has selected to view.
enum _BookingCategoryFilter { all, services, groceries }

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  _BookingCategoryFilter _categoryFilter = _BookingCategoryFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  // Fixed 2026-09-17 — the actual reported repro was "book a service, see
  // it as e.g. 'Proof Submitted' in progress, fully leave the app, come
  // back, and this screen still shows an old status like 'Booking
  // Confirmed'". `myBookingsProvider` is now `.autoDispose` (see its own
  // doc comment) so it no longer caches forever, but nothing was forcing
  // a re-fetch specifically on the moment this matters: the app coming
  // back from the background. Explicitly invalidating on resume closes
  // that gap — the very next build reflects the booking's real, current
  // status instead of whatever was last fetched before backgrounding.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myBookingsProvider);
    }
  }

  /// Statuses where the booking's life-cycle is over (or only a rating /
  /// refund trail remains) — these belong to History. EVERY other status
  /// (pending_payment, reviewed, received, accepted, on_the_way, arrived,
  /// awaiting_verification, rework_requested, follow_up_required,
  /// rescheduled, unassigned, ...) is still in flight and stays Active.
  /// The old rule only treated 4 statuses as Active, so a booking that was
  /// e.g. "On the Way" or "Awaiting Payment" was wrongly filed in History.
  static const Set<String> _historyStatuses = {
    'completed',
    'verified',
    'feedback_pending',
    'feedback_received',
    'closed',
    'cancelled',
    'canceled',
    'rejected',
    'refund_requested',
    'refunded',
    'expired',
  };

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');

  static bool _isActive(Booking b) => !_historyStatuses.contains(_norm(b.status));

  static DateTime _when(Booking b) =>
      DateTime.tryParse(b.scheduledDate) ??
      b.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Splits into (active, history). Active: soonest visit first. History:
  /// most recent first.
  static (List<Booking>, List<Booking>) _partition(List<Booking> all) {
    final active = all.where(_isActive).toList()
      ..sort((a, b) => _when(a).compareTo(_when(b)));
    final history = all.where((b) => !_isActive(b)).toList()
      ..sort((a, b) => _when(b).compareTo(_when(a)));
    return (active, history);
  }

  List<Booking> _applyFilter(List<Booking> all) {
    final visible = all.where((b) => !b.isQuotedWorkBooking).toList();
    return switch (_categoryFilter) {
      _BookingCategoryFilter.all => visible,
      _BookingCategoryFilter.services =>
        visible.where((b) => !b.isGroceryBooking).toList(),
      _BookingCategoryFilter.groceries =>
        visible.where((b) => b.isGroceryBooking).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final bookingsAsync = ref.watch(myBookingsProvider(null));
    final cached = bookingsAsync.valueOrNull;
    final counts = cached == null ? null : _partition(_applyFilter(cached));

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F9FC),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7F9FC),
          title: const Text('My Bookings'),
        ),
        body: LoginRequiredView(
          title: 'Sign in to view bookings',
          subtitle: 'Please log in to track your service requests and bookings.',
          buttonLabel: 'Login / Sign Up',
          icon: Icons.event_note_rounded,
          onPressed: () => context.push('/login'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _mbBg,
      appBar: AppBar(
        backgroundColor: _mbBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'My Bookings',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.navy,
                  borderRadius: BorderRadius.circular(11),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                      text: counts == null
                          ? 'Active'
                          : 'Active (${counts.$1.length})'),
                  Tab(
                      text: counts == null
                          ? 'History'
                          : 'History (${counts.$2.length})'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(bookingsAsync),
    );
  }


  /// Fixed 2026-10-07 ("the Services page shows the loading indicator
  /// again, even though the user has already visited that page and its
  /// data was previously loaded"): `myBookingsProvider` is no longer
  /// `.autoDispose` (see its doc comment in booking_providers.dart), so
  /// `bookingsAsync.valueOrNull` now survives this screen being torn down
  /// and recreated on a bottom-tab switch, and can be rendered instantly.
  /// Whenever cached data already exists — first load already happened,
  /// this visit or an earlier one — it's rendered immediately; a
  /// background refresh (resume, or after create/cancel/reschedule) shows
  /// only a thin top-of-screen progress bar, never the full-list shimmer
  /// again. The full shimmer is now reserved for the genuine first-ever
  /// load, when there is truly nothing to show yet.
  Widget _buildBody(AsyncValue<List<Booking>> bookingsAsync) {
    final cachedBookings = bookingsAsync.valueOrNull;
    if (cachedBookings != null) {
      return Stack(
        children: [
          _buildBookingsContent(cachedBookings),
          if (bookingsAsync.isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }

    return bookingsAsync.when(
      loading: () => ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        itemCount: 4,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) => const _BookingCardSkeleton(),
      ),
      error: (err, stackTrace) => ErrorStateWidget(
        message: err.toString(),
        onRetry: () => ref.refresh(myBookingsProvider(null)),
      ),
      data: (allBookings) => _buildBookingsContent(allBookings),
    );
  }

  Widget _buildBookingsContent(List<Booking> allBookings) {
    // Services & Groceries are the two things this app sells — a
    // scheduled/direct-booked service (AC, electrician, plumbing,
    // cleaning...) versus a grocery-supply order (cart + checkout).
    // Both land here once checked out/booked; this filter just lets
    // the customer narrow the list to one or the other. Derived from
    // real booking data (Booking.isGroceryBooking), never hardcoded.
    // Added 2026-09-26: a Painting/Masonry quotation, once accepted,
    // creates a second "quoted_work" ServiceRequest linked back to the
    // original inspection booking via parent_request — matches the
    // web app's own convention (frontend/src/ui/pages/BookingPage.jsx)
    // of hiding these Stage-2 children from the primary list entirely
    // rather than showing what looks like a duplicate booking; the
    // parent's own detail screen is where its quotation/decision
    // lives, and once converted the customer still reaches the actual
    // work booking through that same parent (ActiveQuoteCard's
    // "accepted" banner references it directly).
    final visibleBookings = allBookings.where((b) => !b.isQuotedWorkBooking).toList();

    final filteredBookings = _applyFilter(visibleBookings);
    final (upcoming, history) = _partition(filteredBookings);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _CategoryFilterChip(
                label: 'All',
                selected: _categoryFilter == _BookingCategoryFilter.all,
                color: AppColors.navy,
                onTap: () => setState(
                    () => _categoryFilter = _BookingCategoryFilter.all),
              ),
              const SizedBox(width: 8),
              _CategoryFilterChip(
                label: 'Services',
                selected:
                    _categoryFilter == _BookingCategoryFilter.services,
                color: AppColors.navy,
                onTap: () => setState(() =>
                    _categoryFilter = _BookingCategoryFilter.services),
              ),
              const SizedBox(width: 8),
              _CategoryFilterChip(
                label: 'Groceries',
                selected:
                    _categoryFilter == _BookingCategoryFilter.groceries,
                color: AppColors.navy,
                onTap: () => setState(() =>
                    _categoryFilter = _BookingCategoryFilter.groceries),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _BookingListView(
                bookings: upcoming,
                emptyTitle: 'No Active Bookings',
                emptySubtitle: 'Book a service today and enjoy hassle-free home maintenance.',
                onRefresh: () => ref.refresh(myBookingsProvider(null).future),
              ),
              _BookingListView(
                bookings: history,
                emptyTitle: 'No Past Bookings',
                emptySubtitle: 'Your completed or cancelled bookings will appear here.',
                onRefresh: () => ref.refresh(myBookingsProvider(null).future),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.navy,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFFE3E8F0),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BookingListView extends StatelessWidget {
  const _BookingListView({
    required this.bookings,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final List<Booking> bookings;
  final String emptyTitle;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EDF7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    size: 40, color: AppColors.navy),
              ),
              const SizedBox(height: 18),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Color(0xFF6B7788),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => context.go('/'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Book a Service',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        itemCount: bookings.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final booking = bookings[index];
          return FadeSlideIn(key: ValueKey('b-${booking.id}'), index: index, child: _BookingCard(booking: booking));
        },
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceNames = booking.items.isNotEmpty
        ? booking.items.map((i) => i.service.title).join(', ')
        : 'Home Service';

    final first = booking.items.isNotEmpty ? booking.items.first.service : null;
    var imageUrl = first?.imageUrl;
    // While the catalog lookup for the package picture is still running we
    // show a shimmer tile — never the category icon, which used to flash
    // first and then swap to the real photo.
    var imageLoading = false;
    if (first != null && (imageUrl ?? '').trim().isEmpty) {
      final lookup = ref
          .watch(bookingItemImageProvider('${first.id}|${first.title}'));
      imageUrl = lookup.valueOrNull;
      imageLoading = lookup.isLoading;
    }

    const grey = Color(0xFF6B7788);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/bookings/${booking.id}', extra: booking),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Request ID, flow tag & status chip
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              booking.requestId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: AppColors.navy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              booking.isGroceryBooking ? 'GROCERY' : 'SERVICE',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: grey,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    BookingStatusChip(status: booking.status),
                  ],
                ),
                const SizedBox(height: 12),

                // Thumbnail + title / schedule / technician
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: first == null
                            ? Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(
                                    Icons.home_repair_service_outlined,
                                    color: AppColors.textHint),
                              )
                            : imageLoading
                            ? const ShimmerBox(
                                width: 68, height: 68, borderRadius: 0)
                            : AppRemoteImage(
                                fallbackWidget: Container(
                                  width: 68,
                                  height: 68,
                                  color: const Color(0xFFE8EDF7),
                                  child: Icon(
                                    booking.isGroceryBooking
                                        ? Icons.shopping_basket_outlined
                                        : Icons.home_repair_service_outlined,
                                    color: AppColors.navy,
                                    size: 28,
                                  ),
                                ),
                                imageUrl: imageUrl,
                                rawPath: imageUrl,
                                title: first.title,
                                categoryName: first.categoryName,
                                slug: first.slug,
                                semanticIcon: ImageUrlHelper.mapCategoryIcon(
                                    first.categoryName, first.slug),
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serviceNames,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 12.5, color: grey),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  formatDateString(booking.scheduledDate),
                                  style: const TextStyle(
                                      fontSize: 11.5, color: grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(Icons.schedule,
                                  size: 12.5, color: grey),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  booking.scheduledTimeSlot,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (booking.technician != null) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.person_outline,
                                    size: 13, color: AppColors.navy),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Tech: ${booking.technician!.name}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.navy,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 1, color: Color(0xFFEDF0F5)),
                const SizedBox(height: 12),

                // Footer: price and available actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${booking.totalAmount}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (booking.canTrack) ...[
                          OutlinedButton.icon(
                            onPressed: () {
                              final identifier = booking.trackingIdentifier ??
                                  '${booking.id}';
                              context.push('/track/$identifier',
                                  extra: booking);
                            },
                            icon: const Icon(Icons.location_on_outlined,
                                size: 14),
                            label: const Text('Track',
                                style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.navy,
                              side: const BorderSide(color: Color(0xFFD5DCE8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              minimumSize: const Size(0, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton(
                          onPressed: () =>
                              context.push('/bookings/${booking.id}'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Text('Details',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton that mirrors [_BookingCard]'s layout while bookings first load.
class _BookingCardSkeleton extends StatelessWidget {
  const _BookingCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerLine(width: 110, height: 12),
              ShimmerLine(width: 72, height: 22, borderRadius: 8),
            ],
          ),
          SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 68, height: 68, borderRadius: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerLine(width: double.infinity, height: 13),
                    SizedBox(height: 7),
                    ShimmerLine(width: 150, height: 11),
                    SizedBox(height: 10),
                    ShimmerLine(width: 120, height: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: Color(0xFFEDF0F5)),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerLine(width: 70, height: 16),
              ShimmerLine(width: 78, height: 34, borderRadius: 20),
            ],
          ),
        ],
      ),
    );
  }
}
