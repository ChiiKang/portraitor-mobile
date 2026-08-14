import 'package:flutter_test/flutter_test.dart';
import 'package:portraitor_mobile/features/processing/domain/portrait_pack_context.dart';

void main() {
  test('partner pack adds server-authoritative prompt and progress fields', () {
    final context = PortraitPackContext(
      tier: 'partner',
      index: 1,
      total: 2,
      person: 'Alice',
      partnerName: 'Bob',
      moreComing: true,
    );

    expect(context.applyTemplateVars({'target_name': 'Alice'}), {
      'target_name': 'Alice',
      'prompt_key': 'partner',
      'partner_name': 'Bob',
    });
    expect(context.applyMetadata({'phase': 'single'}), {
      'phase': 'single',
      'pack': {'index': 1, 'total': 2, 'person': 'Alice'},
      'pack_more_coming': true,
    });
  });

  test('final family portrait carries all prior portraits once', () {
    final context = PortraitPackContext(
      tier: 'family',
      index: 3,
      total: 3,
      person: 'Cara',
      familyMembers: '"Alice", "Bob", "Cara"',
      priorPortraits: const [
        {'person': 'Alice', 'output': 'First'},
        {'person': 'Bob', 'output': 'Second'},
      ],
    );

    expect(context.applyTemplateVars({}), {
      'prompt_key': 'family',
      'family_members': '"Alice", "Bob", "Cara"',
    });
    expect(context.applyMetadata({}), {
      'pack': {'index': 3, 'total': 3, 'person': 'Cara'},
      'pack_portraits': const [
        {'person': 'Alice', 'output': 'First'},
        {'person': 'Bob', 'output': 'Second'},
      ],
    });
  });
}
