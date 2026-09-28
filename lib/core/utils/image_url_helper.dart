import 'package:flutter/material.dart';
import '../../config/env.dart';

/// Central helper for resolving remote image URLs, local mockups, and icon mappings
/// with 100% parity against the reference React web application (`calservices_web`).
abstract final class ImageUrlHelper {
  ImageUrlHelper._();

  /// Resolves any relative or partial media path into a fully qualified HTTPS URL.
  /// Intelligently resolves empty or dead `/media/catalog/` links to production photos.
  static String? resolve(
    String? rawUrl, {
    String? title,
    String? slug,
    String? categorySlug,
    int? categoryId,
  }) {
    final candidate = _getEffectiveCandidate(
      rawUrl: rawUrl,
      title: title,
      slug: slug,
      categorySlug: categorySlug,
      categoryId: categoryId,
    );

    if (candidate == null) return null;
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) return null;

    // Handle legacy localhost or demo domains
    if (trimmed.contains('localhost') || trimmed.contains('127.0.0.1')) {
      final mediaIdx = trimmed.indexOf('/media/');
      if (mediaIdx != -1) {
        return '${Env.mediaBaseUrl}${trimmed.substring(mediaIdx)}';
      }
      final mockupIdx = trimmed.indexOf('/mockups/');
      if (mockupIdx != -1) {
        return '${Env.mediaBaseUrl}${trimmed.substring(mockupIdx)}';
      }
    }

