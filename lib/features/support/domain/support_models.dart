import 'package:equatable/equatable.dart';

/// FAQ item representation.
class FaqItem extends Equatable {
  const FaqItem({
    required this.question,
    required this.answer,
    required this.category,
  });

  final String question;
  final String answer;
  final String category;

  @override
  List<Object?> get props => [question, answer, category];
}

/// Comprehensive list of standard CalServices home services FAQs.
abstract final class CalServicesFaqs {
  static const List<FaqItem> all = [
    // Booking & Scheduling
    FaqItem(
      category: 'Booking & Scheduling',
      question: 'How do I book a home service on CalServices?',
      answer:
          'Simply browse through our service categories on the home screen, select the service you need, choose your preferred date and 2-hour time slot, enter your address, and place the booking with an advance deposit.',
    ),
    FaqItem(
      category: 'Booking & Scheduling',
      question: 'Can I reschedule an existing booking?',
      answer:
          'Yes! You can reschedule your booking up to 2 hours before the scheduled time slot without any additional fee. Go to "My Bookings" > select your booking > tap "Reschedule" to pick a new date and time.',
    ),
    FaqItem(
      category: 'Booking & Scheduling',
      question: 'How do I know which technician is assigned?',
      answer:
          'Once a technician is assigned to your request, you will receive a notification and their profile (name, rating, photo, and direct call button) will appear on your booking details screen and live tracking map.',
    ),

    // Payment & Invoices
    FaqItem(
      category: 'Payment & Invoices',
      question: 'What payment methods are supported?',
      answer:
          'We support all major payment modes through Razorpay, including UPI (Google Pay, PhonePe, Paytm, BHIM), Credit/Debit Cards (Visa, Mastercard, RuPay), NetBanking from 50+ banks, and Wallets.',
    ),
    FaqItem(
      category: 'Payment & Invoices',
      question: 'Why do I need to pay an advance deposit?',
      answer:
          'The 20% advance deposit reserves your time slot and guarantees dedicated technician dispatch. The remaining balance is payable after service completion.',
    ),
    FaqItem(
      category: 'Payment & Invoices',
      question: 'Where can I download my GST invoice?',
      answer:
          'Once your service is marked as completed and paid, your tax invoice will be available for download in the Booking Details screen.',
    ),

    // Cancellation & Refunds
    FaqItem(
      category: 'Cancellation & Refunds',
      question: 'What is the cancellation policy?',
      answer:
          'You can cancel your booking anytime before the technician arrives. If cancelled before technician dispatch, a 100% refund of your advance deposit is initiated to your original payment method.',
    ),
    FaqItem(
      category: 'Cancellation & Refunds',
      question: 'How long does a refund take to process?',
      answer:
          'Refunds are processed automatically via Razorpay within 5-7 business days back to the original source account (UPI / Card / NetBanking).',
    ),

    // Safety & Warranty
    FaqItem(
      category: 'Safety & Warranty',
      question: 'Are CalServices technicians verified?',
      answer:
          'Yes! Every CalServices professional undergoes thorough background checks, identity verification, criminal record screening, and rigorous hands-on skill evaluations.',
    ),
    FaqItem(
      category: 'Safety & Warranty',
      question: 'Does CalServices provide a service warranty?',
      answer:
          'All completed repairs come with our 30-Day CalServices Service Assurance Guarantee. If any issue re-occurs within 30 days, we provide a free re-visit.',
    ),
  ];
}
