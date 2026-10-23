import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../shared/theme/app_colors.dart';

/// Paytm hosted checkout inside the app.
///
/// The server creates the transaction and hands over a one-time `txnToken`;
/// this page only posts it to Paytm's `showPaymentPage` and shows what Paytm
/// renders. Paytm then returns to the server's `/payment/paytm/callback/`,
/// which confirms the payment with Paytm directly. Whatever happens here, the
/// caller asks the server to verify afterwards: this screen never decides
/// whether money was paid.
class PaytmCheckoutScreen extends StatefulWidget {
  const PaytmCheckoutScreen({
    super.key,
    required this.orderId,
    required this.mid,
    required this.txnToken,
    required this.checkoutOrigin,
  });

  final String orderId;
  final String mid;
  final String txnToken;

  /// `https://securestage.paytmpayments.com` (staging) or the production
  /// host, taken from the server-supplied checkout script URL.
  final String checkoutOrigin;

  @override
  State<PaytmCheckoutScreen> createState() => _PaytmCheckoutScreenState();
}

class _PaytmCheckoutScreenState extends State<PaytmCheckoutScreen> {
  late final WebViewController _web;
  bool _loading = true;
  bool _closing = false;

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  @override
  void initState() {
    super.initState();
    final action = '${widget.checkoutOrigin}/theia/api/v1/showPaymentPage'
        '?mid=${Uri.encodeQueryComponent(widget.mid)}'
        '&orderId=${Uri.encodeQueryComponent(widget.orderId)}';
    final html = '''
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body onload="document.getElementById('f').submit()">
<form id="f" method="post" action="${_esc(action)}">
<input type="hidden" name="mid" value="${_esc(widget.mid)}">
<input type="hidden" name="orderId" value="${_esc(widget.orderId)}">
<input type="hidden" name="txnToken" value="${_esc(widget.txnToken)}">
</form><p style="font-family:sans-serif;text-align:center;margin-top:40vh">Opening Paytm...</p></body></html>''';

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
            // Paytm has posted back to our server callback: we are done here.
            if (url.contains('/payment/paytm/callback')) _finish();
          },
        ),
      )
      ..loadHtmlString(html, baseUrl: widget.checkoutOrigin);
  }

  void _finish() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Leave payment?'),
        content: const Text(
          'If you already paid, we will confirm it with Paytm. Otherwise nothing is charged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true) _finish();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Paytm',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.navy),
            onPressed: _confirmClose,
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _web),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}
