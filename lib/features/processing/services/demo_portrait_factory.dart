class DemoPortraitFactory {
  const DemoPortraitFactory._();

  static String build({required String targetName}) {
    final name = targetName.trim().isEmpty ? 'This person' : targetName.trim();

    return '''
# $name's communication portrait

> **Demo preview**
> This sample is generated locally to demonstrate the complete app experience. It is not an AI analysis of the imported conversation.

## At a glance

$name comes across as someone who values clarity, steady connection, and conversations that feel genuine rather than performative. Their communication style appears most comfortable when both people have room to explain what they mean.

## How they connect

- They tend to build trust through consistency and small signs of attention.
- They respond well when feelings and practical details are both acknowledged.
- They seem to prefer direct language delivered with warmth.

## When conversation gets difficult

Tension may grow when assumptions replace questions. A calm check-in, followed by one clear topic at a time, is likely to create more room for understanding than a fast exchange of conclusions.

## What helps

Offer context, say what matters plainly, and leave space for a response. Recognition of effort can be as important as agreement.

## A useful reminder

This demo text is intentionally generic. A real portrait is created only after native store verification and secure server-side processing are available.
'''.trim();
  }
}
