// Legal documents content for Tripora.
//
// These are starter templates tailored to Tripora (an AI-assisted travel
// planning app). Review and adjust them with a legal professional before
// relying on them in production - especially the {{placeholders}} (contact
// email, company/operator name, jurisdiction, last-updated date).

/// A single section/paragraph within a legal document.
class LegalSection {
  const LegalSection(this.title, this.body);

  /// Section heading, or `null`/empty for an unlabelled intro paragraph.
  final String title;

  /// Body text. Blank lines (`\n\n`) are rendered as paragraph breaks.
  final String body;
}

class TermsContent {
  TermsContent._();

  static const String title = 'Terms and Conditions';
  static const List<LegalSection> sections = [
    LegalSection(
      '',
      'Welcome to Tripora. These Terms and Conditions ("Terms") govern your '
      'use of the Tripora mobile application and related services (together, '
      'the "Service"). By creating an account or using the Service, you agree '
      'to be bound by these Terms. If you do not agree, please do not use the '
      'Service.',
    ),
    LegalSection(
      '1. About the Service',
      'Tripora is an AI-assisted travel planning application that helps you '
      'generate itineraries, explore destinations, and plan trips. Trip '
      'itineraries and travel estimates are generated automatically for '
      'convenience only and are not a guarantee of any kind.',
    ),
    LegalSection(
      '2. Your Account',
      'When you create an account you must provide accurate information and '
      'keep your credentials secure. You are responsible for all activity '
      'that occurs under your account. You must be at least the age of '
      'digital consent in your country to use the Service.',
    ),
    LegalSection(
      '3. Acceptable Use',
      'You agree not to misuse the Service, attempt to gain unauthorized '
      'access to it, interfere with its operation, or use it for any unlawful '
      'purpose. We may suspend or terminate accounts that violate these '
      'Terms.',
    ),
    LegalSection(
      '4. AI-Generated Content and No Professional Advice',
      'Trip plans, itineraries, cost estimates, and recommendations produced '
      'by the Service are generated automatically and are not professional '
      'travel, financial, or safety advice. Always verify bookings, prices, '
      'documentation, and local conditions independently. We are not liable '
      'for decisions you make based on the Service.',
    ),
    LegalSection(
      '5. Third-Party Services',
      'The Service may integrate with third-party providers for features such '
      'as flights, stays, and car rentals. Those providers have their own '
      'terms and privacy policies, and we are not responsible for their '
      'services.',
    ),
    LegalSection(
      '6. Intellectual Property',
      'The Tripora name, logo, and Service content are owned by us or our '
      'licensors. You may not copy, modify, or redistribute the Service '
      'except as permitted by law.',
    ),
    LegalSection(
      '7. Termination',
      'You may stop using the Service at any time. We may suspend or '
      'terminate your access for violations of these Terms. Provisions that '
      'by their nature should survive termination will survive.',
    ),
    LegalSection(
      '8. Disclaimers and Limitation of Liability',
      'The Service is provided "as is" and "as available" without warranties '
      'of any kind. To the maximum extent permitted by law, we are not liable '
      'for indirect, incidental, or consequential damages arising from your '
      'use of the Service.',
    ),
    LegalSection(
      '9. Changes to These Terms',
      'We may update these Terms from time to time. We will notify you of '
      'material changes through the Service. Continued use after changes '
      'takes effect means you accept the updated Terms.',
    ),
    LegalSection(
      '10. Contact',
      'If you have questions about these Terms, contact us at '
      '{{LEGAL_CONTACT_EMAIL}}.',
    ),
  ];
}

class PrivacyContent {
  PrivacyContent._();

  static const String title = 'Privacy Policy';
  static const List<LegalSection> sections = [
    LegalSection(
      '',
      'This Privacy Policy explains how Tripora ("we", "us") collects, uses, '
      'and protects your information when you use our Service. By using the '
      'Service you agree to this policy.',
    ),
    LegalSection(
      '1. Information We Collect',
      'Account information: name, email address, and a hashed password when '
      'you register. Profile information you choose to provide, such as your '
      'region or preferences. Trip information you create. Device and usage '
      'information needed to operate and improve the Service.',
    ),
    LegalSection(
      '2. How We Use Your Information',
      'We use your information to provide the Service, create and restore '
      'your trips, send you account emails, personalize your '
      'experience, and keep the Service secure. We do not sell your personal '
      'data.',
    ),
    LegalSection(
      '3. How We Share Information',
      'We only share your information with service providers that help us '
      'operate (for example, email delivery, hosting, and database providers) '
      'and with third-party travel providers when you opt in to those '
      'features. We do not share it for advertising purposes.',
    ),
    LegalSection(
      '4. Data Retention and Security',
      'We keep your data for as long as your account is active or as needed '
      'for legitimate business and legal purposes. We use reasonable security '
      'measures to protect your data, though no method of transmission or '
      'storage is completely secure.',
    ),
    LegalSection(
      '5. Your Rights',
      'Depending on where you live, you may have rights to access, correct, '
      'delete, or export your data, and to object to or restrict certain '
      'processing. You can request account deletion through the app or by '
      'contacting us.',
    ),
    LegalSection(
      '6. Children',
      'The Service is not directed at children below the age of digital '
      'consent, and we do not knowingly collect their data.',
    ),
    LegalSection(
      '7. Changes to This Policy',
      'We may update this Privacy Policy from time to time. We will notify '
      'you of material changes through the Service.',
    ),
    LegalSection(
      '8. Contact',
      'If you have questions about this Privacy Policy or wish to exercise '
      'your rights, contact us at {{LEGAL_CONTACT_EMAIL}}.',
    ),
  ];
}
