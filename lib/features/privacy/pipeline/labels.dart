/// Maps raw model label strings onto the internal taxonomy.
///
/// Direct port of `portraitor_v3/privacy/pipeline/labels.ts`. The alias table is
/// reproduced verbatim, including entries the shipped label set never emits
/// (`date`, `timestamp`, `account number`, `username`), because the detector's
/// label list is configuration and a future change could start emitting them.
library;

import 'types.dart';

const Map<String, PIILabel> _labelAliases = {
  'person name': PIILabel.privatePerson,
  'person': PIILabel.privatePerson,
  'name': PIILabel.privatePerson,
  'private_person': PIILabel.privatePerson,
  'email address': PIILabel.privateEmail,
  'email': PIILabel.privateEmail,
  'private_email': PIILabel.privateEmail,
  'phone number': PIILabel.privatePhone,
  'phone': PIILabel.privatePhone,
  'private_phone': PIILabel.privatePhone,
  'url': PIILabel.privateUrl,
  'private_url': PIILabel.privateUrl,
  'date of birth': PIILabel.privateDate,
  'date': PIILabel.privateDate,
  'timestamp': PIILabel.privateDate,
  'private_date': PIILabel.privateDate,
  'street address': PIILabel.privateAddress,
  'address': PIILabel.privateAddress,
  'private_address': PIILabel.privateAddress,
  'account number': PIILabel.accountNumber,
  'account_number': PIILabel.accountNumber,
  'api key': PIILabel.secret,
  'secret': PIILabel.secret,
  'username': PIILabel.username,
  'unknown': PIILabel.unknown,
};

/// Normalises a raw detector label. Anything unrecognised becomes
/// [PIILabel.unknown] rather than throwing, matching the `?? "unknown"` fallback
/// in the TypeScript original.
PIILabel normalizePrivacyLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return _labelAliases[normalized] ?? PIILabel.unknown;
}
