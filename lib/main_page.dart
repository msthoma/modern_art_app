import 'package:camera/camera.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:modern_art_app/tensorflow/model_selection.dart';
import 'package:modern_art_app/ui/pages/explore_page.dart';
import 'package:modern_art_app/ui/pages/settings_page.dart';

import 'utils/extensions.dart';

class MainPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainPage({Key key, @required this.cameras}) : super(key: key);

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  /// The HeroController is needed for enabling Hero animations in the custom
  /// Navigator below, see this post https://stackoverflow.com/a/60729122
  HeroController _heroController;

  /// The global [_navigatorKey] is necessary so that the nav bar can push
  /// routes to the navigator (the nav bar is located above/in another branch
  /// of the widget hierarchy from the navigator, and thus in another context,
  /// and so it cannot access the navigator using the usual
  /// Navigator.of(context) methods.
  final _navigatorKey = GlobalKey<NavigatorState>();

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _heroController = HeroController(createRectTween: _createRectTween);
  }

  /// Used for enabling Hero animations in the custom Navigator.
  RectTween _createRectTween(Rect begin, Rect end) {
    return MaterialRectArcTween(begin: begin, end: end);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings();
    return Scaffold(
      body: WillPopScope(
        // wrapping the Navigator with a WillPopScope enables the correct
        // handling of the back button on Android
        onWillPop: () async {
          if (_navigatorKey.currentState.canPop()) {
            _navigatorKey.currentState.pop();
            return false;
          }
          return true;
        },
        child: Navigator(
          key: _navigatorKey,
          observers: [_heroController],
          initialRoute: "/",
          onGenerateRoute: (RouteSettings settings) {
            WidgetBuilder builder;
            // route names
            // todo move route names into a list? map?
            switch (settings.name) {
              case "/":
                builder = (BuildContext context) => ExplorePage();
                break;
              case "/identify":
                builder =
                    (BuildContext context) => ModelSelection(widget.cameras);
                break;
              case "/settings":
                builder = (BuildContext context) => SettingsPage();
                break;
              default:
                throw Exception("Invalid route: ${settings.name}");
            }
            return MaterialPageRoute(
              builder: builder,
              settings: settings,
            );
          },
        ),
      ),
      bottomNavigationBar: ConvexAppBar(
        style: TabStyle.fixed,
        backgroundColor: ThemeData.dark().primaryColor,
        initialActiveIndex: _currentIndex,
        items: [
          TabItem(icon: Icon(Icons.home), title: strings.nav.explore),
          TabItem(icon: Icon(Icons.camera), title: strings.nav.identify),
          TabItem(icon: Icon(Icons.settings), title: strings.stngs.title),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              // when the Explore tab is selected, remove everything else from
              // the navigator's stack
              _navigatorKey.currentState
                  .pushNamedAndRemoveUntil("/", (_) => false);
              break;
            case 1:
              _navigatorKey.currentState.pushNamed("/identify");
              break;
            case 2:
              _navigatorKey.currentState.pushNamed("/settings");
              break;
          }
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}