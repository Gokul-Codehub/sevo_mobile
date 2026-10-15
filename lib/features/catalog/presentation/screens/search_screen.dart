import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../home/domain/home_flow_mode.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../../domain/catalog_providers.dart';
import '../../domain/search_keywords.dart';

/// Search box + KEYWORD suggestions, Amazon-style.
///
/// While the customer types, this page shows short keyword phrases only —
/// never packages, products, images or prices. Choosing a keyword (or
/// pressing search on the keyboard) opens the results page for the active
/// mode: `/search/services?q=...` or `/search/groceries?q=...`.
///
/// [mode] comes from the Home search bar (the active Groceries / Services
/// tab); when it is missing the current Home mode is used.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.mode});

  final SearchMode? mode;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  final _speech = SpeechToText();
  _VoiceState _voice = _VoiceState.idle;
  String _heard = '';
  double _level = 0;
  String _voiceDetail = '';

  /// The text the suggestions are currently being fetched for (debounced).
  String _typed = '';

  /// Last suggestions shown, kept on screen while the next ones load so the
  /// list doesn't flash empty on every keystroke.
  List<String> _lastKeywords = const [];

  static const _debounceDelay = Duration(milliseconds: 250);

  late final SearchMode _mode = widget.mode ??
      (ref.read(homeFlowModeProvider) == HomeFlowMode.groceries
          ? SearchMode.groceries
          : SearchMode.services);

  bool get _isGroceries => _mode == SearchMode.groceries;

  @override
  void dispose() {
    _debounce?.cancel();
    _speech.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_voice == _VoiceState.error || _voice == _VoiceState.unavailable) {
      _voice = _VoiceState.idle;
    }
    setState(() {}); // typed text drives the clear button + which view shows
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _typed = value.trim());
    });
  }

  /// Voice search. A full-screen panel walks the customer through it:
  /// "Getting ready" -> "Speak now" (rings swell with their voice, words
  /// appear live) -> "Searching" -> results; or "Didn't catch that" + retry.
  Future<void> _startVoice() async {
    _focus.unfocus();
    setState(() {
      _voice = _VoiceState.preparing;
      _heard = '';
      _level = 0;
      _voiceDetail = '';
    });
    bool ok = false;
    try {
      ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'listening' && _voice == _VoiceState.preparing) {
            setState(() => _voice = _VoiceState.listening);
          }
          if ((s == 'done' || s == 'notListening') && _voice == _VoiceState.listening) {
            _finishVoice();
          }
        },
        onError: (e) {
          if (!mounted || _voice == _VoiceState.idle || _voice == _VoiceState.processing) return;
          // "no match" / "speech timeout" just mean nothing was said.
          final quiet = e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout';
          setState(() {
            _voice = _VoiceState.error;
            _voiceDetail = quiet ? '' : e.errorMsg;
          });
        },
      );
    } catch (_) {}
    if (!mounted) return;
    if (!ok || !(await _speech.hasPermission)) {
      setState(() {
        _voice = _VoiceState.unavailable;
        _voiceDetail = ok ? 'Microphone permission was not granted.' : 'No speech service found.';
      });
      return;
    }
    String? localeId;
    try {
      localeId = (await _speech.systemLocale())?.localeId;
    } catch (_) {}
    if (!mounted) return;
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
        localeId: localeId,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 2),
      ),
      onSoundLevelChange: (db) {
        // Android reports roughly -2..10 dB; fold it into 0..1 for the rings.
        final v = ((db + 2) / 12).clamp(0.0, 1.0);
        if (mounted && _voice == _VoiceState.listening) setState(() => _level = v);
      },
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          _heard = r.recognizedWords;
          if (_voice == _VoiceState.preparing) _voice = _VoiceState.listening;
        });
        _controller.value = TextEditingValue(
          text: r.recognizedWords,
          selection: TextSelection.collapsed(offset: r.recognizedWords.length),
        );
        if (r.finalResult) _finishVoice();
      },
    );
    // Some devices never send the 'listening' status; the mic is open now.
    if (mounted && _voice == _VoiceState.preparing) {
      setState(() => _voice = _VoiceState.listening);
    }
  }

  /// Recogniser finished: search for what was heard, or say nothing was.
  Future<void> _finishVoice() async {
    if (_voice == _VoiceState.processing || _voice == _VoiceState.idle) return;
    await _speech.stop();
    final words = _heard.trim();
    if (words.isEmpty) {
      if (mounted) setState(() => _voice = _VoiceState.error);
      return;
    }
    setState(() => _voice = _VoiceState.processing);
    _controller.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _voice = _VoiceState.idle);
    _submit(words);
  }

  /// What the search box says while voice search is in progress (null = normal hint).
  String? get _voiceHint => switch (_voice) {
        _VoiceState.preparing => 'Getting ready\u2026',
        _VoiceState.listening => _heard.isEmpty ? 'Listening\u2026 speak now' : null,
        _VoiceState.processing => 'Searching\u2026',
        _VoiceState.error => "Didn't catch that \u2014 tap the mic to retry",
        _VoiceState.unavailable =>
          _voiceDetail.isEmpty ? 'Voice search is unavailable' : _voiceDetail,
        _VoiceState.idle => null,
      };

  /// The mic while active: pulses with the voice level; tap to stop.
  Widget _buildVoiceButton() {
    final listening = _voice == _VoiceState.listening;
    return GestureDetector(
      onTap: listening ? _finishVoice : _cancelVoice,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 32 + (listening ? _level * 10 : 0),
            height: 32 + (listening ? _level * 10 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: listening ? 0.18 + _level * 0.2 : 0.1),
            ),
            child: Icon(
              _voice == _VoiceState.processing ? Icons.more_horiz_rounded : Icons.mic_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelVoice() async {
    await _speech.cancel();
    if (mounted) setState(() => _voice = _VoiceState.idle);
  }

  void _fill(String keyword) {
    _controller.value = TextEditingValue(
      text: '$keyword ',
      selection: TextSelection.collapsed(offset: keyword.length + 1),
    );
    _onChanged(_controller.text);
    _focus.requestFocus();
  }

  void _submit(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider(_mode).notifier).add(q);
    context.push('/search/${_mode.wire}?q=${Uri.encodeQueryComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    final live = _controller.text.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Container(
          height: 46,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: _voiceHint ??
                  (_isGroceries
                      ? "Search for 'fresh vegetables'..."
                      : "Search for 'AC service'..."),
              hintMaxLines: 1,
              hintStyle: TextStyle(
                fontSize: 13,
                fontWeight: _voiceHint == null ? FontWeight.w400 : FontWeight.w700,
                color: _voiceHint == null
                    ? AppColors.textHint
                    : (_voice == _VoiceState.error || _voice == _VoiceState.unavailable
                        ? AppColors.textSecondary
                        : AppColors.primary),
              ),
              prefixIcon: _voice == _VoiceState.processing
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.search_rounded, size: 21, color: AppColors.textSecondary),
              suffixIcon: _voice == _VoiceState.preparing ||
                      _voice == _VoiceState.listening ||
                      _voice == _VoiceState.processing
                  ? _buildVoiceButton()
                  : _controller.text.isEmpty
                  ? IconButton(
                      tooltip: 'Search by voice',
                      icon: Icon(
                        _voice == _VoiceState.idle ? Icons.mic_none_rounded : Icons.mic_off_rounded,
                        size: 22,
                        color: _voice == _VoiceState.idle
                            ? AppColors.textSecondary
                            : AppColors.error,
                      ),
                      onPressed: _startVoice,
                    )
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 19),
                      onPressed: () {
                        _debounce?.cancel();
                        _controller.clear();
                        setState(() {
                          _typed = '';
                          _lastKeywords = const [];
                        });
                        _focus.requestFocus();
                      },
                    ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ),
      body: live.length < 2 ? _buildIdle(live) : _buildSuggestions(live),
    );
  }

  // ── Typing: keyword suggestions only ──────────────────────────────────────
  Widget _buildSuggestions(String live) {
    final async = ref.watch(searchSuggestionsProvider((q: _typed, mode: _mode)));
    final fromServer = async.when(
      data: (list) {
        _lastKeywords = list;
        return list;
      },
      loading: () => _lastKeywords,
      error: (_, __) => const <String>[],
    );
    // The customer's own earlier searches that continue what they typed come
    // first (as Amazon does), then the server's suggestions.
    final lower = live.toLowerCase();
    final history = ref
        .watch(recentSearchesProvider(_mode))
        .where((r) => r.toLowerCase().startsWith(lower) && r.toLowerCase() != lower)
        .map(cleanKeyword);
    final keywords = <String>{...history, ...fromServer}.take(9).toList();

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        if (async.isLoading) const LinearProgressIndicator(minHeight: 2),
        for (final k in keywords)
          _KeywordTile(
            keyword: k,
            query: live,
            onTap: () => _submit(k),
            onFill: () => _fill(k),
          ),
        // Always a way to search for exactly what was typed.
        if (keywords.isEmpty)
          ListTile(
            leading: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            title: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Search for '),
                  TextSpan(
                    text: '"$live"',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13.5, color: AppColors.navy),
            ),
            onTap: () => _submit(live),
          ),
      ],
    );
  }

  // ── Empty box: recent + trending ──────────────────────────────────────────
  Widget _buildIdle(String live) {
    final recent = ref.watch(recentSearchesProvider(_mode));
    final trending = ref.watch(trendingKeywordsProvider(_mode)).valueOrNull ?? const <String>[];

    // Groceries often has no trending product terms yet — fall back to the
    // Seller Hub's own department names so the box is never bare.
    final departments = _isGroceries && trending.isEmpty
        ? (ref.watch(marketplaceCategoryTreeProvider).valueOrNull ?? const [])
            .expand((root) => root.children.isEmpty ? [root] : root.children)
            .where((c) => c.hasAnyProducts)
            .map((c) => cleanKeyword(c.name))
            .toSet()
            .take(12)
            .toList()
        : const <String>[];
    final popular = trending.isNotEmpty ? trending : departments;

    final categories = _isGroceries
        ? const []
        : (ref.watch(categoriesProvider).valueOrNull ?? const []);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (recent.isNotEmpty) ...[
          _SectionHeader(
            title: 'Recent searches',
            action: 'Clear',
            onAction: () => ref.read(recentSearchesProvider(_mode).notifier).clear(),
          ),
          for (final r in recent)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, size: 20, color: AppColors.textSecondary),
              title: Text(r, style: const TextStyle(fontSize: 13.5, color: AppColors.navy)),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textHint),
                onPressed: () => ref.read(recentSearchesProvider(_mode).notifier).remove(r),
              ),
              onTap: () => _submit(r),
            ),
          const SizedBox(height: 8),
        ],
        if (popular.isNotEmpty) ...[
          _SectionHeader(title: trending.isNotEmpty ? 'Trending searches' : 'Popular'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in popular)
                ActionChip(
                  avatar: const Icon(Icons.trending_up_rounded, size: 16, color: AppColors.primary),
                  label: Text(k),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => _submit(k),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (categories.isNotEmpty) ...[
          const _SectionHeader(title: 'Popular categories'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in categories)
                ActionChip(
                  label: Text(cat.name),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => context.push('/categories/${cat.slug}', extra: cat),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// One keyword suggestion: the part the customer already typed is regular
/// weight, the completion is bold (as Amazon does), with an arrow that copies
/// the phrase into the search box to keep refining it.
class _KeywordTile extends StatelessWidget {
  const _KeywordTile({
    required this.keyword,
    required this.query,
    required this.onTap,
    required this.onFill,
  });

  final String keyword;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onFill;

  List<InlineSpan> _spans() {
    const regular = TextStyle(fontSize: 14, color: AppColors.navy, fontWeight: FontWeight.w400);
    const bold = TextStyle(fontSize: 14, color: AppColors.navy, fontWeight: FontWeight.w800);
    final q = query.trim().toLowerCase();
    final i = q.isEmpty ? -1 : keyword.indexOf(q);
    if (i < 0) return [TextSpan(text: keyword, style: bold)];
    return [
      if (i > 0) TextSpan(text: keyword.substring(0, i), style: bold),
      TextSpan(text: keyword.substring(i, i + q.length), style: regular),
      if (i + q.length < keyword.length)
        TextSpan(text: keyword.substring(i + q.length), style: bold),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text.rich(TextSpan(children: _spans()), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Use this phrase',
              icon: const Icon(Icons.north_west_rounded, size: 19, color: AppColors.textSecondary),
              onPressed: onFill,
            ),
          ],
        ),
      ),
    );
  }
}

enum _VoiceState { idle, preparing, listening, processing, error, unavailable }
