import 'dart:io';

import 'package:modern_art_app/data/artists_dao.dart';
import 'package:modern_art_app/data/artworks_dao.dart';
import 'package:modern_art_app/data/data_processing.dart';
import 'package:modern_art_app/data/viewings_dao.dart';
import 'package:modern_art_app/lang/localization.dart';
import 'package:moor/ffi.dart';
import 'package:moor/moor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// TODO add supported locales table

// To auto-generate the necessary moor-related code, run the following in the terminal:
// 'flutter packages pub run build_runner build'
// or the following to continuously regenerate code when code changes
// 'flutter packages pub run build_runner watch'

/// Path of locally cached json file with artists info.
const String artistsJsonPath = "assets/data/artists.json";

/// Path of locally cached json file with artworks info.
const String artworksJsonPath = "assets/data/artworks.json";

/// Table for [Artwork]s in database.
///
/// Class "Artwork" is auto-generated, by stripping the trailing "s" in the
/// table name. If a custom name is required, use @DataClassName("CustomName").
class Artworks extends Table {
  TextColumn get id => text()();

  // if primary key is not an autoIncrement IntColumn, it must be set like this
  @override
  Set<Column> get primaryKey => {id};

  // GSheets returns columns keys in all lowercase, so it's necessary to specify
  // the JsonKey below. Setting the column title in the spreadsheet as "artist_id",
  // for example, does not help either, since GSheets removes the underscore in json
  @JsonKey("artistid")
  TextColumn get artistId =>
      text().customConstraint("NULL REFERENCES artists(id)")();

  TextColumn get year => text().nullable()();

  // the fields below are specified so they are included in the generated Artwork
  // class, but will remain null in the table, and only filled on demand from
  // the ArtworkTranslations table, according to the desired locale
  TextColumn get name => text().nullable()();

  TextColumn get description => text().nullable()();

  TextColumn get artist => text().nullable()();

// TODO add current locale
}

/// Table for [ArtworkTranslation]s in database. Each [ArtworkTranslation]
/// holds copies of translatable fields from an [Artwork] in a particular
/// locale; these are then joined in database queries to produce fully
/// translated artwork objects.
class ArtworkTranslations extends Table {
  TextColumn get id =>
      text().customConstraint("NULL REFERENCES artworks(id)")();

  TextColumn get languageCode => text()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {id, languageCode};
}

/// Table for [Artist]s in database.
class Artists extends Table {
  TextColumn get id => text()();

  @override
  Set<Column> get primaryKey => {id};

  @JsonKey("yearbirth")
  TextColumn get yearBirth => text().nullable()();

  @JsonKey("yeardeath")
  TextColumn get yearDeath => text().nullable()();

  // the fields below are specified so they are included in the generated Artist
  // class, but will remain null in the table, and only filled on demand from
  // the ArtistTranslations table, according to the desired locale
  TextColumn get name => text().nullable()();

  TextColumn get biography => text().nullable()();
}

/// Table for [ArtistTranslation]s in database. Each [ArtistTranslation]
/// holds copies of translatable fields from an [Artist] in a particular
/// locale; these are then joined in database queries to produce fully
/// translated artwork objects.
class ArtistTranslations extends Table {
  TextColumn get id => text().customConstraint("NULL REFERENCES artists(id)")();

  TextColumn get languageCode => text()();

  TextColumn get name => text()();

  TextColumn get biography => text().nullable()();

  @override
  Set<Column> get primaryKey => {id, languageCode};
}

class Viewings extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get artworkId =>
      text().customConstraint("NULL REFERENCES artworks(id)")();

  TextColumn get cnnModelUsed => text().nullable()();

  TextColumn get algorithmUsed => text()();

  DateTimeColumn get startTime => dateTime()();

  DateTimeColumn get endTime => dateTime()();

  IntColumn get totalTime => integer()();

  TextColumn get additionalInfo => text()();
}

LazyDatabase _openConnection() {
  // the LazyDatabase util lets us find the right location for the file async.
  return LazyDatabase(() async {
    // put the database file, called db.sqlite here, into the documents folder
    // for your app.
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return VmDatabase(file, logStatements: false);
  });
}

/// Creates an instance of [AppDatabase] (lazily).
///
/// During the first use of [AppDatabase], it is automatically populated from a
/// Json file with the necessary information in assets.
@UseMoor(tables: [
  Artworks,
  ArtworkTranslations,
  Artists,
  ArtistTranslations,
  Viewings,
], daos: [
  ArtworksDao,
  ArtistsDao,
  ViewingsDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// The schemaVersion number should be incremented whenever there is a change
  /// in any of the table definitions (also a migration policy must be declared
  /// below).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          /// Enables foreign keys in the db.
          await customStatement("PRAGMA foreign_keys = ON");

          /// When db is first created, populate it from cached json asset files.
          if (details.wasCreated) {
            // determine supported locales
            var languageCodes = localizedLabels.keys
                .toList()
                .map((locale) => locale.languageCode)
                .toList();

            // TODO make logic into function that accepts generics, since it's the same code repeated twice
            // populate artists and artistTranslations tables
            await getLocalJsonItemList(artistsJsonPath).then(
              (artistEntries) => artistEntries.forEach(
                (entry) {
                  var parsedEntry = parseItemMap(entry);
                  var artist = Artist.fromJson(parsedEntry);
                  into(artists).insertOnConflictUpdate(artist);
                  print("Created entry for artist with id ${artist.id}");
                  languageCodes.forEach(
                    (languageCode) {
                      var translatedEntry = ArtistTranslation.fromJson(
                        parseItemTranslations(parsedEntry, languageCode),
                      );
                      into(artistTranslations).insertOnConflictUpdate(
                        translatedEntry,
                      );
                      print("Created entry for language $languageCode for "
                          "artist with id ${artist.id}");
                    },
                  );
                },
              ),
            );

            // populate artworks and artworkTranslations tables
            await getLocalJsonItemList(artworksJsonPath).then(
              (artworkEntries) => artworkEntries.forEach(
                (entry) {
                  var parsedEntry = parseItemMap(entry);
                  var artwork = Artwork.fromJson(parsedEntry);
                  into(artworks).insertOnConflictUpdate(artwork);
                  print("Created entry for artwork with id ${artwork.id}");
                  languageCodes.forEach(
                    (languageCode) {
                      var translatedEntry = ArtworkTranslation.fromJson(
                        parseItemTranslations(parsedEntry, languageCode),
                      );
                      into(artworkTranslations).insertOnConflictUpdate(
                        translatedEntry,
                      );
                      print("Created entry for language $languageCode for "
                          "artwork with id ${artwork.id}");
                    },
                  );
                },
              ),
            );
          }
        },
      );
}