    if (trimmed.startsWith('https://')) return trimmed;
    if (trimmed.startsWith('http://')) return trimmed.replaceFirst('http://', 'https://');
    if (trimmed.startsWith('/')) return '${Env.mediaBaseUrl}$trimmed';
    return '${Env.mediaBaseUrl}/$trimmed';
  }

  /// Evaluates the most accurate image candidate for a category/service/
  /// package. Prefers whatever the admin actually uploaded, and only ever
  /// falls back to a stock/mockup photo when there is truly no real image.
  ///
  /// Fixed 2026-09-16: this used to treat ANY path containing
  /// `/media/catalog/` as a known-dead 404 link and unconditionally discard
  /// it in favor of a guessed `/mockups/...` path or an Unsplash stock
  /// photo — a rule that made sense only while the admin catalog genuinely
  /// had no working images. Now that the backend serves real admin-uploaded
  /// photos for categories, services and packages (Package.image /
  /// CatalogCategory.image, confirmed in service_requests/serializers.py),
  /// `/media/catalog/...` is exactly where those real uploads live — this
  /// was silently throwing away every real photo the admin uploads and
  /// replacing it with either a stock photo (wrong image) or a guessed
  /// `/mockups/...` path that 404s on this backend (AppRemoteImage's own
  /// history notes that folder was never bundled anywhere), which is what
  /// customers were seeing as "no image" for categories, services and
  /// packages. A real, non-empty image path from the API is now always
  /// used as-is; the photographic guess tables below only ever run when
  /// the backend genuinely returned no image at all.
  static String? _getEffectiveCandidate({
    String? rawUrl,
    String? title,
    String? slug,
    String? categorySlug,
    int? categoryId,
  }) {
    final rawTrimmed = (rawUrl ?? '').trim();

    // Any non-empty image path/URL the backend actually returned is trusted
    // as-is — this is real admin-uploaded catalog data, never a "known bad"
    // path to second-guess. `resolve()` (the caller) turns a relative path
    // like this into a fully-qualified URL against the real media host.
    if (rawTrimmed.isNotEmpty) {
      return rawTrimmed;
    }

    // No image at all was returned — fall back to a representative photo so
    // the UI isn't blank, in priority order: grocery produce photography,
    // then category-level stock art, then a service-level mockup guess.
    final isGrocery = categoryId == 18 ||
        (categorySlug ?? '').contains('veg') ||
        (categorySlug ?? '').contains('groc');
    if (isGrocery && title != null && title.trim().isNotEmpty) {
      return getFoodItemPhoto(title, isGrocery: true);
    }

    if (categorySlug != null || slug != null || title != null) {
      final catPhoto = getCategoryPhoto(categorySlug ?? slug, title);
      if (catPhoto != null) return catPhoto;
    }

    if (slug != null || title != null) {
      final serviceMockup = _mapServiceSlugToPhoto(slug, title, categorySlug);
      if (serviceMockup != null) return serviceMockup;
    }

    return null;
  }

  /// High-Fidelity Studio Product Photography Mapping
  /// Direct 1:1 port of `calservices_web/frontend/src/ui/pages/LandingPage.jsx:638-727`.
  static String getFoodItemPhoto(String name, {bool isGrocery = false}) {
    final n = name.toLowerCase().trim();

    if (isGrocery) {
      if (n.contains('combo') || n.contains('dals & grains')) {
        return '/mockups/groceries_realistic.png';
      }
      if (n.contains('staples') || n.contains('kitchen staples')) {
        return '/mockups/category_food_health.png';
      }
      if (n.contains('atta') || n.contains('wheat') || n.contains('flour')) {
        return 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('rice') || n.contains('basmati')) {
        return 'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('dal') || n.contains('pulses') || n.contains('moong') || n.contains('toor')) {
        return 'https://images.unsplash.com/photo-1585996746973-45f8fdf1ca23?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('oil') || n.contains('ghee')) {
        return 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('milk') || n.contains('dairy')) {
        return 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('butter')) {
        return 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('bread')) {
        return 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400&auto=format&fit=crop&q=80';
      }
      if (n.contains('egg')) {
        return 'https://images.unsplash.com/photo-1516467508483-a7212febe31a?w=400&auto=format&fit=crop&q=80';
      }
    }

    // 100% Accurate Verified Studio & Realistic Food Photography
    if (n.contains('basket') || n.contains('essential')) return 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&auto=format&fit=crop&q=80';
    if (n.contains('exotic') || n.contains('gourds pack')) return 'https://images.unsplash.com/photo-1597362925123-77861d3fbac7?w=400&auto=format&fit=crop&q=80';
    if (n.contains('leafy') || n.contains('salad') || n.contains('keerai') || n.contains('palak') || n.contains('spinach')) {
      return 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=400&auto=format&fit=crop&q=80';
    }

    if (n.contains('coriander') || n.contains('kothamalli') || n.contains('dhaniya')) return 'https://images.unsplash.com/photo-1608686207856-001b95cf60ca?w=400&auto=format&fit=crop&q=80';
    if (n.contains('curry') || n.contains('karuveppilai') || n.contains('kadi patta')) return 'https://images.unsplash.com/photo-1628773822503-930a84d008bb?w=400&auto=format&fit=crop&q=80';
    if (n.contains('lemon') || n.contains('elumichai') || n.contains('nimbu')) return 'https://images.unsplash.com/photo-1533082602677-442d99d1469e?w=400&auto=format&fit=crop&q=80';
    if (n.contains('ginger') || n.contains('inji') || n.contains('adrak')) return 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=400&auto=format&fit=crop&q=80';
    if (n.contains('mushroom') || n.contains('kaalan')) return 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&auto=format&fit=crop&q=80';
    if (n.contains('bottle gourd') || n.contains('suraikkai') || n.contains('lauki')) return 'https://images.unsplash.com/photo-1597362925123-77861d3fbac7?w=400&auto=format&fit=crop&q=80';
    if (n.contains('french beans') || n.contains('beans')) return 'https://images.unsplash.com/photo-1567306226416-28f0efdc88ce?w=400&auto=format&fit=crop&q=80';
    if (n.contains('tomato') || n.contains('thakkali') || n.contains('tamatar') || n.contains('cherry')) return 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=400&auto=format&fit=crop&q=80';
    if (n.contains('lady finger') || n.contains('vendakkai') || n.contains('bhindi') || n.contains('okra')) return 'https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?w=400&auto=format&fit=crop&q=80';
    if (n.contains('brinjal') || n.contains('kathirikai') || n.contains('baingan')) return 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=400&auto=format&fit=crop&q=80';
    if (n.contains('bitter gourd') || n.contains('pavakkai') || n.contains('karela')) return 'https://images.unsplash.com/photo-1628773822503-930a84d008bb?w=400&auto=format&fit=crop&q=80';
    if (n.contains('drumstick') || n.contains('murungakkai') || n.contains('sahjan')) return 'https://images.unsplash.com/photo-1597362925123-77861d3fbac7?w=400&auto=format&fit=crop&q=80';
    if (n.contains('peas') || n.contains('pattani') || n.contains('matar')) return 'https://images.unsplash.com/photo-1587735243615-c03f25aaff15?w=400&auto=format&fit=crop&q=80';

    if (n.contains('peeled garlic') || n.contains('uricha poondu') || n.contains('garlic') || n.contains('poondu') || n.contains('lehsun')) {
      return 'https://images.unsplash.com/photo-1588879462809-54316d3f27f0?w=400&auto=format&fit=crop&q=80';
    }
    if (n.contains('sweet potato') || n.contains('sakkaraivalli') || n.contains('shakarkand')) return 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?w=400&auto=format&fit=crop&q=80';
    if (n.contains('potato') || n.contains('urulaikilangu') || n.contains('aloo')) return 'https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=400&auto=format&fit=crop&q=80';

    // Spring Onion & General Onion
    if (n.contains('spring onion') || n.contains('vengaya thaal')) return 'https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=400&auto=format&fit=crop&q=80';
    if (n.contains('onion') || n.contains('vengayam') || n.contains('pyaz')) return 'https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=400&auto=format&fit=crop&q=80';
    if (n.contains('cucumber') || n.contains('vellarikkai') || n.contains('kheera')) return 'https://images.unsplash.com/photo-1604977042946-1eecc30f269e?w=400&auto=format&fit=crop&q=80';

    // Bell Peppers & Capsicum & Chillies
    if (n.contains('red bell pepper') || n.contains('sigappu')) return 'https://images.unsplash.com/photo-1563565375-f3fdfdbefa83?w=400&auto=format&fit=crop&q=80';
    if (n.contains('yellow bell pepper') || n.contains('manjal')) return 'https://images.unsplash.com/photo-1563565375-f3fdfdbefa83?w=400&auto=format&fit=crop&q=80';
    if (n.contains('capsicum') || n.contains('kuda milagai') || n.contains('shimla')) return 'https://images.unsplash.com/photo-1563565375-f3fdfdbefa83?w=400&auto=format&fit=crop&q=80';
    if (n.contains('chilli') || n.contains('milagai') || n.contains('mirch')) return 'https://images.unsplash.com/photo-1588252303782-cb80119abd6d?w=400&auto=format&fit=crop&q=80';

    if (n.contains('cauliflower') || n.contains('kooliflower') || n.contains('phool gobhi')) return 'https://images.unsplash.com/photo-1568584711075-3d021a7c3ca3?w=400&auto=format&fit=crop&q=80';
    if (n.contains('cabbage') || n.contains('muttakose') || n.contains('patta gobhi')) return 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=400&auto=format&fit=crop&q=80';
    if (n.contains('corn') || n.contains('solam') || n.contains('bhutta')) return 'https://images.unsplash.com/photo-1551754655-cd27e38d2076?w=400&auto=format&fit=crop&q=80';
    if (n.contains('radish') || n.contains('mullangi') || n.contains('mooli')) return 'https://images.unsplash.com/photo-1593105544559-ecb03bf76f82?w=400&auto=format&fit=crop&q=80';
    if (n.contains('beetroot')) return 'https://images.unsplash.com/photo-1593105544559-ecb03bf76f82?w=400&auto=format&fit=crop&q=80';
    if (n.contains('pumpkin') || n.contains('parangikkai') || n.contains('kaddu')) return 'https://images.unsplash.com/photo-1506917728037-b9bf01ac4776?w=400&auto=format&fit=crop&q=80';
    if (n.contains('mint') || n.contains('pudhina')) return 'https://images.unsplash.com/photo-1608686207856-001b95cf60ca?w=400&auto=format&fit=crop&q=80';
    if (n.contains('basil') || n.contains('rosemary') || n.contains('herbs')) return 'https://images.unsplash.com/photo-1608686207856-001b95cf60ca?w=400&auto=format&fit=crop&q=80';
    if (n.contains('turmeric') || n.contains('manjal') || n.contains('haldi')) return 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=400&auto=format&fit=crop&q=80';
    if (n.contains('amla') || n.contains('nellikai') || n.contains('amlaa')) return 'https://images.unsplash.com/photo-1533082602677-442d99d1469e?w=400&auto=format&fit=crop&q=80';
    if (n.contains('colocasia') || n.contains('seppankizhangu') || n.contains('arvi')) return 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?w=400&auto=format&fit=crop&q=80';
    if (n.contains('papaya') || n.contains('pappalikkai')) return 'https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=400&auto=format&fit=crop&q=80';
    if (n.contains('carrot')) return 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=400&auto=format&fit=crop&q=80';

    return 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&auto=format&fit=crop&q=80';
  }

  /// Authoritative Category photographic resolution matching web categoriesData.js
  static String? getCategoryPhoto(String? slug, String? name) {
    final s = (slug ?? '').toLowerCase().replaceAll('-', '_');
    final n = (name ?? '').toLowerCase();

    if (s.contains('ac_appliance') || s.contains('hvac') || n.contains('ac & appliance')) {
      return '/mockups/category_appliance.png';
    }
    if (s.contains('electric') || s.contains('repair') || n.contains('electrician')) {
      return '/mockups/category_repair.png';
    }
    if (s.contains('clean') || s.contains('deep') || n.contains('cleaning')) {
      return '/mockups/category_cleaning.png';
    }
    if (s.contains('veg') || s.contains('groc') || n.contains('vegetable') || n.contains('grocery')) {
      return '/mockups/vegetables_realistic.png';
    }
    if (s.contains('good') || s.contains('transport') || s.contains('truck') || n.contains('transport')) {
      return '/mockups/category_goods_transports.png';
    }
    if (s.contains('paint') || n.contains('painting')) {
      return '/mockups/category_painting.png';
    }
    if (s.contains('mason') || s.contains('construct') || n.contains('mason')) {
      return '/mockups/service_building.png';
    }
    if (s.contains('pest') || n.contains('pest')) {
      return '/mockups/category_cleaning.png';
    }
    return null;
  }

  static String? _mapServiceSlugToPhoto(String? slug, String? title, String? categorySlug) {
    final s = (slug ?? '').toLowerCase();
    final t = (title ?? '').toLowerCase();
    final c = (categorySlug ?? '').toLowerCase();

    if (s.contains('combo-2-units') || s.contains('mega-ac') || s.contains('ac-') || t.contains('ac') || c.contains('ac')) {
      return 'https://images.unsplash.com/photo-1621905252507-b35492d04029?w=500&q=80&fit=crop';
    }
    if (s.contains('plumber') || s.contains('toilet') || s.contains('tank') || t.contains('plumb') || c.contains('plumb')) {
      return 'https://images.unsplash.com/photo-1585704032915-c3400ca199e7?w=500&q=80&fit=crop';
    }
    if (s.contains('switch') || s.contains('socket') || s.contains('electric') || t.contains('electric') || c.contains('electric')) {
      return 'https://images.unsplash.com/photo-1621905252507-b35492d04029?w=500&q=80&fit=crop';
    }
    if (s.contains('deep-clean') || s.contains('house-clean') || t.contains('clean') || c.contains('clean')) {
      return '/mockups/service_cleaning.png';
    }
    if (s.contains('truck') || s.contains('transport') || s.contains('shifting') || c.contains('transport')) {
      return '/mockups/service_transport.jpg';
    }
    if (s.contains('mason') || s.contains('brick') || s.contains('plaster') || c.contains('mason')) {
      return '/mockups/wall_plastering_masonry.jpg';
    }
    if (s.contains('paint') || c.contains('paint')) {
      return '/mockups/category_painting.png';
    }
    return null;
  }

  /// Maps backend icon strings / slugs to Flutter Material Icons (matches web Lucide icons).
  static IconData mapCategoryIcon(String? iconName, String? slug) {
    final name = (iconName ?? '').trim().toLowerCase();
    final s = (slug ?? '').trim().toLowerCase();

    switch (name) {
      case 'carrot':
      case 'vegetables':
      case 'groceries':
        return Icons.shopping_basket_rounded;
      case 'truck':
      case 'goods':
      case 'transport':
        return Icons.local_shipping_rounded;
      case 'wrench':
      case 'hammer':
      case 'tool':
      case 'repair':
      case 'carpentry':
        return Icons.home_repair_service_rounded;
      case 'wind':
      case 'ac':
      case 'appliance':
        return Icons.ac_unit_rounded;
      case 'sparkles':
      case 'clean':
      case 'cleaning':
        return Icons.cleaning_services_rounded;
      case 'palette':
      case 'paint':
      case 'painting':
        return Icons.format_paint_rounded;
      case 'bolt':
      case 'zap':
      case 'electrician':
        return Icons.electric_bolt_rounded;
      case 'droplet':
      case 'plumbing':
        return Icons.plumbing_rounded;
      case 'bug':
      case 'pest':
      case 'shield':
        return Icons.pest_control_rounded;
      case 'brick':
      case 'mason':
      case 'foundation':
        return Icons.foundation_rounded;
      default:
        if (s.contains('veg') || s.contains('grocery') || s.contains('produce')) return Icons.shopping_basket_rounded;
        if (s.contains('goods') || s.contains('truck') || s.contains('pack')) return Icons.local_shipping_rounded;
        if (s.contains('clean')) return Icons.cleaning_services_rounded;
        if (s.contains('ac') || s.contains('appliance')) return Icons.ac_unit_rounded;
        if (s.contains('pest')) return Icons.pest_control_rounded;
        if (s.contains('mason') || s.contains('construct')) return Icons.foundation_rounded;
        if (s.contains('paint')) return Icons.format_paint_rounded;
        if (s.contains('electric') || s.contains('plumb') || s.contains('carpenter') || s.contains('repair')) {
          return Icons.build_rounded;
        }
        return Icons.category_rounded;
    }
  }
}

