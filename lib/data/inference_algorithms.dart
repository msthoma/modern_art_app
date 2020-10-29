import 'package:modern_art_app/data/database.dart';
import 'package:modern_art_app/utils/extensions.dart';
import 'package:modern_art_app/utils/utils.dart';

/// A common supertype class to facilitate the implementation of all
/// inference algorithms used in the app.
abstract class InferenceAlgorithm {
  /// Records the time when the algorithm is first initialised, to allow
  /// calculation of the total time needed to reach a decision.
  final startTime = DateTime.now();

  /// Variable that indicates that no result is available yet.
  final noResult = "";

  /// List that holds a history of all model inferences so far.
  List history = [];

  /// List that holds a history of all inference durations so far, in
  /// milliseconds; used mostly for calculating how many frames are analysed
  /// per second (FPS).
  List<int> inferenceTimeHistory = [];

  /// Number of frames analysed per second.
  double _fps = 0.0;

  /// Current artwork picked by the algorithm as the most likely inference.
  String _topInference = "";

  /// Returns the artwork picked by the algorithm as the most likely inference;
  /// if the algorithm has not decided yet this will be an empty string.
  String get topInference {
    if (hasResult()) {
      return _topInference;
    } else {
      return noResult;
    }
  }

  /// Returns the result by algorithm in a formatted string; must be
  /// implemented by all classes extending [InferenceAlgorithm].
  String get topInferenceFormatted;

  /// Returns the number of frames analysed by the algorithm per second, as a
  /// formatted string.
  String get fps => "${_fps.toStringAsPrecision(2)} fps";

  bool hasResult() => _topInference != "";

  void setTopInference(String value) => _topInference = value;

  void resetTopInference() => _topInference = noResult;

  /// should always call _updateHistories() first
  void updateRecognitions(List<dynamic> recognitions, int inferenceTime);

  void _updateHistories(List<dynamic> recognitions, int inferenceTime) {
    // for now recognitions will only contain 1 element (1 inference from CNN,
    // this is specified in tensorflow_camera), could change this in the future
    // if necessary
    // each item in recognitions is a LinkedHashMap in the form of
    // {confidence: 0.5562283396720886, index: 15, label: untitled_votsis}
    history.addAll(recognitions);
    inferenceTimeHistory.add(inferenceTime);
    _updateFps();
  }

  void _updateFps() {
    if (inferenceTimeHistory.length >= 5) {
      double meanInferenceTime = inferenceTimeHistory
              .sublist(inferenceTimeHistory.length - 5)
              .reduce((a, b) => a + b) /
          5;
      _fps = 1000 / meanInferenceTime;
    }
  }

  ViewingsCompanion topInferenceAsViewingsCompanion() {
    // TODO throw when _topInference is "no_artwork", or maybe make an entry in db with it and restart inferring
    var endTime = DateTime.now();
    return ViewingsCompanion.insert(
      artworkId: _topInference,
      startTime: startTime,
      endTime: endTime,
      totalTime:
          endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch,
      algorithmUsed: this.runtimeType.toString(),
      additionalInfo: _additionalDetailsForViewing(),
    );
  }

  // store information such as artworkScore, sensitivity, windowLength, threshold
  String _additionalDetailsForViewing();
}

/// 1st algorithm: averages the probabilities of all appearances of each artwork
/// in a sliding window of length [windowLength] over the stream of predictions
/// by the model. If the artwork with the highest mean exceeds the [sensitivity]
/// threshold, it is chosen as the "winner". In case of ties in artwork top
/// means, no winner is chosen and the algorithm proceeds to the next window.
class WindowAverageAlgo extends InferenceAlgorithm {
  final double sensitivity;
  final int windowLength;
  double _topMean = 0.0;
  var _probsByID = DefaultDict<String, List<double>>(() => []);

  WindowAverageAlgo({this.sensitivity, this.windowLength});

  @override
  void updateRecognitions(List<dynamic> recognitions, int inferenceTime) {
    _updateHistories(recognitions, inferenceTime);

    if (history.length >= windowLength) {
      // sort probabilities of the last windowLength recognitions by artworkId
      history.sublist(history.length - windowLength).forEach((recognition) {
        _probsByID[recognition["label"]].add(recognition["confidence"]);
      });

      // get mean probability for each artworkId
      var meansByID = <String, double>{
        for (var id in _probsByID.entries)
          id.key: id.value.reduce((a, b) => a + b) / id.value.length
      };

      // sort artworkIds by mean, largest to smallest
      // meansByID is converted to LinkedHashMap here, that guarantees
      // preserving key insertion order
      meansByID = meansByID.sortedByValue((mean) => mean, order: Order.desc);

      _topMean = 0.0;

      var entries = meansByID.entries.toList();

      // check if the first artwork's probability exceeds the sensitivity
      if (entries[0].value >= sensitivity / 100) {
        if (meansByID.length == 1) {
          // case of only one id
          setTopInference(entries[0].key);
          _topMean = entries[0].value;
        } else if (meansByID.length > 1 &&
            entries[0].value != entries[1].value) {
          // case of multiple ids with no ties between the top 2
          setTopInference(entries[0].key);
          _topMean = entries[0].value;
        } else {
          // there is a tie in means, wait for next round
          resetTopInference();
        }
      } else {
        // no winner yet
        resetTopInference();
      }

      _probsByID.clear();
    }
  }

