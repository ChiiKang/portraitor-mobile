import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:portraitor_mobile/core/theme/tokens.dart';
import 'package:portraitor_mobile/shared/widgets/gradient_button.dart';

class HowItWorksPage extends StatefulWidget {
  final VoidCallback onNext;

  const HowItWorksPage({super.key, required this.onNext});

  @override
  State<HowItWorksPage> createState() => _HowItWorksPageState();
}

class _HowItWorksPageState extends State<HowItWorksPage> {
  late final VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
        Uri.parse(
          'https://portraitor.ai/assets/video/portraitor-explainer.mp4',
        ),
      )
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PortraitorTokens.space24),
      child: Column(
        children: [
          const Spacer(flex: 2),
          const Text(
            'How it works?',
            style: PortraitorTokens.titleLg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: PortraitorTokens.space16),
          ClipRRect(
            borderRadius: BorderRadius.circular(PortraitorTokens.radiusXl),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: PortraitorTokens.borderSoft),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child:
                    _initialized
                        ? GestureDetector(
                          onTap: _togglePlay,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              if (!_controller.value.isPlaying)
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        )
                        : const Center(
                          child: CircularProgressIndicator(
                            color: PortraitorTokens.brandPurple,
                          ),
                        ),
              ),
            ),
          ),
          const SizedBox(height: PortraitorTokens.space32),
          const _StepRow(
            number: '1',
            text: 'Export a chat from WhatsApp or Telegram',
          ),
          const SizedBox(height: PortraitorTokens.space16),
          const _StepRow(number: '2', text: 'Share it with Portraitor'),
          const SizedBox(height: PortraitorTokens.space16),
          const _StepRow(
            number: '3',
            text: 'Get a detailed personality portrait in ~90 seconds',
          ),
          const Spacer(flex: 3),
          GradientButton(
            onPressed: widget.onNext,
            child: const Text('Continue'),
          ),
          const SizedBox(height: PortraitorTokens.space24),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: PortraitorTokens.brandSoft,
            borderRadius: BorderRadius.circular(PortraitorTokens.radiusSm),
          ),
          child: Center(
            child: Text(
              number,
              style: PortraitorTokens.titleSm.copyWith(
                color: PortraitorTokens.brandPurple,
              ),
            ),
          ),
        ),
        const SizedBox(width: PortraitorTokens.space12),
        Expanded(child: Text(text, style: PortraitorTokens.bodyLg)),
      ],
    );
  }
}
