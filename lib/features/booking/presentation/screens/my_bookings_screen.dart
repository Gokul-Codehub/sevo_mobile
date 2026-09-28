import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/common_widgets.dart';
import '../../../auth/domain/auth_notifier.dart';
import '../../domain/booking_models.dart';
import '../../domain/booking_providers.dart';

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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final bookingsAsync = ref.watch(myBookingsProvider(null));

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Bookings')),
        body: EmptyStateWidget(
          title: 'Sign in to view bookings',
          subtitle: 'Please log in to track your service requests and bookings.',
          emoji: '🔐',
          actionLabel: 'Login / Sign Up',
          action: () => context.push('/login'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Upcoming / Active'),
            Tab(text: 'Completed / History'),
          ],
        ),
      ),
      body: bookingsAsync.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: 3,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => const ShimmerCard(height: 160),
        ),
        error: (err, stackTrace) => ErrorStateWidget(
          message: err.toString(),
          onRetry: () => ref.refresh(myBookingsProvider(null)),
        ),
        data: (allBookings) {
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

          final filteredBookings = switch (_categoryFilter) {
            _BookingCategoryFilter.all => visibleBookings,
            _BookingCategoryFilter.services =>
              visibleBookings.where((b) => !b.isGroceryBooking).toList(),
            _BookingCategoryFilter.groceries =>
              visibleBookings.where((b) => b.isGroceryBooking).toList(),
          };

          final upcoming = filteredBookings.where((b) => b.isUpcoming).toList();
          final history = filteredBookings.where((b) => !b.isUpcoming).toList();

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
                      color: AppColors.serviceBlue,
                      onTap: () => setState(() =>
                          _categoryFilter = _BookingCategoryFilter.services),
                    ),
                    const SizedBox(width: 8),
                    _CategoryFilterChip(
                      label: 'Groceries',
                      selected:
                          _categoryFilter == _BookingCategoryFilter.groceries,
                      color: AppColors.groceryGreen,
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
        },
      ),
    );
  }
}

class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.primary,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
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
      return EmptyStateWidget(
        title: emptyTitle,
        subtitle: emptySubtitle,
        emoji: '📋',
        actionLabel: 'Book a Service',
        action: () => context.go('/'),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final booking = bookings[index];
          return _BookingCard(booking: booking);
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceNames = booking.items.isNotEmpty
        ? booking.items.map((i) => i.service.title).join(', ')
        : 'Home Service';

    // Blue = service booking, Green = grocery — same flow-accent rule
    // applied on the catalog/checkout side, so a booking's card border
    // and tag agree with how it looked when the customer placed it.
    final flowAccent = booking.isGroceryBooking
        ? AppColors.groceryGreen
        : AppColors.serviceBlue;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: flowAccent.withValues(alpha: 0.35), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/bookings/${booking.id}', extra: booking),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Request ID, Flow tag & Status Chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            booking.requestId,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: flowAccent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: flowAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            booking.isGroceryBooking ? 'GROCERY' : 'SERVICE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: flowAccent,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  BookingStatusChip(status: booking.status),
                ],
              ),
              const Divider(height: 16),

              // Service Title
              Text(
                serviceNames,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Date & Time
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    booking.scheduledDate,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.schedule, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    booking.scheduledTimeSlot,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Technician info if assigned
              if (booking.technician != null) ...[
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Technician: ${booking.technician!.name}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              const Divider(height: 16),

              // Footer: Price and Available Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${booking.totalAmount}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (booking.canTrack) ...[
                        OutlinedButton.icon(
                          onPressed: () {
                            final identifier = booking.trackingIdentifier ?? '${booking.id}';
                            context.push('/track/$identifier', extra: booking);
                          },
                          icon: const Icon(Icons.location_on_outlined, size: 14),
                          label: const Text('Track', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.tonal(
                        onPressed: () => context.push('/bookings/${booking.id}'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text('Details', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
