import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:google_fonts/google_fonts.dart';
import 'package:mawaqit/i18n/l10n.dart';
import 'package:mawaqit/main.dart';
import 'package:mawaqit/src/models/mosque.dart';
import 'package:mawaqit/src/pages/mosque_search/widgets/permission_screen_with_button.dart';
import 'package:mawaqit/src/pages/onBoarding/widgets/on_boarding_permission_adhan_screen.dart';
import 'package:mawaqit/src/services/mosque_manager.dart';
import 'package:mawaqit/src/services/permissions_manager.dart';
import 'package:mawaqit/src/state_management/on_boarding/on_boarding.dart';
import 'package:mawaqit/src/widgets/mosque_simple_tile.dart';
import 'package:page_transition/page_transition.dart';
import 'package:provider/provider.dart' as Provider;
import '../../../../i18n/AppLanguage.dart';
import '../../../helpers/AppRouter.dart';
import '../../../helpers/SharedPref.dart';
import '../../../helpers/keyboard_custom.dart';
import '../../../state_management/random_hadith/random_hadith_notifier.dart';
import '../../home/OfflineHomeScreen.dart';
import 'package:fpdart/fpdart.dart' as fp;
import 'package:sizer/sizer.dart';

class ChromeCastMosqueInputSearch extends ConsumerStatefulWidget {
  const ChromeCastMosqueInputSearch({
    Key? key,
    this.onDone,
    this.selectedNode = const fp.None(),
    this.isOnboarding = false,
  }) : super(key: key);

  final void Function()? onDone;
  final fp.Option<FocusNode> selectedNode;
  final bool isOnboarding;

  @override
  ConsumerState<ChromeCastMosqueInputSearch> createState() => _ChromeCastMosqueInputSearchState();
}

class _ChromeCastMosqueInputSearchState extends ConsumerState<ChromeCastMosqueInputSearch> {
  final inputController = TextEditingController();
  final scrollController = ScrollController();
  SharedPref sharedPref = SharedPref();

