import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mawaqit/src/helpers/RelativeSizes.dart';
import 'package:mawaqit/src/helpers/repaint_boundaries.dart';
import 'package:mawaqit/src/mawaqit_image/mawaqit_image_cache.dart';
import 'package:mawaqit/src/models/announcement.dart';
import 'package:mawaqit/src/pages/home/sub_screens/normal_home.dart';
import 'package:mawaqit/src/pages/home/widgets/AboveSalahBar.dart';
import 'package:mawaqit/src/pages/home/widgets/workflows/WorkFlowWidget.dart';
import 'package:mawaqit/src/services/mosque_manager.dart';
import 'package:mawaqit/src/services/user_preferences_manager.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../../state_management/workflow/announcement_workflow/announcement_workflow_notifier.dart'
    as announcement_workflow;

import '../../../state_management/workflow/announcement_workflow/announcement_workflow_state.dart';
import '../widgets/salah_items/responsive_mini_salah_bar_widget.dart';

class AnnouncementScreen extends ConsumerStatefulWidget {
  AnnouncementScreen({
    Key? key,
    this.onDone,
    this.enableVideos = true,
  }) : super(key: key);

  final VoidCallback? onDone;

  /// used to disable videos on mosques
  final bool enableVideos;

  @override
  ConsumerState createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends ConsumerState<AnnouncementScreen> {
  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      log('announcement: AnnouncementScreen: 1 startAnnouncement called enableVideos: ${widget.enableVideos}');
      ref.read(announcement_workflow.announcementWorkflowProvider.notifier).startAnnouncement(
            widget.enableVideos,
          );
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(announcement_workflow.announcementWorkflowProvider, (previous, next) {
      if (next.value!.status == AnnouncementWorkflowStatus.completed) {
        // All announcements have been displayed
        log('announcement: AnnouncementScreen: 1 widget.onDone?.call() called ');
        widget.onDone?.call();
      }
      if (next.hasError) {
        // An error occurred during the announcement workflow
        widget.onDone?.call();
      }
    });
    return ref.watch(announcement_workflow.announcementWorkflowProvider).maybeWhen(
          orElse: () => Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor), // Green color
            ),
          ),
          data: (state) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              announcementWidgets(
                state.announcementItem.announcement,
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 1.vh),
                  child: AboveSalahBar(),
                ),
              ),
              IgnorePointer(
                child: Padding(padding: EdgeInsets.only(bottom: 1.5.vh), child: ResponsiveMiniSalahBarWidget()),
              )
            ],
          ),
        );
  }

  /// return the widget of the announcement based on its type
  Widget announcementWidgets(Announcement activeAnnouncement, {VoidCallback? nextAnnouncement}) {
    if (activeAnnouncement.content != null) {
      return _TextAnnouncement(
        content: activeAnnouncement.content!,
        title: activeAnnouncement.title,
      );
    } else if (activeAnnouncement.imageFile != null) {
      return _ImageAnnouncement(
        image: activeAnnouncement.imageFile!,
        onError: nextAnnouncement,
      );
    } else if (activeAnnouncement.video != null) {
      return _VideoAnnouncement(
        key: ValueKey(activeAnnouncement.video),
        url: activeAnnouncement.video!,
        onEnded: nextAnnouncement, // Make sure this is correctly called when the video ends
      );
    }

    return SizedBox();
  }
}

class _TextAnnouncement extends StatelessWidget {
  const _TextAnnouncement({Key? key, required this.title, required this.content}) : super(key: key);

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey("$content $title"),
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          // title
          SizedBox(height: 10.vh),
          Text(
            title ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              shadows: kAnnouncementTextShadow,
              fontSize: 50,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
              letterSpacing: 1,
            ),
          ).animate().slide().addRepaintBoundary(),
          // content
          SizedBox(height: 3.vh),
          Expanded(
            child: AutoSizeText(
              content,
              stepGranularity: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                shadows: kAnnouncementTextShadow,
                fontSize: 8.vwr,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ).animate().fade(delay: 500.milliseconds).addRepaintBoundary(),
          ),
          SizedBox(height: 20.vh),
        ],
      ),
    );
  }

  get kAnnouncementTextShadow => [
        Shadow(
          offset: Offset(0, 9),
          blurRadius: 15,
          color: Colors.black54,
        ),
      ];
}

class _ImageAnnouncement extends StatelessWidget {
  const _ImageAnnouncement({
    Key? key,
    required this.image,
    this.onError,
  }) : super(key: key);

  final Uint8List? image;

  /// used to skip to the next announcement if the image failed to load
  final VoidCallback? onError;

  @override
  Widget build(BuildContext context) {
    return Image(
      image: Image.memory(image!).image,
      fit: BoxFit.fill,
      width: double.infinity,
      height: double.infinity,
    ).animate().slideX().addRepaintBoundary();
  }
}

class _VideoAnnouncement extends ConsumerStatefulWidget {
  const _VideoAnnouncement({
    Key? key,
    required this.url,
    this.onEnded,
  }) : super(key: key);

  final String url;
  final VoidCallback? onEnded;

  @override
  ConsumerState<_VideoAnnouncement> createState() => _VideoAnnouncementState();
}

class _VideoAnnouncementState extends ConsumerState<_VideoAnnouncement> {
  late YoutubePlayerController _controller;
  Timer? _timeoutTimer;

  @override
  void initState() {
    final mosqueManager = context.read<MosqueManager>();
    ref.read(videoProvider.notifier).state = true;
    _controller = YoutubePlayerController(
      initialVideoId: YoutubePlayer.convertUrlToId(widget.url)!,
      flags: YoutubePlayerFlags(
        autoPlay: true,
        mute: mosqueManager.typeIsMosque,
        useHybridComposition: false,
        hideControls: true,
        forceHD: true,
      ),
    )..addListener(() {
        if (_controller.value.isReady && _controller.value.isPlaying) {
          _startTimeoutTimer();
        }
      });

    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        ref.read(videoProvider.notifier).state = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Center(
        child: YoutubePlayer(
          onEnded: (data) {
            ref.read(videoProvider.notifier).state = false;
          },
          controller: _controller,
          showVideoProgressIndicator: true,
        ),
      ),
    );
  }
}

final videoProvider = StateProvider<bool>((ref) => true);
