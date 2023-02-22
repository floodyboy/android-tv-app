import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:mawaqit/src/helpers/Api.dart';
import 'package:mawaqit/src/helpers/RelativeSizes.dart';
import 'package:mawaqit/src/helpers/repaint_boundires.dart';
import 'package:mawaqit/src/pages/home/widgets/AboveSalahBar.dart';
import 'package:mawaqit/src/pages/home/widgets/SalahTimesBar.dart';
import 'package:mawaqit/src/themes/UIShadows.dart';
import 'package:provider/provider.dart';

import '../../../helpers/StringUtils.dart';
import '../../../services/mosque_manager.dart';

class RandomHadithScreen extends StatelessWidget {
  const RandomHadithScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mosqueManager = context.read<MosqueManager>();
    final mosqueConfig = mosqueManager.mosqueConfig;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: AboveSalahBar(),
        ),
        Expanded(
          child: FutureBuilder<String>(
            future: Api.randomHadith(language: mosqueConfig!.hadithLang!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return SizedBox.shrink();

              return RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: Center(
                    child: AutoSizeText(
                      snapshot.data ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 100.vw,
                        fontWeight: FontWeight.bold,
                        shadows: kIqamaCountDownTextShadow,
                        fontFamily: StringManager.getFontFamilyByString(
                          snapshot.data ?? '',
                        ),
                        color: Colors.white,
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: .5.seconds).addRepaintBoundary(),
              );
            },
          ),
        ),
        SalahTimesBar(
          miniStyle: true,
          microStyle: true,
        ),
        SizedBox(height: 4.vh),
      ],
    );
  }
}