  List<Mosque> results = [];
  bool loading = false;
  bool noMore = false;
  String? error;

  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'chromecast_search_node');
  final FocusNode _loadMoreFocusNode = FocusNode(debugLabel: 'chromecast_load_more_node');
  final FocusNode _mainFocusNode = FocusNode(debugLabel: 'chromecast_main_focus_node');

  List<FocusNode> _resultFocusNodes = [];
  int _currentFocusIndex = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mosqueManagerProvider.notifier).state = None();
      _searchFocusNode.requestFocus();
    });
    _loadMoreFocusNode.addListener(_onLoadMoreFocus);
  }

  void _onLoadMoreFocus() {
    if (_loadMoreFocusNode.hasFocus && !loading && !noMore && loadMore != null) {
      loadMore?.call();
      scrollToTheEndOfTheList();
    }
  }

  void _updateFocusNodes() {
    for (var node in _resultFocusNodes) {
      node.dispose();
    }

    _resultFocusNodes = List.generate(
      results.length,
      (index) => FocusNode(debugLabel: 'chromecast_result_${index}_node'),
    );

    for (int i = 0; i < _resultFocusNodes.length; i++) {
      _resultFocusNodes[i].addListener(() {
        if (_resultFocusNodes[i].hasFocus) {
          setState(() {
            _currentFocusIndex = i;
          });
        }
      });
    }
  }

  void Function()? loadMore;

  void scrollToTheEndOfTheList() {
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: 200.milliseconds,
      curve: Curves.ease,
    );
  }

  void _searchMosque(String mosque, int page) async {
    if (loading) return;
    loadMore = () => _searchMosque(mosque, page + 1);

    if (mosque.isEmpty) {
      setState(() {
        error = S.of(context).mosqueNameError;
        loading = false;
      });
      return;
    }

    setState(() {
      error = null;
      loading = true;
    });

    final mosqueManager = Provider.Provider.of<MosqueManager>(context, listen: false);
    await mosqueManager.searchMosques(mosque, page: page).then((value) {
      if (!mounted) return;

      setState(() {
        loading = false;

        if (page == 1) {
          results = [];
          _currentFocusIndex = -1;
        }

        noMore = value.isEmpty;
        final oldResultsLength = results.length;
        results = [...results, ...value];

        _updateFocusNodes();

        if (page > 1 && _currentFocusIndex == oldResultsLength - 1 && value.isNotEmpty) {
          _currentFocusIndex = oldResultsLength;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _resultFocusNodes.isNotEmpty &&
                _currentFocusIndex < _resultFocusNodes.length &&
                _resultFocusNodes[_currentFocusIndex].canRequestFocus) {
              _resultFocusNodes[_currentFocusIndex].requestFocus();
              _ensureItemVisible(_currentFocusIndex);
            }
          });
        }
      });
    }).catchError((e, stack) {
      if (!mounted) return;

      setState(() {
        logger.w(e.toString(), stackTrace: stack);
        loading = false;
        error = S.of(context).backendError;
      });
    });
  }

  Future<void> _selectMosque(Mosque mosque) async {
    try {
      await context.read<MosqueManager>().setMosqueUUid(mosque.uuid.toString());

      final mosqueManager = context.read<MosqueManager>();
      final hadithLangCode = await context.read<AppLanguage>().getHadithLanguage(mosqueManager);
      ref.read(randomHadithNotifierProvider.notifier).fetchAndCacheHadith(language: hadithLangCode);

      if (mosqueManager.typeIsMosque) {
        ref.read(mosqueManagerProvider.notifier).state = Option.fromNullable(SearchSelectionType.mosque);
      } else {
        ref.read(mosqueManagerProvider.notifier).state = Option.fromNullable(SearchSelectionType.home);
      }

      if (!widget.isOnboarding && !mosqueManager.typeIsMosque) {
        await _checkAndShowPermissionScreen();
      } else {
        widget.onDone?.call();
      }
    } catch (e, stack) {
      if (e is InvalidMosqueId) {
        setState(() {
          loading = false;
          error = S.of(context).slugError;
        });
      } else {
        setState(() {
          loading = false;
          error = S.of(context).backendError;
        });
      }
    }
  }

  Future<void> _checkAndShowPermissionScreen() async {
    if (!mounted) return;

    final isRooted = await PermissionsManager.shouldAutoInitializePermissions();

    if (isRooted) {
      widget.onDone?.call();
      return;
    }

    final permissionsGranted = await PermissionsManager.arePermissionsGranted();

    if (!permissionsGranted) {
      if (!mounted) return;

      await Navigator.push(
        context,
        PageTransition(
          type: PageTransitionType.fade,
          alignment: Alignment.center,
          child: PermissionScreenWithButton(
            selectedNode: widget.selectedNode,
          ),
        ),
      );

      if (mounted) {
        widget.onDone?.call();
      }
    } else {
      widget.onDone?.call();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
    if (results.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_searchFocusNode.hasFocus) {
        if (results.isNotEmpty) {
          setState(() => _currentFocusIndex = results.length - 1);
          _resultFocusNodes[_currentFocusIndex].requestFocus();
          _ensureItemVisible(_currentFocusIndex);
        }
        return KeyEventResult.handled;
      } else if (_currentFocusIndex == 0) {
        setState(() => _currentFocusIndex = -1);
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      } else if (_currentFocusIndex > 0) {
        setState(() => _currentFocusIndex--);
        _resultFocusNodes[_currentFocusIndex].requestFocus();
        _ensureItemVisible(_currentFocusIndex);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_searchFocusNode.hasFocus) {
        if (results.isNotEmpty) {
          setState(() => _currentFocusIndex = 0);
          _resultFocusNodes[_currentFocusIndex].requestFocus();
          _ensureItemVisible(_currentFocusIndex);
        }
        return KeyEventResult.handled;
      } else if (_currentFocusIndex == results.length - 1) {
        if (!noMore && loadMore != null) {
          loadMore?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) => scrollToTheEndOfTheList());
          return KeyEventResult.handled;
        } else {
          setState(() => _currentFocusIndex = -1);
          _searchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      } else if (_currentFocusIndex >= 0 && _currentFocusIndex < results.length - 1) {
        setState(() => _currentFocusIndex++);
        _resultFocusNodes[_currentFocusIndex].requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureItemVisible(_currentFocusIndex));
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
      if (_currentFocusIndex >= 0 && _currentFocusIndex < results.length) {
        _selectMosque(results[_currentFocusIndex]);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _ensureItemVisible(int index) {
    if (index < 0 || index >= results.length || !scrollController.hasClients) return;

    final double itemHeight = 80.0;
    final double listViewHeight = MediaQuery.of(context).size.height * 0.6;
    double itemPosition = index * itemHeight;

    if (itemPosition < scrollController.offset || itemPosition > scrollController.offset + listViewHeight) {
      scrollController.animateTo(
        itemPosition - (listViewHeight / 2) + (itemHeight / 2),
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _mainFocusNode.dispose();
    _loadMoreFocusNode.dispose();
    for (var node in _resultFocusNodes) {
      node.dispose();
    }
    inputController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      child: Focus(
        focusNode: _mainFocusNode,
        onKey: _handleKeyEvent,
        child: Align(
          alignment: Alignment(0, -.3),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.symmetric(vertical: 80, horizontal: 10),
            cacheExtent: 99999,
            children: [
              Text(
                S.of(context).searchMosque,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: theme.brightness == Brightness.dark ? null : theme.primaryColor,
                ),
              ).animate().slideY(begin: -1).fade(),
              SizedBox(height: 20),
              searchField(theme).animate().slideX(begin: 1, delay: 200.milliseconds).fadeIn(),
              SizedBox(height: 20),
              for (var i = 0; i < results.length; i++)
                MosqueSimpleTile(
                  key: Key('mosque_tile_${results[i].uuid}'),
                  autoFocus: false,
                  mosque: results[i],
                  selectedNode: widget.selectedNode,
                  focusNode: _resultFocusNodes.isNotEmpty ? _resultFocusNodes[i] : null,
                  hasFocus: _currentFocusIndex == i,
                  onTap: () => _selectMosque(results[i]),
                ).animate().slideX(delay: 70.milliseconds * (i % 5)).fade(),
              if (results.isNotEmpty)
                Focus(
                  focusNode: _loadMoreFocusNode,
                  child: Center(
                    child: SizedBox(
                      height: 40,
                      child: Builder(
                        builder: (context) {
                          if (loading) return CircularProgressIndicator();
                          if (noMore && results.isEmpty) return Text(S.of(context).mosqueNoResults);
                          if (noMore) return Text(S.of(context).mosqueNoMore);
                          return GestureDetector(
                            onTap: () {
                              if (!noMore && loadMore != null) {
                                loadMore?.call();
                                scrollToTheEndOfTheList();
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: theme.brightness == Brightness.dark
                                    ? Colors.white10
                                    : theme.primaryColor.withOpacity(0.1),
                              ),
                              child: Text(
                                'load more',
                                style: TextStyle(
                                  color: theme.brightness == Brightness.dark ? Colors.white70 : theme.primaryColor,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget searchField(ThemeData theme) {
    return TextFormField(
      controller: inputController,
      style: GoogleFonts.inter(
        color: theme.brightness == Brightness.dark ? null : theme.primaryColor,
        fontSize: 12.sp,
        fontWeight: FontWeight.w500,
      ),
      onFieldSubmitted: (val) => _searchMosque(val, 1),
      cursorColor: theme.brightness == Brightness.dark ? null : theme.primaryColor,
      keyboardType: TextInputType.none,
      autofocus: true,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        filled: true,
        errorText: error,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: theme.primaryColor, width: 2),
        ),
        hintText: S.of(context).searchForMosque,
        hintStyle: TextStyle(
          fontSize: 8.sp,
          fontWeight: FontWeight.normal,
          color: theme.brightness == Brightness.dark ? null : theme.primaryColor.withOpacity(0.4),
        ),
        suffixIcon: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => _searchMosque(inputController.text, 1),
          child: Icon(Icons.search_rounded),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: theme.primaryColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: theme.primaryColor, width: 1),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: 2,
          horizontal: 20,
        ),
      ),
    );
  }
}
