# HANDOVER / KT — CalServices Customer App (`calservices_customer`)

**Purpose of this file:** lets a fresh Claude session (on another laptop) continue Divya's work on the SEVO / CalServices customer Flutter app with no prior context.
**Owner / requester:** Divya (divya@caldimengg.in), Caldim Engineering.
**Last updated:** 2026-10-10 · **State:** all code below is written; user still has to rebuild + test (see §8).

---

## 1. Read this first (rules of engagement)

| Rule | Detail |
|---|---|
| Never touch `D:\sevo` | Read-only reference of the web developers' code. Never modify. |
| Don't revert web devs' changes | Standing instruction: *"web developers might change things, don't revert/alter our app."* Adapt the app to the backend, not the other way round, unless it is a true backend bug. |
| Backend bug fixes allowed | `D:\Cus\backend` + admin panel `D:\Cus\frontend` may be edited for bugs raised in this engagement. `D:\Ven\backend` (vendor / Seller Hub) is **read-only reference**. |
| Cart = groceries/vegetables ONLY | Never put services in `cartProvider` (tried and explicitly reverted 2026-10-08). Services flow: package → details → slot → book. |
| Don't trust repo docs | `calservices-main` docs (CLAUDE.md, ARCHITECTURE.md, API.md…) describe a different product (QuickTIMS). Use the `calservices-mobile` skill + real code. |
| Ask before big/irreversible things | Divya works iteratively with screenshots; confirm scope on ambiguous multi-step requests. |
| Divya's reporting preference | Structured, visually clear summaries (tables/sections) for bug-fix reports. |

---

## 2. Project map

| Thing | Location |
|---|---|
| Flutter app (this engagement) | `D:\Caldim\Caldim\calservices_mobile\calservices_customer` |
| Customer backend (Django REST, live at `https://sevo.co.in`) | `D:\Cus\backend` |
| Admin panel (Vite/React, dev on `localhost:5173`) | `D:\Cus\frontend` |
| Vendor / Seller Hub backend (read-only) | `D:\Ven\backend` (key file: `workforce_api/views_marketplace_integration.py`) |
| Web reference (read-only, never modify) | `D:\sevo` |

**Stack (app):** Flutter, Riverpod (`FutureProvider`, `autoDispose`, `family`), go_router, Dio via `ApiClient`, `video_player`, custom painters/clippers.
**Two "catalogs":**
1. *Services* – Django `Category → Service → Package → Add-on` (`/api/catalog/...`).
2. *Groceries* – **Seller Hub Marketplace**, owned by the vendor app, proxied by the customer backend at `/api/marketplace/...` (`workforce_integration/marketplace_views.py`). Works independently of the services catalog.

### Backend facts that bite
- `APPEND_SLASH = False` → every API path **must end with `/`** (`/api/catalog/categories` = 404).
- Money arrives as strings; envelopes vary (`{success,data}`, DRF raw, marketplace raw paginated). The app normalises via `ResponseNormalizer`.
- Home screen **swallows API errors** (renders empty sections) — an empty home usually means a failing endpoint, check it directly.

---

## 3. How to work on files (device-bridge workflow)

On Divya's original setup the Windows machine was reachable **only** through the remote-devices bridge (no `device_bash`). If your new laptop has the repo locally, just edit in place and skip this section — but keep the **CRLF** and **verification** lessons.

1. `device_stage_files` the live file → lands in `/mnt/user-data/uploads/...`.
2. **Copy** to a separate `/mnt/user-data/outputs/...` path and edit only the copy. *(Staging a path overwrites whatever is at that uploads path — never edit inside uploads/.)*
3. Edit with a script that opens files with `newline=''` (many files are **CRLF**, e.g. `home_screen.dart`, backend `views.py`; Python default newline mode silently converts them).
4. Syntax-check: `pip install tree-sitter tree-sitter-dart` and parse (no Dart SDK is available in the cloud sandbox; no `flutter analyze` possible).
5. Re-stage live file/`device_list_dir` to confirm mtime unchanged, then `device_commit_files` with `expectedMtimeMs`.
6. **Verify the commit** by listing the dir and comparing byte size. Known quirk: the first commit after a re-stage sometimes writes stale content → re-commit with the new mtime.

