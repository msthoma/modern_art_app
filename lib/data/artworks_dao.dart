import 'package:modern_art_app/data/database.dart';
import 'package:moor/moor.dart';

part 'artworks_dao.g.dart';

/// Data access object for [Artwork] database related operations.
@UseDao(tables: [Artworks, ArtworkTranslations, ArtistTranslations])
class ArtworksDao extends DatabaseAccessor<AppDatabase>
    with _$ArtworksDaoMixin {
  ArtworksDao(AppDatabase db) : super(db);

  /// Gets a list of all artworks in the db.
  Future<List<Artwork>> get allArtworkEntries => select(artworks).get();

  Stream<List<Artwork>> watchAllArtworks({String languageCode = "en"}) =>
      (select(artworks).join([
        leftOuterJoin(
            artworkTranslations, artworkTranslations.id.equalsExp(artworks.id)),
        leftOuterJoin(artistTranslations,
            artistTranslations.id.equalsExp(artworks.artistId))
      ])
            ..where(artworkTranslations.languageCode.equals(languageCode) &
                artistTranslations.languageCode.equals(languageCode)))
          .map((e) => composeTranslatedArtwork(
              artwork: e.readTable(artworks),
              artworkTranslation: e.readTable(artworkTranslations),
              artistTranslation: e.readTable(artistTranslations)))
          .watch();

  /// Gets a live stream of all artworks in the db (automatically emits new items
  /// whenever the underlying data changes).
  Stream<List<Artwork>> get watchAllArtworkEntries => select(artworks).watch();

  /// Gets a list of all artworks for a given painter.
  Future<List<Artwork>> getArtworksByArtist(Artist artist) =>
      (select(artworks)..where((artwork) => artwork.artist.equals(artist.name)))
          .get();

  Stream<List<Artwork>> watchArtworksByArtist(Artist artist) =>
      (select(artworks)..where((artwork) => artwork.artist.equals(artist.name)))
          .watch();

  Stream<List<Artwork>> watchArtworksByArtist2(
          {@required String artistId, String languageCode = "en"}) =>
      ((select(artworks)..where((artwork) => artwork.artistId.equals(artistId)))
              .join([
        leftOuterJoin(
            artworkTranslations, artworkTranslations.id.equalsExp(artworks.id)),
        leftOuterJoin(artistTranslations,
            artistTranslations.id.equalsExp(artworks.artistId))
      ])
                ..where(artworkTranslations.languageCode.equals(languageCode) &
                    artistTranslations.languageCode.equals(languageCode)))
          .map((e) => composeTranslatedArtwork(
              artwork: e.readTable(artworks),
              artworkTranslation: e.readTable(artworkTranslations),
              artistTranslation: e.readTable(artistTranslations)))
          .watch();

  /// Safely insert an [Artwork] into db, with the use of an [ArtworksCompanion].
  /// Returns the generated [Artwork] id.
  Future<int> addCArtwork(ArtworksCompanion artworkC) =>
      into(artworks).insert(artworkC);

  /// Upsert [Artwork] in db (insert if new, replace if exists already). Returns
  /// the generated/replaced [Artwork] id.
  Future<int> upsertArtwork(Artwork artwork) =>
      into(artworks).insertOnConflictUpdate(artwork);

  /// Get artwork by id.
  Future<Artwork> getArtworkById(String id) =>
      (select(artworks)..where((tbl) => tbl.id.equals(id))).getSingle();

  SimpleSelectStatement<$ArtworksTable, Artwork> artworksByArtist(
          String artistId) =>
      select(artworks)..where((artwork) => artwork.artistId.equals(artistId));
}

Artwork composeTranslatedArtwork({
  Artwork artwork,
  ArtworkTranslation artworkTranslation,
  ArtistTranslation artistTranslation,
}) =>
    artwork.copyWith(
        name: artworkTranslation.name,
        description: artworkTranslation.description,
        artist: artistTranslation.name);