  @override
  String get topInferenceFormatted {
    if (hasResult()) {
      return _topInference + " (${(_topMean * 100).toStringAsPrecision(2)}%)";
    } else {
      return noResult;
    }
  }

  @override
  String _additionalDetailsForViewing() => {
        "topMean": _topMean,
        "sensitivity": sensitivity,
        "windowLength": windowLength,
      }.toString();
}

/// 2nd algorithm: tallies the number of appearances of each artwork in a
/// sliding window of length [windowLength] over the stream of predictions by
/// the model. The artwork with the highest count is chosen as the "winner". In
/// case of ties in artwork top counts, no winner is chosen and the algorithm
/// proceeds to the next window.
///
/// We could improve this algorithm by only accepting as winner the artwork
/// that has a majority count, i.e. more than half, in the window.
class WindowHighestCountAlgo extends InferenceAlgorithm {
  final double sensitivitySetting;
  final int windowLength;
  var _countsByID = DefaultDict<String, int>(() => 0);

  WindowHighestCountAlgo({this.windowLength, this.sensitivitySetting = 0.0});

  @override
  void updateRecognitions(List recognitions, int inferenceTime) {
    _updateHistories(recognitions, inferenceTime);

    // here the sensitivity setting is not taken into account as is

    if (history.length >= windowLength) {
      // count the occurrences of the last windowLength recognitions by artworkId
      history.sublist(history.length - windowLength).forEach((recognition) {
        _countsByID[recognition["label"]] += 1;
      });

      // sort artworkIds by their counts, largest to smallest
      // sortedCounts is of type LinkedHashMap, that guarantees preserving key
      // insertion order
      var sortedCounts =
          _countsByID.sortedByValue((count) => count, order: Order.desc);

      var topEntry = sortedCounts.entries.toList()[0];

      if (sortedCounts.length == 1) {
        // if there is only one artwork in map, set it as top
        setTopInference(topEntry.key);
      } else if (topEntry.value != sortedCounts.values.toList()[1]) {
        // if there are no ties between first and second artworks, set first as top
        setTopInference(topEntry.key);
      } else {
        // in case of a tie, wait for next round to decide
        resetTopInference();
      }

      _countsByID.clear();
    }
  }

  @override
  String get topInferenceFormatted {
    if (hasResult()) {
      return _topInference +
          " (count of ${_countsByID[_topInference]} in last "
              "$windowLength inferences)";
    } else {
      return noResult;
    }
  }

  @override
  String _additionalDetailsForViewing() => {
        "topCount": _countsByID[_topInference],
        "sensitivity": sensitivitySetting,
        "windowLength": windowLength,
      }.toString();
}

/// 3rd algorithm: keep count of all predictions for each artwork, and pick as
/// "winner" the first artwork to reach [countThreshold]. If [sensitivity] is
/// specified, only those predictions that equal or exceed it are counted.
///
/// Resembles [First-past-the-post voting](https://en.wikipedia.org/wiki/First-past-the-post_voting),
/// hence the name.
class FirstPastThePostAlgo extends InferenceAlgorithm {
  final double sensitivity;
  final int countThreshold;
  var _countsByID = DefaultDict<String, int>(() => 0);

  FirstPastThePostAlgo({this.countThreshold, this.sensitivity = 0.0});

  @override
  void updateRecognitions(List recognitions, int inferenceTime) {
    _updateHistories(recognitions, inferenceTime);

    // keep count of each inference per artworkId
    recognitions.forEach((recognition) {
      double recProbability = recognition["confidence"];
      // here if sensitivitySetting is not specified, every inference counts,
      // otherwise inferences with lower values are not counted
      if (recProbability >= (sensitivity / 100)) {
        _countsByID[recognition["label"]] += 1;
      }
    });

    // sort artworkIds by their counts, largest to smallest
    // sortedCounts is of type LinkedHashMap, that guarantees preserving key
    // insertion order
    var sortedCounts =
        _countsByID.sortedByValue((count) => count, order: Order.desc);

    var entries = sortedCounts.entries.toList();

    // check the first artwork's count exceeds the count threshold
    if (entries[0].value >= countThreshold) {
      if (sortedCounts.length == 1) {
        // case of only one artwork that exceeds threshold
        setTopInference(entries[0].key);
      } else if (entries[0].value != entries[1].value) {
        // case of multiple artworks with no ties between the top 2
        setTopInference(entries[0].key);
      } else {
        // there is a tie in counts, wait for next round
        resetTopInference();
      }
    } else {
      // no winner yet
      resetTopInference();
    }
  }

