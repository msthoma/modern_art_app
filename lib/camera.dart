import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:modern_art_app/data/artworks_dao.dart';
import 'package:modern_art_app/data/database.dart';
import 'package:modern_art_app/ui/widgets/artwork_details_page.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class TakePictureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const TakePictureScreen({Key key, @required this.cameras}) : super(key: key);

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  CameraController _controller;
  Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    // create CameraController
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
    );
    // initialize controller
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // dispose controller when widget is disposed
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Point the camera to a painting"),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            //future complete, display preview
            return CameraPreview(_controller);
          } else {
            // if not, display loading indicator
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.camera_alt),
        //onpressed callback
        onPressed: () async {
          // try to take a picture
          try {
            // ensure the camera is initialized
            await _initializeControllerFuture;
            //construct path for picture file
            final path = join(
              // store the picture in the temp directory, find the temp
              // directory using the `path_provider` plugin
              (await getTemporaryDirectory()).path,
              "${DateTime.now()}.png",
            );
            // take picture
            await _controller.takePicture(path);
            Artwork randomArtwork;
            Provider.of<ArtworksDao>(context, listen: false)
                .allArtworkEntries
                .then((value) =>
                    randomArtwork = value[math.Random().nextInt(value.length)]);
            // if picture was taken, show it in DisplayPictureScreen widget
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ArtworkDetailsPage(artwork: randomArtwork),
              ),
            );
          } catch (e) {
            // catch any errors
            print(e);
          }
        },
      ),
    );
  }
}

void getRandom() {
  // Provider.of<ArtworksDao>(context)
}
