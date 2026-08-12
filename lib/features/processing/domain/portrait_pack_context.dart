class PortraitPackContext {
  const PortraitPackContext({
    required this.tier,
    required this.index,
    required this.total,
    required this.person,
    this.partnerName,
    this.familyMembers,
    this.moreComing = false,
    this.priorPortraits = const [],
  });

  final String tier;
  final int index;
  final int total;
  final String person;
  final String? partnerName;
  final String? familyMembers;
  final bool moreComing;
  final List<Map<String, dynamic>> priorPortraits;

  Map<String, dynamic> applyTemplateVars(Map<String, dynamic> source) => {
    ...source,
    'prompt_key': tier,
    if (partnerName != null && partnerName!.isNotEmpty)
      'partner_name': partnerName,
    if (familyMembers != null && familyMembers!.isNotEmpty)
      'family_members': familyMembers,
  };

  Map<String, dynamic> applyMetadata(Map<String, dynamic> source) => {
    ...source,
    'pack': {'index': index, 'total': total, 'person': person},
    if (moreComing) 'pack_more_coming': true,
    if (!moreComing && priorPortraits.isNotEmpty)
      'pack_portraits': priorPortraits,
  };
}