---

## 4. What has been built (chronological, condensed)

### Earlier rounds (see also memory notes)
Profile-update endpoint fix; domain move to `sevo.co.in`; Vegetable Inventory admin module; booking slot payload fixes; admin-configurable `PricingConfig`; GPS dialog; "Go to Cart"; Home switcher/greeting redesigns; tab-reload fix (`myBookingsProvider` keepAlive); grocery cart slot filtering, coupon sheet crash fixes; AI assistant ("Ask Apta", formerly AI Mitra) with return/refund wizard + photo upload; **variants** and **Baskets/Combos** consumed from the vendor API; QA bug-sheet fixes (inactive package, wrong category, stale cache, payment-method selector); search debounce; stable `ValueKey`s on tiles; footer label animation.

### 2026-10-09 → 10 (this segment)
| # | Feature | Where |
|---|---|---|
| 1 | **Groceries banners**: only banners flagged `groceries`/`both`/`all`; no services fallback; no banner if none configured; no blur; no slide dots | `home_screen.dart` (`_PromoBannerCarouselState`) |
| 2 | Banner inset 16px with continuous **wave bottom** (`_WaveBottomClipper`); hero video feathered into the yellow header (`_feather`) | `home_screen.dart` |
| 3 | White pill removed around SEVO logo + location | `home_screen.dart` |
| 4 | **Admin "Home Video (per section)"** card → `config.mobile.heroVideos.{groceries,services}`; app renders `_HomeHeroVideo` | `HomePageCustomizerPage.jsx`, `homepage_repository.dart`, `home_screen.dart` |
| 5 | Services header gradient `0xFF8EC3F2 → 0xFFE4F1FE`; Groceries `0xFFF9C93A → 0xFFFFE98A` | `home_screen.dart`, `home_flow_theme.dart` |
| 6 | **Backend fix:** `/api/catalog/categories/` returned 500 (undefined `cache_key` in `CatalogCategoryListView`); guarded `cache.get` in both catalog views | `D:\Cus\backend\service_requests\views.py` |
| 7 | **Cart delivery slots**: always-visible "Delivery slot" card (Instant + 3 dates + real slots, Retry on failure) | `grocery_cart_screen.dart` (`_buildDeliverySlotCard`), `DeliverySlotDay.failed` in `marketplace_catalog_repository.dart` |
| 8 | **Product image carousel** (PageView + dots) from vendor `images` | `grocery_product_detail_screen.dart` (`_ProductGallery`), `MarketplaceProduct.images/galleryImages` |
| 9 | **Units in one product page**: listings collapse variants per `variant_group_id` (`_collapseVariantGroups` in `getProducts`); detail page has "Choose unit" (`_UnitSelector`) **above "About this product"**, switching price/image/stock/description/cart line in place (`_GroceryProductDetailBodyState._selectedVariantId`, `_variantItem`) | `marketplace_catalog_repository.dart`, `grocery_product_detail_screen.dart` |
| 10 | **Banner video loads once**: app-wide `VideoPlayerController` cache keyed by URL (max 4, LRU, ref-counted, paused when unmounted) | `lib/shared/widgets/banner_media.dart` (`_BannerVideoCache`) |
| 11 | **Smooth Groceries↔Services switch**: `_UnifiedActiveModeSection` is now stateful with an `AnimationController`; `_UnifiedActiveBackgroundPainter` morphs the raised tab (generic sliding-tab path, `progress` 0=Services…1=Groceries, repaint-driven); body under tabs uses `AnimatedSize`+`AnimatedSwitcher`; backdrop colour tween; tab label `AnimatedDefaultTextStyle`; mode content fades via `_ModeContentFade` (`SliverOpacity` + `SliverMainAxisGroup`) | `home_screen.dart` |