  @override
  String get topInferenceFormatted {
    if (hasResult()) {
      // if we continue counting after the first top inference is chosen, the
      // top inference may change, and the return value below will no longer be
      // "correct", but in normal circumstances the app will not reach such a
      // scenario, since it will pick the first result and stop counting
      return _topInference +
          " (First to reach count of $countThreshold - current "
              "count ${_countsByID[_topInference]})";
    } else {
      return noResult;
    }
  }

  @override
  String _additionalDetailsForViewing() => {
        "topCount": _countsByID[_topInference],
        "sensitivity": sensitivity,
        "countThreshold": countThreshold,
      }.toString();
}

/// 4th algorithm: based loosely on the Persistence algorithm used by
/// Seidenary et al. 2017. The artwork whose prediction counter exceeds [P]
/// is chosen as  the winner. Similar to the 3rd algorithm
/// [FirstPastThePostAlgo], but also decrements the counters of previous
/// predictions when a new prediction is different. If [sensitivity] is
/// specified, only those predictions that equal or exceed it are counted.
class SeidenaryAlgo extends InferenceAlgorithm {
  final int P;
  final double sensitivity;
  var _counters = DefaultDict<String, int>(() => 0);

  SeidenaryAlgo({this.P, this.sensitivity = 0.0});

  @override
  void updateRecognitions(List recognitions, int inferenceTime) {
    _updateHistories(recognitions, inferenceTime);

    if (recognitions.length > 0) {
      // here if sensitivitySetting is not specified, every inference counts,
      // otherwise inferences with lower values are not counted
      if (recognitions.first["confidence"] * 100 >= sensitivity) {
        // add 1 to the top inference of this round
        var topArtwork = recognitions.first["label"];
        _counters[topArtwork] += 1;
        // subtract 1 from all other previous inferences
        _counters.keys.forEach((key) {
          if (key != topArtwork) {
            _counters[key] -= 1;
          }
        });
      }
    }

    if (_counters.isNotEmpty) {
      // sort artwork counters by their counts, largest to smallest
      // sortedCounters is converted to LinkedHashMap here, that guarantees
      // preserving key insertion order
      var sortedCounters = _counters.sortedByValue((count) => count);

      var entries = sortedCounters.entries.toList();

      // check if the first counter exceeds P
      if (entries[0].value >= P) {
        if (sortedCounters.length == 1) {
          // case of only one counter that exceeds threshold
          setTopInference(entries[0].key);
        } else if (entries[0].value != entries[1].value) {
          // case of multiple counters with no ties between the top 2
          setTopInference(entries[0].key);
        } else {
          // there is a tie in counters, wait for next round
          resetTopInference();
        }
      } else {
        // no winner yet
        resetTopInference();
      }
    }
  }

  @override
  String get topInferenceFormatted {
    if (hasResult()) {
      return _topInference + " (p=${_counters[_topInference]})";
    } else {
      return noResult;
    }
  }

  @override
  String _additionalDetailsForViewing() => {
        "topCount (p)": _counters[_topInference],
        "sensitivity": sensitivity,
        "P": P,
      }.toString();
}

// Variables with descriptions of algorithms, to be used elsewhere in the app
const firstAlgorithm = "1 - Window average probability";
const secondAlgorithm = "2 - Window highest count";
const thirdAlgorithm = "3 - First past the post";
const fourthAlgorithm = "4 - Seidenary et al. 2017 Persistence";

/// All algorithms mapped as functions, so they can be easily initialised
/// without may if-else statements.
final allAlgorithms = <String, Function(double sensitivity, int winThreshP)>{
  firstAlgorithm: (double sensitivity, int winThreshP) => WindowAverageAlgo(
        sensitivity: sensitivity,
        windowLength: winThreshP,
      ),
  secondAlgorithm: (double sensitivity, int winThreshP) =>
      WindowHighestCountAlgo(
        sensitivitySetting: sensitivity,
        windowLength: winThreshP,
      ),
  thirdAlgorithm: (double sensitivity, int winThreshP) => FirstPastThePostAlgo(
        sensitivity: sensitivity,
        countThreshold: winThreshP,
      ),
  fourthAlgorithm: (double sensitivity, int winThreshP) => SeidenaryAlgo(
        sensitivity: sensitivity,
        P: winThreshP,
      )
};
