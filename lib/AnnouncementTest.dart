import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:mawaqit/src/services/mosque_manager.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class AnnouncementTest extends StatefulWidget {
  const AnnouncementTest({Key? key}) : super(key: key);

  @override
  State<AnnouncementTest> createState() => _AnnouncementTestState();
}

class _AnnouncementTestState extends State<AnnouncementTest> {
  int activeIndex = 0;
  Duration announcementDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    if (context
        .read<MosqueManager>()
        .mosque!
        .announcements
        .isNotEmpty) {
      nextScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mosqueProvider = context.watch<MosqueManager>();

    if (mosqueProvider.mosque == null || mosqueProvider.times == null) return SizedBox();

    final mosque = mosqueProvider.mosque!;
    return
      Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: mosque.image != null
                  ? NetworkImage(mosque.image!) as ImageProvider
                  : AssetImage('assets/backgrounds/splash_screen_5.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            color: Colors.black54,
            child: (context
                .read<MosqueManager>()
                .mosque!
                .announcements
                .isNotEmpty) ? announcementWidgets():Center(
                child: Container(
                  child: Text(
                    style: TextStyle(
                      fontSize: 62,
                      color: Colors.white70,
                    ),
                    "Not found Announcement",
                  ),
                )),
          ),
        ),
      );
  }

  Widget announcementWidgets() {
    final announcement = context
        .read<MosqueManager>()
        .mosque!
        .announcements[activeIndex];

    if (announcement.content != null) {
      return textAnnouncement(announcement.content!, announcement.title);
    } else if (announcement.image != null) {
      return imageAnnouncement(announcement.image!);
    } else if (announcement.video != null) {
      return videoAnnouncement(announcement.video!);
    }

    return Center(
        child: Container(
          child: Text(
            style: TextStyle(
              fontSize: 62,
              color: Colors.white70,
            ),
            "Not found Announcement",
          ),
        ));
  }

  Widget textAnnouncement(String content, String title) {
    return Column(
      children: [
        // title
        AutoSizeText(title,
            stepGranularity: 12,
            textAlign: TextAlign.center,
            style: TextStyle(
                shadows: kAnnouncementTextShadow,
                fontSize: 62,
                fontWeight: FontWeight.bold,
                fontFamily: 'hafs',
                color: Colors.amber,
                letterSpacing: 1)),
        // content
        Expanded(
          child: AutoSizeText(content,
              stepGranularity: 12,
              textAlign: TextAlign.center,
              style: TextStyle(
                  shadows: kAnnouncementTextShadow,
                  fontSize: 62,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'hafs',
                  color: Colors.white,
                  letterSpacing: 1)),
        ),
      ],
    );
  }

  Widget imageAnnouncement(String image) {
    return Image.network(
      image,
      fit: BoxFit.cover,
    );
  }

  Widget videoAnnouncement(String video) {
    late YoutubePlayerController _controller = YoutubePlayerController(
      initialVideoId: YoutubePlayer.convertUrlToId(
        video,
      )!,
      flags: YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
      ),
    );
    return Stack(
      children: [
        YoutubePlayer(
          onEnded: (metaData) {
            print("end video");
            nextScreen();
          },
          controller: _controller,
          showVideoProgressIndicator: true,
        ),
      ],
    );
  }

  nextScreen() {
    final announcement = context
        .read<MosqueManager>()
        .mosque!
        .announcements;
    setState(() {
      activeIndex++;
      if (activeIndex >= announcement.length) {
        activeIndex = 0;
      }
    });
    if (announcement[activeIndex].video == null) {
      Future.delayed(announcementDuration).then(
            (value) => nextScreen(),
      );
    }
  }

  get kAnnouncementTextShadow =>
      [
        Shadow(
          offset: Offset(0, 9),
          blurRadius: 15,
          color: Colors.black54,
        ),
      ];
}