---

## 5. Key code anchors

- `MarketplaceProduct` (`lib/features/catalog/data/marketplace_catalog_repository.dart`): parses `primary_image`, `images`, `variant_group_id/label/attribute_name`, `variants` (siblings **including itself**), specs/storage/expiry. `toServiceItem()` → cart id `800000000 + id`, slug `seller-hub-<id>`, `categorySlug: 'seller_hub_groceries'`.
- `marketplaceProductDetailProvider(id)` enriches the detail page in the background (gallery, variants, specs).
- `marketplaceDeliverySlotsForDateProvider(date)` (autoDispose family): returns `DeliverySlotDay.fetchFailed` on error (UI shows Retry).
- Home: `homepageConfigProvider` is **not** autoDispose (stays alive); `home_screen.dart` is ~212 KB — edit surgically.
- Vendor API (read `D:\Ven\backend\workforce_api\views_marketplace_integration.py`): list supports `group_variants=true` server-side (the app currently groups client-side because it's unknown whether the proxy forwards that param — a cleaner future fix is to forward it in `marketplace_views.py`).

---

## 6. Open items / needs human action

| Priority | Item | Owner |
|---|---|---|
| **High** | Deploy `D:\Cus\backend\service_requests\views.py` to the live server and restart; verify `https://sevo.co.in/api/catalog/categories/` → 200 | Divya / server admin |
| **High** | Divya must **rebuild** the Flutter app to see anything from §4.2 | Divya |
| High | `flutter clean` fails with a Dart SDK lock: kill `dart` processes → delete `<flutter>\bin\cache\dart-sdk` and its stamp → run `flutter doctor` | Divya |
| Medium | Run `python manage.py migrate` (pending `accounts.0028`; earlier `0013_pricingconfig` / `0128_packageoption` unconfirmed) | Divya |
| Medium | Test on device: cart slot card, carousel, unit switching (esp. a unit with no sibling image), mode-switch animation smoothness, banner video not reloading | Divya |
| Low | Pagination caveat: variant collapsing is per result page — a product whose units fall on different pages could appear twice; fix by forwarding `group_variants=true` through the proxy | next dev |
| Low | Pull-to-refresh missing on most screens; AppToast conversion partial; `diagnose_customer_identity.py` output pending; bundle (combo) price not supported in checkout | backlog |
| Info | Unverified assumptions in new code: sibling variants may not carry a gallery (falls back to primary image); `SliverMainAxisGroup` inside `SliverOpacity` should be fine on Flutter ≥3.13 (project uses SDK ^3.13.1 / Flutter ≥3.44) | verify at build |

If the first build shows compile errors, they most likely sit in the five files edited last: `home_screen.dart`, `grocery_cart_screen.dart`, `grocery_product_detail_screen.dart`, `marketplace_catalog_repository.dart`, `banner_media.dart` (only syntax-parsed, never analysed).

---

## 7. Lessons / gotchas collected

1. Empty Home sections ≠ empty data: call the endpoint directly (and remember the trailing slash) before theorising about migrations. The 2026-10-09 "no categories" issue was a backend `NameError`-style bug, not migrations.
2. Measure before resizing animations (AI robot Lottie had baked-in padding) — don't guess-and-check.
3. Preserve CRLF; never retype file content from truncated tool output.
4. Window-/screenshot-driven feedback: Divya sends annotated screenshots (red/green/black marks) — read each annotation literally.
5. Admin-editable content (greeting words, banners, top cards, hero videos) must remain admin-driven; don't hardcode.

---

## 8. Suggested first steps for the next Claude

1. Read this file, then the memory file `/areas/calservices-customer-app.md` if the memory tools exist.
2. Ask Divya whether the rebuild succeeded; get the exact compile errors / screenshots if not.
3. Fix any compile issues in the five files above, then iterate on UX feedback.
4. Keep this document updated (append to §4 and §6) at the end of each session.
